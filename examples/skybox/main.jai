SKYBOX_FILE_NAMES :: string.["images/0.png", "images/1.png", "images/2.png", "images/3.png", "images/4.png", "images/5.png"];

WindowWidth, WindowHeight := 1280, 720;



main :: () {
    window := create_window(WindowWidth, WindowHeight, "Skybox Example");
    Gaco.init(window);
    skybox_shader := Gaco.load_shader("skybox.gaco");

    vertices := Vector3.[
        .{-0.5,  0.5,  0.5},
        .{ 0.5,  0.5,  0.5},
        .{ 0.5, -0.5,  0.5},
        .{-0.5, -0.5,  0.5},
        .{-0.5,  0.5, -0.5},
        .{ 0.5,  0.5, -0.5},
        .{ 0.5, -0.5, -0.5},
        .{-0.5, -0.5, -0.5},
    ];
    indices := u16.[
        0,1,2, 2,3,0, // Front
        6,5,4, 4,7,6, // Back
        0,4,5, 5,1,0, // Top
        2,6,7, 7,3,2, // Bottom
        0,3,7, 7,4,0, // Left
        6,2,1, 1,5,6, // Right
    ];

    skybox_vertex_buffer := Gaco.create_buffer(vertices, .Vertex, .Immutable);
    skybox_index_buffer := Gaco.create_buffer(indices, .Index, .Immutable);
    skybox_texture := Gaco.create_texture_array_from_files(SKYBOX_FILE_NAMES, flags=.Cubemap | .Sampled);


    transform_buffer := Gaco.create_buffer(Matrix4_Identity, .Constant, .Dynamic);

    Gaco.set_shader(skybox_shader);

    Gaco.bind_buffer(skybox_vertex_buffer);
    Gaco.bind_buffer(skybox_index_buffer);
    Gaco.bind_texture(skybox_texture, 0);

    Gaco.bind_buffer(transform_buffer, 0, .Vertex);

    quit := false;
    while !quit {
        update_window_events();
        for get_window_resizes() {
            WindowWidth, WindowHeight = it.width, it.height;
            Gaco.resize(it.width, it.height);
            unclip_cursor();
            Camera.proj = make_projection_matrix(FOV * PI / 180.0, cast(float)it.width/cast(float)it.height, 0.1, 1000, depth_range_01 = true);
        }

        for events_this_frame {
            if it.type == .QUIT quit = true;
            else if it.type == .KEYBOARD {
                if it.key_code == {
                case .ESCAPE; quit=true;
                case .MOUSE_BUTTON_RIGHT;
                    if !it.repeat {
                        if it.key_pressed {
                            set_controlling_camera(true, window);
                        }
                        else {
                            set_controlling_camera(false, window);
                        }
                    }
                }
            }
        }

        update_camera(transform_buffer);
        Gaco.clear(0.5, 0.3, 0.3, 1.0);

        Gaco.set_rasterizer_state(.Front_Cull);
        Gaco.draw(true, indices.count);
        Gaco.set_rasterizer_state(.Default);

        Gaco.present();
    }

}



#run {
    ok := Gaco.compile_shader("skybox.hlsl", "skybox.gaco", .Vertex | .Fragment);
    if !ok {
        compiler_report("skybox.hlsl", 0, 0, "Couldn't compile the shader\n");
    }

}

#load "camera.jai";

#import "Compiler";
#import "Window_Creation";
#import "Input";
#import "Math";
Gaco :: #import,dir "../../Gaco";