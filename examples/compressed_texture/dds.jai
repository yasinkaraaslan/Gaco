// https://learn.microsoft.com/en-us/windows/win32/direct3ddds/dx-graphics-dds-reference
//
// Only BC6 and BC7 are supported because those are the only ones Gaco supports.

load_dds :: (file_name: string) -> bool, DDS_Data {
    content, success := read_entire_file(file_name);
    if !success {
        log_error("[dds] Unable to load file %!", file_name);
        return false, .{};
    }

    success=, data := load_dds_from_memory(content, file_name);
    if !success {
        free(content);
        return false, .{};
    }

    data.memory = content;
    return true, data;
}

load_dds_from_memory :: (_content: string, name: string) -> bool, DDS_Data {
    content := _content;

    magic := (cast(*u32)content.data).*;
    if magic != DDS_MAGIC {
        log_error("[dds] '%' has incorrect magic! Wanted 0x%, got 0x%.", name, formatInt(DDS_MAGIC, 16), formatInt(magic, 16));
        return false, .{};
    }

    advance(*content, size_of(type_of(DDS_MAGIC)));

    if content.count < size_of(DDS_Header) {
        log_error("[dds] '%' is too small to even contain a header!", name);
        return false, .{};
    }

    dds_data: DDS_Data;

    header := cast(*DDS_Header)content.data;
    if header.size != size_of(DDS_Header) {
        log_error("[dds] '%' has incorrect header size! Wanted %, got %.", name, size_of(DDS_Header), header.size);
        return false, dds_data;
    }

    if (header.flags & DDS_HEADER_REQUIRED_FLAGS) != DDS_HEADER_REQUIRED_FLAGS{
        log_error("[dds] '%' has header flags that are not valid! Required ones are %, got %.", name, DDS_HEADER_REQUIRED_FLAGS, header.flags);
        return false, dds_data;
    }

    dds_data.header = header;

    advance(*content, size_of(DDS_Header));

    pixel_format := header.pixel_format;
    if pixel_format.size != size_of(DDS_Pixel_Format) {
        log_error("[dds] '%' has incorrect pixel format structure size! Wanted %, got %.", name, size_of(DDS_Pixel_Format), pixel_format.size);
        return false, dds_data;
    }

    array_size: u32 = 1;

    if !(pixel_format.flags & .Four_CC) || pixel_format.four_cc != DX10_CC {
        log_error("[dds] '%' is not a DX10 DDS (FourCC: %). Only BC6/BC7 (DX10) are supported.", name, get_fourcc(pixel_format.four_cc));
        return false, dds_data;
    }

    if content.count < size_of(DDS_Header_DXT) {
        log_error("[dds] '%' is missing the DX10 header!", name);
        return false, dds_data;
    }

    optional_header := cast(*DDS_Header_DXT)content.data;
    array_size = cast(u32)max(1, optional_header.array_size);

    format := dxgi_to_texture_format(optional_header.format);
    if format == .Unknown {
        log_error("[dds] '%' has unsupported DXGI format % (only BC6/BC7 is supported).", name, optional_header.format);
        return false, dds_data;
    }

    if optional_header.misc_flags & .TEXTURECUBE
        array_size *= 6;

    dds_data.format = format;
    dds_data.optional_header = optional_header;
    advance(*content, size_of(DDS_Header_DXT));

    if header.caps2 & .Cubemap && array_size == 1
        array_size = 6;

    dds_data.array_size = array_size;

    mipmap_count := cast(u32)max(1, header.mipmap_count);
    dds_data.image_data = NewArray(array_size * mipmap_count, *u8);

    for i: 0..array_size-1 {
        for j: 0..mipmap_count-1 {
            index := j + i * mipmap_count;
            mip_width  := cast(u32)max(1, header.width >> j);
            mip_height := cast(u32)max(1, header.height >> j);
            mip_depth  := cast(u32)max(1, header.depth >> j); // Only for 3D textures

            block_width  := (mip_width  + 3) / 4;
            block_height := (mip_height + 3) / 4;
            block_depth  := (mip_depth  + 3) / 4;
            size := block_width * block_height * block_depth * BC67_BYTES_PER_BLOCK;

            if content.count < size {
                log_error("[dds] '%' ran out of image data at mip % of array slice %.", name, j, i);
                return false, dds_data;
            }

            dds_data.image_data[index] = content.data;
            advance(*content, size);
        }
    }

    // We really did something wrong if this fires up.
    assert(content.count == 0);

    return true, dds_data;
}

deinit :: (using dds_data: *DDS_Data) {
    array_free(image_data);
    if memory free(memory);
}

dxgi_to_texture_format :: (format: DXGI_Format) -> Gaco.Texture_Format {
    if format == {
        case .BC6H_UF16;      return .BC6U;
        case .BC6H_SF16;      return .BC6S;
        case .BC7_UNORM;      return .BC7;
        case .BC7_UNORM_SRGB; return .BC7_SRGB;
        case;                 return .Unknown;
    }
}

DDS_Data :: struct {
    header: *DDS_Header;
    optional_header: *DDS_Header_DXT;
    image_data: []*u8; // Index: Mip slice + (Array slice * Mip levels)
    format: Gaco.Texture_Format;
    array_size: u32;
    memory: string; // Owns if not empty
}

DDS_Header :: struct {
    size: u32;
    flags: Flags;
    height: u32;
    width: u32;
    pitch_or_linear_size: u32;
    depth: u32;
    mipmap_count: u32;
    reserved1: [11]u32;
    pixel_format: DDS_Pixel_Format;

    caps:  Caps;
    caps2: Caps2;
    caps3: u32; // Unused
    caps4: u32; // Unused
    reserved2: u32;

    Flags :: enum_flags u32 {
        Caps;
        Height;
        Width;
        Pitch;
        Pixel_Format :: 0x1000;
        Mipmap_Count :: 0x20000;
        Linear_Size  :: 0x80000;
        Depth        :: 0x800000;
    }
    Caps :: enum_flags u32 {
        Complex :: 0x8;
        Texture :: 0x1000;
        Mipmap  :: 0x400000;
    }
    Caps2 :: enum_flags u32 {
        Cubemap            :: 0x200;
        Cubemap_Positive_X :: 0x400;
        Cubemap_Negative_X :: 0x800;
        Cubemap_Positive_Y :: 0x1000;
        Cubemap_Negative_Y :: 0x2000;
        Cubemap_Positive_Z :: 0x4000;
        Cubemap_Negative_Z :: 0x8000;
        Volume             :: 0x200000;
    }
}

DDS_Header_DXT :: struct {
    format: DXGI_Format;
    dimension: DDS_Resource_Dimension;
    misc_flags: DDS_Resource_Misc;
    array_size: u32;
    misc_flags2: Misc_Flags;

    Misc_Flags :: enum u32 {
        Alpha_Mode_Unknown;
        Alpha_Mode_Straight;
        Alpha_Mode_Premultiplied;
        Alpha_Mode_Opaque;
        Alpha_Mode_Custom;
    }
}

DDS_Pixel_Format :: struct {
    size: u32;
    flags: Flags;
    four_cc: u32;
    rgb_bit_count: u32;
    r_bit_mask: u32;
    g_bit_mask: u32;
    b_bit_mask: u32;
    a_bit_mask: u32;

    Flags :: enum_flags u32 {
        Alpha_Pixels;
        Alpha;
        Four_CC;
        RGB          :: 0x40;
        YUV          :: 0x200;
        Luminance    :: 0x20000;
    }
}

// DXGI_FORMAT values used by DDS_HEADER_DXT10
DXGI_Format :: enum u32 {
    UNKNOWN          :: 0;
    BC6H_TYPELESS    :: 94;
    BC6H_UF16;
    BC6H_SF16;
    BC7_TYPELESS;
    BC7_UNORM;
    BC7_UNORM_SRGB;
}

DDS_Resource_Dimension :: enum u32 {
    Unknown;
    Buffer;
    Texture1D;
    Texture2D;
    Texture3D;
}

DDS_Resource_Misc :: enum_flags u32 {
    TEXTURECUBE :: 0x4;
}

#scope_file

get_fourcc :: (n: u32) -> string {
    s: string = ---;
    s.data = (*n).(*u8);
    s.count = 4;
    return s;
}

make_magic4 :: (s: string) -> u32 {
    assert(s.count == 4);
    return (cast(*u32)s.data).*;
}

DX10_CC :: #run make_magic4("DX10");
DDS_MAGIC :: #run make_magic4("DDS ");
DDS_HEADER_REQUIRED_FLAGS : DDS_Header.Flags : .Caps | .Height | .Width | .Pixel_Format;
BC67_BYTES_PER_BLOCK :: 16;
