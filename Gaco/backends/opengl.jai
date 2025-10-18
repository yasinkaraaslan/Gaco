Shader :: struct {
    type: Shader_Type;
    input_vao: GLuint;

    vertex_shader: GLuint;
    fragment_shader: GLuint;
    compute_shader: GLuint;
}

// Buffers are typeless in OpenGL but we use the information when binding the buffer.
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
Render_Target :: struct{}

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
        #assert false "This OS doesn't support deinit() right now.";
    }
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
    // @Incomplete
}

compile_shader_to_bytecode :: (source: string, type: Shader_Type, shader_name: string) -> Shader_Bytecode, bool {
    return .{}, true;
}

load_shader_from_bytecode :: (bytecode: Shader_Bytecode, type: Shader_Type) -> Shader {
    return .{};
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
    // @Incomplete
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
        byte_offset := ifx current_index_format == GL_UNSIGNED_INT 4 else 2;

        glDrawElementsBaseVertex(mode, count, current_index_format, cast(*void) (byte_offset * first), base_vertex);
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
        dc := GetDC(main_window);
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
// SPIR-V
VS_EXTENSION :: ".spvs";
FS_EXTENSION :: ".spfs";
CS_EXTENSION :: ".spcs";

#scope_file

using GL_State: struct {
    main_window: WT.Window_Type;
    global_pipeline: GLuint;

    current_primitive_type := Primitive_Type.Triangle_List;
    current_index_format: GLenum; // GL_UNSIGNED_SHORT, GL_UNSIGNED_INT
    current_swap_interval: u32; // We shouldn't trust that the default is 0 actually.
}
#import "GL";
#if OS == .WINDOWS {
    #import "Windows";
}
else #if OS == .LINUX {
    #import "X11";
}

WT :: #import "Window_Type";
