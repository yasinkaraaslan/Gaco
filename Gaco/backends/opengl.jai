// TODO(Yasin): Use a seperate framebuffer from the back buffer.

Shader :: struct {
    type: Shader_Type;
    input_vao: GLuint;
    program: GLuint; // This is a 'seperable' program that contains the shaders specified with type.
}

Buffer :: struct (type: Buffer_Type) {
    object: GLuint;
    size: u32;
    stride: u32;
    // ...
}

Sampler :: struct {
    object: GLuint;
}

Texture :: struct {
    object: GLuint;
    pixel_format: GLuint;
    pixel_type: GLuint;
    width, height, stride: u32;
    depth: u32 = 1;
    flags: Texture_Flags;
    pbo_size: u32;
}

Render_Target :: struct {
    framebuffer: GLuint;
    color_view_count: u32;
}

Blend_State :: struct {
    enabled: bool;
    src_blend: GLenum;
    dst_blend: GLenum;
    src_blend_alpha: GLenum;
    dst_blend_alpha: GLenum;

    blend_op: GLenum;
    blend_op_alpha: GLenum;

    red: GLboolean;
    green: GLboolean;
    blue: GLboolean;
    alpha: GLboolean;
}

Rasterizer_State :: struct {
    polygon_mode: GLenum;
    cull_mode: GLenum;
    scissor_enabled: bool;
}

Depth_Stencil_State :: struct {
    depth_enabled: bool;
    depth_write_mask: GLboolean;
    depth_func: GLenum;

    stencil_enabled: bool;
    // @Incomplete: Add the rest of the stencil fields here.
}

is_empty :: (texture: Texture) -> bool {
    return glIsTexture(texture.object) == GL_FALSE;
}

is_empty :: (using shader: Shader) -> bool {
    empty_vao := glIsVertexArray(input_vao) == GL_TRUE;

    return type == .Unspecified || glIsProgram(program) || (!empty_vao && type & .Vertex);
}

is_empty :: (render_target: Render_Target) -> bool {
    // 0 is actually a valid id (window back buffer) but we hope that the user doesn't check that :)
    return render_target.framebuffer != 0;
}

init :: (window: WT.Window_Type, wanted_msaa: u32 = 4) {
    // TODO(Yasin): Replace this with our own procedure so we can use stencil buffers.
    gl_create_context(window, 4, 6, false, DEBUG, cast(s32)wanted_msaa);
    gl_load(*gl);

    major, minor := gl_get_version();
    if major < 4 || minor < 5 { // We support 4.5
        log_error("[Gaco] Unsupported GL version: %.%, need at least 4.5", major, minor);
    }

    main_window = window;

    #if DEBUG {
        // D3D11 crashes on errors (because there is no way to register a callback...)
        // so we do the same thing here to be compatible, is this a good idea?
        gl_enable_debug_output(break_on_error=true);
    }
    glFrontFace(GL_CW); // We use clockwise for both OpenGL and D3D11
    glClipControl(GL_LOWER_LEFT, GL_ZERO_TO_ONE);


    // So we can bind vertex buffers without setting a shader.
    glCreateVertexArrays(1, *empty_stupid_vao);
    glBindVertexArray(empty_stupid_vao);

    glCreateProgramPipelines(1, *global_pipeline);
    glBindProgramPipeline(global_pipeline);
    init_preloaded_modes();

    default_sampler = create_sampler(); // To be the same with d3d11
    for 0..47 {
        bind_sampler(default_sampler, cast(u32)it);
    }
}

deinit :: () {
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
        // @Incomplete
    }
    else {
        #assert false;
    }
    glDeleteProgramPipelines(1, *global_pipeline);
    glDeleteVertexArrays(1, *empty_stupid_vao);
    destroy_sampler(*default_sampler);
}

create_buffer :: (data: *void, count: u32, stride: u32, $type: Buffer_Type, usage := Buffer_Usage.Default) -> Buffer(type) {
    buffer: Buffer(type);
    buffer.size = count * stride;
    buffer.stride = stride;

    // D3D11 also doesn't allow it.
    assert(count > 0 && stride > 0, "Creating a buffer with 0 size is not permitted");

    glCreateBuffers(1, *buffer.object);
    storage_flags: GLbitfield;

    #if type == .Copy {
        storage_flags |= GL_MAP_READ_BIT;
    }

    if usage == {
    case .Dynamic;
        storage_flags |= GL_MAP_WRITE_BIT;
        #through;
    case .Default;
        storage_flags |= GL_DYNAMIC_STORAGE_BIT;
    }

    glNamedBufferStorage(buffer.object, buffer.size, data, storage_flags);
    return buffer;
}
bind_buffer :: (buffer: Buffer(.Vertex), slot: u32 = 0, offset: u32 = 0) {
    glBindVertexBuffer(slot, buffer.object, offset, buffer.stride);
}

bind_buffer :: (buffer: Buffer(.Index)) {
    // assert(buffer.stride == 2 || buffer.stride == 4);
    current_index_stride = buffer.stride;
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, buffer.object);
}

bind_buffer :: (buffer: Buffer(.Constant), slot: u32 = 0, bind_to: Shader_Type) {
    if bind_to & .Vertex
        glBindBufferBase(GL_UNIFORM_BUFFER, slot, buffer.object);

    if bind_to & .Fragment
        glBindBufferBase(GL_UNIFORM_BUFFER, slot + 16, buffer.object);

    if bind_to & .Compute
        glBindBufferBase(GL_UNIFORM_BUFFER, slot + 32, buffer.object);

}

bind_buffer :: (buffer: Buffer(.Structured), slot: u32 = 0, bind_to: Shader_Type) {
    if bind_to & .Vertex
        glBindBufferBase(GL_SHADER_STORAGE_BUFFER, slot, buffer.object);
    if bind_to & .Fragment
        glBindBufferBase(GL_SHADER_STORAGE_BUFFER, slot+16, buffer.object);
    if bind_to & .Compute
        glBindBufferBase(GL_SHADER_STORAGE_BUFFER, slot+32, buffer.object);
}

// Same as above
bind_buffer :: (buffer: Buffer(.RWStructured), slot: u32 = 0) {
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, slot, buffer.object);
}

map_buffer :: (buffer: *Buffer, flags: Map_Flags) -> *void {
    access: GLbitfield;

    if flags & .Read {
        access |= GL_MAP_READ_BIT;
    }

    if flags & .Write {
        access |= GL_MAP_WRITE_BIT;
        #if buffer.type != .Copy {
            access |= GL_MAP_INVALIDATE_BUFFER_BIT;
        }
    }
    return glMapNamedBufferRange(buffer.object, 0, buffer.size, access);
}

unmap_buffer :: (buffer: *Buffer) {
    if glUnmapNamedBuffer(buffer.object) == GL_FALSE {
        log_error("[Gaco] Couldn't unmap buffer!");
    }
}

// This is actually here for api compatibility with D3D11.
// The 'Texture' we have here is a pixel buffer object. So we assert that before doing anything.

// Note that this gives a different data than the D3D11 one because the lower-left is 0,0 as opposed to upper-left.
// You have to check the backend when using it.
map_texture :: (texture: *Texture, flags: Map_Flags) -> *void {
    assert(texture.flags & .Copy != 0, "Only copy buffers can be mapped to read.");
    access: GLbitfield;
    if flags & .Read  access |= GL_MAP_READ_BIT;
    if flags & .Write access |= GL_MAP_WRITE_BIT;
    return glMapNamedBufferRange(texture.object, 0, texture.pbo_size, access);
}

unmap_texture :: (texture: *Texture) {
    assert(texture.flags & .Copy != 0);
    if glUnmapNamedBuffer(texture.object) == GL_FALSE {
        log_error("[Gaco] Couldn't unmap texture!");
    }
}

update_buffer :: (buffer: *Buffer, data: *void) {
    glNamedBufferSubData(buffer.object, 0, buffer.size, data);
}

update_texture :: (texture: *Texture, data: *void, rect: Rect, subresource: u32 = 0) {
    glPixelStorei(GL_UNPACK_ALIGNMENT, cast(s32)texture.stride);
    // @Incomplete: This is wrong for texture arrays
    glTextureSubImage2D(texture.object, cast(s32)subresource, rect.x, rect.y, cast(u32)rect.width, cast(u32)rect.height, texture.pixel_format, texture.pixel_type, data);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
}

// update_texture :: (texture: *Texture, data: *void, box: Box, subresource: u32 = 0) {
// }

update_texture :: inline (using texture: *Texture, data: *void, subresource: u32 = 0) {
    update_texture(texture, data, .{0, 0, cast(s32)width, cast(s32)height}, subresource);
}

write_buffer :: (buffer: *Buffer, data: *void, size: int) {
    mapped_data := map_buffer(buffer, .Write);
    memcpy(mapped_data, data, size);
    unmap_buffer(buffer);
}

copy_buffer :: (from: Buffer, to: *Buffer) {
    glCopyNamedBufferSubData(from.object, to.object, 0, 0, from.size);
}

destroy_buffer :: (buffer: *Buffer) {
    glDeleteBuffers(1, *buffer.object);
    buffer.object = 0;
}

destroy_texture :: (texture: *Texture) {
    glDeleteTextures(1, *texture.object);
    texture.object = 0;
}

destroy_shader :: (shader: *Shader) {
    glDeleteProgram(shader.program);
    shader.program = 0;
    if shader.type & .Vertex {
        glDeleteVertexArrays(1, *shader.input_vao);
        shader.input_vao = 0;
    }
}

compile_shader_to_bytecode :: (source: string, type: Shader_Type, shader_name: string) -> Shader_Bytecode, bool {
    bytecode: Shader_Bytecode;
    dxc_shader_type: DXC.Shader_Type;
    args: DXC.Dxc_Shader_Compiler_Args;
    args.shader_name = shader_name;
    args.shader_model_version = "6_0";
    args.shader_source = source;
    args.add_debug_info = DEBUG;
    args.spirv_target_env = "vulkan1.1";

    compile :: (entry_point: string, shader_type: DXC.Shader_Type) -> string #expand {
        `args.entry_point = entry_point;
        `args.shader_type = shader_type;
        extra_args: [..]string;
        extra_args.allocator = temp;

        array_add(*extra_args, "-fspv-flatten-resource-arrays", "-fspv-reflect");
        shift_args := string.[
            "-fvk-t-shift", "0", "all",
            "-fvk-b-shift", "0", "all",
            "-fvk-s-shift", "0", "all",
            "-fvk-u-shift", "0", "all",
        ];
        shift_amount: string;
        if shader_type == {
        case .Vertex;
        case .Fragment;
            shift_amount = "16";
        case .Compute;
            shift_amount = "32";
        }
        if shift_amount {
            for 0..3 {
                shift_args[3*it+1] = shift_amount;
            }
            array_add(*extra_args, ..shift_args);
        }

        `args.extra_args = extra_args;

        result := DXC.DXC_Compile(`args);
        if !result {
            `return .{}, false;
        }
        `args.extra_args = .[];
        return cast(string)result;
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

    return bytecode, true;
}

load_shader_from_bytecode :: (bytecode: Shader_Bytecode, type: Shader_Type) -> Shader {
    shader: Shader;

    load :: (shader_type: GLenum, binary: string, entry_point: string) -> GLuint #expand {
        s := glCreateShader(shader_type);
        glShaderBinary(1, *s, GL_SHADER_BINARY_FORMAT_SPIR_V, binary.data, cast(u32)binary.count);
        glSpecializeShader(s, entry_point, 0, null, null);

        is_compiled: GLint;
        glGetShaderiv(s, GL_COMPILE_STATUS, *is_compiled);
        if is_compiled == 0 {
            info_len: GLint;
            glGetShaderiv(program, GL_INFO_LOG_LENGTH, *info_len);
            if info_len > 0 {
                info_log := alloc(info_len,, temp);
                glGetShaderInfoLog(program, cast(GLsizei)info_len, null, info_log);
                log_error("[Gaco] Shader compilation failed: %", to_string(info_log));
            }
            else {
                log_error("[Gaco] Shader compilation failed with no info log.");
            }
            log_error("[Gaco] Shader loading failed.");
            `return .{};
        }
        return s;
    }

    delete :: inline (s: GLuint) {
        if s != 0  glDeleteShader(s);
    }
    vertex_shader: GLuint;
    fragment_shader: GLuint;
    compute_shader: GLuint;
    defer {
        delete(vertex_shader);
        delete(fragment_shader);
        delete(compute_shader);
    }

    program := glCreateProgram();
    glProgramParameteri(program, GL_PROGRAM_SEPARABLE, 1);

    if type & .Vertex {
        shader.input_vao = get_input_vao_from_spv(bytecode.vs);
        vertex_shader = load(GL_VERTEX_SHADER, bytecode.vs, VS_ENTRY_POINT);
        glAttachShader(program, vertex_shader);
    }
    if type & .Fragment {
        fragment_shader = load(GL_FRAGMENT_SHADER, bytecode.fs, FS_ENTRY_POINT);
        glAttachShader(program, fragment_shader);
    }
    if type & .Compute {
        compute_shader = load(GL_COMPUTE_SHADER, bytecode.cs, CS_ENTRY_POINT);
        glAttachShader(program, compute_shader);
    }

    glLinkProgram(program);

    is_linked: GLint;
    glGetProgramiv(program, GL_LINK_STATUS, *is_linked);
    if is_linked == 0 {
        info_len: GLint;
        glGetProgramiv(program, GL_INFO_LOG_LENGTH, *info_len);

        if info_len > 0 {
            info_log := alloc(info_len,, temp);
            glGetProgramInfoLog(program, cast(GLsizei)info_len, null, info_log);
            log_error("[Gaco] Shader linking failed: %", to_string(info_log));
        } else {
            log_error("[Gaco] Shader linking failed with no info log.");
        }
        glDeleteProgram(program);
        return .{};
    }

    shader.program = program;
    shader.type = type;
    return shader;
}

clear :: (r: float, g: float, b: float, a: float, depth := 1.0, stencil: u8 = 0, $flags: Clear_Flags = .Color | .Depth | .Stencil) {
    window_render_target := Render_Target.{0, 1};
    clear(window_render_target, r, g, b, a, depth, stencil, flags);

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

clear :: (render_target: Render_Target, r: float, g: float, b: float, a: float, depth := 1.0, stencil: u8 = 0, $flags: Clear_Flags = .Color | .Depth | .Stencil) {
    #if flags & .Color {
        color := float.[r,g,b,a];
        for 0..render_target.color_view_count - 1 {
            glClearNamedFramebufferfv(render_target.framebuffer, GL_COLOR, cast(s32)it, color.data);
        }
    }
    #if flags & .Depth {
        glClearNamedFramebufferfv(render_target.framebuffer, GL_DEPTH, 0, *depth);
    }
    #if flags & .Stencil {
        glClearNamedFramebufferiv(render_target.framebuffer, GL_STENCIL, 0, *(cast(s32)stencil));
    }
}

set_shader :: (shader: Shader) {
    stages: GLbitfield;
    if shader.type & .Vertex {
        stages |= GL_VERTEX_SHADER_BIT;

        // We have to rebind the vertex, index and instance buffer because we can't just change
        // the input vao and be done with it!!
        Bound_Buffer :: struct {
            object: GLuint;
            stride: u32;
            offset: u32;
        }

        get_bound :: (slot: u32) -> Bound_Buffer {
            buffer: Bound_Buffer;
            glGetIntegeri_v(GL_VERTEX_BINDING_BUFFER, slot, cast(*GLint)*buffer.object);
            glGetIntegeri_v(GL_VERTEX_BINDING_OFFSET, slot, cast(*GLint)*buffer.offset);
            glGetIntegeri_v(GL_VERTEX_BINDING_STRIDE, slot, cast(*GLint)*buffer.stride);
            return buffer;
        }

        bind :: (buffer: Bound_Buffer, slot: u32) {
            if buffer.object {
                glBindVertexBuffer(slot, buffer.object, buffer.offset, buffer.stride);
            }
        }

        vertex_buffer := get_bound(0);
        instance_buffer := get_bound(1);
        index_buffer: GLuint;
        glGetIntegerv(GL_ELEMENT_ARRAY_BUFFER_BINDING, cast(*GLint)*index_buffer);

        glBindVertexArray(shader.input_vao);
        bind(vertex_buffer, 0);
        bind(instance_buffer, 1);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, index_buffer);
    }
    if shader.type & .Fragment  stages |= GL_FRAGMENT_SHADER_BIT;
    if shader.type & .Compute   stages |= GL_COMPUTE_SHADER_BIT;

    glUseProgramStages(global_pipeline, stages, shader.program);
    glValidateProgramPipeline(global_pipeline);
}

set_scissor :: (using rect: Rect) {
    glScissor(x, y, cast(u32)width, cast(u32)height);
}

set_viewport :: (x: float, y: float, width: float, height: float, near_depth := 0.0, far_depth := 1.0) {
    glViewportIndexedf(0, x, y, width, height);
    glDepthRangef(near_depth, far_depth);
}

set_blend_mode :: (mode: Blend_Mode) {
    state := blend_modes[mode];
    if state.enabled {
        glEnable(GL_BLEND);
        using state;
        glBlendFuncSeparate(src_blend, dst_blend, src_blend_alpha, dst_blend_alpha);
        glBlendEquationSeparate(blend_op, blend_op_alpha);

        glColorMask(red, green, blue, alpha);

    }
    else {
        glDisable(GL_BLEND);
    }
}

set_rasterizer_mode :: (mode: Rasterizer_Mode) {
    state := rasterizer_modes[mode];
    glPolygonMode(GL_FRONT_AND_BACK, state.polygon_mode);
    if state.cull_mode {
        glEnable(GL_CULL_FACE);
        glCullFace(state.cull_mode);
    }
    else {
        glDisable(GL_CULL_FACE);
    }
    if state.scissor_enabled {
        glEnable(GL_SCISSOR_TEST);
    }
    else {
        glDisable(GL_SCISSOR_TEST);
    }
}

set_depth_stencil_mode :: (mode: Depth_Stencil_Mode) {
    state := depth_stencil_modes[mode];
    if state.depth_enabled {
        using state;
        glEnable(GL_DEPTH_TEST);
        glDepthMask(depth_write_mask);
        glDepthFunc(depth_func);
    }
    else {
        glDisable(GL_DEPTH_TEST);
    }

    if state.stencil_enabled {
        glEnable(GL_STENCIL_TEST);
        // @Incomplete: Rest of the procedures
    }
    else {
        glDisable(GL_STENCIL_TEST);
    }
}

draw :: ($indexed: bool, count: u32, first: u32 = 0, base_vertex: s32 = 0) {
    #if indexed {
        format := ifx current_index_stride == 4 cast(u32)GL_UNSIGNED_INT else cast(u32)GL_UNSIGNED_SHORT;
        glDrawElementsBaseVertex(current_primitive_mode, count, format, cast(*void)(current_index_stride * first), base_vertex);
    }
    else {
        glDrawArrays(current_primitive_mode, cast(GLint)first, count);
    }
}

draw_instanced :: ($indexed: bool, count: u32, instance_count: u32, first: u32 = 0, first_instance: u32 = 0, base_vertex: s32 = 0) {
    format := ifx current_index_stride == 4 cast(u32)GL_UNSIGNED_INT else cast(u32)GL_UNSIGNED_SHORT;
    #if indexed {
        glDrawElementsInstancedBaseVertexBaseInstance(current_primitive_mode, count, format, cast(*void)(current_index_stride * first), instance_count, base_vertex, first_instance);
    }
    else {
        glDrawArraysInstancedBaseInstance(current_primitive_mode, first, count, instance_count, first_instance);
    }
}

dispatch_compute :: (num_groups_x: u32, num_groups_y: u32, num_groups_z: u32) {
    glDispatchCompute(num_groups_x, num_groups_y, num_groups_z);
}

present :: (interval: u32 = 1) {
    if interval != current_swap_interval {
        #if OS == .WINDOWS {
            wglSwapIntervalEXT(cast(s32)interval);
        }
        else #if OS == .LINUX {
            glXSwapIntervalEXT(x_global_display, main_window, interval);
        }
        current_swap_interval = interval;
    }
    #if OS == .WINDOWS {
        dc := wglGetCurrentDC();
        SwapBuffers(dc);
    }
    else #if OS == .LINUX {
        glXSwapBuffers(x_global_display, main_window);
    }
}

create_render_target :: (color_textures: []Texture, depth_stencil_texture: Texture) -> Render_Target {
    render_target: Render_Target;
    draw_buffers := NewArray(color_textures.count, GLenum,, temp);
    glCreateFramebuffers(1, *render_target.framebuffer);
    for color_textures {
        assert(it.flags & .Render_Target != 0, "[Gaco] A color texture used for creating a render target has to have the Render_Target flag. This is a requirement for keeping the api compatible with D3D11.");
        attachment := GL_COLOR_ATTACHMENT0 + cast(u32)it_index;
        glNamedFramebufferTexture(render_target.framebuffer, attachment, it.object, 0);
        draw_buffers[it_index] = attachment;
    }
    if !is_empty(depth_stencil_texture) {
        glNamedFramebufferTexture(render_target.framebuffer, GL_DEPTH_STENCIL_ATTACHMENT , depth_stencil_texture.object, 0);
    }
    glNamedFramebufferDrawBuffers(render_target.framebuffer, cast(u32)draw_buffers.count, draw_buffers.data);
    status := glCheckNamedFramebufferStatus(render_target.framebuffer, GL_FRAMEBUFFER);
    if status != GL_FRAMEBUFFER_COMPLETE {
        log_error("Unable to create render target! Status: 0x%", formatInt(status, 16));
        return .{};
    }
    render_target.color_view_count = cast(u32)draw_buffers.count;
    return render_target;
}

set_render_target :: (render_target: Render_Target) {
    glBindFramebuffer(GL_FRAMEBUFFER, render_target.framebuffer);
}

destroy_render_target :: (render_target: *Render_Target) {
    glDeleteFramebuffers(1, *render_target.framebuffer);
}

resize :: (width: int, height: int) -> window_render_target: Render_Target {
    glViewport(0, 0, cast(GLuint)width, cast(GLuint)height);
    return .{}; // @Incomplete: Use our own framebuffer instead of the default one
}

create_texture :: (data: []*u8, width: u32, height: u32, array_count_or_depth: u32 = 1, mip_levels_or_msaa: u32 = 1, format := Texture_Format.RGBA8, flags := Texture_Flags.None) -> Texture {
    generate_mips := (flags & .Generate_Mips) && mip_levels_or_msaa != 1;

    gl_info := GL_MAPPING_ARRAY[format];
    if gl_info.internal_format == 0 {
        log_error("[Gaco] Error while creating texture: Format % is Unknown or unsupported.", format);
        return .{};
    }

    bytes_per_block := TEXTURE_BYTES_PER_BLOCK[format];

    texture := Texture.{
        width = width,
        height = height,
        stride = bytes_per_block,
        flags = flags,
        pixel_type = gl_info.upload_type,
        pixel_format = gl_info.upload_format
    };

    if flags & .Copy {
        size := width * height * bytes_per_block;
        glCreateBuffers(1, *texture.object);
        glNamedBufferStorage(texture.object, size, null, GL_DYNAMIC_STORAGE_BIT | GL_MAP_READ_BIT);
        texture.pbo_size = size;
        return texture;
    }

    target: GLenum = GL_TEXTURE_2D;

    is_cube  := (flags & .Cubemap) != 0;
    logical_array_count := array_count_or_depth;
    if is_cube logical_array_count /= 6;
    is_array := logical_array_count > 1;
    is_3d    := (flags & .Is_3D) != 0;
    is_msaa  := (flags & .Multisample) != 0;

    if is_3d {
        if is_msaa log_error("[Gaco] Warning: MSAA 3D textures are not standard in OpenGL.");
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

    glCreateTextures(target, 1, *texture.object);

    mip_levels := ifx is_msaa 1 else mip_levels_or_msaa;

    if is_msaa {
        if is_array {
            glTextureStorage3DMultisample(texture.object, mip_levels_or_msaa, gl_info.internal_format, width, height, array_count_or_depth, GL_TRUE);
        } else {
            glTextureStorage2DMultisample(texture.object, mip_levels_or_msaa, gl_info.internal_format, width, height, GL_TRUE);
        }
    }
    else {
        if target == GL_TEXTURE_3D || target == GL_TEXTURE_2D_ARRAY || target == GL_TEXTURE_CUBE_MAP_ARRAY {
            depth := ifx target == GL_TEXTURE_CUBE_MAP_ARRAY then logical_array_count * 6 else logical_array_count;
            glTextureStorage3D(texture.object, mip_levels, gl_info.internal_format, width, height, depth);
        }
        else {
            // GL_TEXTURE_2D, GL_TEXTURE_1D, and GL_TEXTURE_CUBE_MAP use 2D storage
            glTextureStorage2D(texture.object, mip_levels, gl_info.internal_format, width, height);
        }
    }

    if data && !is_msaa {
        mips_to_upload := ifx generate_mips 1 else mip_levels;
        slices         := ifx is_3d 1 else array_count_or_depth;

        for slice: 0..slices-1 {
            for mip: 0..mips_to_upload-1 {
                data_index := mip + slice * mip_levels;
                if data_index >= data.count break;

                pixels := data[data_index];
                if !pixels continue;

                mip_width  := cast(u32)max(1, width >> mip);
                mip_height := cast(u32)max(1, height >> mip);
                mip_depth  := ifx is_3d cast(u32)max(1, array_count_or_depth >> mip) else 1;

                zoffset   := ifx is_3d then 0 else slice;
                depth_arg := ifx is_3d then mip_depth else 1;

                if is_block_compression(format) {
                    bw := (mip_width + 3) / 4;
                    bh := (mip_height + 3) / 4;
                    image_size := cast(u32)(bw * bh * bytes_per_block * mip_depth);

                    if target == GL_TEXTURE_2D {
                        glCompressedTextureSubImage2D(texture.object, cast(s32)mip, 0, 0, mip_width, mip_height, gl_info.internal_format, image_size, pixels);
                    }
                    else if target == GL_TEXTURE_CUBE_MAP {
                        glBindTexture(GL_TEXTURE_CUBE_MAP, texture.object);
                        glCompressedTexSubImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X + cast(u32)zoffset, cast(s32)mip, 0, 0, mip_width, mip_height, gl_info.internal_format, image_size, pixels);
                        glBindTexture(GL_TEXTURE_CUBE_MAP, 0);
                    }
                    else {
                        glCompressedTextureSubImage3D(texture.object, cast(s32)mip, 0, 0, cast(s32)zoffset, mip_width, mip_height, depth_arg, gl_info.internal_format, image_size, pixels);
                    }
                }
                else {
                    if target == GL_TEXTURE_2D {
                        glTextureSubImage2D(texture.object, cast(s32)mip, 0, 0, mip_width, mip_height, gl_info.upload_format, gl_info.upload_type, pixels);
                    }
                    else if target == GL_TEXTURE_CUBE_MAP {
                        // @Workaround: DSA glTextureSubImage3D ignores zoffset on some drivers.
                        glBindTexture(GL_TEXTURE_CUBE_MAP, texture.object);
                        glTexSubImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X + cast(u32)zoffset, cast(s32)mip, 0, 0, mip_width, mip_height, gl_info.upload_format, gl_info.upload_type, pixels);
                        glBindTexture(GL_TEXTURE_CUBE_MAP, 0);
                    }
                    else {
                        glTextureSubImage3D(texture.object, cast(s32)mip, 0, 0, cast(s32)zoffset, mip_width, mip_height, depth_arg, gl_info.upload_format, gl_info.upload_type, pixels);
                    }
                }
            }
        }
    }

    if generate_mips {
        glGenerateTextureMipmap(texture.object);
    }

    return texture;
}

bind_texture :: (texture: Texture, slot: u32, bind_to := Shader_Type.Fragment) {
    if bind_to & .Vertex
        glBindTextureUnit(slot, texture.object);
    if bind_to & .Fragment
        glBindTextureUnit(slot + 16, texture.object);
    if bind_to & .Compute
        glBindTextureUnit(slot + 32, texture.object);
}

copy_texture :: inline (from: Texture, to: *Texture) {
    copy_texture(from, to, .{0, 0, cast(s32)from.width, cast(s32)from.height});
}

copy_texture :: (from: Texture, to: *Texture, source_rect: Rect) {
    if to.flags & .Copy {
        glBindBuffer(GL_PIXEL_PACK_BUFFER, to.object);
        glGetTextureSubImage(from.object, 0, source_rect.x, source_rect.y, 0, cast(u32)source_rect.width, cast(u32)source_rect.height, 1, from.pixel_format, from.pixel_type, to.pbo_size, null);
        glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
    }
    else {
        // @Incomplete: Only 2D textures.
        glCopyImageSubData(from.object, GL_TEXTURE_2D, 0, source_rect.x, source_rect.y, 0, to.object, GL_TEXTURE_2D, 0, 0, 0, 0, cast(u32)source_rect.width, cast(u32)source_rect.height, 1);
    }
}

copy_from_render_target :: (render_target: Render_Target, to: *Texture, depth_stencil := false, index: u32 = 0) {
    if render_target.framebuffer == 0 { // Back buffer
        glNamedFramebufferReadBuffer(0, GL_BACK);
    }
    else {
        glNamedFramebufferReadBuffer(render_target.framebuffer, GL_COLOR_ATTACHMENT0 + index);
    }

    if to.flags & .Copy {
        glBindBuffer(GL_PIXEL_PACK_BUFFER, to.object);
        glReadPixels(0, 0, to.width, to.height, to.pixel_format, to.pixel_type, null);
        glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
    }
    else {
        glCopyTextureSubImage2D(to.object, 0, 0, 0, 0, 0, to.width, to.height);
    }
}

create_sampler :: (filtering := Sampler_Filtering.Linear, edge_handling := Sampler_Edge_Handling.Clamp, max_anisotropy: u32 = 1, comparison := false) -> Sampler {
    sampler: Sampler;
    glCreateSamplers(1, *sampler.object);
    FILTER_TABLE :: GLint.[GL_LINEAR, GL_NEAREST];
    EDGE_TABLE :: GLint.[GL_REPEAT, GL_MIRRORED_REPEAT, GL_CLAMP_TO_EDGE, GL_CLAMP_TO_BORDER];

    gl_filtering := FILTER_TABLE[filtering];
    gl_edge := EDGE_TABLE[edge_handling];

    if comparison {
        glSamplerParameteri(sampler.object, GL_TEXTURE_COMPARE_MODE, GL_COMPARE_REF_TO_TEXTURE);
        glSamplerParameteri(sampler.object, GL_TEXTURE_COMPARE_FUNC, GL_NEVER); // @Incomplete
    }

    glSamplerParameteri(sampler.object, GL_TEXTURE_MIN_FILTER, gl_filtering);
    glSamplerParameteri(sampler.object, GL_TEXTURE_MAG_FILTER, gl_filtering);

    glSamplerParameteri(sampler.object, GL_TEXTURE_WRAP_S, gl_edge);
    glSamplerParameteri(sampler.object, GL_TEXTURE_WRAP_T, gl_edge);
    glSamplerParameteri(sampler.object, GL_TEXTURE_WRAP_R, gl_edge);
    return sampler;
}

bind_sampler :: (sampler: Sampler, slot: u32, bind_to := Shader_Type.Fragment) {
    if bind_to & .Vertex
        glBindSampler(slot, sampler.object);
    if bind_to & .Fragment
        glBindSampler(slot+16, sampler.object);
    if bind_to & .Compute
        glBindSampler(slot+32, sampler.object);
}

destroy_sampler :: (sampler: *Sampler) {
    glDeleteSamplers(1, *sampler.object);
    sampler.object = 0;
}

#scope_module
// Unlike D3D11, a single SPIR-V file can actually have multiple entry-points.
// We might want to use this fact later on.

VS_EXTENSION :: ".spvs";
FS_EXTENSION :: ".spfs";
CS_EXTENSION :: ".spcs";

#scope_file
init_preloaded_modes :: () {
    // Depth Stencil Modes
    {
        using Depth_Stencil_Mode;
        state := Depth_Stencil_State.{
            depth_enabled = true,
            depth_write_mask = GL_TRUE,
            depth_func = GL_LEQUAL,
            stencil_enabled = true
        };
        depth_stencil_modes[Depth_Stencil] = state;

        state.depth_func = GL_GEQUAL;
        depth_stencil_modes[Depth_Reversed] = state;

        state.depth_func = GL_LEQUAL;
        state.depth_write_mask = GL_FALSE;
        depth_stencil_modes[No_Depth_Mask] = state;

        state.depth_enabled = false;
        depth_stencil_modes[No_Depth] = state;

        state.stencil_enabled = false;
        depth_stencil_modes[No_Depth_Stencil] = state;

        state.depth_enabled = true;
        state.depth_write_mask = GL_TRUE;
        state.depth_func = GL_LEQUAL;
        depth_stencil_modes[No_Stencil] = state;

        set_depth_stencil_mode(.Depth_Stencil);
    }

    // Rasterizer Modes
    {
        using Rasterizer_Mode;
        state := Rasterizer_State.{
            polygon_mode = GL_FILL,
            cull_mode = GL_BACK,
            scissor_enabled = true,
        };
        rasterizer_modes[Scissor] = state;

        state.scissor_enabled = false;
        rasterizer_modes[Default] = state;

        state.cull_mode = GL_FRONT;
        rasterizer_modes[Front_Cull] = state;

        state.cull_mode = 0; // Special
        rasterizer_modes[No_Cull] = state;
        set_rasterizer_mode(.Default);
    }

    // Blend Modes
    {
        using Blend_Mode;
        state := Blend_State.{
            enabled=true,
            src_blend = GL_SRC_ALPHA,
            dst_blend = GL_ONE_MINUS_SRC_ALPHA,
            src_blend_alpha = GL_ONE,
            dst_blend_alpha = GL_ZERO,
            blend_op = GL_FUNC_ADD,
            blend_op_alpha = GL_FUNC_ADD,
            red = true, green = true, blue = true, alpha = true
        };

        blend_modes[Alpha] = state;

        state.enabled = false;
        blend_modes[None] = state;
        set_blend_mode(.None);
    }
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

        semantic_str := ifx it.semantic then to_string(it.semantic) else to_string(it.name);
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
using GL_State: struct {
    main_window: WT.Window_Type;
    global_pipeline: GLuint;
    empty_stupid_vao: GLuint; // Because we cannot bind a vertex buffer without a vao

    current_primitive_mode: GLuint = GL_TRIANGLES;
    current_index_stride: GLenum; // GL_UNSIGNED_SHORT, GL_UNSIGNED_INT
    current_swap_interval: u32; // We shouldn't trust that the default is 0 actually.

    default_sampler: Sampler;
    rasterizer_modes: [#run enum_count(Rasterizer_Mode)]Rasterizer_State;
    blend_modes: [#run enum_count(Blend_Mode)]Blend_State;
    depth_stencil_modes: [#run enum_count(Depth_Stencil_Mode)]Depth_Stencil_State;
}

GL_Format_Info :: struct {
    internal_format : u32;
    upload_format   : u32;
    upload_type     : u32;
}

GL_MAPPING_ARRAY :: GL_Format_Info.[
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
    .{ GL_R16F,     GL_RED,  GL_HALF_FLOAT },                     // R16F
    .{ GL_RG16F,    GL_RG,   GL_HALF_FLOAT },                     // RG16F
    .{ GL_RGBA16F,  GL_RGBA, GL_HALF_FLOAT },                     // RGBA16F
    .{ GL_R32F,     GL_RED,  GL_FLOAT },                          // R32F
    .{ GL_RG32F,    GL_RG,   GL_FLOAT },                          // RG32F
    .{ GL_RGBA32F,  GL_RGBA, GL_FLOAT },                          // RGBA32F
    .{ GL_R11F_G11F_B10F, GL_RGB, GL_UNSIGNED_INT_10F_11F_11F_REV},// RG11B10F
    .{ GL_RGB9_E5,  GL_RGB,  GL_UNSIGNED_INT_5_9_9_9_REV },       // RGB9E5F

    // Integer formats
    .{ GL_R16I,     GL_RED_INTEGER,  GL_SHORT },                  // R16I
    .{ GL_RG16I,    GL_RG_INTEGER,   GL_SHORT },                  // RG16I
    .{ GL_RGBA16I,  GL_RGBA_INTEGER, GL_SHORT },                  // RGBA16I
    .{ GL_R32I,     GL_RED_INTEGER,  GL_INT },                    // R32I
    .{ GL_RG32I,    GL_RG_INTEGER,   GL_INT },                    // RG32I
    .{ GL_RGB32I,   GL_RGB_INTEGER,  GL_INT },                    // RGB32I
    .{ GL_RGBA32I,  GL_RGBA_INTEGER, GL_INT },                    // RGBA32I

    // Block compression formats
    .{ GL_COMPRESSED_RGB_BPTC_UNSIGNED_FLOAT, 0, 0 },             // BC6U
    .{ GL_COMPRESSED_RGB_BPTC_SIGNED_FLOAT,   0, 0 },             // BC6S
    .{ GL_COMPRESSED_RGBA_BPTC_UNORM,         0, 0 },             // BC7
    .{ GL_COMPRESSED_SRGB_ALPHA_BPTC_UNORM,   0, 0 },             // BC7_SRGB

    // Depth formats
    .{ GL_DEPTH_COMPONENT16, GL_DEPTH_COMPONENT, GL_UNSIGNED_SHORT },             // D16
    .{ GL_DEPTH24_STENCIL8,  GL_DEPTH_STENCIL,   GL_UNSIGNED_INT_24_8 },          // D24S8
    .{ GL_DEPTH_COMPONENT32F,GL_DEPTH_COMPONENT, GL_FLOAT },                      // D32F
    .{ GL_DEPTH32F_STENCIL8, GL_DEPTH_STENCIL,   GL_FLOAT_32_UNSIGNED_INT_24_8_REV } // D32FS8
];
#import "GL";
DXC :: #import "dxc_compiler";

#if OS == .WINDOWS {
    #import "Windows";
}
else #if OS == .LINUX {
    #import "X11";
}

WT :: #import "Window_Type";
