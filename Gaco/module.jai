#module_parameters (BACKEND := DEFAULT_BACKEND, DEBUG := false, REQUEST_HIGH_PERFORMANCE_GPU := true) {
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
    mappings: []Texture_Sampler_Mapping; // Only used for OpenGL SPIR-V backend
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

    Indirect;
    Structured;
    Structured_RW;
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
    Non_Blocking;
}

Texture_Flags :: enum_flags u32 {
    None :: 0;
    Cubemap :: 1;
    Sampled;
    Generate_Mips;
    Is_3D;
    Multisample;
    Render_Target;
    Copy; // This actually makes the 'Texture' a pixel buffer object on OpenGL and a staging texture on D3D11.
    Compute_RW; // RWTexture2D
}

Texture_Format :: enum u16 {
    Unknown :: 0;

    // Fixed point formats.
    R8      :: 1;
    RG8;
    RGBA8;
    RGBA8_SRGB;
    BGRA8;
    BGRA8_SRGB;
    B5G6R5;
    RGB10A2;
    R16;

    // Floating point formats.
    R16F;
    RG16F;
    RGBA16F;
    R32F;
    RG32F;
    RGBA32F;
    RG11B10F;
    RGB9E5F;

    // Integer formats.
    R16I;
    RG16I;
    RGBA16I;
    R32I;
    RG32I;
    RGB32I;
    RGBA32I;

    // Unsigned integer formats
    R16U;
    RG16U;
    RGBA16U;
    R32U;
    RG32U;
    RGB32U;
    RGBA32U;

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

Compare_Op :: enum u8 {
    None  :: 0;
    Never :: 1;
    Less;
    Equal;
    Less_Equal;
    Greater;
    Not_Equal;
    Greater_Equal;
    Always;
}

Stencil_Op :: enum u8 {
    Keep :: 1;
    Zero;
    Replace;
    Incr;
    Decr;
    Invert;
    Incr_Wrap;
    Decr_Wrap;
}

Blend :: enum u8 {
    Zero;
    One;
    Src_Color;
    Inv_Src_Color;
    Src_Alpha;
    Inv_Src_Alpha;
    Dest_Alpha;
    Inv_Dest_Alpha;
    Dest_Color;
    Inv_Dest_Color;
    Src_Alpha_Sat;
    Blend_Factor; // You pass it to the procedure
    Inv_Blend_Factor;
    Src1_Color;
    Inv_Src1_Color;
    Src1_Alpha;
    Inv_Src1_Alpha;
}

Blend_Op :: enum u8 {
    Add :: 1;
    Subtract;
    Rev_Subtract;
    Min;
    Max;
}

Fill_Mode :: enum u8 {
    Wireframe :: 2;
    Solid     :: 3;
}

Cull_Mode :: enum u8 {
    None  :: 1;
    Front;
    Back;
}

Rasterizer_Desc :: struct {
    fill_mode               := Fill_Mode.Solid;
    cull_mode               := Cull_Mode.Back;
    front_counter_clockwise := false;
    depth_bias              : s32 = 0;
    depth_bias_clamp        := 0.0;
    slope_scaled_depth_bias := 0.0;
    depth_clip_enable       := true;
    scissor_enable          := false;
    antialiased_line_enable := false;
}

Blend_Write_Mask :: enum_flags u8 {
    Red    :: 1;
    Green  :: 2;
    Blue   :: 4;
    Alpha  :: 8;
    All    :: 15;
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


Depth_Stencil_Desc :: struct {
    depth_enable := true;
    depth_write := true;
    depth_func := Compare_Op.Less_Equal;

    stencil_enable := true;
    stencil_read_mask : u8 = 0xFF;
    stencil_write_mask: u8 = 0xFF;

    front_face := Stencil_Face_Desc.{};
    back_face := Stencil_Face_Desc.{};
}

Stencil_Face_Desc :: struct {
    fail_op, depth_fail_op, pass_op := Stencil_Op.Keep;
    compare_op := Compare_Op.Always;
}

Blend_Desc :: struct {
    blend_enable     := false;
    src_blend        := Blend.One;
    dest_blend       := Blend.Zero;
    blend_op         := Blend_Op.Add;
    src_blend_alpha  := Blend.One;
    dest_blend_alpha := Blend.Zero;
    blend_op_alpha   := Blend_Op.Add;
    write_mask       := Blend_Write_Mask.All;
    alpha_to_coverage_enable := false;
}

Viewport_Desc :: struct {
    x, y, width, height: float;
    near_depth := 0.0;
    far_depth := 1.0;
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

// This is used for SPIR-V files because the sampler and texture indices
// are the same in OpenGL so we have to have a system to map our seperate
// sampler and texture indices.
Texture_Sampler_Mapping :: struct {
    mapped_index: u8;
    texture_index: u8;
    sampler_index: u8;
    stage: Shader_Type;

    NO_SAMPLER :: 0xFF;
}

Shader_Header :: struct {
    magic: u32;
    version: u32;
    backend: Shader_Backend;
    type: Shader_Type;
    mapping_count: u16; // Only used for SPIR-V
    vs_size: u32;
    fs_size: u32;
    cs_size: u32;
}

compile_shader_from_memory :: (source: string, type: Shader_Type, debug_file_name: string, defines := string.[]) -> string, bool {
    bytecode, ok := compile_shader_to_bytecode(source, type, debug_file_name, defines,, temp);
    if !ok return "", false;

    backend :: #ifx BACKEND == .D3D11 Shader_Backend.DXBC else Shader_Backend.SPIR_V;

    header := Shader_Header.{
        magic = GACO_MAGIC,
        version = 1,
        backend = backend,
        type = type,
        mapping_count = cast(u16)bytecode.mappings.count,
        vs_size = xx bytecode.vs.count,
        fs_size = xx bytecode.fs.count,
        cs_size = xx bytecode.cs.count,
    };

    sb: String_Builder;
    append(*sb, cast(*u8)*header, size_of(Shader_Header));
    append(*sb, cast(*u8)bytecode.mappings.data, bytecode.mappings.count * size_of(Texture_Sampler_Mapping));
    append(*sb, bytecode.vs);
    append(*sb, bytecode.fs);
    append(*sb, bytecode.cs);
    return builder_to_string(*sb), true;
}

compile_shader :: (file_name: string, output_file_name: string, type: Shader_Type, defines := string.[]) -> bool {
    push_allocator(temp);
    source, ok := read_entire_file(file_name, zero_terminated=true);
    if !ok return false;

    file_data:, ok = compile_shader_from_memory(source, type, file_name, defines);
    if !ok return false;

    return write_entire_file(output_file_name, file_data);
}

load_shader :: (file_name: string) -> Shader {
    source, ok := read_entire_file(file_name,, temp);
    if !ok  return .{};
    return load_shader_from_memory(source, file_name);
}

load_shader_from_memory :: (source: string, debug_name := "") -> Shader {
    cursor := source.data;
    header := (cast(*Shader_Header)cursor).*;

    if header.magic != GACO_MAGIC {
        log_error("[Gaco] Shader magic is wrong! Expected: % Got: %", formatInt(GACO_MAGIC, 16), formatInt(header.magic, 16));
        return .{};
    }

    bytecode: Shader_Bytecode;

    cursor += size_of(Shader_Header);
    bytecode.mappings.data = cast(*Texture_Sampler_Mapping)cursor;
    bytecode.mappings.count = header.mapping_count;

    cursor += header.mapping_count * size_of(Texture_Sampler_Mapping);
    bytecode.vs.data = cursor;
    bytecode.vs.count = header.vs_size;

    cursor += header.vs_size;
    bytecode.fs.data = cursor;
    bytecode.fs.count = header.fs_size;

    cursor += header.fs_size;
    bytecode.cs.data = cursor;
    bytecode.cs.count = header.cs_size;

    return load_shader_from_bytecode(bytecode, header.type, debug_name);
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

create_texture_from_file :: (file_name: string, mip_levels: u32 = 1, format := Texture_Format.RGBA8, flags := Texture_Flags.Sampled) -> Texture {
    bytes, ok := read_entire_file(file_name,, temp);
    if !ok return .{};

    return create_texture_from_memory(bytes, mip_levels, format, flags);
}

create_texture_from_memory :: (memory: string, mip_levels: u32 = 1, format := Texture_Format.RGBA8, flags := Texture_Flags.Sampled) -> Texture {
    width, height, file_channels: s32;

    buffer := stbi_load_from_memory(memory.data, cast(s32)memory.count, *width, *height, *file_channels, format_to_channels(format));
    defer if buffer stbi_image_free(buffer);

    if !buffer {
        log_error("[Gaco] Failed to load image from memory.");
        return .{};
    }

    return create_texture(.[buffer], cast(u32)width, cast(u32)height, 1, mip_levels, format, flags);
}

create_texture_array_from_files :: (file_names: []string, mip_levels: u32 = 1, format := Texture_Format.RGBA8, flags := Texture_Flags.Sampled) -> Texture {
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
            // This is probably an error most of the time, maybe a warning would be in place
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

// Allocates on temp
// NOTE(Yasin): This creates a huge performance penalty.
// So it's advised to use this only when debugging.
read_buffer :: (buffer: *Buffer, copy_buffer_to_use: *Buffer(.Copy) = null) -> *void {
    buffer_to_map: *Buffer(.Copy) = ---;
    temp_copy_buffer: Buffer(.Copy);
    defer if is_valid(temp_copy_buffer) destroy_buffer(*temp_copy_buffer);

    if copy_buffer_to_use {
        buffer_to_map = copy_buffer_to_use;
    }
    else {
        #if buffer.type == .Copy {
            buffer_to_map = buffer;
        }
        else {
            temp_copy_buffer = create_buffer(null, buffer.size / buffer.stride, buffer.stride, .Copy);
            buffer_to_map = *temp_copy_buffer;
        }
    }

    copy_buffer(buffer, buffer_to_map);

    data := alloc(buffer.size,, temp);

    mapped_data := map_buffer(buffer_to_map, .Read);
    memcpy(data, mapped_data, buffer.size);
    unmap_buffer(buffer_to_map);
    return data;
}

create_sampler :: inline (filtering := Sampler_Filtering.Linear, edge_handling := Sampler_Edge_Handling.Clamp, border_color := Vector4.{0,0,0,0}, max_anisotropy: u32 = 1, compare_op := Compare_Op.None, debug_name := "") -> Sampler {
    return create_sampler(filtering, filtering, filtering, edge_handling, edge_handling, edge_handling, border_color, max_anisotropy, compare_op, debug_name);
}

set_rasterizer_state :: (desc: Rasterizer_Desc) {
    gaco_state.rasterizer = desc;
    backend_set_rasterizer_state(desc);
}
set_blend_state :: (desc: Blend_Desc, alpha_to_coverage_enable := false, blend_factor := Vector4.{}, sample_mask: u32 = 0xFFFF_FFFF) {
    gaco_state.independent_blend = false;
    gaco_state.blend_count = 1;
    gaco_state.blends[0] = desc;
    gaco_state.alpha_to_coverage = alpha_to_coverage_enable;
    gaco_state.blend_factor = blend_factor;
    gaco_state.sample_mask = sample_mask;

    backend_set_blend_state(desc, alpha_to_coverage_enable, blend_factor, sample_mask);
}

set_blend_states :: (descs: []Blend_Desc, alpha_to_coverage_enable := false, blend_factor := Vector4.{}, sample_mask: u32 = 0xFFFF_FFFF) {
    assert(descs.count <= 8);

    gaco_state.independent_blend = true;
    gaco_state.blend_count = descs.count;
    memcpy(gaco_state.blends.data, descs.data, size_of(Blend_Desc) * descs.count);
    gaco_state.alpha_to_coverage = alpha_to_coverage_enable;
    gaco_state.blend_factor = blend_factor;
    gaco_state.sample_mask = sample_mask;

    backend_set_blend_states(descs, alpha_to_coverage_enable, blend_factor, sample_mask);
}

set_depth_stencil_state :: (desc: Depth_Stencil_Desc, stencil_ref: u8 = 0xFF) {
    gaco_state.depth_stencil = desc;
    gaco_state.stencil_ref = stencil_ref;

    backend_set_depth_stencil_state(desc, stencil_ref);
}

set_viewport :: (desc: Viewport_Desc) {
    gaco_state.viewport = desc;
    backend_set_viewport(desc);
}

set_scissor :: (desc: Rect) {
    gaco_state.scissor = desc;
    backend_set_scissor(desc);
}

set_render_target :: (render_target: Render_Target) {
    gaco_state.render_target = render_target;
    backend_set_render_target(render_target);
}

set_primitive_type :: (primitive_type: Primitive_Type) {
    gaco_state.primitive_type = primitive_type;
    backend_set_primitive_type(primitive_type);
}

push_rasterizer_state :: (desc: Rasterizer_Desc) #expand {
    saved_rs := gaco_state.rasterizer;
    set_rasterizer_state(desc);
    `defer set_rasterizer_state(saved_rs);
}

push_depth_stencil_state :: (desc: Depth_Stencil_Desc, stencil_ref: u8 = 0xFF) #expand {
    saved_ds  := gaco_state.depth_stencil;
    saved_ref := gaco_state.stencil_ref;
    set_depth_stencil_state(desc, stencil_ref);
    `defer set_depth_stencil_state(saved_ds, saved_ref);
}

push_blend_state :: (desc: Blend_Desc, alpha_to_coverage_enable := false, blend_factor := Vector4.{}, sample_mask: u32 = 0xFFFF_FFFF) #expand {
    saved_independent := gaco_state.independent_blend;
    saved_count       := gaco_state.blend_count;
    saved_blends      := gaco_state.blends;
    saved_a2c         := gaco_state.alpha_to_coverage;
    saved_factor      := gaco_state.blend_factor;
    saved_mask        := gaco_state.sample_mask;

    set_blend_state(desc, alpha_to_coverage_enable, blend_factor, sample_mask);

    `defer {
        if saved_independent {
            slice: []Blend_Desc;
            slice.data = saved_blends.data;
            slice.count = saved_count;
            set_blend_states(slice, saved_a2c, saved_factor, saved_mask);
        } else {
            set_blend_state(saved_blends[0], saved_a2c, saved_factor, saved_mask);
        }
    }
}

push_viewport :: (desc: Viewport_Desc) #expand {
    saved_viewport := gaco_state.viewport;
    set_viewport(desc);
    `defer set_viewport(saved_viewport);
}

push_scissor :: (desc: Rect) #expand {
    saved_scissor := gaco_state.scissor;
    set_scissor(desc);
    `defer set_scissor(saved_scissor);
}

push_render_target :: (render_target: Render_Target) #expand {
    saved_rt := gaco_state.render_target;
    set_render_target(render_target);
    `defer set_render_target(saved_rt);
}

push_primitive_type :: (primitive_type: Primitive_Type) #expand {
    saved_pt := gaco_state.primitive_type;
    set_primitive_type(primitive_type);
    `defer set_primitive_type(saved_pt);
}

debug_region :: (name: string) #expand {
    begin_debug_region(name);
    `defer end_debug_region();
}

free :: (bytecode: Shader_Bytecode) {
    if bytecode.mappings array_free(bytecode.mappings);
    if bytecode.vs  free(bytecode.vs);
    if bytecode.fs  free(bytecode.fs);
    if bytecode.cs  free(bytecode.cs);
}

gaco_state : struct {
    viewport: Viewport_Desc;
    scissor: Rect;
    rasterizer: Rasterizer_Desc;

    independent_blend: bool;
    blends: [8]Blend_Desc;
    blend_count: int = 1;
    alpha_to_coverage: bool;
    blend_factor: Vector4;
    sample_mask: u32;

    depth_stencil: Depth_Stencil_Desc;
    stencil_ref: u8 = 0xFF;

    render_target: Render_Target;
    primitive_type: Primitive_Type;
}

#if BACKEND == {
case .D3D11;
#load "backends/d3d11.jai";
case .OpenGL;
#load "backends/opengl.jai";

#import,dir "modules/spirv_reflect";
DXC :: #import,dir "modules/dxc_compiler";
#if OS == .LINUX {
    #import,dir "modules/EGL";
}
case .Metal;
#load "backends/metal.jai";
}


#scope_module

#if REQUEST_HIGH_PERFORMANCE_GPU && OS == .WINDOWS {
    #program_export
    NvOptimusEnablement: u32 = 1;
    #program_export
    AmdPowerXpressRequestHighPerformance: s32 = 1;
}

Shader_Backend :: enum u8 {
    Unspecified :: 0;
    DXBC :: 1;
    SPIR_V;
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

max_mip_levels :: inline (width: u32, height: u32) -> u32 {
    mip_levels: u32 = 0;
    max_dim := max(width, height);
    while max_dim > 0 {
        mip_levels += 1;
        max_dim >>= 1;
    }
    return mip_levels;
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

// FNV-1a
get_plain_old_data_hash :: (my_struct_with_no_pointers: $T) -> u32 {
    data: []u8;
    data.data = cast(*u8)*my_struct_with_no_pointers;
    data.count = size_of(T);

    hash: u32 = 0x811c9dc5;
    prime :: 0x01000193;

    for data {
        hash ^= cast(u32)it;
        hash *= prime;
    }
    return hash;
}

compare_plain_old_data :: (d0: $T, d1: T) -> bool{
    return memcmp(*d0, *d1, size_of(T)) == 0;
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

    // Unsigned integer
    2,  // R16U
    4,  // RG16U
    8,  // RGBA16U
    4,  // R32U
    8,  // RG32U
    12, // RGB32U
    16, // RGBA32U

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
#import "Hash_Table";
#import "Math";

#scope_file
#import "stb_image";
