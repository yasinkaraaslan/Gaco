#run {
    ok := Gaco.compile_shader("triangle.hlsl", "triangle.gaco", .Vertex | .Fragment);
    if !ok {
        compiler_report("Couldn't compile triangle.hlsl");
    }
    #import "Compiler";
}

main :: () {
    window := create_window(1280, 720,"Gaco Triangle");
    Gaco.init(window);
    defer Gaco.deinit();
    shader := Gaco.load_shader("triangle.gaco");
    vertices := Vector3.[
        .{0.0, 0.5, 0},
        .{0.5, -0.5, 0},
        .{-0.5, -0.5, 0}
    ];
    buffer := Gaco.create_buffer(vertices, .Vertex);

    Gaco.bind_buffer(buffer);
    Gaco.set_shader(shader);
    quit := false;
    while !quit {
        update_window_events();
        for get_window_resizes() {
            Gaco.resize(it.width, it.height);
        }
        for events_this_frame {
            if it.type == .QUIT quit = true;
        }

        Gaco.clear(.{1.0, 0.5, 0.3, 1.0});
        Gaco.draw(false, 3);
        Gaco.present();
    }
}

#import "Window_Creation";
#import "Input";
#import "Math";
Gaco :: #import,dir "../../Gaco";