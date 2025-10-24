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
        log_error("Unsupported GL version: %.%, need at least 4.5", major, minor);
    }

    main_window = window;

    #if DEBUG {
        // D3D11 crashes on errors (because there is no way to register a callback...)
        // so we do the same thing here to be compatible, is this a good idea?
        gl_enable_debug_output(break_on_error=true);
    }
    glFrontFace(GL_CW); // We use clockwise for both OpenGL and D3D11
    glClipControl(GL_LOWER_LEFT, GL_ZERO_TO_ONE); // Why does lower left work??

    // So we can bind vertex buffers without setting a shader.
    glCreateVertexArrays(1, *empty_stupid_vao);
    glBindVertexArray(empty_stupid_vao);

    glCreateProgramPipelines(1, *global_pipeline);
    glBindProgramPipeline(global_pipeline);
    init_preloaded_modes();
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

bind_buffer :: (buffer: Buffer(.Constant), slot: u32 = 0) {
    glBindBufferBase(GL_UNIFORM_BUFFER, slot, buffer.object);
}

bind_buffer :: (buffer: Buffer(.Structured), slot: u32 = 0) {
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, slot, buffer.object);
}

// Same as above
bind_buffer :: (buffer: Buffer(.RWStructured), slot: u32 = 0) {
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, slot, buffer.object);
}

map_buffer :: (buffer: *Buffer, flags: Map_Flags) -> *void {
    access: GLbitfield;

    if flags & .Read {
        access |= GL_MAP_READ_BIT;
        #if buffer.type != .Copy {
            access |= GL_MAP_INVALIDATE_BUFFER_BIT;
        }
    }

    if flags & .Write access |= GL_MAP_WRITE_BIT;
    return glMapNamedBufferRange(buffer.object, 0, buffer.size, access);
}

unmap_buffer :: (buffer: *Buffer) {
    if glUnmapNamedBuffer(buffer.object) == GL_FALSE {
        log_error("[Gaco] Couldn't unmap buffer!");
    }
}

update_buffer :: (buffer: *Buffer, data: *void) {
    glNamedBufferSubData(buffer.object, 0, buffer.size, data);
}

update_texture :: (texture: *Texture, data: *void, rect: Rect, subresource: u32 = 0) {
    glPixelStorei(GL_UNPACK_ALIGNMENT, cast(s32)texture.stride);
    // @Incomplete: This is wrong for texture arrays
    glTextureSubImage2D(texture.object, cast(s32)subresource, rect.x, rect.y, cast(u32)rect.width, cast(u32)rect.height, texture.pixel_format, texture.pixel_type, data);
}

update_texture :: (texture: *Texture, data: *void, box: Box, subresource: u32 = 0) {
}

update_texture :: inline (using texture: *Texture, data: *void, subresource: u32 = 0) {
    update_texture(texture, data, .{0, 0, cast(s32)width, cast(s32)height}, subresource);
}

write_buffer :: (buffer: *Buffer, data: *void, size: int) {
    mapped_data := map_buffer(buffer, .Write);
    memcpy(mapped_data, data, size);
    unmap_buffer(buffer);
}

copy_buffer :: (from: *Buffer, to: *Buffer) {
    glCopyNamedBufferSubData(from.object, to.object, 0, 0, from.size);

}

destroy_buffer :: (buffer: *Buffer) {
    glDeleteBuffers(1, *buffer.object);
}

destroy_texture :: (texture: *Texture) {
    glDeleteTextures(1, *texture.object);
}

compile_shader_to_bytecode :: (source: string, type: Shader_Type, shader_name: string) -> Shader_Bytecode, bool {
    bytecode: Shader_Bytecode;
    dxc_shader_type: DXC.Shader_Type;
    args: DXC.Dxc_Shader_Compiler_Args;
    args.shader_name = shader_name;
    args.shader_model_version = "6_0";
    args.shader_source = source;
    args.add_debug_info = DEBUG;
    args.compile_as_spirv = true;

    compile :: (entry_point: string, shader_type: DXC.Shader_Type) -> string #expand {
        `args.entry_point = entry_point;
        `args.shader_type = shader_type;
        result := DXC.DXC_Compile(`args);
        if !result {
            `return .{}, false;
        }

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
            log_error("[Gaco] Shader loading failed."); // @Incomplete: Give more info.
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
        glDeleteProgram(program);
        log_error("[Gaco] Shader program linking failed!"); // @Incomplete: Give more info.
        return .{};
    }

    shader.program = program;
    shader.type = type;
    return shader;
}

clear :: (r: float, g: float, b: float, a: float, depth := 1.0, stencil: u8 = 0, $flags: Clear_Flags = .Color | .Depth | .Stencil) {
    glClearColor(r,g,b,a);
    glClearDepthf(depth);
    glClearStencil(cast(GLint)stencil);

    mask: GLbitfield;
    #if flags & .Color
        mask |= GL_COLOR_BUFFER_BIT;
    #if flags & .Depth
        mask |= GL_DEPTH_BUFFER_BIT;
    #if flags & .Stencil
        mask |= GL_STENCIL_BUFFER_BIT;
    glClear(mask);
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
        glClearNamedFramebufferiv(render_target.framebuffer, GL_STENCIL, 0, cast(*s32)*stencil);
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
        glDrawArrays(mode, cast(GLint)first, count);
    }
}

draw_instanced :: ($indexed: bool, count: u32, instance_count: u32, first: u32 = 0, first_instance: u32 = 0, base_vertex: s32 = 0) {
    format := ifx current_index_stride == 4 cast(u32)GL_UNSIGNED_INT else cast(u32)GL_UNSIGNED_SHORT;
    #if indexed {
        glDrawElementsInstancedBaseVertexBaseInstance(current_primitive_mode, count, format, cast(*void)(current_index_stride * first), instance_count, base_vertex, first_instance);
    }
    else {
        glDrawArraysInstanced(curent_primitive_mode, first, count, instance_count, first_instance);
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
        attachment := GL_COLOR_ATTACHMENT0 + cast(u32)it_index;
        glNamedFramebufferTexture(render_target.framebuffer, attachment, it.object, 0);
        draw_buffers[it_index] = attachment;
    }
    if !is_empty(depth_stencil_texture) {
        glNamedFramebufferTexture(render_target.framebuffer, GL_DEPTH_ATTACHMENT, depth_stencil_texture.object, 0);
    }
    glNamedFramebufferDrawBuffers(render_target.framebuffer, cast(u32)draw_buffers.count, draw_buffers.data);
    render_target.color_view_count = cast(u32)draw_buffers.count;
    return render_target;
}

set_render_target :: (render_target: Render_Target) {
    glBindFramebuffer(GL_FRAMEBUFFER, render_target.framebuffer);
}

destroy_render_target :: (render_target: *Render_Target) {
    glDeleteFramebuffers(1, *render_target.framebuffer);
}

resize :: (width: int, height: int) {
    glViewport(0, 0, cast(GLuint)width, cast(GLuint)height);
}

create_texture :: (data: []*u8, width: u32, height: u32, channels: u32, array_count_or_depth: u32 = 1, mip_levels_or_msaa: u32 = 1, format := Texture_Format.Default, flags := Texture_Flags.None) -> Texture {
    GL_COMPRESSED_RGBA_BPTC_UNORM_ARB :: 0x8E8C;
    GL_COMPRESSED_SRGB_ALPHA_BPTC_UNORM_ARB :: 0x8E8D;
    GL_COMPRESSED_RGB_BPTC_SIGNED_FLOAT_ARB :: 0x8E8E;
    GL_COMPRESSED_RGB_BPTC_UNSIGNED_FLOAT_ARB :: 0x8E8F;

    target: GLuint = GL_TEXTURE_2D;

    msaa: u32 = 1;
    mip_levels: u32 = 1;
    array_count: u32 = 1;
    depth: u32 = 1;

    if flags & .Multisample
        msaa = mip_levels_or_msaa;
    else
        mip_levels = mip_levels_or_msaa;

    if flags & .Is_3D {
        target = GL_TEXTURE_3D;
        depth = array_count_or_depth;
    }
    else if flags & .Cubemap {
        // if array_count_or_depth > 6 {
            target = GL_TEXTURE_CUBE_MAP_ARRAY;
        // }
        // else {
            // target = GL_TEXTURE_CUBE_MAP;
        // }
    }
    else if array_count_or_depth > 1 {
        if flags & .Multisample target = GL_TEXTURE_2D_MULTISAMPLE_ARRAY;
        else                         target = GL_TEXTURE_2D_ARRAY;
    }
    else if flags & .Multisample target = GL_TEXTURE_2D_MULTISAMPLE;

    formats: [4]GLenum;
    bytes_per_block := channels;
    internal_format: GLenum;
    if format == {
    case .U32;
        formats = .[GL_R32UI, GL_RG32UI, GL_RGB32UI, GL_RGBA32UI];
        bytes_per_block *= 4;
    case .SRGB;
        // We do not specify GL_SRGB8 because D3D11 doesn't support it.
        formats[3] = GL_SRGB8_ALPHA8;
    case .Float16;
        formats = .[GL_R16F, GL_RG16F, GL_RGB16F, GL_RGBA16F];
        bytes_per_block *= 2;
    case .Float32;
        formats = .[GL_R32F, GL_RG32F, GL_RGB32F, GL_RGBA32F];
        bytes_per_block *= 4;
    case .BC6U;
        internal_format = GL_COMPRESSED_RGB_BPTC_UNSIGNED_FLOAT_ARB;
    case .BC6S;
        internal_format = GL_COMPRESSED_RGB_BPTC_SIGNED_FLOAT_ARB;
    case .BC7;
        internal_format = GL_COMPRESSED_RGBA_BPTC_UNORM_ARB;
    case .BC7_SRGB;
        internal_format = GL_COMPRESSED_SRGB_ALPHA_BPTC_UNORM_ARB;
    case .Default;
        formats = .[GL_R8, GL_RG8, 0, GL_RGBA8];
        // @Incomplete: flags & .Depth_Stencil
    case;
        log_error("[Gaco] Unknown teUIxture format: %", format);
        return .{};
    }
    if !internal_format {
        internal_format = formats[channels - 1];
        if !internal_format {
            log_error("[Gaco] Error while creating texture: % channels with format % is not compatible.", channels, format);
            return .{};
        }
    }

    texture := Texture.{width=width, height=height, stride=bytes_per_block};
    PIXEL_TYPE_TABLE :: GLenum.[GL_UNSIGNED_BYTE, GL_UNSIGNED_INT, GL_UNSIGNED_BYTE, GL_HALF_FLOAT, GL_FLOAT];
    PIXEL_FORMAT_TABLE :: GLenum.[GL_RED, GL_RG, GL_RGB, GL_RGBA];
    texture.pixel_type = PIXEL_TYPE_TABLE[format];
    texture.pixel_format = PIXEL_FORMAT_TABLE[channels - 1];
    glCreateTextures(target, 1, *texture.object);

    if flags & .Is_3D {
        glTextureStorage3D(texture.object, mip_levels, internal_format, width, height, array_count_or_depth);
    }
    else {
        glTextureStorage2D(texture.object, mip_levels, internal_format, width, height);

        // NOTE(Yasin): We will probably overhaul this before the release.
        // @Incomplete: Arrays
        // @Incomplete: Depth_Stencil
        // @Incomplete: Compression textures
        if data {
            update_texture(*texture, data[0]);
        }
    }

    if flags & .Generate_Mips {
        glGenerateTextureMipmap(texture.object);
    }

    return texture;
}

bind_texture :: (texture: Texture, slot: u32) {
    glBindTextureUnit(slot, texture.object);
}

copy_texture :: (from: *Texture, to: *Texture) {
    // @Incomplete: Only 2D textures.
    glCopyImageSubData(from.object, GL_TEXTURE_2D, 0, 0, 0, 0, to.object, GL_TEXTURE_2D, 0, 0, 0, 0, from.width, from.height, from.depth);
}

copy_texture :: (from: *Texture, to: *Texture, source_rect: Rect) {
    glCopyImageSubData(from.object, GL_TEXTURE_2D, 0, source_rect.x, source_rect.y, 0, to.object, GL_TEXTURE_2D, 0, 0, 0, 0, cast(u32)source_rect.width, cast(u32)source_rect.height, 1);
}

create_sampler :: (filtering := Sampler_Filtering.Linear, edge_handling := Sampler_Edge_Handling.Wrap, max_anisotropy: u32 = 1, comparison := false) -> Sampler {
    sampler: Sampler;
    glCreateSamplers(1, *sampler.object);
    FILTER_TABLE :: GLint.[GL_LINEAR, GL_NEAREST];
    EDGE_TABLE :: GLint.[GL_REPEAT, GL_MIRRORED_REPEAT, GL_CLAMP_TO_EDGE, GL_CLAMP_TO_BORDER];

    gl_filtering := FILTER_TABLE[filtering];
    gl_edge := EDGE_TABLE[edge_handling];

    glSamplerParameteri(sampler.object, GL_TEXTURE_MIN_FILTER, gl_filtering);
    glSamplerParameteri(sampler.object, GL_TEXTURE_MAG_FILTER, gl_filtering);

    glSamplerParameteri(sampler.object, GL_TEXTURE_WRAP_S, gl_edge);
    glSamplerParameteri(sampler.object, GL_TEXTURE_WRAP_T, gl_edge);
    glSamplerParameteri(sampler.object, GL_TEXTURE_WRAP_R, gl_edge);
    return sampler;
}

bind_sampler :: (sampler: Sampler, slot: u32) {
    glBindSampler(slot, sampler.object);
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
    module: SpvReflectShaderModule;
    check :: (result: SpvReflectResult) #expand {
        if result != .SUCCESS {
            log_error("[Gaco] SPIR-V shader reflection failed: %", result);
            `return 0;
        }
    }
    Attrib_Proc_Variant :: enum u32 {
        Float;
        Int;
        Double;
    }
    spv_to_gl :: (format: SpvReflectFormat) -> type: GLenum, variant: Attrib_Proc_Variant {
        type: GLenum;
        variant: Attrib_Proc_Variant;

        if format >= .R16_UINT && format <= .R16G16B16A16_SFLOAT {
            base := format - .R16_UINT;
            if base % 7 == {
            case 0;
                type = GL_UNSIGNED_SHORT;
                variant = .Int;
            case 1;
                type = GL_SHORT;
                variant = .Int;
            case 2;
                type = GL_HALF_FLOAT;
                variant = .Float;
            };
        }
        else if format >= .R32_UINT && format <= .R32G32B32A32_SFLOAT {
            base := format - .R32_UINT;
            if base % 3 == {
            case 0;
                type = GL_UNSIGNED_INT;
                variant = .Int;
            case 1;
                type = GL_INT;
                variant = .Int;
            case 2;
                type = GL_FLOAT;
                variant = .Float;
            }
        }
        else if format >= .R64_UINT && format <= .R64G64B64A64_SFLOAT {
            base := format - .R64_UINT;
            variant = .Double;
            if base % 3 == {
            case 0;
            case 1;
                log_error("[Gaco] OpenGL doesn't support 64 bit integer vertex attributes! Couldn't create input vao!");
                type = 0;
            case 2;
                type = GL_DOUBLE;
            }
        }
        return type, variant;
    }


    check(spvReflectCreateShaderModule(cast(u64)spv_bytecode.count, spv_bytecode.data, *module));
    defer spvReflectDestroyShaderModule(*module);

    entry_count: u32;
    check(spvReflectEnumerateEntryPointInputVariables(*module, VS_ENTRY_POINT, *entry_count, null));
    entry_variables := NewArray(entry_count, *SpvReflectInterfaceVariable,, temp);
    check(spvReflectEnumerateEntryPointInputVariables(*module, VS_ENTRY_POINT, *entry_count, entry_variables.data));

    input_vao: GLuint;
    glCreateVertexArrays(1, *input_vao);

    offset: u32;
    for entry_variables {
        assert(it.format != .UNDEFINED);

        type, variant := spv_to_gl(it.format);
        if type == 0 {
            glDeleteVertexArrays(1, *input_vao);
            return 0;
        }

        comps := ifx it.numeric.vector.component_count else 1;
        row_count := ifx it.numeric.matrix.row_count else 1;
        for j: 0..row_count - 1 {
            loc := it.location + j;

            glEnableVertexArrayAttrib(input_vao, loc);
            if variant == {
            case .Float;
                glVertexArrayAttribFormat (input_vao, loc, cast(s32)comps, type, GL_FALSE, offset);
            case .Int;
                glVertexArrayAttribIFormat(input_vao, loc, cast(s32)comps, type, offset);
            case .Double;
                glVertexArrayAttribLFormat(input_vao, loc, cast(s32)comps, type, offset);
            }
            glVertexArrayAttribBinding(input_vao, loc, 0);
            offset += comps * it.numeric.scalar.width / 8;
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

    rasterizer_modes: [#run enum_count(Rasterizer_Mode)]Rasterizer_State;
    blend_modes: [#run enum_count(Blend_Mode)]Blend_State;
    depth_stencil_modes: [#run enum_count(Depth_Stencil_Mode)]Depth_Stencil_State;

}
#import "GL";
DXC :: #import "dxc_compiler";
#import,dir "spirv_reflect";

#if OS == .WINDOWS {
    #import "Windows";
}
else #if OS == .LINUX {
    #import "X11";
}

WT :: #import "Window_Type";
