#module_parameters (BACKEND := DEFAULT_BACKEND, DEBUG:=false) {
    Backend_Type :: enum u32 #specified {
        OpenGL :: 0;
        D3D11  :: 1;
        Metal  :: 2;
    };

    DEFAULT_BACKEND :: #run -> Backend_Type {
        #if      OS == .WINDOWS || OS == .XBOX    return .D3D11;
        else #if OS == .LINUX   || OS == .ANDROID return .OpenGL;
        else #if OS == .MACOS   || OS == .IOS     return .Metal;
    }

    //
    // Note that you have to add this to your main program to enable DEBUG while using the D3D11 backend:
    // D3D11 :: #import "d3d11"()(INCLUDE_DEBUG_BINDINGS=true);
    //
}

Shader_Type :: enum_flags u32 {
    Unspecified :: 0;
    Vertex :: 1;
    Fragment;
    Compute;
};

Shader_Bytecode :: struct {
    vs: string;
    fs: string;
    cs: string;
}

Primitive_Type :: enum u32 {
    Line_List;
    Line_Strip;

    Triangle_List;
    Triangle_Strip;
}

// We use HLSL naming here since we expect it to be used for all backends.
Buffer_Type :: enum u32 {
    Vertex;
    Index;
    Constant;
    Copy;

    Draw_Indirect;
    Dispatch_Indirect;

    Structured;
    RWStructured;
}

Buffer_Usage :: enum u32 {
    Default;
    Dynamic;
    Immutable;
}

Map_Flags :: enum_flags u32 {
    Read;
    Write;
}

Texture_Flags :: enum_flags u32 {
    None :: 0;
    SRGB :: 1;
    Cubemap;
    Generate_Mips;
    RWCompute; // @Rename
}

Sampler_Filtering :: enum u32 {
    Linear;
    Nearest;
}

Sampler_Edge_Handling :: enum u32 {
    Wrap;
    Mirror;
    Clamp;
    Border;
}

// Helper struct for creating Draw_Indirect buffers.
// These are the same for all rendering APIs out there.
Draw_Indirect_Args :: struct(indexed: bool) {
    count: u32;
    instance_count: u32;
    first: u32;
    #if indexed {
        base_vertex: s32;
    }
    first_instance: u32;
}

// NOTE(Yasin): If you want to add a new state or change an existing one, remember to do it on init as well.
Blend_State :: enum u32 #specified {
    None  :: 0;
    Alpha :: 1;
}

// ^^
Rasterizer_State :: enum u32 #specified {
    Default    :: 0;
    Front_Cull :: 1;
    No_Cull    :: 2;
    Scissor    :: 3;
}

Rect :: struct {
    x, y, w, h : s32 = 0;
}

// compile_shader and load_shader create and load separate files for each shader type.
// If you want to implement something like a single package file for your shaders,
// consider using compile_shader_to_bytecode and load_shader_from_bytecode.

compile_shader :: (file_name: string, output_file_without_extension: string, type: Shader_Type) -> bool {
    push_allocator(temp);
    source, read_ok := read_entire_file(file_name, zero_terminated=true);
    if !read_ok return false;

    bytecode, compile_ok := compile_shader_to_bytecode(source, type, path_filename(file_name));
    if !compile_ok return false;
    if type & .Vertex {
        write_ok := write_entire_file(join(output_file_without_extension, VS_EXTENSION), bytecode.vs);
        if !write_ok return false;
    }

    if type & .Fragment {
        write_ok := write_entire_file(join(output_file_without_extension, FS_EXTENSION), bytecode.fs);
        if !write_ok return false;
    }

    if type & .Compute {
        write_ok := write_entire_file(join(output_file_without_extension, CS_EXTENSION), bytecode.cs);
        if !write_ok return false;
    }

    return true;
}


load_shader :: (file_name_without_extension: string, type: Shader_Type) -> Shader {
    push_allocator(temp);
    bytecode: Shader_Bytecode;
    ok := false;

    if type & .Vertex {
        file_name := join(file_name_without_extension, VS_EXTENSION);
        bytecode.vs, ok = read_entire_file(file_name);
        if !ok return .{};
    }

    if type & .Fragment {
        file_name := join(file_name_without_extension, FS_EXTENSION);
        bytecode.fs, ok = read_entire_file(file_name);
        if !ok return .{};
    }

    if type & .Compute {
        file_name := join(file_name_without_extension, CS_EXTENSION);
        bytecode.cs, ok = read_entire_file(file_name);
        if !ok return .{};
    }
    return load_shader_from_bytecode(bytecode, type);
}

create_buffer :: (data: *$T, $type: Buffer_Type, usage := Buffer_Usage.Default) -> Buffer(type) {
    data_pointer : *void = ---;
    DATA_INFO :: type_info(T);
    count, stride: u32;
    #if DATA_INFO.type == .ARRAY {
        if type == .Index {
            element_info := (cast(*Type_Info_Array)DATA_INFO).element_type;
            assert(element_info == type_info(u32) || element_info == type_info(u16), "Index buffers can only be created with u16 or u32 arrays. Got: %\n", T);
        }

        stride = cast(u32)size_of(type_of(data.*[0]));
        count = cast(u32)data.count;
        data_pointer = data.data;
    }
    else {
        assert(type != .Index, "Index buffers can only be created with u16 or u32 arrays. Got: %\n", T);

        stride = cast(u32)size_of(type_of(data.*));
        count = 1;
        data_pointer = data;
    }
    return create_buffer(data_pointer, count, stride, type, usage);
}

create_texture_from_file :: (file_name: string, mip_levels : u32 = 1, flags := Texture_Flags.None, desired_channels : u32 = 0) -> Texture {
    bytes, ok := read_entire_file(file_name,, temp);

    if !ok return .{};
    return create_texture_from_memory(bytes, mip_levels, flags, desired_channels);
}

create_texture_from_memory :: (memory: string, mip_levels : u32 = 1, flags := Texture_Flags.None, desired_channels: u32 = 0) -> Texture {
    width, height, channels: s32;

    // NOTE(Yasin): Unfortunately, this is allocated with malloc and there is no way to read into an existing buffer.
    // https://github.com/nothings/stb/issues/58

    buffer := stbi_load_from_memory(memory.data, cast(s32)memory.count, *width, *height, *channels, cast(s32) desired_channels);
    defer stbi_image_free(buffer);
    return create_texture(buffer, cast(u32)width, cast(u32)height, ifx desired_channels desired_channels else cast(u32)channels, mip_levels, flags);
}

create_texture_array_from_files :: (file_names: []string, mip_levels: u32 = 1, flags := Texture_Flags.None, desired_channels : u32 = 0) -> Texture {
    data := NewArray(file_names.count, *u8,, temp);
    defer for data {
        if it  stbi_image_free(it);
    }

    texture_width, texture_height, texture_channels: u32;
    for file_names {
        bytes, ok := read_entire_file(it,, temp);
        if !ok return .{};
        width, height, channels: s32;

        data[it_index] = stbi_load_from_memory(bytes.data, cast(s32)bytes.count, *width, *height, *channels, cast(s32)desired_channels);

        if it_index == 0 {
            texture_width    = cast(u32)width;
            texture_height   = cast(u32)height;
            texture_channels = ifx desired_channels desired_channels else cast(u32)channels;
        }
    }

    return create_texture_array(data, texture_width, texture_height, texture_channels, mip_levels, flags);
}

#if BACKEND == {
case .D3D11;
#load "backends/d3d11.jai";
case .OpenGL;
#load "backends/opengl.jai";
case .Metal;
#load "backends/metal.jai";
}

#scope_module
VS_ENTRY_POINT :: "vertex_main";
FS_ENTRY_POINT :: "fragment_main";
CS_ENTRY_POINT :: "compute_main";

#import "String";
#import "File";
#import "Basic";

#scope_file
#import "stb_image";
