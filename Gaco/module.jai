#module_parameters (BACKEND := DEFAULT_BACKEND, DEBUG:=false) {
    Backend_Type :: enum u32 {
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
    Cubemap :: 1;
    Generate_Mips;
    Is_3D;
    Multisample;
    Render_Target;
    Depth_Stencil;
    Copy; // This actually makes the 'Texture' a pixel buffer object on OpenGL and a staging texture on D3D11.
    Compute_RW; // RWTexture2D
}

// I only put the most common formats here, for simplicity sake.
// You may extend this if you need more.
// Some combinations (e.g. RGB8) have equivalents
// in OpenGL but not in D3D11.
Texture_Format :: enum u32 {
    Default; // Default one according to the flags, 8 bits per channel most of the time.
    U32; // R32_UINT, R32G32_UINT ...
    SRGB;
    Float16;
    Float32;

    // Block compression formats. These do not care about
    // the channels argument passed to create_texture.
    BC6U; // Unsigned float16
    BC6S; // Signed float16
    BC7;
    BC7_SRGB;
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
// This is the same for all rendering APIs out there.
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
Blend_State :: enum u32 {
    None;
    Alpha;
}

// ^^
Rasterizer_State :: enum u32 {
    Default;
    Front_Cull;
    No_Cull;
    Scissor;
}

// ...
Depth_Stencil_State :: enum u32 {
    Depth_Stencil;
    No_Depth;
    No_Stencil;
    No_Depth_Stencil;
}

Clear_Flags :: enum_flags u32 {
    None :: 0;
    Color :: 1;
    Depth;
    Stencil;
}

Rect :: struct {
    x, y, w, h: s32;
}

Box :: struct {
    x, y, z: s32;
    w, h, d: s32;
}

// compile_shader and load_shader create and load separate files for each shader type.
// If you want to implement something like a single package file for your shaders,
// consider using compile_shader_to_bytecode and load_shader_from_bytecode.

compile_shader :: (file_name: string, output_file_without_extension: string, type: Shader_Type) -> bool {
    push_allocator(temp);
    source, ok := read_entire_file(file_name, zero_terminated=true);
    if !ok return false;

    bytecode:, ok = compile_shader_to_bytecode(source, type, path_filename(file_name));
    if !ok return false;
    if type & .Vertex {
        ok = write_entire_file(join(output_file_without_extension, VS_EXTENSION), bytecode.vs);
        if !ok return false;
    }

    if type & .Fragment {
        ok = write_entire_file(join(output_file_without_extension, FS_EXTENSION), bytecode.fs);
        if !ok return false;
    }

    if type & .Compute {
        ok = write_entire_file(join(output_file_without_extension, CS_EXTENSION), bytecode.cs);
        if !ok return false;
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

create_buffer :: (data: $T, $type: Buffer_Type, usage := Buffer_Usage.Default) -> Buffer(type) {
    data_pointer : *void = ---;
    DATA_INFO :: type_info(T);
    count, stride: u32;
    #if DATA_INFO.type == .ARRAY {
        #if type == .Index {
            ARRAY_INFO :: (cast(*Type_Info_Array)DATA_INFO);
            #assert ARRAY_INFO.element_type == type_info(u32) || ARRAY_INFO.element_type == type_info(u16) "Index buffers can only be created with u16 or u32 arrays.";
        }

        stride = cast(u32)size_of(type_of(data[0]));
        count = cast(u32)data.count;
        data_pointer = data.data;
    }
    else {
        #assert type != .Index "Index buffers can only be created with u16 or u32 arrays.";

        stride = cast(u32)size_of(type_of(data));
        count = 1;
        data_pointer = *data;
    }
    return create_buffer(data_pointer, count, stride, type, usage);
}

create_texture_from_file :: (file_name: string, mip_levels : u32 = 1, format := Texture_Format.Default, flags := Texture_Flags.None, desired_channels : u32 = 0) -> Texture {
    bytes, ok := read_entire_file(file_name,, temp);

    if !ok return .{};
    return create_texture_from_memory(bytes, mip_levels, format, flags, desired_channels);
}

create_texture_from_memory :: (memory: string, mip_levels : u32 = 1, format := Texture_Format.Default, flags := Texture_Flags.None, desired_channels: u32 = 0) -> Texture {
    width, height, channels: s32;

    // NOTE(Yasin): Unfortunately, this is allocated with malloc and there is no way to read into an existing buffer.
    // https://github.com/nothings/stb/issues/58

    buffer := stbi_load_from_memory(memory.data, cast(s32)memory.count, *width, *height, *channels, cast(s32) desired_channels);
    defer stbi_image_free(buffer);
    array_size := width * height * channels;
    return create_texture(.[.{array_size, buffer}], cast(u32)width, cast(u32)height, ifx desired_channels desired_channels else cast(u32)channels, 1, mip_levels, format, flags);
}

create_texture_array_from_files :: (file_names: []string, mip_levels: u32 = 1, format := Texture_Format.Default, flags := Texture_Flags.None, desired_channels : u32 = 0) -> Texture {
    data := NewArray(file_names.count, []u8,, temp);
    defer for data {
        if it  stbi_image_free(it.data);
    }

    texture_width, texture_height, texture_channels: u32;
    for file_names {
        bytes, ok := read_entire_file(it,, temp);
        if !ok return .{};
        width, height, channels: s32;

        data[it_index].data = stbi_load_from_memory(bytes.data, cast(s32)bytes.count, *width, *height, *channels, cast(s32)desired_channels);
        data[it_index].count = width * height * channels;

        if it_index == 0 {
            texture_width    = cast(u32)width;
            texture_height   = cast(u32)height;
            texture_channels = ifx desired_channels desired_channels else cast(u32)channels;
        }
    }
    count : u32 = cast(u32)file_names.count;
    return create_texture(data, texture_width, texture_height, texture_channels, count, mip_levels, format, flags);
}

// Use write_buffer for buffers with .Dynamic usage and update_buffer for those with .Default usage.
write_buffer :: inline (buffer: *Buffer, data: $T) {
    #if type_info(T).type == .ARRAY {
        ELEMENT_SIZE :: size_of(type_of(data[0]));
        if ELEMENT_SIZE != buffer.stride {
            buffer.stride = ELEMENT_SIZE;
        }

        write_buffer(buffer, data.data, data.count * ELEMENT_SIZE);
    }
    else {
        write_buffer(buffer, *data, size_of(T));
    }
}

free :: (bytecode: Shader_Bytecode) {
    if bytecode.vs free(bytecode.vs);
    if bytecode.fs free(bytecode.fs);
    if bytecode.cs free(bytecode.cs);
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

// This name wouldn't make sense if the enum values jump, but whatever.
enum_count :: ($T: Type) -> s64 {
    low, high := enum_range_given_info(type_info(T));
    return high + 1;
}

is_block_compression :: inline (format: Texture_Format) -> bool {
    return format >= .BC6U && format <= .BC7_SRGB;
}

#import "String";
#import "File";
#import "Basic";

#scope_file
#import "stb_image";
