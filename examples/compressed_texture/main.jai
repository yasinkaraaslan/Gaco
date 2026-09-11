// Texture taken from: https://polyhaven.com/a/medieval_red_brick
// nvcompress -bc7 medieval_red_brick.png

#run {
    ok := Gaco.compile_shader("texture.hlsl", "texture.gaco", .Vertex | .Fragment);
    if !ok {
        compiler_report("Couldn't compile texture.hlsl");
    }
    #import "Compiler";
}

main :: () {
    window := create_window(1280, 720, "Gaco Compressed Texture");
    Gaco.init(window);
    defer Gaco.deinit();

    shader := Gaco.load_shader("texture.gaco");

    Vertex_Input :: struct {
        pos: Vector3;
        uv: Vector2;
    }
    vertices := Vertex_Input.[
        .{.{-1.0,  1.0, 0}, .{0, 0}},
        .{.{ 1.0,  1.0, 0}, .{1, 0}},
        .{.{ 1.0, -1.0, 0}, .{1, 1}},
        .{.{-1.0, -1.0, 0}, .{0, 1}},
    ];
    indices := u16.[0, 1, 2, 2, 3, 0];

    vertex_buffer := Gaco.create_buffer(vertices, .Vertex);
    index_buffer := Gaco.create_buffer(indices, .Index);

    texture: Gaco.Texture;
    ok, dds := load_dds("medieval_red_brick.dds");
    if ok {
        defer deinit(*dds);

        flags := Gaco.Texture_Flags.Sampled;
        if dds.optional_header.misc_flags & .TEXTURECUBE || dds.header.caps2 & .Cubemap {
            flags |= .Cubemap;
        }

        texture = Gaco.create_texture(dds.image_data, dds.header.width, dds.header.height, dds.array_size, dds.header.mipmap_count, dds.format, flags);
    }

    Gaco.bind_buffer(vertex_buffer);
    Gaco.bind_buffer(index_buffer);
    Gaco.set_shader(shader);
    if Gaco.is_valid(texture) {
        Gaco.bind_texture(texture, 0);
    }

    quit := false;
    while !quit {
        update_window_events();
        for get_window_resizes() {
            Gaco.resize(it.width, it.height);
        }
        for events_this_frame {
            if it.type == .QUIT quit = true;
        }

        Gaco.clear(.{0.1, 0.1, 0.12, 1.0});
        if Gaco.is_valid(texture) {
            Gaco.draw(true, indices.count);
        }
        Gaco.present();
    }
}

#load "dds.jai";

#import "Window_Creation";
#import "Input";
#import "Math";
#import "Basic";
#import "File";
Gaco :: #import,dir "../../Gaco";
