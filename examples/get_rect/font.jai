#run {
    Gaco.compile_shader("shaders/sources/text.hlsl", "shaders/text", .Vertex | .Fragment);
}

MAX_CHARACTERS :: 512;

fonts_init :: () {
    error := FT_Init_FreeType(*FtLibrary);
    TextShader = Gaco.load_shader("shaders/text", .Vertex | .Fragment);
    assert(!error);

    TextVertexBuffer = Gaco.create_buffer(null, MAX_CHARACTERS * 4, size_of(Text_Vertex_Data), .Vertex, .Dynamic);
    index_data : [6*MAX_CHARACTERS]u16;
    for 0..MAX_CHARACTERS-1 {
        base := cast(u16) (it*4);
        index_data[6*it+0]=base+0;
        index_data[6*it+1]=base+1;
        index_data[6*it+2]=base+2;
        index_data[6*it+3]=base+2;
        index_data[6*it+4]=base+1;
        index_data[6*it+5]=base+3;
    }

    TextIndexBuffer = Gaco.create_buffer(index_data, .Index, .Immutable);

    // This should be replaced in the next resize call.
    WindowProjConstantBuffer = Gaco.create_buffer(Matrix4_Identity, .Constant);

    v : struct {
        v: Vector2 #align 16;
    };
    TextPosConstantBuffer = Gaco.create_buffer(v, .Constant, .Dynamic);
}

load_font :: (file_name: string, size: int) -> *Font {
    content := cast([]u8)read_entire_file(file_name); // @Leak
    return load_font_from_memory(content, size);
}

load_font_from_memory :: (memory: []u8, size: int) -> *Font {
    font := New(Font);

    error := FT_New_Memory_Face(FtLibrary, memory.data, cast(s32) memory.count, 0, *font.face);
    if error {
        log_error("Error loading font, Error Code: %\n", error);
        return null;
    }
    font.has_kerning = FT_HAS_KERNING(font.face);
    error = FT_Set_Pixel_Sizes(font.face, 0, cast(u32)size);

    metrics := font.face.size.metrics;
    font.character_height = xx size;
    font.em_width = xx metrics.x_ppem;
    font.typical_ascender = metrics.ascender / 64.0;
    font.typical_descender = metrics.descender / 64.0;
    font.ascent = font.typical_ascender + font.typical_descender;
    texture_width, texture_height : u32;
    for 32..126 {
        if FT_Load_Char(font.face, cast(u32)it, FT_LOAD_BITMAP_METRICS_ONLY) != 0 {
            log_error("Unable to load character: '%'\n", it);
            continue;
        };

        // We are just putting them on a straight line
        using font.face.glyph.bitmap;
        texture_width += width;
        if rows > texture_height  texture_height = rows;
    }

    font.texture = Gaco.create_texture(.[], texture_width, texture_height, 1);


    x : u32;
    for 32..126 {
        if FT_Load_Char(font.face, cast(u32)it, FT_LOAD_RENDER) != 0 {
            log_error("Unable to load character for render: '%'\n", it);
            continue;
        };
        using font.face.glyph;
        rect := Gaco.Rect.{
            x = xx x,
            y = 0,
            width = xx bitmap.width,
            height = xx bitmap.rows
        };

        glyph := *font.glyphs[it];
        glyph.advance = advance.x / 64.0;


        glyph.bitmap_width = bitmap.width;
        glyph.bitmap_height = bitmap.rows;
        glyph.bitmap_left = bitmap_left;
        glyph.bitmap_top = bitmap_top;

        // Space doesn't need a texture
        if it == #char " " continue;
        u0 := cast(float) x / cast(float) texture_width;
        u1 := u0 + cast(float) bitmap.width / cast(float) texture_width;
        v0 := 0.0;
        v1 := v0 + cast(float) bitmap.rows / cast(float) texture_height;

        p0 : Vector2;
        p1 := p0 + .{x= cast(float) bitmap.width};
        p2 := p0 + .{y= cast(float) bitmap.rows};
        p3 := p1 + .{y= cast(float) bitmap.rows};

        glyph.vertices[0] = .{p0, .{u0, v0}};
        glyph.vertices[1] = .{p1, .{u1, v0}};
        glyph.vertices[2] = .{p2, .{u0, v1}};
        glyph.vertices[3] = .{p3, .{u1, v1}};

        Gaco.update_texture(*font.texture, bitmap.buffer, rect);
        x += bitmap.width;
    }

    font.constant_buffer = Gaco.create_buffer(Vector4.{}, .Constant);
    return font;
}

fonts_window_resize :: (width: int, height: int) {
    // Map window coordinates to -> [-1, 1]
    proj := Matrix4_Identity;
    proj._11 = 2.0 / xx width;
    proj._14 = -1;

    proj._22 = -2.0 / xx height;
    proj._24 = 1;

    Gaco.update_buffer(*WindowProjConstantBuffer, *proj);
}


prepare_text :: (using font: *Font, text: string, effect_flags: Font_Effects = 0) -> s64 {
    x := 0.0;
    y := 0.0;

    vertices : [..]Text_Vertex_Data;
    vertices.allocator = temp;

    num_chars: u32; // Excluding space, new line etc.
    width := 0.0;
    for char: text {
        if char >= 32 && char <= 126 {
            glyph := glyphs[char];

            y_addition := y - glyph.bitmap_top;
            x_addition := x + glyph.bitmap_left;
            x += glyph.advance;

            if has_kerning && it_index != 0 {
                kerning: FT_Vector;
                previous := FT_Get_Char_Index(face, text[it_index - 1]);
                current  := FT_Get_Char_Index(face, char);

                FT_Get_Kerning(face, previous, current, xx FT_Kerning_Mode.DEFAULT, *kerning);
                kern := kerning.x / 64.0;
                x_addition += kern;
                x += kern;
            }

            if char == " " {
                continue;
            }
            if x > width  width += glyph.advance;

            for 0..3 {
                glyph.vertices[it].position += Vector2.{x_addition, y_addition};
            }

            array_add(*vertices, ..glyph.vertices);
            num_chars += 1;
        }
        else if char == "\n" {
            y += character_height;
            x = 0;
        }

    }
    // @Incomplete: Handle this situation
    assert(num_chars <= MAX_CHARACTERS);

    Gaco.write_buffer(*TextVertexBuffer, vertices);
    num_chars_to_render = num_chars;
    temporary_glyphs_width_in_pixels = cast(s64)width;
    return cast(s64)width;
}


draw_prepared_text :: (font: *Font, x: s64, y: s64, color := Vector4.{1, 1, 1, 1}, effects: Font_Effects = 0) {
    draw_prepared_text(font, cast(float)x, cast(float)y, color, effects);
}
draw_prepared_text :: (font: *Font, x: float, y: float, color := Vector4.{1, 1, 1, 1}, effects: Font_Effects = 0) {
    Gaco.write_buffer(*TextPosConstantBuffer, Vector2.{x, y});


    if color != font.selected_color {
        font.selected_color = color;
        Gaco.update_buffer(*font.constant_buffer, *color);
    }

    Gaco.set_blend_state(.Alpha);
    Gaco.set_shader(TextShader);
    Gaco.bind_buffer(TextVertexBuffer);
    Gaco.bind_buffer(TextIndexBuffer);

    Gaco.bind_buffer(WindowProjConstantBuffer, 0, .Vertex);
    Gaco.bind_buffer(TextPosConstantBuffer, 1, .Vertex);

    Gaco.bind_buffer(font.constant_buffer, 0, .Fragment);
    Gaco.bind_texture(font.texture, 0);
    Gaco.draw(true, font.num_chars_to_render * 6);
    Gaco.set_blend_state(.None);
}

draw_text :: inline (font: *Font, text: string, x: s64, y: s64, color := Vector4.{1,1,1,1}) {
    prepare_text(font, text);
    draw_prepared_text(font, x, y, color);
}

draw_text_ascended :: inline (font: *Font, text: string, x: float, y: float, color := Vector4.{1,1,1,1}) {
    prepare_text(font, text);
    draw_prepared_text(font, x, y + font.ascent, color);
}

Font_Effects :: enum{};

// @Incomplete: Can only do ASCII
Font :: struct {
    face: FT_Face;
    ascent: float;
    typical_descender: float;
    typical_ascender: float;

    character_height: u32;
    em_width: float;
    constant_buffer: Gaco.Buffer(.Constant);
    glyphs: [128]Glyph_Info;

    texture: Gaco.Texture;
    selected_color: Vector4;
    num_chars_to_render: u32;

    has_kerning: bool;


    // Unused but they are here because GetRect needs them for some reason.
    temporary_glyphs: [..]Glyph_Info;
    temporary_glyphs_byte_offsets: [..]int;
    temporary_glyphs_width_in_pixels: int;
}

Glyph_Info :: struct {
    advance: float;
    vertices: [4]Text_Vertex_Data;
    bitmap_width, bitmap_height: u32;
    bitmap_left, bitmap_top: s32;
}
Text_Vertex_Data :: struct {
    position: Vector2;
    uv: Vector2;
}

TextVertexBuffer: Gaco.Buffer(.Vertex);
TextIndexBuffer: Gaco.Buffer(.Index);
WindowProjConstantBuffer: Gaco.Buffer(.Constant);
TextPosConstantBuffer: Gaco.Buffer(.Constant);
FtLibrary: FT_Library;
TextShader: Gaco.Shader;

#import "freetype-2.12.1";