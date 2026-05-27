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

Shader_Bytecode :: struct {
    vs: string;
    fs: string;
    cs: string;
}

Shader_Type :: enum_flags u8 {
    Unspecified :: 0;
    Vertex :: 1;
    Fragment;
    Compute;
};

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

    Indirect; // Draw indirect or dispatch indirect buffer

    Structured;
    RWStructured;
}

Buffer_Usage :: enum u32 {
    Default;
    Dynamic;
    Immutable;
}

// Use this in create_buffer maybe?
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

Texture_Format :: enum u16 {
    Unknown :: 0;

    R8      :: 1;        // Fixed point formats.
    RG8;
    RGBA8;
    RGBA8_SRGB;
    BGRA8;
    BGRA8_SRGB;
    B5G6R5;
    RGB10A2;
    R16;

    R16F;   // Floating point formats.
    RG16F;
    RGBA16F;
    R32F;
    RG32F;
    RGBA32F;
    RG11B10F;
    RGB9E5F;

    R16I;           // Integer formats.
    RG16I;
    RGBA16I;
    R32I;
    RG32I;
    RGB32I;
    RGBA32I;

    // Block compression formats.
    BC6U; // Unsigned float16
    BC6S; // Signed float16
    BC7;
    BC7_SRGB;

    // Depth formats.
    D16;
    D24S8;
    D32F;
    D32FS8;
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
// This is same for all the rendering APIs out there.
Draw_Indirect_Args :: struct(indexed: bool) {
    count: u32;
    instance_count: u32;
    first: u32;
    #if indexed {
        base_vertex: s32;
    }
    first_instance: u32;
}


// If you want to add a mode, remember to do it on init_preloaded_modes as well.
Blend_Mode :: enum u32 {
    None;
    Alpha;
}

Rasterizer_Mode :: enum u32 {
    Default;
    Front_Cull;
    No_Cull;
    Scissor;
}
Depth_Stencil_Mode :: enum u32 {
    Depth_Stencil;
    No_Depth;
    No_Depth_Mask;
    Depth_Reversed;
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
    x, y, width, height: s32;
}

Box :: struct {
    x, y, z: s32;
    width, height, depth: s32;
}

compile_shader :: (file_name: string, output_file_name: string, type: Shader_Type) -> bool {
    push_allocator(temp);
    source, ok := read_entire_file(file_name, zero_terminated=true);
    if !ok return false;

    bytecode:, ok = compile_shader_to_bytecode(source, type, path_filename(file_name));
    if !ok return false;

    backend :: #ifx BACKEND == .D3D11 Shader_Backend.DXBC else Shader_Backend.SPIR_V;
    header := Shader_Header.{
        magic = GACO_MAGIC,
        version = 1,
        backend = backend,
        type = type,
        sampler_mapping_count = 0, // for now
        vs_size = xx bytecode.vs.count,
        fs_size = xx bytecode.fs.count,
        cs_size = xx bytecode.cs.count,
    };

    mapping_size := header.sampler_mapping_count * size_of(Sampler_Mapping);
    sb: String_Builder;
    append(*sb, cast(*u8)*header, size_of(Shader_Header));
    // append(*sb, *sampler_mappings, mapping_size); @Incomplete
    append(*sb, bytecode.vs);
    append(*sb, bytecode.fs);
    append(*sb, bytecode.cs);
    return write_entire_file(output_file_name, *sb);
}

load_shader :: (file_name: string) -> Shader {
    push_allocator(temp);
    data, ok := read_entire_file(file_name);
    if !ok  return .{};
    return load_shader_from_memory(data);
}

load_shader_from_memory :: (data: string) -> Shader {
    header := (cast(*Shader_Header)data.data).*;
    if header.magic != GACO_MAGIC {
        log_error("[Gaco] Shader magic is wrong! Expected: % Got: %", GACO_MAGIC, header.magic);
        return .{};
    }
    bytecode: Shader_Bytecode;

    mappings_offset := size_of(Shader_Header);

    vs_offset := mappings_offset + (header.sampler_mapping_count * size_of(Sampler_Mapping));
    fs_offset := vs_offset + header.vs_size;
    cs_offset := fs_offset + header.fs_size;

    bytecode.vs.data = data.data + vs_offset;
    bytecode.vs.count = header.vs_size;

    bytecode.fs.data = data.data + fs_offset;
    bytecode.fs.count = header.fs_size;

    bytecode.cs.data = data.data + cs_offset;
    bytecode.cs.count = header.cs_size;

    return load_shader_from_bytecode(bytecode, header.type);
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

create_texture_from_file :: (file_name: string, mip_levels: u32 = 1, format := Texture_Format.RGBA8, flags := Texture_Flags.None) -> Texture {
    bytes, ok := read_entire_file(file_name,, temp);
    if !ok return .{};

    return create_texture_from_memory(bytes, mip_levels, format, flags);
}

create_texture_from_memory :: (memory: string, mip_levels: u32 = 1, format := Texture_Format.RGBA8, flags := Texture_Flags.None) -> Texture {
    width, height, file_channels: s32;

    buffer := stbi_load_from_memory(memory.data, cast(s32)memory.count, *width, *height, *file_channels, format_to_channels(format));
    defer if buffer stbi_image_free(buffer);

    if !buffer {
        log_error("[Gaco] Failed to load image from memory.");
        return .{};
    }

    return create_texture(.[buffer], cast(u32)width, cast(u32)height, 1, mip_levels, format, flags);
}

create_texture_array_from_files :: (file_names: []string, mip_levels: u32 = 1, format := Texture_Format.RGBA8, flags := Texture_Flags.None) -> Texture {
    data := NewArray(file_names.count, *u8,, temp);
    defer for data {
        if it stbi_image_free(it);
    }

    texture_width, texture_height: u32;

    for file_names {
        bytes, ok := read_entire_file(it,, temp);
        if !ok {
            log_error("[Gaco] Failed to read file for texture array: %", it);
            return .{};
        }

        width, height, file_channels: s32;
        data[it_index] = stbi_load_from_memory(bytes.data, cast(s32)bytes.count, *width, *height, *file_channels, format_to_channels(format));

        if !data[it_index] {
            log_error("[Gaco] STBI Failed to decode image for texture array: %", it);
            return .{};
        }

        if it_index == 0 {
            texture_width  = cast(u32)width;
            texture_height = cast(u32)height;
        } else if cast(u32)width != texture_width || cast(u32)height != texture_height {
            log_error("[Gaco] Texture array mismatch: % dimensions do not match the first slice.", it);
            return .{};
        }
    }

    count := cast(u32)file_names.count;
    return create_texture(data, texture_width, texture_height, count, mip_levels, format, flags);
}

// Use write_buffer for buffers with .Dynamic usage and update_buffer for those with .Default usage.
write_buffer :: inline (buffer: *Buffer, data: $T) {
    data_pointer: *void = ---;
    size: s64 = ---;
    #if type_info(T).type == .ARRAY {
        ELEMENT_SIZE :: size_of(type_of(data[0]));
        if ELEMENT_SIZE != buffer.stride {
            buffer.stride = ELEMENT_SIZE;
        }
        data_pointer = data.data;
        size = data.count * ELEMENT_SIZE;
    }
    else {
        data_pointer = *data;
        size = size_of(T);
    }
    write_buffer(buffer, data_pointer, ifx size < buffer.size else buffer.size);
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
#import,dir "spirv_reflect";
case .Metal;
#load "backends/metal.jai";
}

#scope_module

Shader_Backend :: enum u8 {
    Unspecified :: 0;
    DXBC :: 1;
    SPIR_V;
}

Shader_Header :: struct {
    magic: u32;
    version: u32;
    backend: Shader_Backend;
    type: Shader_Type;
    sampler_mapping_count: u16; // Only used for SPIR-V
    vs_size: u32;
    fs_size: u32;
    cs_size: u32;
}

// This is used for SPIR-V files because the sampler and texture indices
// are the same in OpenGL so they have to match.
Sampler_Mapping :: struct {
    mapped_index: u8;
    texture_index: u8;
    sampler_index: u8;
    stage: Shader_Type;
}

GACO_MAGIC :: 0x4F434147; // "GACO"
VS_ENTRY_POINT :: "vertex_main";
FS_ENTRY_POINT :: "fragment_main";
CS_ENTRY_POINT :: "compute_main";

INSTANCE_PREFIX :: "INST_";

format_to_channels :: (format: Texture_Format) -> s32 {
    if format == {
        case .R8;         return 1;
        case .RG8;        return 2;
        case .RGBA8;      return 4;
        case .RGBA8_SRGB; return 4;
        case .BGRA8;      return 4;
        case .BGRA8_SRGB; return 4;
        case;             return 4;
    };
}

// This name wouldn't make sense if the enum values jump, but whatever.
enum_count :: ($T: Type) -> s64 {
    low, high := enum_range_given_info(type_info(T));
    return high + 1;
}

is_block_compression :: inline (format: Texture_Format) -> bool {
    return format >= .BC6U && format <= .BC7_SRGB;
}

get_semantic_info :: (semantic: string) -> is_instance: bool, step_rate: u32 {
    if starts_with(semantic, INSTANCE_PREFIX) {
        step_rate: u32 = 1;

        // Get step rate from the semantic
        // NOTE(Yasin): If the numbered characters are the last ones (e.g. TEXTURE0, INST_3)
        // then the number gets passed as semantic index and cannot be seen by this code.

        c := INSTANCE_PREFIX.count;
        if c < semantic.count && is_digit(semantic[c]) { // INST_2_*
            s := advance(semantic, c);
            step_rate=, success, remainder := string_to_int(s, T = u32);
            assert(success);
        }

        return true, step_rate;
    }
    return false, 0;
}

TEXTURE_BYTES_PER_BLOCK :: u32.[
    0,  // Unknown

    // Fixed point
    1,  // R8
    2,  // RG8
    4,  // RGBA8
    4,  // RGBA8_SRGB
    4,  // BGRA8
    4,  // BGRA8_SRGB
    2,  // B5G6R5
    4,  // RGB10A2
    2,  // R16

    // Floating point
    2,  // R16F
    4,  // RG16F
    8,  // RGBA16F
    4,  // R32F
    8,  // RG32F
    16, // RGBA32F
    4,  // RG11B10F
    4,  // RGB9E5F

    // Integer
    2,  // R16I
    4,  // RG16I
    8,  // RGBA16I
    4,  // R32I
    8,  // RG32I
    12, // RGB32I
    16, // RGBA32I

    // Block compression (Bytes per 4x4 block)
    16, // BC6U
    16, // BC6S
    16, // BC7
    16, // BC7_SRGB

    // Depth
    2,  // D16
    4,  // D24S8
    4,  // D32F
    8   // D32FS8 (D32_FLOAT_S8X24_UINT is 64 bits = 8 bytes)
];

#import "String";
#import "File";
#import "Basic";

#scope_file
#import "stb_image";
