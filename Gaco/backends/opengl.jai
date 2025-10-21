// TODO(Yasin): Use a seperate framebuffer from the back buffer.

Shader :: struct {
    type: Shader_Type;
    input_vao: GLuint;
    program: GLuint; // This is a 'seperable' program that contains the shaders specified with type.
}

Buffer :: struct (type: Buffer_Type) {
    buffer: GLuint;
    size: u32;
    stride: u32;
    // ...
}

Sampler :: struct {
    sampler: GLuint;
}

Texture :: struct {
    texture: GLuint;
}
Render_Target :: struct {
}

Blend_State :: struct {
    enabled: bool;
    src_blend: GLenum;
    dst_blend: GLenum;
    blend_op: GLenum;

    src_blend_alpha: GLenum;
    dst_blend_alpha: GLenum;
    blend_op_alpha: GLenum;

    red: GLboolean;
    green: GLboolean;
    blue: GLboolean;
    alpha: GLboolean;
}

Rasterizer_State :: struct {}
Depth_Stencil_State :: struct {}

is_empty :: (texture: Texture) -> bool {
    return glIsTexture(texture.texture) == GL_TRUE;
}

is_empty :: (using shader: Shader) -> bool {
    i := glIsVertexArray(input_vao)  == GL_TRUE;
    v := glIsShader(vertex_shader)   == GL_TRUE;
    f := glIsShader(fragment_shader) == GL_TRUE;
    c := glIsShader(compute_shader)  == GL_TRUE;

    empty_vs := type & .Vertex   && (!v || !i);
    empty_fs := type & .Fragment && !f;
    empty_cs := type & .Compute  && !c;

    return type == .Unspecified || empty_vs || empty_fs || empty_cs;
}

is_empty :: (render_target: Render_Target) -> bool {}

init :: (window: WT.Window_Type, wanted_msaa: u32 = 4) {
    // TODO(Yasin): Replace this with our own procedure so we can use stencil buffers.
    gl_create_context(window, 4, 6, false, DEBUG, cast(s32)wanted_msaa);
    gl_load(*gl);

    main_window = window;

    #if DEBUG {
        // D3D11 crashes on errors (because there is no way to register a callback...)
        // so we do the same thing here to be compatible, is this a good idea?
        gl_enable_debug_output(break_on_error=true);
    }

    // @Cleanup: These should be in preloaded modes.
    glEnable(GL_CULL_FACE);
    glFrontFace(GL_CW); // We use clockwise for both OpenGL and D3D11

    glCreateVertexArrays(1, *empty_stupid_vao);
    glBindVertexArray(empty_stupid_vao);

    glCreateProgramPipelines(1, *global_pipeline);
    glBindProgramPipeline(global_pipeline);
    // init_preloaded_modes();

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

    glCreateBuffers(1, *buffer.buffer);
    storage_flags: GLbitfield;

    #if type == .Copy {
        storage_flags |= GL_MAP_READ_BIT;
    }

    if usage == .Dynamic {
        storage_flags |= GL_DYNAMIC_STORAGE_BIT | GL_MAP_WRITE_BIT;
    }

    glNamedBufferStorage(buffer.buffer, buffer.size, data, storage_flags);
    return buffer;
}
bind_buffer :: (buffer: Buffer(.Vertex), slot: u32 = 0, offset: u32 = 0) {
    glBindVertexBuffer(slot, buffer.buffer, offset, buffer.stride);
}

bind_buffer :: (buffer: Buffer(.Index)) {
    // assert(buffer.stride == 2 || buffer.stride == 4);
    current_index_stride = buffer.stride;
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, buffer.buffer);
}


// NOTE(Yasin): bind_to is just here for compatibility with D3D11,
// I will find a better way to handle this later on.
bind_buffer :: (buffer: Buffer(.Constant), slot: u32 = 0, bind_to: Shader_Type) {
    glBindBufferBase(GL_UNIFORM_BUFFER, slot, buffer.buffer);
}
map_buffer :: (buffer: *Buffer, flags: Map_Flags) -> *void {
    access: GLbitfield;
    if flags & .Read  access |= GL_MAP_READ_BIT;
    if flags & .Write access |= GL_MAP_WRITE_BIT;
    return glMapNamedBufferRange(buffer.buffer, 0, buffer.size, access);
}

unmap_buffer :: (buffer: *Buffer) {
    if glUnmapNamedBuffer(buffer.buffer) == GL_FALSE {
        log_error("Couldn't unmap buffer!");
    }
}

write_buffer :: (buffer: *Buffer, data: *void, size: int) {
    mapped_data := map_buffer(buffer, .Write);
    memcpy(mapped_data, data, size);
    unmap_buffer(buffer);
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
            log_error("Shader loading failed."); // @Incomplete: Give more info.
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
        log_error("Shader program linking failed!"); // @Incomplete: Give more info.
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

set_shader :: (shader: Shader) {
    stages: GLbitfield;
    if shader.type & .Vertex {
        stages |= GL_VERTEX_SHADER_BIT;

        // We have to rebind the vertex and instance buffer because we can't just change
        // the input vao and be done with it!!
        Bound_Buffer :: struct {
            buffer: GLuint;
            stride: u32;
            offset: u32;
        }

        get_bound :: (slot: u32) -> Bound_Buffer {
            buffer: Bound_Buffer;
            glGetIntegeri_v(GL_VERTEX_BINDING_BUFFER, slot, cast(*GLint)*buffer.buffer);
            glGetIntegeri_v(GL_VERTEX_BINDING_OFFSET, slot, cast(*GLint)*buffer.offset);
            glGetIntegeri_v(GL_VERTEX_BINDING_STRIDE, slot, cast(*GLint)*buffer.stride);
            return buffer;
        }

        bind :: (buffer: Bound_Buffer, slot: u32) {
            if buffer.buffer {
                glBindVertexBuffer(slot, buffer.buffer, buffer.offset, buffer.stride);
            }
        }

        vertex_buffer := get_bound(0);
        instance_buffer := get_bound(1);
        glBindVertexArray(shader.input_vao);
        bind(vertex_buffer, 0);
        bind(instance_buffer, 1);
    }
    if shader.type & .Fragment  stages |= GL_FRAGMENT_SHADER_BIT;
    if shader.type & .Compute   stages |= GL_COMPUTE_SHADER_BIT;

    glUseProgramStages(global_pipeline, stages, shader.program);
    glValidateProgramPipeline(global_pipeline);
}

draw :: ($indexed: bool, count: u32, first: u32 = 0, base_vertex: s32 = 0) {
    mode: GLenum;
    if current_primitive_type == {
    case .Line_List;
        mode = GL_LINES;
    case .Line_Strip;
        mode = GL_LINE_STRIP;
    case .Triangle_List;
        mode = GL_TRIANGLES;
    case .Triangle_Strip;
        mode = GL_TRIANGLE_STRIP;
    }

    #if indexed {
        format := ifx current_index_stride == 4 cast(u32)GL_UNSIGNED_INT else cast(u32)GL_UNSIGNED_SHORT;
        glDrawElementsBaseVertex(mode, count, format, cast(*void) (current_index_stride * first), base_vertex);
    }
    else {
        glDrawArrays(mode, cast(GLint)first, count);
    }
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

resize :: (width: int, height: int) {
    glViewport(0, 0, cast(GLuint)width, cast(GLuint)height);
}
#scope_module
// Unlike D3D11, a single SPIR-V file can actually have multiple entry-points.
// We might want to use this fact later on.

VS_EXTENSION :: ".spvs";
FS_EXTENSION :: ".spfs";
CS_EXTENSION :: ".spcs";

#scope_file

get_input_vao_from_spv :: (spv_bytecode: string) -> GLuint {
    module: SpvReflectShaderModule;
    check :: (result: SpvReflectResult) #expand {
        if result != .SUCCESS {
            log_error("SPIR-V shader reflection failed: %", result);
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
                log_error("OpenGL doesn't support 64 bit integer vertex attributes! Couldn't create input vao!");
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
    current_primitive_type := Primitive_Type.Triangle_List;
    current_index_stride: GLenum; // GL_UNSIGNED_SHORT, GL_UNSIGNED_INT
    current_swap_interval: u32; // We shouldn't trust that the default is 0 actually.
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
