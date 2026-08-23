Shader :: struct {
    type: Shader_Type;
    input_vao: GLuint;
    vs_program: GLuint;
    fs_program: GLuint;
    cs_program: GLuint;

    mappings: []Texture_Sampler_Mapping;
}

Buffer :: struct (type: Buffer_Type) {
    object: GLuint;
    size: u32;
    stride: u32;
    fence: GLsync;
}

Texture :: struct {
    object: GLuint;
    width, height, stride: u32;
    depth: u32 = 1;
    mip_levels: u32 = 1;
    format: Texture_Format;
    flags: Texture_Flags;

    union {
        target: GLenum; // For sampled textures
        struct { // For pbos (.Copy textures)
            pbo_size: u32;
            fence: GLsync;
        }
    }
}

Sampler :: struct {
    object: GLuint;
}

Render_Target :: struct {
    framebuffer: GLuint;
    color_view_count: u32;
}

Timer :: struct {
    start_query: GLuint;
    end_query: GLuint;
    #overlay(start_query) queries: [2]GLuint;
    recording: bool;
}

is_valid :: (texture: Texture) -> bool {
    if texture.flags & .Copy return glIsBuffer(texture.object);
    return glIsTexture(texture.object);
}

is_valid ::(sampler: Sampler) -> bool {
    return glIsSampler(sampler.object);
}

is_valid :: (buffer: Buffer) -> bool {
    return glIsBuffer(buffer.object);
}

is_valid :: (using shader: Shader) -> bool {
    empty_vs := type & .Vertex   && (!glIsProgram(vs_program) || !glIsVertexArray(input_vao));
    empty_fs := type & .Fragment && !glIsProgram(fs_program);
    empty_cs := type & .Compute  && !glIsProgram(cs_program);

    return type != .Unspecified && !empty_vs && !empty_fs && !empty_cs;
}

is_valid :: (render_target: Render_Target) -> bool {
    status := glCheckNamedFramebufferStatus(render_target.framebuffer, GL_FRAMEBUFFER);
    return status == GL_FRAMEBUFFER_COMPLETE;
}

is_valid :: (timer: Timer) -> bool {
    return glIsQuery(timer.start_query) && glIsQuery(timer.end_query);
}

init :: (window: WT.Window_Type) {
    MAJOR :: 4;
    MINOR :: 5;

    #if REQUEST_HIGH_PERFORMANCE_GPU && OS == .LINUX {
        #import "POSIX";
        #import "File_Utilities";

        // Request dGPU from Mesa
        setenv("DRI_PRIME", "1", 1);

        // Request dGPU from Nvidia proprietary drivers
        if file_exists("/sys/module/nvidia") {
            setenv("__NV_PRIME_RENDER_OFFLOAD", "1", 1);
            setenv("__GLX_VENDOR_LIBRARY_NAME", "nvidia", 1);
            // setenv("__EGL_VENDOR_LIBRARY_FILENAMES", "/usr/share/glvnd/egl_vendor.d/10_nvidia.json", 1)
            // setenv("__NV_PRIME_RENDER_OFFLOAD_PROVIDER","NVIDIA-G0", 1);
        }
    }

    #if OS == .WINDOWS {
        if window == WT.INVALID_WINDOW {
            wgl_create_compute_context(MAJOR, MINOR, DEBUG);
        }
        else {
            wgl_create_context(window, major_version=MAJOR, minor_version=MINOR, debug=DEBUG, wanted_msaa=0);
        }
    }
    else {
        // Mesa has a bug. We can't enable debug it until it's fixed.
        // https://gitlab.freedesktop.org/mesa/mesa/-/work_items/16043
        egl_create_context(window, MAJOR, MINOR, debug=false);
    }

    gl_load(*gl);
    major, minor := gl_get_version();

    if major < 4 || minor < 5 { // We support 4.5 and require SPIR-V extension.
        log_error("[Gaco] Unsupported GL version: %.%, need at least 4.5", major, minor);
    }

    #if DEBUG {
        renderer_name := glGetString(GL_RENDERER);
        log("[Gaco] OpenGL Renderer: %", to_string(renderer_name));

        // D3D11 crashes on errors (because there is no way to register a callback...)
        // so we do the same thing here to be compatible.
        glEnable(GL_DEBUG_OUTPUT);
        glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS);
        glDebugMessageCallback(gl_debug_callback, null);
    }

    glCreateProgramPipelines(1, *global_pipeline);
    glBindProgramPipeline(global_pipeline);

    if window == WT.INVALID_WINDOW return;

    main_window = window;

    // NOTE(Yasin): Setting this on its own just makes the output upside down so
    // we reinvert it when blitting our custom framebuffer to the backbuffer. (check present())
    //
    // So why set this then? Because otherwise, if you draw to a texture and try to read it from
    // cpu or sample it from gpu, the memory layout would be different between D3D11 and OpenGL, which is annoying.
    //
    // Now everything seems to work correctly with our trick, but if a library directly plugs into OpenGL (such as ImGui)
    // and assumes GL_UPPER_LEFT means the screen is upside down, we might get unwanted effects.
    // You have to make sure the library doesn't depend on this value or better yet, maybe not plug something directly to
    // a backend since the purpose of this module is to abstract away all the weird differences and annoyances.
    glClipControl(GL_UPPER_LEFT, GL_ZERO_TO_ONE);

    glEnable(GL_SAMPLE_MASK);
    glEnable(GL_FRAMEBUFFER_SRGB);
    glEnable(GL_TEXTURE_CUBE_MAP_SEAMLESS);
    glEnable(GL_PRIMITIVE_RESTART_FIXED_INDEX);
    glDisable(GL_DITHER);

    glProvokingVertex(GL_FIRST_VERTEX_CONVENTION);

    // So we can bind vertex buffers without setting a shader.
    glCreateVertexArrays(1, *empty_stupid_vao);
    glBindVertexArray(empty_stupid_vao);

    set_depth_stencil_state(.{});
    set_rasterizer_state(.{});
    set_blend_state(.{blend_enable=false});


    set_swap_interval(0);
    _, _, window_width, window_height = get_dimensions(main_window, false);

    default_sampler = create_sampler();
}

deinit :: () {
    glDeleteProgramPipelines(1, *global_pipeline);
    glDeleteVertexArrays(1, *empty_stupid_vao);
    destroy_sampler(*default_sampler);

    #if OS == .WINDOWS {
        hglrc := wglGetCurrentContext();
        if hglrc {
            hdc := wglGetCurrentDC();

            wglMakeCurrent(null, null) ;
            ReleaseDC (main_window, hdc) ;
            wglDeleteContext(hglrc);
        }
    }
    else #if OS == .LINUX {
        gl_context := eglGetCurrentContext();
        if gl_context {
            eglDestroyContext(egl_display, gl_context);
        }
    }
}

create_buffer :: (data: *void, count: u32, stride: u32, $type: Buffer_Type, usage := Buffer_Usage.Default, debug_name := "") -> Buffer(type) {
    buffer: Buffer(type);
    buffer.size = count * stride;
    buffer.stride = stride;

    assert(buffer.size > 0, "[Gaco] Creating a buffer with 0 size is not permitted.");

    #if type == .Constant if stride % 16 != 0 {
        message: string;
        if debug_name
            message = tprint("[Gaco] Buffer creation failed ('%'): Constant buffers require 16-byte aligned size (got %).", debug_name, buffer.size);
        else
            message = tprint("[Gaco] Buffer creation failed: Constant buffers require 16-byte aligned size (got %).", buffer.size);

        log_error(message);

        #if DEBUG {
            debug_break();
        }
        return .{};
    }

    glCreateBuffers(1, *buffer.object);

    storage_flags: GLbitfield;
    #if type == .Copy {
        storage_flags |= GL_MAP_READ_BIT | GL_CLIENT_STORAGE_BIT;
    }
    else if usage == .Default {
        storage_flags |= GL_DYNAMIC_STORAGE_BIT;
    }

    if usage == .Dynamic {
        storage_flags |= GL_MAP_WRITE_BIT;
    }

    glNamedBufferStorage(buffer.object, buffer.size, data, storage_flags);
    if debug_name  gl_set_debug_name(buffer.object, GL_BUFFER, debug_name);

    return buffer;
}

bind_buffer :: (buffer: Buffer(.Vertex), slot: u32 = 0, offset: u32 = 0) {
    if slot == 0 {
        bound_vertex_buffer.object = buffer.object;
        bound_vertex_buffer.stride = buffer.stride;
        bound_vertex_buffer.offset = offset;
    }
    else if slot == 1 {
        bound_instance_buffer.object = buffer.object;
        bound_instance_buffer.stride = buffer.stride;
        bound_instance_buffer.offset = offset;
    }
    glBindVertexBuffer(slot, buffer.object, offset, buffer.stride);
}

bind_buffer :: (buffer: Buffer(.Index)) {
    assert(buffer.stride == 2 || buffer.stride == 4);

    current_index_stride = buffer.stride;
    bound_index_buffer = buffer.object;
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, buffer.object);
}

bind_buffer :: (buffer: Buffer(.Constant), slot: u32 = 0, bind_to: Shader_Type) {
    if bind_to & .Vertex
        glBindBufferBase(GL_UNIFORM_BUFFER, slot + VS_SHIFT, buffer.object);

    if bind_to & .Fragment
        glBindBufferBase(GL_UNIFORM_BUFFER, slot + FS_SHIFT, buffer.object);

    if bind_to & .Compute
        glBindBufferBase(GL_UNIFORM_BUFFER, slot + CS_SHIFT, buffer.object);

}

bind_buffer :: (buffer: Buffer(.Structured), slot: u32 = 0, bind_to: Shader_Type) {
    if bind_to & .Vertex
        glBindBufferBase(GL_SHADER_STORAGE_BUFFER, slot + VS_SHIFT, buffer.object);
    if bind_to & .Fragment
        glBindBufferBase(GL_SHADER_STORAGE_BUFFER, slot + FS_SHIFT, buffer.object);
    if bind_to & .Compute
        glBindBufferBase(GL_SHADER_STORAGE_BUFFER, slot + CS_SHIFT, buffer.object);
}

bind_buffer :: (buffer: Buffer(.Structured_RW), slot: u32 = 0) {
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, slot, buffer.object);
}

// Same as above
bind_buffer :: (buffer: Buffer(.Indirect), slot: u32 = 0) {
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, slot, buffer.object);
}

// You can ignore 'busy' if you didn't specify .Non_Blocking
map_buffer :: (buffer: *Buffer, flags: Map_Flags) -> *void, busy: bool {
    data, busy := gl_map_buffer(buffer.object, buffer.size, flags, buffer.type == .Copy, buffer.fence);
    return data, busy;
}

unmap_buffer :: (buffer: *Buffer) {
    if glUnmapNamedBuffer(buffer.object) == GL_FALSE {
        log_error("[Gaco] Couldn't unmap buffer!");
    }

    if buffer.fence {
        glDeleteSync(buffer.fence);
        buffer.fence = 0;
    }
}


// This is actually here for api compatibility with D3D11.
// The 'Texture' we have here is a pixel buffer object. So we assert that before doing anything.
// You can ignore 'busy' if you didn't specify .Non_Blocking
map_texture :: (texture: *Texture, flags: Map_Flags) -> *void, busy: bool {
    assert(texture.flags & .Copy != 0, "[Gaco] Only copy textures can be mapped to read.");
    data, busy := gl_map_buffer(texture.object, texture.pbo_size, flags, true, texture.fence);
    return data, busy;
}

unmap_texture :: (texture: *Texture) {
    assert(texture.flags & .Copy != 0);
    if glUnmapNamedBuffer(texture.object) == GL_FALSE {
        log_error("[Gaco] Couldn't unmap texture!");
    }

    if texture.fence {
        glDeleteSync(texture.fence);
        texture.fence = 0;
    }
}

update_buffer :: (buffer: *Buffer, data: *void) {
    glNamedBufferSubData(buffer.object, 0, buffer.size, data);
}

update_texture :: (texture: *Texture, data: *void, rect: Rect, subresource: u32 = 0) {
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

    mip   := subresource % texture.mip_levels;
    layer := subresource / texture.mip_levels;

    is_layered := is_target_layered(texture.target);
    gl_info := GL_TEXTURE_MAP_ARRAY[texture.format];

    if is_block_compression(texture.format) {
        bw := (cast(u32)rect.width + 3) / 4;
        bh := (cast(u32)rect.height + 3) / 4;
        image_size := cast(u32)(bw * bh * texture.stride);

        if is_layered {
            glCompressedTextureSubImage3D(texture.object, cast(s32)mip,
                rect.x, rect.y, cast(s32)layer, cast(u32)rect.width, cast(u32)rect.height, 1,
                gl_info.pixel_format, image_size, data);
        } else {
            glCompressedTextureSubImage2D(texture.object, cast(s32)mip,
                rect.x, rect.y, cast(u32)rect.width, cast(u32)rect.height,
                gl_info.pixel_format, image_size, data);
        }
    }
    else {
        if is_layered {
            glTextureSubImage3D(texture.object, cast(s32)mip,
                rect.x, rect.y, cast(s32)layer, cast(u32)rect.width, cast(u32)rect.height, 1,
                gl_info.pixel_format, gl_info.pixel_type, data);
        } else {
            glTextureSubImage2D(texture.object, cast(s32)mip,
                rect.x, rect.y, cast(u32)rect.width, cast(u32)rect.height,
                gl_info.pixel_format, gl_info.pixel_type, data);
        }
    }

    glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
}

update_texture :: (texture: *Texture, data: *void, box: Box, subresource: u32 = 0) {
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    gl_info := GL_TEXTURE_MAP_ARRAY[texture.format];

    if is_block_compression(texture.format) {
        bw := (cast(u32)box.width + 3) / 4;
        bh := (cast(u32)box.height + 3) / 4;
        image_size := cast(u32)(bw * bh * texture.stride * cast(u32)box.depth);

        glCompressedTextureSubImage3D(
            texture.object, cast(s32)subresource,
            box.x, box.y, box.z,
            cast(u32)box.width, cast(u32)box.height, cast(u32)box.depth,
            gl_info.pixel_format, image_size, data
        );
    }
    else {
        glTextureSubImage3D(
            texture.object, cast(s32)subresource,
            box.x, box.y, box.z,
            cast(u32)box.width, cast(u32)box.height, cast(u32)box.depth,
            gl_info.pixel_format, gl_info.pixel_type, data
        );
    }

    glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
}

update_texture :: inline (using texture: *Texture, data: *void, subresource: u32 = 0) {
    if flags & .Is_3D {
        update_texture(texture, data, Box.{0, 0, 0, cast(s32)width, cast(s32)height, cast(s32)depth}, subresource);
    } else {
        update_texture(texture, data, Rect.{0, 0, cast(s32)width, cast(s32)height}, subresource);
    }
}

write_buffer :: (buffer: *Buffer, data: *void, size: int) {
    mapped := glMapNamedBufferRange(buffer.object, 0, size, GL_MAP_WRITE_BIT | GL_MAP_INVALIDATE_BUFFER_BIT);
    memcpy(mapped, data, size);
    glUnmapNamedBuffer(buffer.object);
}

copy_buffer :: (from: Buffer, to: *Buffer) {
    glCopyNamedBufferSubData(from.object, to.object, 0, 0, from.size);

    #if to.type == .Copy {
        if to.fence glDeleteSync(to.fence);
        to.fence = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
    }
}

destroy_buffer :: (buffer: *Buffer) {
    if buffer.fence {
        glDeleteSync(buffer.fence);
        buffer.fence = 0;
    }
    glDeleteBuffers(1, *buffer.object);
    buffer.object = 0;
}

destroy_texture :: (texture: *Texture) {
    if texture.flags & .Copy {
        glDeleteBuffers(1, *texture.object);
        if texture.fence {
            glDeleteSync(texture.fence);
            texture.fence = 0;
        }
    }
    else
        glDeleteTextures(1, *texture.object);
    texture.object = 0;
}

destroy_shader :: (shader: *Shader) {
    if shader.type & .Vertex {
        glDeleteVertexArrays(1, *shader.input_vao);
        shader.input_vao = 0;
        glDeleteProgram(shader.vs_program);
        shader.vs_program = 0;
    }
    if shader.type & .Fragment {
        glDeleteProgram(shader.fs_program);
        shader.fs_program = 0;
    }
    if shader.type & .Compute {
        glDeleteProgram(shader.cs_program);
        shader.cs_program = 0;
    }

    array_free(shader.mappings);
}

compile_shader_to_bytecode :: (source: string, type: Shader_Type, file_name: string, defines := string.[]) -> Shader_Bytecode, bool {
    bytecode: Shader_Bytecode;

    args: DXC.Dxc_Shader_Compiler_Args;
    args.shader_name = file_name;
    args.shader_model_version = "6_0";
    args.shader_source = source;

    args.add_debug_info = DEBUG;
    args.spirv_target_env = "vulkan1.1";
    args.defines = defines;

    args.spirv_generate_non_semanantic_debug_info = false;

    sampler_mappings := [..]Texture_Sampler_Mapping.{allocator=temp};

    compile :: (entry_point: string, shader_type: Shader_Type) -> string #expand {
        `args.entry_point = entry_point;

        // Convert to DXC shader type
        if shader_type == {
        case .Vertex;   `args.shader_type = .Vertex;
        case .Fragment; `args.shader_type = .Fragment;
        case .Compute;  `args.shader_type = .Compute;
        }

        extra_args: [..]string;
        extra_args.allocator = temp;


        // array_add(*extra_args, "-fspv-flatten-resource-arrays");
        if shader_type == .Vertex {
            array_add(*extra_args, "-fspv-preserve-interface");
            // array_add(*extra_args, "-fvk-invert-y");
        }

        t_shift := "0";
        b_shift := "0";
        s_shift := "0";

        if shader_type == {
        case .Vertex;
            t_shift = VS_SHIFT_STR;
            b_shift = VS_SHIFT_STR;
            s_shift = VS_SHIFT_STR;
        case .Fragment;
            t_shift = FS_SHIFT_STR;
            b_shift = FS_SHIFT_STR;
            s_shift = FS_SHIFT_STR;
        case .Compute;
            t_shift = CS_SHIFT_STR;
            b_shift = CS_SHIFT_STR;
            s_shift = CS_SHIFT_STR;
        }

        shift_args := string.[
            "-fvk-t-shift", t_shift, "all",
            "-fvk-b-shift", b_shift, "all",
            "-fvk-s-shift", s_shift, "all",
        ];
        array_add(*extra_args, ..shift_args);
        `args.extra_args = extra_args;

        result := DXC.DXC_Compile(`args,, temp);
        if !result {
            `return .{}, false;
        }
        new_bytecode := build_combined_image_samplers(cast(string)result, shader_type, *sampler_mappings);
        return new_bytecode;
    }

    if type & .Vertex {
        bytecode.vs = compile(VS_ENTRY_POINT, .Vertex);

    }
    if type & .Fragment {
        bytecode.fs = compile(FS_ENTRY_POINT, .Fragment);
    }
    if type & .Compute {
        bytecode.cs = compile(CS_ENTRY_POINT, .Compute);
    }
    bytecode.mappings = array_copy(sampler_mappings);
    return bytecode, true;
}

load_shader_from_bytecode :: (bytecode: Shader_Bytecode, type: Shader_Type, debug_name := "") -> Shader {
    shader: Shader;
    load :: (shader_type: GLenum, binary: string, entry_point: string) -> GLuint #expand {
        program := glCreateProgram();
        glProgramParameteri(program, GL_PROGRAM_SEPARABLE, 1);
        if `debug_name  gl_set_debug_name(program, GL_PROGRAM, `debug_name);

        shader := glCreateShader(shader_type);
        defer if shader glDeleteShader(shader);

        glShaderBinary(1, *shader, GL_SHADER_BINARY_FORMAT_SPIR_V, binary.data, cast(u32)binary.count);
        glSpecializeShader(shader, entry_point, 0, null, null);
        is_compiled: GLint;
        glGetShaderiv(shader, GL_COMPILE_STATUS, *is_compiled);
        if is_compiled == 0 {
            info_len: GLint;
            glGetShaderiv(shader, GL_INFO_LOG_LENGTH, *info_len);
            if info_len > 0 {
                info_log := alloc(info_len,, temp);
                glGetShaderInfoLog(shader, cast(GLsizei)info_len, null, info_log);
                log_error("[Gaco] Shader compilation failed: %", to_string(info_log));
            }
            else {
                log_error("[Gaco] Shader compilation failed with no info log.");
            }
            log_error("[Gaco] Shader loading failed.");
            `return .{};
        }

        glAttachShader(program, shader);
        glLinkProgram(program);
        is_linked: GLint;
        glGetProgramiv(program, GL_LINK_STATUS, *is_linked);
        if is_linked == 0 {
            info_len: GLint;
            glGetProgramiv(program, GL_INFO_LOG_LENGTH, *info_len);

            if info_len > 0 {
                info_log := alloc(info_len,, temp);
                glGetProgramInfoLog(program, cast(GLsizei)info_len, null, info_log);
                log_error("[Gaco] Shader linking failed: %",to_string(info_log));
            } else {
                log_error("[Gaco] Shader linking failed with no info log.");
            }
            glDeleteProgram(program);
            `return .{};
        }
        return program;
    }

    if type & .Vertex {
        shader.input_vao = get_input_vao_from_spv(bytecode.vs);
        shader.vs_program = load(GL_VERTEX_SHADER, bytecode.vs, VS_ENTRY_POINT);
    }
    if type & .Fragment {
        shader.fs_program = load(GL_FRAGMENT_SHADER, bytecode.fs, FS_ENTRY_POINT);
    }
    if type & .Compute {
        shader.cs_program = load(GL_COMPUTE_SHADER, bytecode.cs, CS_ENTRY_POINT);
    }

    shader.type = type;
    shader.mappings = array_copy(bytecode.mappings);

    return shader;
}

clear :: inline (color: Vector4, depth := 1.0, stencil: u8 = 0, $flags: Clear_Flags = .Color | .Depth | .Stencil) {
    window_render_target := Render_Target.{custom_fbo, 1};

    clear(window_render_target, color, depth, stencil, flags);

    // Commented code clears the currently bound framebuffer.

    // glClearColor(r,g,b,a);
    // glClearDepthf(depth);
    // glClearStencil(cast(GLint)stencil);

    // mask: GLbitfield;
    // #if flags & .Color
    //     mask |= GL_COLOR_BUFFER_BIT;
    // #if flags & .Depth
    //     mask |= GL_DEPTH_BUFFER_BIT;
    // #if flags & .Stencil
    //     mask |= GL_STENCIL_BUFFER_BIT;
    // glClear(mask);
}

clear :: (render_target: Render_Target, color: Vector4, depth := 1.0, stencil: u8 = 0, $flags: Clear_Flags = .Color | .Depth | .Stencil) {
    #if flags & .Color {
        for 0..render_target.color_view_count - 1 {
            glClearNamedFramebufferfv(render_target.framebuffer, GL_COLOR, cast(s32)it, color.component.data);
        }
    }
    #if flags & .Depth {
        glClearNamedFramebufferfv(render_target.framebuffer, GL_DEPTH, 0, *depth);
    }
    #if flags & .Stencil {
        val := cast(s32)stencil;
        glClearNamedFramebufferiv(render_target.framebuffer, GL_STENCIL, 0, *val);
    }
}

set_shader :: (shader: Shader) {
    stages: GLbitfield;
    if shader.type & .Vertex {
        stages |= GL_VERTEX_SHADER_BIT;

        // We have to rebind the vertex, index and instance buffer because we can't just change
        // the input vao and be done with it!!

        bind :: (buffer: GL_State.Bound_Buffer, slot: u32) {
            glBindVertexBuffer(slot, buffer.object, buffer.offset, buffer.stride);
        }

        glBindVertexArray(shader.input_vao);

        bind(bound_vertex_buffer, 0);
        bind(bound_instance_buffer, 1);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, bound_index_buffer);

        vs_mappings = shader.mappings;
        glUseProgramStages(global_pipeline, GL_VERTEX_SHADER_BIT, shader.vs_program);
    }
    if shader.type & .Fragment {
        fs_mappings = shader.mappings;
        glUseProgramStages(global_pipeline, GL_FRAGMENT_SHADER_BIT, shader.fs_program);
    }
    if shader.type & .Compute {
        cs_mappings = shader.mappings;
        glUseProgramStages(global_pipeline, GL_COMPUTE_SHADER_BIT, shader.cs_program);
    }

    #if DEBUG {
        glValidateProgramPipeline(global_pipeline);

        is_valid: GLint;
        glGetProgramPipelineiv(global_pipeline, GL_VALIDATE_STATUS, *is_valid);
        if is_valid == 0 {
            info_len: GLint;
            glGetProgramPipelineiv(global_pipeline, GL_INFO_LOG_LENGTH, *info_len);
            if info_len > 0 {
                info_log := alloc(info_len,, temp);
                glGetProgramPipelineInfoLog(global_pipeline, cast(GLsizei)info_len, null, info_log);
                log_error("[Gaco] Pipeline validation failed: %", to_string(info_log));
            }
        }
    }

}

set_primitive_type :: (primitive_type: Primitive_Type) {
    if #complete primitive_type == {
    case .Line_List;
        current_primitive_mode = GL_LINES;
    case .Line_Strip;
        current_primitive_mode = GL_LINE_STRIP;
    case .Triangle_List;
        current_primitive_mode = GL_TRIANGLES;
    case .Triangle_Strip;
        current_primitive_mode = GL_TRIANGLE_STRIP;
    }
}

set_scissor :: (using rect: Rect) {
    glScissor(x, y, cast(u32)width, cast(u32)height);
}

set_viewport :: (using info: Viewport_Desc) {
    glViewportIndexedf(0, x, y, width, height);
    glDepthRangef(near_depth, far_depth);
}

get_viewport :: () -> Viewport_Desc {
    info: Viewport_Desc;

    glGetFloatv(GL_VIEWPORT, *info.x);
    glGetFloatv(GL_DEPTH_RANGE, *info.near_depth);

    return info;
}

set_rasterizer_state :: (desc: Rasterizer_Desc) {
    glPolygonMode(GL_FRONT_AND_BACK, GL_FILL_MODE_MAP[desc.fill_mode]);

    if desc.cull_mode == .None {
        glDisable(GL_CULL_FACE);
    } else {
        glEnable(GL_CULL_FACE);
        glCullFace(GL_CULL_MODE_MAP[desc.cull_mode]);
    }

    front_face := ifx desc.front_counter_clockwise then cast(u32)GL_CCW else GL_CW;
    glFrontFace(front_face);

    if desc.depth_bias != 0 || desc.slope_scaled_depth_bias != 0.0 {
        glEnable(GL_POLYGON_OFFSET_FILL);
        glEnable(GL_POLYGON_OFFSET_LINE);

        glPolygonOffsetClamp(desc.slope_scaled_depth_bias, cast(float) desc.depth_bias, desc.depth_bias_clamp);
    } else {
        glDisable(GL_POLYGON_OFFSET_FILL);
        glDisable(GL_POLYGON_OFFSET_LINE);
    }

    if desc.depth_clip_enable {
        glDisable(GL_DEPTH_CLAMP);
    } else {
        glEnable(GL_DEPTH_CLAMP);
    }

    if desc.scissor_enable {
        glEnable(GL_SCISSOR_TEST);
    } else {
        glDisable(GL_SCISSOR_TEST);
    }

    if desc.antialiased_line_enable {
        glEnable(GL_LINE_SMOOTH);
    } else {
        glDisable(GL_LINE_SMOOTH);
    }
}

set_blend_state :: (desc: Blend_Desc, alpha_to_coverage_enable := false, blend_factor := Vector4.{}, sample_mask: u32 = 0xFFFF_FFFF) {
    if desc.blend_enable {
        glEnable(GL_BLEND);

        glBlendFuncSeparate(
            GL_BLEND_MAP[desc.src_blend], GL_BLEND_MAP[desc.dest_blend],
            GL_BLEND_MAP[desc.src_blend_alpha], GL_BLEND_MAP[desc.dest_blend_alpha]
        );

        glBlendEquationSeparate(
            GL_BLEND_OP_MAP[desc.blend_op], GL_BLEND_OP_MAP[desc.blend_op_alpha]
        );
    } else {
        glDisable(GL_BLEND);
    }

    glBlendColor(blend_factor.x, blend_factor.y, blend_factor.z, blend_factor.w);

    r := cast(GLboolean) ((desc.write_mask & .Red)   != 0);
    g := cast(GLboolean) ((desc.write_mask & .Green) != 0);
    b := cast(GLboolean) ((desc.write_mask & .Blue)  != 0);
    a := cast(GLboolean) ((desc.write_mask & .Alpha) != 0);
    glColorMask(r, g, b, a);

    glSampleMaski(0, sample_mask);
    if alpha_to_coverage_enable glEnable(GL_SAMPLE_ALPHA_TO_COVERAGE);
    else glDisable(GL_SAMPLE_ALPHA_TO_COVERAGE);
}

set_blend_state :: (descs: []Blend_Desc, alpha_to_coverage_enable := false, blend_factor := Vector4.{}, sample_mask: u32 = 0xFFFF_FFFF) {
    for descs {
        i := cast(GLuint) it_index;

        if it.blend_enable {
            glEnablei(GL_BLEND, i);

            glBlendFuncSeparatei(i,
                GL_BLEND_MAP[it.src_blend], GL_BLEND_MAP[it.dest_blend],
                GL_BLEND_MAP[it.src_blend_alpha], GL_BLEND_MAP[it.dest_blend_alpha]
            );

            glBlendEquationSeparatei(i,
                GL_BLEND_OP_MAP[it.blend_op], GL_BLEND_OP_MAP[it.blend_op_alpha]
            );
        } else {
            glDisablei(GL_BLEND, i);
        }

        r := cast(GLboolean) ((it.write_mask & .Red)   != 0);
        g := cast(GLboolean) ((it.write_mask & .Green) != 0);
        b := cast(GLboolean) ((it.write_mask & .Blue)  != 0);
        a := cast(GLboolean) ((it.write_mask & .Alpha) != 0);
        glColorMaski(i, r, g, b, a);
    }

    glBlendColor(blend_factor.x, blend_factor.y, blend_factor.z, blend_factor.w);
    glSampleMaski(0, sample_mask);

    if alpha_to_coverage_enable glEnable(GL_SAMPLE_ALPHA_TO_COVERAGE);
    else glDisable(GL_SAMPLE_ALPHA_TO_COVERAGE);
}

set_depth_stencil_state :: (desc: Depth_Stencil_Desc, stencil_ref: u8 = 0xFF) {
    if desc.depth_enable {
        glEnable(GL_DEPTH_TEST);
        glDepthFunc(GL_COMPARISON_MAP[desc.depth_func]);
    }
    else {
        glDisable(GL_DEPTH_TEST);
    }

    glDepthMask(desc.depth_write);

    if desc.stencil_enable {
        glEnable(GL_STENCIL_TEST);

        func_and_op :: (using face_desc: Stencil_Face_Desc, front: bool) #expand {
            face := ifx front GL_FRONT.(u32) else GL_BACK;
            glStencilFuncSeparate(face, GL_COMPARISON_MAP[compare_op], stencil_ref, desc.stencil_read_mask);
            glStencilOpSeparate(face, GL_STENCIL_OP_MAP[fail_op], GL_STENCIL_OP_MAP[depth_fail_op], GL_STENCIL_OP_MAP[pass_op]);
        }

        func_and_op(desc.front_face, true);
        func_and_op(desc.back_face, false);
    }
    else {
        glDisable(GL_STENCIL_TEST);
    }

    glStencilMask(desc.stencil_write_mask);
}

draw :: ($indexed: bool, count: u32, first: u32 = 0, base_vertex: s32 = 0) {
    flush_graphics_bindings();
    #if indexed {
        format := ifx current_index_stride == 4 cast(u32)GL_UNSIGNED_INT else cast(u32)GL_UNSIGNED_SHORT;
        glDrawElementsBaseVertex(current_primitive_mode, count, format, cast(*void)(current_index_stride * first), base_vertex);
    }
    else {
        glDrawArrays(current_primitive_mode, cast(GLint)first, count);
    }
}

draw_instanced :: ($indexed: bool, count: u32, instance_count: u32, first: u32 = 0, first_instance: u32 = 0, base_vertex: s32 = 0) {
    flush_graphics_bindings();
    format := ifx current_index_stride == 4 cast(u32)GL_UNSIGNED_INT else cast(u32)GL_UNSIGNED_SHORT;
    #if indexed {
        glDrawElementsInstancedBaseVertexBaseInstance(current_primitive_mode, count, format, cast(*void)(current_index_stride * first), instance_count, base_vertex, first_instance);
    }
    else {
        glDrawArraysInstancedBaseInstance(current_primitive_mode, first, count, instance_count, first_instance);
    }
}

draw_indirect :: ($indexed: bool, buffer: Buffer(.Indirect), byte_offset: u32 = 0) {
    flush_graphics_bindings();
    glBindBuffer(GL_DRAW_INDIRECT_BUFFER, buffer.object);
    #if indexed {
        format := ifx current_index_stride == 4 cast(u32)GL_UNSIGNED_INT else cast(u32)GL_UNSIGNED_SHORT;
        glDrawElementsIndirect(current_primitive_mode, format, cast(*void)byte_offset);
    }
    else {
        glDrawArraysIndirect(current_primitive_mode, cast(*void)byte_offset);
    }
}


dispatch_compute :: (num_groups_x: u32, num_groups_y: u32, num_groups_z: u32) {
    flush_compute_bindings();
    glDispatchCompute(num_groups_x, num_groups_y, num_groups_z);
    glMemoryBarrier(GL_BUFFER_UPDATE_BARRIER_BIT | GL_SHADER_STORAGE_BARRIER_BIT);
}

dispatch_compute_indirect :: (buffer: Buffer(.Indirect), byte_offset: u32 = 0) {
    flush_compute_bindings();
    glBindBuffer(GL_DISPATCH_INDIRECT_BUFFER, buffer.object);
    glDispatchComputeIndirect(cast(GLintptr)byte_offset);
    glMemoryBarrier(GL_COMMAND_BARRIER_BIT | GL_SHADER_STORAGE_BARRIER_BIT);
}

present :: (interval: u32 = 1) {
    if xx interval != current_swap_interval {
        set_swap_interval(xx interval);
    }

    current_fbo: GLuint;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, cast(*s32)*current_fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    defer glBindFramebuffer(GL_FRAMEBUFFER, current_fbo);

    // Disable when blitting to avoid unwanted gamma correction.
    glDisable(GL_FRAMEBUFFER_SRGB);

    if current_msaa == 1 || (internal_width == window_width && internal_height == window_height) {
        glBlitNamedFramebuffer(
            custom_fbo, 0,
            0, 0, window_width, window_height,
            0, window_height, window_width, 0,
            GL_COLOR_BUFFER_BIT,
            GL_NEAREST // msaa resolve must use nearest
        );
    }
    else { // Slow path if you are rendering at a different resolution with msaa
        glBlitNamedFramebuffer(
            custom_fbo, resolve_fbo,
            0, 0, internal_width, internal_height,
            0, 0, internal_width, internal_height,
            GL_COLOR_BUFFER_BIT,
            GL_NEAREST
        );

        glBlitNamedFramebuffer(
            resolve_fbo, 0,
            0, 0, internal_width, internal_height,
            0, window_height, window_width, 0,
            GL_COLOR_BUFFER_BIT,
            GL_LINEAR
        );
    }

    glEnable(GL_FRAMEBUFFER_SRGB);

    #if OS == .WINDOWS {
        dc := wglGetCurrentDC();
        SwapBuffers(dc);
    }
    else #if OS == .LINUX {
        eglSwapBuffers(egl_display, egl_surface);
    }

}

create_render_target :: (color_textures: []Texture, depth_stencil_texture: Texture, debug_name := "") -> Render_Target {
    render_target: Render_Target;

    draw_buffers := NewArray(color_textures.count, GLenum,, temp);
    glCreateFramebuffers(1, *render_target.framebuffer);

    for color_textures {
        assert(it.flags & .Render_Target != 0, "[Gaco] Color texture used for creating a render target must have Render_Target flag.");
        attachment := GL_COLOR_ATTACHMENT0 + cast(u32)it_index;
        glNamedFramebufferTexture(render_target.framebuffer, attachment, it.object, 0);
        draw_buffers[it_index] = attachment;
    }

    if is_valid(depth_stencil_texture) {
        attachment : GLenum = GL_DEPTH_ATTACHMENT;
        gl_info := GL_TEXTURE_MAP_ARRAY[depth_stencil_texture.format];
        if gl_info.pixel_format == GL_DEPTH_STENCIL {
            attachment = GL_DEPTH_STENCIL_ATTACHMENT;
        }
        glNamedFramebufferTexture(render_target.framebuffer, attachment, depth_stencil_texture.object, 0);
    }

    render_target.color_view_count = cast(u32)draw_buffers.count;
    glNamedFramebufferDrawBuffers(render_target.framebuffer, cast(u32)draw_buffers.count, draw_buffers.data);

    status := glCheckNamedFramebufferStatus(render_target.framebuffer, GL_FRAMEBUFFER);
    if status != GL_FRAMEBUFFER_COMPLETE {
        log_error("[Gaco] Unable to create render target! Status: 0x%", formatInt(status, 16));
        return .{};
    }

    if debug_name  gl_set_debug_name(render_target.framebuffer, GL_FRAMEBUFFER, debug_name);

    return render_target;
}

set_render_target :: (render_target: Render_Target) {
    glBindFramebuffer(GL_FRAMEBUFFER, render_target.framebuffer);
}

destroy_render_target :: (render_target: *Render_Target) {
    glDeleteFramebuffers(1, *render_target.framebuffer);
}

resize :: (width: int, height: int, msaa: u32 = 4, color_format := Texture_Format.RGBA8, depth_format := Texture_Format.D24S8) -> render_target: Render_Target {
    if custom_fbo != 0 {
        glDeleteFramebuffers(1, *custom_fbo);
        glDeleteTextures(1, *custom_color_texture);
        glDeleteRenderbuffers(1, *custom_rbo);

        glDeleteFramebuffers(1, *resolve_fbo);
        glDeleteTextures(1, *resolve_color_texture);
    }

    glCreateFramebuffers(1, *custom_fbo);

    color_info := GL_TEXTURE_MAP_ARRAY[color_format];
    depth_info := GL_TEXTURE_MAP_ARRAY[depth_format];

    if msaa > 1 {
        glCreateTextures(GL_TEXTURE_2D_MULTISAMPLE, 1, *custom_color_texture);
        glTextureStorage2DMultisample(custom_color_texture, msaa, color_info.internal_format, xx width, xx height, GL_TRUE);
    }
    else {
        glCreateTextures(GL_TEXTURE_2D, 1, *custom_color_texture);
        glTextureStorage2D(custom_color_texture, 1, color_info.internal_format, xx width, xx height);
    }

    glNamedFramebufferTexture(custom_fbo, GL_COLOR_ATTACHMENT0, custom_color_texture, 0);

    glCreateRenderbuffers(1, *custom_rbo);
    depth_attachment : GLenum = GL_DEPTH_ATTACHMENT;
    if depth_info.pixel_format == GL_DEPTH_STENCIL {
        depth_attachment = GL_DEPTH_STENCIL_ATTACHMENT;
    }
    glNamedRenderbufferStorageMultisample(custom_rbo, msaa, depth_info.internal_format, xx width, xx height);
    glNamedFramebufferRenderbuffer(custom_fbo, depth_attachment, GL_RENDERBUFFER, custom_rbo);

    glCreateFramebuffers(1, *resolve_fbo);
    glCreateTextures(GL_TEXTURE_2D, 1, *resolve_color_texture);
    glTextureStorage2D(resolve_color_texture, 1, color_info.internal_format, xx width, xx height);
    glNamedFramebufferTexture(resolve_fbo, GL_COLOR_ATTACHMENT0, resolve_color_texture, 0);

    status := glCheckNamedFramebufferStatus(custom_fbo, GL_FRAMEBUFFER);
    if status != GL_FRAMEBUFFER_COMPLETE {
        log_error("[Gaco] FBO is incomplete! Status: %", status);
    }

    glBindFramebuffer(GL_FRAMEBUFFER, custom_fbo);
    glViewport(0, 0, cast(GLuint)width, cast(GLuint)height);

    internal_width = xx width;
    internal_height = xx height;
    _, _, window_width, window_height = get_dimensions(main_window, false);

    #if OS == .LINUX {
        if egl_child_window != 0 {
            XResizeWindow(x_global_display, egl_child_window, xx window_width, xx window_height);
        }
    }

    current_msaa = msaa;

    return .{custom_fbo, 1};
}

create_texture :: (data: []*u8, width: u32, height: u32, array_count_or_depth: u32 = 1, mip_levels_or_msaa: u32 = 1, format := Texture_Format.RGBA8, flags := Texture_Flags.Sampled, debug_name := "") -> Texture {
    generate_mips := (flags & .Generate_Mips) && mip_levels_or_msaa != 1;

    gl_info := GL_TEXTURE_MAP_ARRAY[format];
    if gl_info.internal_format == 0 {
        log_error("[Gaco] Couldn't create texture: Format % is Unknown or unsupported.", format);
        return .{};
    }

    bytes_per_block := TEXTURE_BYTES_PER_BLOCK[format];

    texture := Texture.{
        width = width,
        height = height,
        stride = bytes_per_block,
        depth = array_count_or_depth,
        flags = flags,
        format = format,
    };

    if flags & .Copy {
        size := width * height * bytes_per_block * array_count_or_depth;
        glCreateBuffers(1, *texture.object);
        glNamedBufferStorage(texture.object, size, null, GL_MAP_READ_BIT | GL_MAP_WRITE_BIT | GL_CLIENT_STORAGE_BIT);
        texture.pbo_size = size;
        return texture;
    }

    target: GLenum = GL_TEXTURE_2D;

    is_cube  := (flags & .Cubemap) != 0;
    if is_cube texture.depth /= 6;

    is_array := texture.depth > 1;
    is_3d    := (flags & .Is_3D) != 0;
    is_msaa  := (flags & .Multisample) != 0;

    if is_3d {
        assert(!is_msaa, "[Gaco] MSAA 3D textures are not supported.");
        target = GL_TEXTURE_3D;
    }
    else if is_cube {
        if is_array target = GL_TEXTURE_CUBE_MAP_ARRAY;
        else        target = GL_TEXTURE_CUBE_MAP;
    }
    else if is_array {
        if is_msaa target = GL_TEXTURE_2D_MULTISAMPLE_ARRAY;
        else       target = GL_TEXTURE_2D_ARRAY;
    }
    else {
        if is_msaa target = GL_TEXTURE_2D_MULTISAMPLE;
        else       target = GL_TEXTURE_2D;
    }

    mip_levels := ifx is_msaa 1 else mip_levels_or_msaa;
    if mip_levels == 0 && generate_mips
        mip_levels = max_mip_levels(width, height);

    texture.mip_levels = mip_levels;
    texture.target = target;
    glCreateTextures(target, 1, *texture.object);

    texture.depth = array_count_or_depth;
    if is_msaa {
        if is_array {
            glTextureStorage3DMultisample(texture.object, mip_levels_or_msaa, gl_info.internal_format, width, height, array_count_or_depth, GL_TRUE);
        } else {
            glTextureStorage2DMultisample(texture.object, mip_levels_or_msaa, gl_info.internal_format, width, height, GL_TRUE);
        }
    }
    else {
        if target == GL_TEXTURE_3D || target == GL_TEXTURE_2D_ARRAY || target == GL_TEXTURE_CUBE_MAP_ARRAY {
            glTextureStorage3D(texture.object, mip_levels, gl_info.internal_format, width, height, array_count_or_depth);
        }
        else {
            // GL_TEXTURE_2D, GL_TEXTURE_1D, and GL_TEXTURE_CUBE_MAP use 2D storage
            glTextureStorage2D(texture.object, mip_levels, gl_info.internal_format, width, height);
        }
    }

    if data && !is_msaa {
        mips_to_upload := ifx generate_mips 1 else mip_levels;
        array_count    := ifx is_3d 1 else array_count_or_depth;

        expected_count := array_count * mips_to_upload;
        if data.count < expected_count {
            log_error("[Gaco] Error while creating texture: Incomplete data array. Expected count %, got %.", expected_count, data.count);
            return .{};
        }

        for 0..array_count-1 {
            for mip: 0..mips_to_upload-1 {
                data_index := mip + it * mip_levels;
                pixels := data[data_index];
                if !pixels continue;

                mip_width  := cast(u32)max(1, width >> mip);
                mip_height := cast(u32)max(1, height >> mip);
                mip_depth  := ifx is_3d cast(u32)max(1, array_count_or_depth >> mip) else 1;

                zoffset   := ifx is_3d then 0 else it;
                depth_arg := ifx is_3d then mip_depth else 1;

                if is_block_compression(format) {
                    bw := (mip_width + 3) / 4;
                    bh := (mip_height + 3) / 4;
                    image_size := cast(u32)(bw * bh * bytes_per_block * mip_depth);

                    if target == GL_TEXTURE_2D {
                        glCompressedTextureSubImage2D(texture.object, cast(s32)mip, 0, 0, mip_width, mip_height, gl_info.internal_format, image_size, pixels);
                    }
                    else {
                        glCompressedTextureSubImage3D(texture.object, cast(s32)mip, 0, 0, cast(s32)zoffset, mip_width, mip_height, depth_arg, gl_info.internal_format, image_size, pixels);
                    }
                }
                else {
                    if target == GL_TEXTURE_2D {
                        glTextureSubImage2D(texture.object, cast(s32)mip, 0, 0, mip_width, mip_height, gl_info.pixel_format, gl_info.pixel_type, pixels);
                    }
                    else {
                        glTextureSubImage3D(texture.object, cast(s32)mip, 0, 0, cast(s32)zoffset, mip_width, mip_height, depth_arg, gl_info.pixel_format, gl_info.pixel_type, pixels);
                    }
                }
            }
        }
    }

    glTextureParameteri(texture.object, GL_TEXTURE_MAX_LEVEL, cast(s32)(mip_levels - 1));

    if generate_mips {
        glGenerateTextureMipmap(texture.object);
    }

    if debug_name  gl_set_debug_name(texture.object, GL_TEXTURE, debug_name);

    return texture;
}

bind_texture :: (texture: Texture, slot: u32, bind_to := Shader_Type.Fragment) {
    if texture.flags & .Compute_RW {
        // Compute UAVs don't use samplers so no need to map
        gl_info := GL_TEXTURE_MAP_ARRAY[texture.format];
        glBindImageTexture(slot, texture.object, 0, xx is_target_layered(texture.target), 0, GL_READ_WRITE, gl_info.internal_format);
        return;
    }

    assert(texture.flags & .Sampled != 0, "[Gaco] Texture must have Sampled flag to be bound to a shader.");

    if bind_to & .Vertex   bound_textures[slot + VS_SHIFT] = texture.object;
    if bind_to & .Fragment bound_textures[slot + FS_SHIFT] = texture.object;
    if bind_to & .Compute  bound_textures[slot + CS_SHIFT] = texture.object;
}

copy_texture :: inline (from: Texture, to: *Texture) {
    copy_texture(from, to, .{0, 0, cast(s32)from.width, cast(s32)from.height});
}

copy_texture :: (from: Texture, to: *Texture, source_rect: Rect) {
    if to.flags & .Copy {
        gl_info := GL_TEXTURE_MAP_ARRAY[from.format];

        glBindBuffer(GL_PIXEL_PACK_BUFFER, to.object);
        glGetTextureSubImage(from.object, 0, source_rect.x, source_rect.y, 0, cast(u32)source_rect.width, cast(u32)source_rect.height, 1, gl_info.pixel_format, gl_info.pixel_type, to.pbo_size, null);
        glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);

        if to.fence glDeleteSync(to.fence);
        to.fence = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
    }
    else {
        // @Incomplete: Only 2D textures.
        glCopyImageSubData(from.object, from.target, 0, source_rect.x, source_rect.y, 0, to.object, to.target, 0, 0, 0, 0, cast(u32)source_rect.width, cast(u32)source_rect.height, 1);
    }
}

copy_texture :: (from: Texture, to: *Texture, source_box: Box) {
    if to.flags & .Copy {
        gl_info := GL_TEXTURE_MAP_ARRAY[from.format];

        glBindBuffer(GL_PIXEL_PACK_BUFFER, to.object);
        glPixelStorei(GL_PACK_ALIGNMENT, 1);
        glGetTextureSubImage(
            from.object, 0,
            source_box.x, source_box.y, source_box.z,
            cast(u32)source_box.width, cast(u32)source_box.height, cast(u32)source_box.depth,
            gl_info.pixel_format, gl_info.pixel_type,
            to.pbo_size, null
        );
        glPixelStorei(GL_PACK_ALIGNMENT, 4);
        glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);

        if to.fence glDeleteSync(to.fence);
        to.fence = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
    }
    else {
        glCopyImageSubData(
            from.object, from.target, 0,
            source_box.x, source_box.y, source_box.z,
            to.object, to.target, 0,
            0, 0, 0,
            cast(u32)source_box.width, cast(u32)source_box.height, cast(u32)source_box.depth
        );
    }
}

copy_from_render_target :: (render_target: Render_Target, to: *Texture, index: u32 = 0) {
    src_tex: GLuint = 0;
    samples: GLint = 1;

    if render_target.framebuffer == custom_fbo {
        src_tex = custom_color_texture;
        samples = cast(GLint) current_msaa;
    }
    else {
        attachment := GL_COLOR_ATTACHMENT0 + index;
        glGetNamedFramebufferAttachmentParameteriv(render_target.framebuffer, attachment, GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME, xx *src_tex);
        glGetTextureLevelParameteriv(src_tex, 0, GL_TEXTURE_SAMPLES, *samples);
    }

    needs_resolve := samples > 1;

    final_tex := src_tex;
    temp_fbo: GLuint;

    if needs_resolve {
        glCreateFramebuffers(1, *temp_fbo);
        glCreateTextures(GL_TEXTURE_2D, 1, *final_tex);

        gl_info := GL_TEXTURE_MAP_ARRAY[to.format];
        glTextureStorage2D(final_tex, 1, gl_info.internal_format, to.width, to.height);
        glNamedFramebufferTexture(temp_fbo, GL_COLOR_ATTACHMENT0, final_tex, 0);

        glNamedFramebufferReadBuffer(render_target.framebuffer, GL_COLOR_ATTACHMENT0 + index);

        glBlitNamedFramebuffer(
            render_target.framebuffer, temp_fbo,
            0, 0, xx to.width, xx to.height,
            0, 0, xx to.width, xx to.height,
            GL_COLOR_BUFFER_BIT,
            GL_NEAREST
        );
    }

    defer if needs_resolve {
        glDeleteFramebuffers(1, *temp_fbo);
        glDeleteTextures(1, *final_tex);
    }

    if to.flags & .Copy {
        gl_info := GL_TEXTURE_MAP_ARRAY[to.format];

        glBindBuffer(GL_PIXEL_PACK_BUFFER, to.object);
        glPixelStorei(GL_PACK_ALIGNMENT, 1);

        glGetTextureSubImage(
            final_tex, 0,
            0, 0, 0,
            to.width, to.height, 1,
            gl_info.pixel_format, gl_info.pixel_type,
            to.pbo_size, null
        );

        glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
        glPixelStorei(GL_PACK_ALIGNMENT, 4);

        if to.fence glDeleteSync(to.fence);
        to.fence = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
    }
    else {
        glCopyImageSubData(
            final_tex, GL_TEXTURE_2D, 0, 0, 0, 0,
            to.object, to.target, 0, 0, 0, 0,
            to.width, to.height, 1
        );
    }
}

create_sampler :: (min_filtering: Sampler_Filtering, mag_filtering: Sampler_Filtering, mip_filtering: Sampler_Filtering,
                   u_handling: Sampler_Edge_Handling, v_handling: Sampler_Edge_Handling, w_handling: Sampler_Edge_Handling,
                   border_color := Vector4.{0,0,0,0}, max_anisotropy: u32 = 1, compare_op := Compare_Op.None, debug_name := "") -> Sampler {
    sampler: Sampler;
    glCreateSamplers(1, *sampler.object);

    if compare_op != .None {
        glSamplerParameteri(sampler.object, GL_TEXTURE_COMPARE_MODE, GL_COMPARE_REF_TO_TEXTURE);
        glSamplerParameteri(sampler.object, GL_TEXTURE_COMPARE_FUNC, xx GL_COMPARISON_MAP[compare_op]);
    }

    /*
      GL_NEAREST                :: 0x2600;
      GL_LINEAR                 :: 0x2601;

      GL_NEAREST_MIPMAP_NEAREST :: 0x2700;
      GL_LINEAR_MIPMAP_NEAREST  :: 0x2701;
      GL_NEAREST_MIPMAP_LINEAR  :: 0x2702;
      GL_LINEAR_MIPMAP_LINEAR   :: 0x2703;
    */

    gl_min := cast(GLint) GL_NEAREST_MIPMAP_NEAREST;
    gl_mag := cast(GLint) GL_NEAREST;

    if min_filtering == .Linear gl_min += 1;
    if mag_filtering == .Linear gl_mag += 1;

    if mip_filtering == .Linear gl_min += 2;

    glSamplerParameteri(sampler.object, GL_TEXTURE_MIN_FILTER, gl_min);
    glSamplerParameteri(sampler.object, GL_TEXTURE_MAG_FILTER, gl_mag);
    glSamplerParameterf(sampler.object, GL_TEXTURE_MAX_ANISOTROPY, cast(float) max_anisotropy);

    WRAP_TABLE :: GLint.[GL_REPEAT, GL_MIRRORED_REPEAT, GL_CLAMP_TO_EDGE, GL_CLAMP_TO_BORDER];
    glSamplerParameteri(sampler.object, GL_TEXTURE_WRAP_S, WRAP_TABLE[u_handling]);
    glSamplerParameteri(sampler.object, GL_TEXTURE_WRAP_T, WRAP_TABLE[v_handling]);
    glSamplerParameteri(sampler.object, GL_TEXTURE_WRAP_R, WRAP_TABLE[w_handling]);

    glSamplerParameterfv(sampler.object, GL_TEXTURE_BORDER_COLOR, border_color.component.data);

    if debug_name  gl_set_debug_name(sampler.object, GL_SAMPLER, debug_name);

    return sampler;
}

bind_sampler :: (sampler: Sampler, slot: u32, bind_to := Shader_Type.Fragment) {
    if bind_to & .Vertex   bound_samplers[slot + VS_SHIFT] = sampler.object;
    if bind_to & .Fragment bound_samplers[slot + FS_SHIFT] = sampler.object;
    if bind_to & .Compute  bound_samplers[slot + CS_SHIFT] = sampler.object;
}

destroy_sampler :: (sampler: *Sampler) {
    glDeleteSamplers(1, *sampler.object);
    sampler.object = 0;
}

create_timer :: (debug_name := "") -> Timer {
    timer: Timer;
    glCreateQueries(GL_TIMESTAMP, timer.queries.count, timer.queries.data);
    if debug_name {
        gl_set_debug_name(timer.start_query, GL_QUERY, tprint("%_Start", debug_name));
        gl_set_debug_name(timer.end_query, GL_QUERY, tprint("%_End", debug_name));
    }

    return timer;
}

start_timer :: (timer: *Timer) {
    timer.recording = true;
    glQueryCounter(timer.start_query, GL_TIMESTAMP);
}

stop_timer :: (timer:  *Timer) {
    glQueryCounter(timer.end_query, GL_TIMESTAMP);
}

timer_get_ms :: (timer: *Timer) -> ready: bool, float {
    if !timer.recording return true, 0.0;

    start_timestamp: u64;
    end_timestamp: u64;

    available: GLint = 0;
    glGetQueryObjectiv(timer.end_query, GL_QUERY_RESULT_AVAILABLE, *available);

    if !available return false, 0.0;

    timer.recording = false;
    glGetQueryObjectui64v(timer.start_query, GL_QUERY_RESULT_NO_WAIT, *start_timestamp);
    glGetQueryObjectui64v(timer.end_query, GL_QUERY_RESULT_NO_WAIT, *end_timestamp);

    return true, cast(float)((end_timestamp - start_timestamp).(float64) / 1000000.0);
}

begin_debug_region :: (name: string) {
    #if DEBUG {
        glPushDebugGroup(GL_DEBUG_SOURCE_APPLICATION, 0, cast(GLsizei)name.count, name.data);
    }
}

end_debug_region :: () {
    #if DEBUG {
        glPopDebugGroup();
    }
}

insert_debug_marker :: (name: string) {
    #if DEBUG {
        glDebugMessageInsert(GL_DEBUG_SOURCE_APPLICATION, GL_DEBUG_TYPE_MARKER, 0, GL_DEBUG_SEVERITY_NOTIFICATION, cast(GLsizei)name.count, name.data);
    }
}

#scope_file

set_swap_interval :: (interval: s32) {
    #if OS == .WINDOWS {
        wglSwapIntervalEXT(interval);
    }
    else #if OS == .LINUX {
        eglSwapInterval(egl_display, interval);
    }
    current_swap_interval = interval;
}

get_input_vao_from_spv :: (spv_bytecode: string) -> GLuint {
    #import "Sort";
    module: SpvReflectShaderModule;
    check :: (result: SpvReflectResult) #expand {
        if result != .SUCCESS {
            log_error("[Gaco] SPIR-V shader reflection failed: %", result);
            `return 0;
        }
    }

    Attrib_Type :: enum u8 {
        Float;
        Normalized;
        Int;
        Double;
    }

    spv_to_gl :: (format: SpvReflectFormat) -> type: GLenum, attrib_type: Attrib_Type {
        if format == {
            // 16-bit formats
            case .R16_UINT; #through; case .R16G16_UINT; #through; case .R16G16B16_UINT; #through; case .R16G16B16A16_UINT;
                return GL_UNSIGNED_SHORT, .Int;
            case .R16_SINT; #through; case .R16G16_SINT; #through; case .R16G16B16_SINT; #through; case .R16G16B16A16_SINT;
                return GL_SHORT, .Int;
            case .R16_SFLOAT; #through; case .R16G16_SFLOAT; #through; case .R16G16B16_SFLOAT; #through; case .R16G16B16A16_SFLOAT;
                return GL_HALF_FLOAT, .Float;

            // 32-bit formats
            case .R32_UINT; #through; case .R32G32_UINT; #through; case .R32G32B32_UINT; #through; case .R32G32B32A32_UINT;
                return GL_UNSIGNED_INT, .Int;
            case .R32_SINT; #through; case .R32G32_SINT; #through; case .R32G32B32_SINT; #through; case .R32G32B32A32_SINT;
                return GL_INT, .Int;
            case .R32_SFLOAT; #through; case .R32G32_SFLOAT; #through; case .R32G32B32_SFLOAT; #through; case .R32G32B32A32_SFLOAT;
                return GL_FLOAT, .Float;

            // 64-bit float formats
            case .R64_SFLOAT; #through; case .R64G64_SFLOAT; #through; case .R64G64B64_SFLOAT; #through; case .R64G64B64A64_SFLOAT;
                return GL_DOUBLE, .Double;

            case;
                // This will catch 64-bit ints (which OpenGL VAOs don't handle natively via standard attrib formats)
                // and UNDEFINED formats.
                log_error("[Gaco] Unsupported SPIR-V format mapped to OpenGL VAO: %", format);
                return 0, .Float;
        }
    }

    check(spvReflectCreateShaderModule(cast(u64)spv_bytecode.count, spv_bytecode.data, *module));
    defer spvReflectDestroyShaderModule(*module);

    entry_count: u32;
    check(spvReflectEnumerateEntryPointInputVariables(*module, VS_ENTRY_POINT, *entry_count, null));

    raw_variables := NewArray(entry_count, *SpvReflectInterfaceVariable,, temp);
    check(spvReflectEnumerateEntryPointInputVariables(*module, VS_ENTRY_POINT, *entry_count, raw_variables.data));

    valid_variables: [..] *SpvReflectInterfaceVariable;
    valid_variables.allocator = temp;
    for raw_variables {
        if it.location != 0xFFFF_FFFF {
            array_add(*valid_variables, it);
        }
    }
    quick_sort(valid_variables, x => x.location);

    input_vao: GLuint;
    glCreateVertexArrays(1, *input_vao);

    binding_offsets: [2]u32;

    for valid_variables {
        assert(it.format != .UNDEFINED);
        type, attrib_type := spv_to_gl(it.format);
        if type == 0 {
            glDeleteVertexArrays(1, *input_vao);
            return 0;
        }

        semantic_str := ifx it.semantic then to_string(it.semantic) else {
            name := to_string(it.name);
            advance(name, 7); // "in.var."
        }

        is_instance, step_rate := get_semantic_info(semantic_str);

        binding_index := ifx is_instance cast(GLuint)1 else 0;

        if is_instance {
            glVertexArrayBindingDivisor(input_vao, binding_index, step_rate);
        }

        comps        := ifx it.numeric.vector.component_count else 1;
        row_count    := ifx it.numeric.matrix.row_count else 1;
        scalar_bytes := it.numeric.scalar.width / 8;

        binding_offsets[binding_index] = (binding_offsets[binding_index] + scalar_bytes - 1) & ~(scalar_bytes - 1);

        for j: 0..row_count - 1 {
            loc := it.location + j;

            glEnableVertexArrayAttrib(input_vao, loc);
            if attrib_type == {
                case .Float;      glVertexArrayAttribFormat(input_vao, loc, cast(s32)comps, type, GL_FALSE, binding_offsets[binding_index]);
                case .Normalized; glVertexArrayAttribFormat(input_vao, loc, cast(s32)comps, type, GL_TRUE, binding_offsets[binding_index]);
                case .Int;        glVertexArrayAttribIFormat(input_vao, loc, cast(s32)comps, type, binding_offsets[binding_index]);
                case .Double;     glVertexArrayAttribLFormat(input_vao, loc, cast(s32)comps, type, binding_offsets[binding_index]);
            }

            glVertexArrayAttribBinding(input_vao, loc, binding_index);

            binding_offsets[binding_index] += comps * scalar_bytes;
        }
    }

    return input_vao;
}

VS_SHIFT :: 0;
FS_SHIFT :: 32;
CS_SHIFT :: 64;

VS_SHIFT_STR :: "0";
FS_SHIFT_STR :: "32";
CS_SHIFT_STR :: "64";

// I had to reimplement this function from spirv-opt because OpenGL...
build_combined_image_samplers :: (bytecode: string, stage: Shader_Type, mappings: *[..]Texture_Sampler_Mapping) -> new_bytecode: string {
    if bytecode.count < 20 return "";

    words := cast(*u32) bytecode.data;
    num_words := bytecode.count / 4;

    // Word 3 in the header is the "ID Bound".
    // All SPIR-V IDs are guaranteed to be strictly less than this number.
    // This lets us use simple arrays for lookups.

    id_bound := words[3];

    bindings      := NewArray(id_bound, u32,, temp);       // Result ID -> Binding value
    loads         := NewArray(id_bound, u32,, temp);       // Result ID -> Variable ID it loaded from
    id_remap      := NewArray(id_bound, u32,, temp);       // Old ID -> New ID to replace it with
    deleted_ids   := NewArray(id_bound, bool,, temp);      // IDs marked for deletion
    inst_ptrs     := NewArray(id_bound, [..]u32,, temp);  // ID -> Pointer to instruction data
    binding_insts := NewArray(id_bound, [..]u32,, temp);

    for i: 0..id_bound-1 {
        bindings[i] = 0xFFFF_FFFF;
        loads[i]    = 0;
        id_remap[i] = 0;
        deleted_ids[i] = false;
    }

    instructions: [..] [..]u32;
    instructions.allocator = temp;

    // Parsing the instructions
    i := 5;
    while i < num_words {
        count := words[i] >> 16;
        inst := [..]u32.{allocator=temp};
        array_reserve(*inst, count);
        for w: 0..count-1 array_add(*inst, words[i + w]);

        op := cast(SpvOp) (inst[0] & 0xFFFF);
        if op == {
            case .Decorate;
                decoration := cast(SpvDecoration) inst[2];
                if decoration == .Binding {
                    bindings[inst[1]] = inst[3];
                    binding_insts[inst[1]] = inst; // Save the instruction pointer to edit later
                }

                // SPIR-V produced with spirv_target_env=vulkan1.1 uses VertexIndex/InstanceIndex,
                // but GL_ARB_gl_spirv expects VertexId/InstanceId.
                else if decoration == .BuiltIn {
                    builtin_value := cast(*SpvBuiltIn)*inst[3];
                    if builtin_value.* == .VertexIndex {
                        builtin_value.* = .VertexId;
                    }
                    else if builtin_value.* == .InstanceIndex {
                        builtin_value.* = .InstanceId;
                    }
                }
            case .Load;
                loads[inst[2]] = inst[3];
                inst_ptrs[inst[2]] = inst;
            case .Variable;
                inst_ptrs[inst[2]] = inst;
        }

        array_add(*instructions, inst);
        i += count;
    }

    // Helper: Find an existing Pointer type for our combined SampledImage, or inject a new one.
    get_or_create_ptr_type :: (type_id: u32, insts: *[..] [..]u32, bound: *u32) -> u32 {
        for inst: insts.* {
            op := cast(SpvOp) (inst[0] & 0xFFFF);
            if op == .TypePointer {
                if inst[2] == 0 && inst[3] == type_id return inst[1];
            }
        }
        new_id := bound.*;
        bound.* += 1;
        new_inst := [..]u32.{allocator=temp};
        array_add(*new_inst, (4 << 16) | cast(u32) SpvOp.TypePointer);
        array_add(*new_inst, new_id);
        array_add(*new_inst, 0);
        array_add(*new_inst, type_id);

        // Inject before the first Variable or Function definition
        insert_idx := insts.count;
        for idx: 0..insts.count-1 {
            op := cast(SpvOp) (insts.*[idx][0] & 0xFFFF);
            if op == .Variable || op == .Function {
                insert_idx = idx;
                break;
            }
        }
        array_insert_at(insts, new_inst, insert_idx);
        return new_id;
    }

    // Look for where a separate Texture and Sampler are merged (OpSampledImage).
    // We rewrite the original Texture variable to be a combined SampledImage instead,
    // and delete the separate Sampler.
    for inst: instructions {
        op := cast(SpvOp) (inst[0] & 0xFFFF);

        if op == .SampledImage {
            sampled_img_type := inst[1];
            sampled_img_id   := inst[2];
            image_load_id    := inst[3];
            sampler_load_id  := inst[4];

            image_var_id   := loads[image_load_id];
            sampler_var_id := loads[sampler_load_id];

            img_binding  := bindings[image_var_id];
            samp_binding := bindings[sampler_var_id];

            // If we found a valid pairing, record it and update the SPIR-V binding literal
            if img_binding != 0xFFFF_FFFF && samp_binding != 0xFFFF_FFFF {
                mapped_idx: u8;
                found := false;
                for m: mappings.* {
                    if m.texture_index == cast(u8)img_binding && m.sampler_index == cast(u8)samp_binding {
                        mapped_idx = m.mapped_index;
                        found = true;
                        break;
                    }
                }

                if !found {
                    mapped_idx = cast(u8) mappings.count;
                    mapping: Texture_Sampler_Mapping;
                    mapping.mapped_index  = mapped_idx;
                    mapping.texture_index = cast(u8) img_binding;
                    mapping.sampler_index = cast(u8) samp_binding;
                    mapping.stage         = stage;
                    array_add(mappings, mapping);
                }

                // Overwrite the original Texture's SPIR-V OpDecorate Binding with the new mapped binding slot
                decorate_inst := binding_insts[image_var_id];
                if decorate_inst {
                    decorate_inst[3] = cast(u32) mapped_idx;
                }
            }

            // Route all future usages of this combined image back to the texture's load ID
            id_remap[sampled_img_id] = image_load_id;

            // Change the Texture Variable's type to pointer-to-SampledImage
            ptr_type := get_or_create_ptr_type(sampled_img_type, *instructions, *id_bound);
            var_inst := inst_ptrs[image_var_id];
            if var_inst var_inst[1] = ptr_type;

            // Change all OpLoads of this texture variable to return a SampledImage
            for ptr: instructions {
                if cast(SpvOp) (ptr[0] & 0xFFFF) == .Load {
                    if ptr[3] == image_var_id ptr[1] = sampled_img_type;
                }
            }

            // Mark the Sampler definitions and the OpSampledImage itself for deletion (.Nop)
            inst[0] = 0;
            if sampler_var_id && inst_ptrs[sampler_var_id]   inst_ptrs[sampler_var_id][0] = 0;
            if sampler_load_id && inst_ptrs[sampler_load_id] inst_ptrs[sampler_load_id][0] = 0;

            deleted_ids[sampler_var_id] = true;
            deleted_ids[sampler_load_id] = true;
        }
    }


    // If we leave OpNames or OpDecorates pointing to deleted samplers, validation will fail.
    for inst: instructions {
        op := cast(SpvOp) (inst[0] & 0xFFFF);

        if op == .Name || op == .Decorate {
            target_id := inst[1];
            if target_id < deleted_ids.count && deleted_ids[target_id] {
                inst[0] = 0; // Nop it out
            }
        }
    }

    // TODO(Yasin): Handle standalone textures (used with .Load())

    // Reconstruct the flat bytecode, skipping Nops and rewiring usages.
    out: [..]u32;
    for w: 0..4 array_add(*out, words[w]);
    out[3] = id_bound;

    for inst: instructions {
        op := cast(SpvOp) (inst[0] & 0xFFFF);

        if op == .Nop continue;

        // Safely remap IDs only where we guarantee they are IDs, not literal numbers.
        // For texture sampling, Word 3 is always the target SampledImage ID.
        if (op >= .ImageSampleImplicitLod && op <= .ImageDrefGather) || op == .Image {
            if inst.count > 3 {
                id := inst[3];
                if id < id_remap.count && id_remap[id] != 0 {
                    inst[3] = id_remap[id];
                }
            }
        }

        for w: 0..inst.count-1 array_add(*out, inst[w]);
    }


    new_bytecode: string;
    new_bytecode.data  = cast(*u8) out.data;
    new_bytecode.count = out.count * size_of(u32);

    return new_bytecode;
}

flush_resource_bindings :: (mappings: []Texture_Sampler_Mapping, stage: Shader_Type) {
    stage_index := 0;
    shift: u8 = VS_SHIFT;

    if stage == {
        case .Fragment;
            stage_index = 1;
            shift = FS_SHIFT;
        case .Compute;
            stage_index = 2;
            shift = CS_SHIFT;
    }

    for mappings {
        if it.stage != stage continue;

        unit := it.mapped_index;

        texture_object  := bound_textures[it.texture_index];

        glBindTextureUnit(cast(GLuint)unit, texture_object);

        if it.sampler_index != Texture_Sampler_Mapping.NO_SAMPLER {
            sampler_object := bound_samplers[it.sampler_index];

            // Use the default sampler if the user didn't specify it
            if sampler_object == 0
                sampler_object = default_sampler.object;

            glBindSampler(cast(GLuint)unit, sampler_object);
        }

    }
}

flush_graphics_bindings :: () {
    if vs_mappings flush_resource_bindings(vs_mappings, .Vertex);
    if fs_mappings flush_resource_bindings(fs_mappings, .Fragment);
}

flush_compute_bindings :: () {
    if cs_mappings flush_resource_bindings(cs_mappings, .Compute);
}

gl_map_buffer :: inline (object: GLuint, size: u32, flags: Map_Flags, $copy: bool, fence: GLsync) -> *void, busy: bool {
    if flags & .Non_Blocking && fence {
        status := glClientWaitSync(fence, 0, 0);
        if status == GL_TIMEOUT_EXPIRED {
            return null, true;
        }
        if status == GL_WAIT_FAILED {
            log_error("[Gaco] glClientWaitSync failed.");
            return null, false;
        }
    }

    access: GLbitfield;
    if flags & .Read  access |= GL_MAP_READ_BIT;
    if flags & .Write {
        access |= GL_MAP_WRITE_BIT;
        if flags & .Non_Blocking access |= GL_MAP_UNSYNCHRONIZED_BIT;
        #if !copy access |= GL_MAP_INVALIDATE_BUFFER_BIT;
    }

    ptr := glMapNamedBufferRange(object, 0, size, access);
    if !ptr {
        log_error("[Gaco] Couldn't map object!");
        return null, false;
    }

    return ptr, false;
}

is_target_layered :: (target: GLenum) -> bool {
    return target == GL_TEXTURE_2D_ARRAY
        || target == GL_TEXTURE_3D
        || target == GL_TEXTURE_CUBE_MAP
        || target == GL_TEXTURE_CUBE_MAP_ARRAY
        || target == GL_TEXTURE_2D_MULTISAMPLE_ARRAY;
}

MAX_SLOTS :: 96;
using GL_State: struct {
    main_window: Window_Type;

    internal_width, internal_height: s32;
    window_width, window_height: s32;
    current_msaa: u32;
    current_swap_interval: s32;

    custom_fbo: GLuint;
    custom_color_texture: GLuint;
    custom_rbo: GLuint;

    // Sigh...
    resolve_fbo: GLuint;
    resolve_color_texture: GLuint;

    global_pipeline: GLuint;
    empty_stupid_vao: GLuint; // Because we cannot bind a vertex buffer without a vao

    #if OS == .LINUX {
        egl_display: EGLDisplay;
        egl_surface: EGLSurface;
        egl_child_window: Window;
    }

    Bound_Buffer :: struct {
        object: GLuint;
        stride: u32;
        offset: u32;
    }

    bound_vertex_buffer: Bound_Buffer;
    bound_instance_buffer: Bound_Buffer;
    bound_index_buffer: GLuint;

    current_primitive_mode: GLuint = GL_TRIANGLES;
    current_index_stride: u32;

    vs_mappings: []Texture_Sampler_Mapping;
    fs_mappings: []Texture_Sampler_Mapping;
    cs_mappings: []Texture_Sampler_Mapping;

    bound_textures: [MAX_SLOTS] GLuint;
    bound_samplers: [MAX_SLOTS] GLuint;

    default_sampler: Sampler;
}

GL_Format_Info :: struct {
    internal_format : u32;
    pixel_format   : u32;
    pixel_type     : u32;
}


#assert GL_TEXTURE_MAP_ARRAY.count == enum_count(Texture_Format);
GL_TEXTURE_MAP_ARRAY :: GL_Format_Info.[
    .{ GL_NONE, 0, 0 }, // Unknown

    // Fixed point formats
    .{ GL_R8,             GL_RED,  GL_UNSIGNED_BYTE },                  // R8
    .{ GL_RG8,            GL_RG,   GL_UNSIGNED_BYTE },                  // RG8
    .{ GL_RGBA8,          GL_RGBA, GL_UNSIGNED_BYTE },                  // RGBA8
    .{ GL_SRGB8_ALPHA8,   GL_RGBA, GL_UNSIGNED_BYTE },                  // RGBA8_SRGB
    .{ GL_RGBA8,          GL_BGRA, GL_UNSIGNED_BYTE },                  // BGRA8
    .{ GL_SRGB8_ALPHA8,   GL_BGRA, GL_UNSIGNED_BYTE },                  // BGRA8_SRGB
    .{ GL_RGB565,         GL_RGB,  GL_UNSIGNED_SHORT_5_6_5 },           // B5G6R5
    .{ GL_RGB10_A2,       GL_RGBA, GL_UNSIGNED_INT_2_10_10_10_REV },    // RGB10A2
    .{ GL_R16,            GL_RED,  GL_UNSIGNED_SHORT },                 // R16

    // Floating point formats
    .{ GL_R16F,     GL_RED,  GL_HALF_FLOAT },                           // R16F
    .{ GL_RG16F,    GL_RG,   GL_HALF_FLOAT },                           // RG16F
    .{ GL_RGBA16F,  GL_RGBA, GL_HALF_FLOAT },                           // RGBA16F
    .{ GL_R32F,     GL_RED,  GL_FLOAT },                                // R32F
    .{ GL_RG32F,    GL_RG,   GL_FLOAT },                                // RG32F
    .{ GL_RGBA32F,  GL_RGBA, GL_FLOAT },                                // RGBA32F
    .{ GL_R11F_G11F_B10F, GL_RGB, GL_UNSIGNED_INT_10F_11F_11F_REV},     // RG11B10F
    .{ GL_RGB9_E5,  GL_RGB,  GL_UNSIGNED_INT_5_9_9_9_REV },             // RGB9E5F

    // Integer formats
    .{ GL_R16I,     GL_RED_INTEGER,  GL_SHORT },                        // R16I
    .{ GL_RG16I,    GL_RG_INTEGER,   GL_SHORT },                        // RG16I
    .{ GL_RGBA16I,  GL_RGBA_INTEGER, GL_SHORT },                        // RGBA16I
    .{ GL_R32I,     GL_RED_INTEGER,  GL_INT },                          // R32I
    .{ GL_RG32I,    GL_RG_INTEGER,   GL_INT },                          // RG32I
    .{ GL_RGB32I,   GL_RGB_INTEGER,  GL_INT },                          // RGB32I
    .{ GL_RGBA32I,  GL_RGBA_INTEGER, GL_INT },                          // RGBA32I

    // Unsigned integer formats
    .{ GL_R16UI,    GL_RED_INTEGER,  GL_UNSIGNED_SHORT },               // R16U
    .{ GL_RG16UI,   GL_RG_INTEGER,   GL_UNSIGNED_SHORT },               // RG16U
    .{ GL_RGBA16UI, GL_RGBA_INTEGER, GL_UNSIGNED_SHORT },               // RGBA16U
    .{ GL_R32UI,    GL_RED_INTEGER,  GL_UNSIGNED_INT },                 // R32U
    .{ GL_RG32UI,   GL_RG_INTEGER,   GL_UNSIGNED_INT },                 // RG32U
    .{ GL_RGB32UI,  GL_RGB_INTEGER,  GL_UNSIGNED_INT },                 // RGB32U
    .{ GL_RGBA32UI, GL_RGBA_INTEGER, GL_UNSIGNED_INT },                 // RGBA32U

    // Block compression formats
    .{ GL_COMPRESSED_RGB_BPTC_UNSIGNED_FLOAT, 0, 0 },                   // BC6U
    .{ GL_COMPRESSED_RGB_BPTC_SIGNED_FLOAT,   0, 0 },                   // BC6S
    .{ GL_COMPRESSED_RGBA_BPTC_UNORM,         0, 0 },                   // BC7
    .{ GL_COMPRESSED_SRGB_ALPHA_BPTC_UNORM,   0, 0 },                   // BC7_SRGB

    // Depth formats
    .{ GL_DEPTH_COMPONENT16, GL_DEPTH_COMPONENT, GL_UNSIGNED_SHORT },                // D16
    .{ GL_DEPTH24_STENCIL8,  GL_DEPTH_STENCIL,   GL_UNSIGNED_INT_24_8 },             // D24S8
    .{ GL_DEPTH_COMPONENT32F,GL_DEPTH_COMPONENT, GL_FLOAT },                         // D32F
    .{ GL_DEPTH32F_STENCIL8, GL_DEPTH_STENCIL,   GL_FLOAT_32_UNSIGNED_INT_24_8_REV } // D32FS8
];

#assert GL_COMPARISON_MAP.count == enum_count(Compare_Op);
GL_COMPARISON_MAP :: GLenum.[GL_NONE, GL_NEVER, GL_LESS, GL_EQUAL, GL_LEQUAL, GL_GREATER, GL_NOTEQUAL, GL_GEQUAL, GL_ALWAYS];

#assert GL_STENCIL_OP_MAP.count == enum_count(Stencil_Op);
GL_STENCIL_OP_MAP :: GLenum.[GL_NONE, GL_KEEP, GL_ZERO, GL_REPLACE, GL_INCR, GL_DECR, GL_INVERT, GL_INCR_WRAP, GL_DECR_WRAP];

#assert GL_BLEND_MAP.count == enum_count(Blend);
GL_BLEND_MAP :: GLenum.[
    GL_ZERO,
    GL_ONE,
    GL_SRC_COLOR,
    GL_ONE_MINUS_SRC_COLOR,
    GL_SRC_ALPHA,
    GL_ONE_MINUS_SRC_ALPHA,
    GL_DST_ALPHA,
    GL_ONE_MINUS_DST_ALPHA,
    GL_DST_COLOR,
    GL_ONE_MINUS_DST_COLOR,
    GL_SRC_ALPHA_SATURATE,
    GL_CONSTANT_COLOR,
    GL_ONE_MINUS_CONSTANT_COLOR,
    GL_SRC1_COLOR,
    GL_ONE_MINUS_SRC1_COLOR,
    GL_SRC1_ALPHA,
    GL_ONE_MINUS_SRC1_ALPHA,
];

#assert GL_BLEND_OP_MAP.count == enum_count(Blend_Op);
GL_BLEND_OP_MAP :: GLenum.[
    GL_NONE,
    GL_FUNC_ADD,
    GL_FUNC_SUBTRACT,
    GL_FUNC_REVERSE_SUBTRACT,
    GL_MIN,
    GL_MAX,
];

#assert GL_FILL_MODE_MAP.count == enum_count(Fill_Mode);
GL_FILL_MODE_MAP :: GLenum.[
    0,0,
    GL_LINE,
    GL_FILL,
];

#assert GL_CULL_MODE_MAP.count == enum_count(Cull_Mode);
GL_CULL_MODE_MAP :: GLenum.[
    0,
    GL_NONE,
    GL_FRONT,
    GL_BACK,
];

#if DEBUG {
gl_debug_callback :: (source: GLenum, type: GLenum, id: GLuint, severity: GLenum, length: GLsizei, message: *u8, userParam: *void) #c_call {
    push_context,defer_pop;

    if source != GL_DEBUG_SOURCE_APPLICATION && type != GL_DEBUG_TYPE_OTHER && type != GL_DEBUG_TYPE_UNDEFINED_BEHAVIOR {
        error := type == GL_DEBUG_TYPE_ERROR;
        flags := ifx error Log_Flags.ERROR else .WARNING;
        message_str := string.{length, message};

        log("[Gaco] %", message_str, flags=flags);
        if error {
            debug_break();
        }
    }
}

}

gl_set_debug_name :: (id: GLuint, type: GLenum, name: string) {
    #if DEBUG {
        if id == 0 return;
        glObjectLabel(type, id, cast(GLsizei) name.count, name.data);
    }
}

#if OS == .WINDOWS {

wgl_create_compute_context :: (major: s32, minor: s32, debug: bool) {
    #import "Windows_Utf8";
    hInstance := GetModuleHandleW(null);

    wc: WNDCLASSEXW;
    wc.lpfnWndProc   = DefWindowProcA;
    wc.hInstance     = hInstance;
    wc.lpszClassName = utf8_to_wide("DummyGLCompute",, temp);
    wc.style         = CS_OWNDC;
    wc.cbSize        = size_of(WNDCLASSEXW);
    RegisterClassExW(*wc);

    hwnd := CreateWindowExW(
        0, wc.lpszClassName, utf8_to_wide("GL Compute",, temp),
        0, 0, 0, 1, 1,
        null, null, hInstance, null
    );
    hdc := GetDC(hwnd);

    pfd: PIXELFORMATDESCRIPTOR;
    pfd.nSize      = size_of(PIXELFORMATDESCRIPTOR);
    pfd.nVersion   = 1;
    pfd.dwFlags    = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL;
    pfd.iPixelType = PFD_TYPE_RGBA;
    pfd.cColorBits = 32;

    pf := ChoosePixelFormat(hdc, *pfd);
    SetPixelFormat(hdc, pf, *pfd);

    dummy_ctx := wglCreateContext(hdc);
    wglMakeCurrent(hdc, dummy_ctx);

    wglCreateContextAttribsARB: (hdc: HDC, hShareContext : HGLRC, attribList : *s32)->HGLRC #c_call;
    wglCreateContextAttribsARB = xx wglGetProcAddress("wglCreateContextAttribsARB");

    attribs: [9] s32;
    idx := 0;
    attribs[idx] = WGL_CONTEXT_MAJOR_VERSION_ARB; idx += 1;
    attribs[idx] = major;                         idx += 1;
    attribs[idx] = WGL_CONTEXT_MINOR_VERSION_ARB; idx += 1;
    attribs[idx] = minor;                         idx += 1;
    attribs[idx] = WGL_CONTEXT_PROFILE_MASK_ARB;  idx += 1;
    attribs[idx] = WGL_CONTEXT_CORE_PROFILE_BIT_ARB; idx += 1;

    if debug {
        attribs[idx] = WGL_CONTEXT_FLAGS_ARB;       idx += 1;
        attribs[idx] = WGL_CONTEXT_DEBUG_BIT_ARB;   idx += 1;
    }
    attribs[idx] = 0;

    compute_ctx := wglCreateContextAttribsARB(hdc, null, attribs.data);
    wglMakeCurrent(hdc, compute_ctx);
    wglDeleteContext(dummy_ctx);
}

}
else #if OS == .LINUX {

egl_create_context :: (window: Window_Type, major: s32, minor: s32, debug: bool) {
    assert(x_global_display != null);
    egl_display = eglGetDisplay(cast(EGLNativeDisplayType) x_global_display);

    if egl_display == EGL_NO_DISPLAY {
        log_error("[Gaco] Failed to get EGL display. Error: 0x%", formatInt(eglGetError(), 16));
        return;
    }

    if !eglInitialize(egl_display, null, null) {
        log_error("[Gaco] Failed to initialize EGL. Error: 0x%", formatInt(eglGetError(), 16));
        return;
    }

    if !eglBindAPI(EGL_OPENGL_API) {
        log_error("[Gaco] Failed to bind OpenGL API. Error: 0x%", formatInt(eglGetError(), 16));
        return;
    }

    attribs := EGLint.[
        EGL_SURFACE_TYPE,    EGL_WINDOW_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT,
        EGL_RED_SIZE,        8,
        EGL_GREEN_SIZE,      8,
        EGL_BLUE_SIZE,       8,
        EGL_DEPTH_SIZE,      24,
        EGL_NONE
    ];

    chosen_config: EGLConfig;
    num_configs: EGLint;
    if !eglChooseConfig(egl_display, attribs.data, *chosen_config, 1, *num_configs) || num_configs == 0 {
        log_error("[Gaco] Failed to choose EGLConfig.");
        return;
    }

    target_window := cast(Window) window;

    if window != WT.INVALID_WINDOW {
        egl_visual_id: EGLint;
        eglGetConfigAttrib(egl_display, chosen_config, EGL_NATIVE_VISUAL_ID, *egl_visual_id);

        vinfo_template: XVisualInfo;
        vinfo_template.visualid = cast(VisualID) egl_visual_id;
        num_visuals: s32;
        VisualIDMask :: 0x1;
        vinfo := XGetVisualInfo(x_global_display, VisualIDMask, *vinfo_template, *num_visuals);

        if !vinfo {
            log_error("[Gaco] Failed to get XVisualInfo for EGL Visual ID 0x%.", formatInt(egl_visual_id, 16));
            return;
        }

        win_attrs: XWindowAttributes;
        XGetWindowAttributes(x_global_display, target_window, *win_attrs);

        swa: XSetWindowAttributes;
        swa.colormap = XCreateColormap(x_global_display, target_window, vinfo.visual, AllocNone);
        swa.event_mask = StructureNotifyMask;

        // We have to create a child window because the window created with create_window isn't compatible with EGL
        // on certain GPUs.
        // This doesn't seem to have much performance degradation according to my testing.
        egl_child_window = XCreateWindow(
            x_global_display,
            target_window,
            0, 0,
            cast(u32) win_attrs.width,
            cast(u32) win_attrs.height,
            0,
            vinfo.depth,
            InputOutput,
            vinfo.visual,
            cast(u64) (CWColormap | CWEventMask),
            *swa
        );

        XMapWindow(x_global_display, egl_child_window);
        XFree(vinfo);

        target_window = egl_child_window;
    }

    context_attribs: [9] EGLint;
    idx := 0;

    context_attribs[idx] = EGL_CONTEXT_MAJOR_VERSION;            idx += 1;
    context_attribs[idx] = major;                                idx += 1;
    context_attribs[idx] = EGL_CONTEXT_MINOR_VERSION;            idx += 1;
    context_attribs[idx] = minor;                                idx += 1;
    context_attribs[idx] = EGL_CONTEXT_OPENGL_PROFILE_MASK;      idx += 1;
    context_attribs[idx] = EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT;  idx += 1;

    if debug {
        context_attribs[idx] = EGL_CONTEXT_FLAGS_KHR;             idx += 1;
        context_attribs[idx] = EGL_CONTEXT_OPENGL_DEBUG_BIT_KHR;  idx += 1;
    }

    context_attribs[idx] = EGL_NONE;

    egl_context := eglCreateContext(egl_display, chosen_config, EGL_NO_CONTEXT, context_attribs.data);
    if !egl_context {
        log_error("[Gaco] Failed to create EGL context. Error: 0x%", formatInt(eglGetError(), 16));
        return;
    }

    egl_surface = EGL_NO_SURFACE;
    if window != WT.INVALID_WINDOW {
        egl_surface = eglCreateWindowSurface(egl_display, chosen_config, cast(EGLNativeWindowType) target_window, null);
        if !egl_surface {
            log_error("[Gaco] Failed to create window egl_surface. Error: 0x%", formatInt(eglGetError(), 16));
            return;
        }
    }

    if !eglMakeCurrent(egl_display, egl_surface, egl_surface, egl_context) {
        log_error("[Gaco] Failed to make EGL context current. Error: 0x%", formatInt(eglGetError(), 16));
        return;
    }
}

}

#import "GL";

#if OS == .WINDOWS {
    #import "Windows";
}
else #if OS == .LINUX {
    #import "X11";
}

#import "Window_Creation";
