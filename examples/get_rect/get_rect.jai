#import "GetRect_LeftHanded"()(Type_Indicator);
#run {
    Gaco.compile_shader("shaders/sources/color.hlsl", "shaders/color", .Vertex | .Fragment);
    Gaco.compile_shader("shaders/sources/image.hlsl", "shaders/image", .Vertex | .Fragment);
}

gr_init :: () {
    ColorShader = Gaco.load_shader("shaders/color", .Vertex | .Fragment);
    ImageShader = Gaco.load_shader("shaders/image", .Vertex | .Fragment);
    vertices: [512]Vertex_Data;
    VerticesBuffer = Gaco.create_buffer(*vertices, .Vertex, .Dynamic);

    procs := Draw_Procs.{
        texture_load_from_memory = gr_texture_load_from_memory,
        set_scissor = gr_set_scissor,
        clear_scissor = Gaco.disable_scissor,
        set_shader_for_color = gr_set_shader_for_color,
        set_shader_for_images = gr_set_shader_for_images,

        prepare_text = prepare_text,
        draw_prepared_text = draw_prepared_text,

        get_mouse_pointer_position = get_mouse_pointer_position, // from Window_Creation
        get_font_at_size = load_font_from_memory,

        immediate_triangle = gr_immediate_triangle,
        immediate_quad = gr_immediate_quad,
        immediate_flush = gr_immediate_flush,

    };
    ui_init(procs = *procs);
}

gr_set_shader_for_color :: (enable_blend := false) {

    if enable_blend  Gaco.set_blend(.Alpha);
    Gaco.set_shader(ColorShader);
}

gr_set_shader_for_images :: (texture: *Gaco.Texture) {
    Gaco.set_blend(.Alpha);
    Gaco.bind_texture(texture, 0);
    Gaco.set_shader(ImageShader);
}

gr_immediate_triangle :: (p0: Vector3, p1: Vector3, p2: Vector3, c0 := Vector4.{1,1,1,1}, c1 := Vector4.{1,1,1,1}, c2 := Vector4.{1,1,1,1}, uv0 := Vector2.{}, uv1 := Vector2.{}, uv2 := Vector2.{}, normal := Vector3.{z=1}) {
    // Normal is ignored for now.

    vertices := Vertex_Data.[
    .{p0.xy, c0, uv0},
    .{p1.xy, c1, uv1},
    .{p2.xy, c2, uv2},
    ];

    array_add(*VerticesToDraw, ..vertices);
}

gr_immediate_quad :: (p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, color := Vector4.{1,1,1,1}, uv0 := Vector2.{0,0}, uv1 := Vector2.{1,0}, uv2 := Vector2.{1,1}, uv3 := Vector2.{0, 1}) {
    vertices := Vertex_Data.[
        .{p0, color, uv0},
        .{p1, color, uv1},
        .{p2, color, uv2},
        .{p0, color, uv0},
        .{p2, color, uv2},
        .{p3, color, uv3},
    ];

    array_add(*VerticesToDraw, ..vertices);
}

gr_immediate_flush :: () {
    if VerticesToDraw {
        Gaco.write_buffer(*VerticesBuffer, VerticesToDraw);
        Gaco.bind_buffer(VerticesBuffer);
        Gaco.bind_buffer(WindowProjConstantBuffer, .Vertex, 0);
        Gaco.draw(false, cast(u32)VerticesToDraw.count);
        array_reset(*VerticesToDraw);
    }
    Gaco.set_blend(.None);
}

gr_texture_load_from_memory :: (texture: *Gaco.Texture, memory: []u8, srgb: bool, build_mipmaps: bool) -> bool {
    result := Gaco.create_texture_from_memory(memory, ifx srgb then .SRGB else .None);
    if result.texture != null {
        texture.* = result;
        return true;
    }
    return false;
}

gr_set_scissor :: (x0: s32, y0: s32, x1: s32, y1: s32) {
    Gaco.enable_scissor();
    rect: Gaco.Rect;
    rect.x = x0;
    rect.y = y0 ;
    rect.w = x1 - x0;
    rect.h = y1 - y0;
    Gaco.set_scissor(rect);
}

#scope_file
ColorShader, ImageShader: Gaco.Shader;
VerticesBuffer: Gaco.Buffer(.Vertex);
VerticesToDraw: [..]Vertex_Data;

Vertex_Data :: struct {
    pos: Vector2;
    color: Vector4;
    uv: Vector2;
}

_Font_Effects :: Font_Effects;
_Font :: Font;
_Window_Type :: Window_Type;
Type_Indicator :: struct {
    Font :: _Font;
    Texture :: Gaco.Texture;
    Font_Effects :: _Font_Effects;
    Window_Type :: _Window_Type;
}