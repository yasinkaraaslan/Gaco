MAX_CHARACTERS :: 512;

Blend_Alpha :: Gaco.Blend_Desc.{blend_enable=true, src_blend = .Src_Alpha, dest_blend = .Inv_Src_Alpha};

fonts_init :: () {
    error := FT_Init_FreeType(*FtLibrary);
    Shader = Gaco.load_shader("shaders/text.gaco");
    assert(!error);

    VertexBuffer = Gaco.create_buffer(null, MAX_CHARACTERS * 4, size_of(Text_Vertex_Data), .Vertex, .Dynamic);
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

    IndexBuffer = Gaco.create_buffer(index_data, .Index, .Immutable);

    // This should be replaced in the next resize call.
    VertexConstantBuffer = Gaco.create_buffer(Matrix4_Identity, .Constant);
}

load_font :: (filename: string, size: u32) -> Font {
    font: Font;
    content := read_entire_file(filename); // @Leak

    error := FT_New_Memory_Face(FtLibrary, content.data, cast(s32) content.count, 0, *font.face);
    if error {
        log_error("Error loading font: % - Error Code: %\n", filename, error);
        return .{};
    }
    font.has_kerning = FT_HAS_KERNING(font.face);
    error = FT_Set_Pixel_Sizes(font.face, 0, size);

    metrics := font.face.size.metrics;
    font.ascender = (metrics.ascender / 64.0) + (metrics.descender / 64.0);
    font.size = size;
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

    font.texture = Gaco.create_texture(.[], texture_width, texture_height, format = .R8);

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
        glyph.advance_x = advance.x / 64.0;


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

    proj : Vector4;
    font.fragment_cb = Gaco.create_buffer(proj, .Constant);
    return font;
}

prepare_quads_for_text :: (using font: *Font, text: string, position: Vector2) -> u32 {
    x := 0.0;
    y := 0.0;

    vertices : [..]Text_Vertex_Data;
    vertices.allocator = temp;

    num_chars: u32; // Excluding space, new line etc.
    for char: text {
        if char >= 32 && char <= 126 {
            glyph := glyphs[char];

            y_addition := y - glyph.bitmap_top + ascender;
            x_addition := x + glyph.bitmap_left;
            x += glyph.advance_x;

            if char == " " {
                continue;
            }

            if has_kerning && it_index != 0 {
                kerning: FT_Vector;
                previous := FT_Get_Char_Index(face, text[it_index - 1]);
                current  := FT_Get_Char_Index(face, char);

                FT_Get_Kerning(face, previous, current, xx FT_Kerning_Mode.DEFAULT, *kerning);
                x_addition += kerning.x / 64.0;
            }

            for 0..3 {
                glyph.vertices[it].position += position + Vector2.{x_addition, y_addition};
            }

            array_add(*vertices, ..glyph.vertices);
            num_chars += 1;
        }
        else if char == "\n" {
            y += font.size;
            x = 0;
        }

    }
    assert(num_chars <= MAX_CHARACTERS);

    Gaco.write_buffer(*VertexBuffer, vertices);
    return num_chars;
}

fonts_window_resize :: (width: int, height: int) {
    // Map window coordinates to -> [-1, 1]

    proj := Matrix4_Identity;
    proj._11 = 2.0 / xx width;
    proj._14 = -1;

    proj._22 = -2.0 / xx height;
    proj._24 = 1;

    Gaco.update_buffer(*VertexConstantBuffer, *proj);
}

draw_text :: (using font: *Font, text: string, position: Vector2, color := Vector4.{1,1,1,1}) {
    num_chars := prepare_quads_for_text(font, text, position);

    Gaco.set_blend_state(Blend_Alpha);
    Gaco.set_rasterizer_state(.{cull_mode=.None});

    Gaco.set_shader(Shader);
    Gaco.bind_buffer(VertexBuffer);
    Gaco.bind_buffer(IndexBuffer);
    Gaco.bind_buffer(VertexConstantBuffer, 0, .Vertex);
    Gaco.bind_buffer(fragment_cb, 0, .Fragment);
    Gaco.bind_texture(texture, 0);

    if color != selected_color {
        selected_color = color;
        Gaco.update_buffer(*fragment_cb, *color);
    }

    Gaco.draw(true, num_chars * 6);
    Gaco.set_blend_state(.{blend_enable=false});
}

// NOTE(Yasin): Can only do ASCII
Font :: struct {
    face: FT_Face;
    size: u32;
    ascender: float;
    fragment_cb: Gaco.Buffer(.Constant);
    glyphs: [128]Glyph_Info;

    texture: Gaco.Texture;
    selected_color: Vector4;

    has_kerning: bool;
}

Glyph_Info :: struct {
    advance_x: float;
    vertices: [4]Text_Vertex_Data;
    bitmap_width, bitmap_height: u32;
    bitmap_left, bitmap_top: s32;
}
Text_Vertex_Data :: struct {
    position: Vector2;
    uv: Vector2;
}

VertexBuffer: Gaco.Buffer(.Vertex);
IndexBuffer: Gaco.Buffer(.Index);
VertexConstantBuffer: Gaco.Buffer(.Constant);
FtLibrary: FT_Library;
Shader: Gaco.Shader;

#import "freetype";