FOV :: 60;

Constant_Buffer :: struct {
    transformation := Matrix4_Identity;
}

FrameInfo : struct {
    delta: float;
    last: float64;
}

WindowWidth, WindowHeight := 1280, 720;
ControllingCamera := false;

main :: () {
    window := create_window(WindowWidth, WindowHeight, "Gacomera!");

    Gaco.init(window);
    defer Gaco.deinit();
    shader := Gaco.load_shader("shaders/texture.gaco");

    Vertex_Input :: struct {
        vertex: Vector3;
        uv: Vector2;
    }
    vertex_inputs := Vertex_Input.[
        .{.{-0.5,  0.5,  0.5}, .{1.0/3.0, 0  }},
        .{.{ 0.5,  0.5,  0.5}, .{2.0/3.0, 0  }},
        .{.{ 0.5, -0.5,  0.5}, .{2.0/3.0, 1.0/4.0}},
        .{.{-0.5, -0.5,  0.5}, .{1.0/3.0, 1.0/4.0}},

        .{.{-0.5,  0.5, -0.5}, .{1.0/3.0, 3.0/4.0}},
        .{.{ 0.5,  0.5, -0.5}, .{2.0/3.0, 3.0/4.0}},
        .{.{ 0.5, -0.5, -0.5}, .{2.0/3.0, 0.5}},
        .{.{-0.5, -0.5, -0.5}, .{1.0/3.0, 0.5}},

        .{.{-0.5,  0.5,  0.5}, .{0, 1.0/4.0  }},
        .{.{-0.5,  0.5, -0.5}, .{0, 0.5  }},

        .{.{ 0.5,  0.5,  0.5}, .{1, 1.0/4.0  }},
        .{.{ 0.5,  0.5, -0.5}, .{1, 0.5}},

        .{.{-0.5,  0.5,  0.5}, .{1.0/3.0, 1}},
        .{.{ 0.5,  0.5,  0.5}, .{2.0/3.0, 1}},

    ];

    indices := u16.[
        0,1,2, 2,3,0, // Front
        6,5,4, 4,7,6, // Back
        13,12,4, 4,5,13, // Top
        2,6,7, 7,3,2, // Bottom
        9,8,3, 3,7,9, // Left
        10,11,6, 6,2,10, // Right
    ];

    constant : Constant_Buffer;

    vertex_buffer := Gaco.create_buffer(vertex_inputs, .Vertex);
    index_buffer := Gaco.create_buffer(indices, .Index);
    vs_cb := Gaco.create_buffer(constant, .Constant, .Dynamic);

    texture := Gaco.create_texture_from_file("images/mc_cube.png");

    Gaco.set_shader(shader);

    quit := false;

    Gaco.bind_buffer(vertex_buffer);
    Gaco.bind_buffer(index_buffer);
    Gaco.bind_buffer(vs_cb, 0, .Vertex);

    Gaco.bind_texture(texture, 0);
    FrameInfo.last = seconds_since_init();
    while !quit {
        reset_temporary_storage();

        {
            current := seconds_since_init();
            FrameInfo.delta = cast(float) (current - FrameInfo.last);
            FrameInfo.last = current;
        }

        update_window_events();
        for get_window_resizes() {
            WindowWidth, WindowHeight = it.width, it.height;
            Gaco.resize(it.width, it.height);
            unclip_cursor();
            Camera.proj = make_projection_matrix(PI * FOV / 180.0, cast(float)it.width/cast(float)it.height, 0.001, 1000, depth_range_01 = true);
            success, view := inverse(Camera.transform);
            if !success {
                log_error("Couldn't inverse camera transform");
            }

            Camera.proj_view = Camera.proj * view;
        }
        for events_this_frame {
            if it.type == {
            case .QUIT; quit = true;
            case .KEYBOARD;
                if it.key_code == {
                case .ESCAPE; quit = true;
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
        update_camera();


        Gaco.clear(.{1.0, 0.5, 0.3, 1.0});
        draw_cube(.{0, 0, -3}, vs_cb, xx indices.count);
        draw_cube(.{0, 0, -10}, vs_cb, xx indices.count);

        Gaco.present(0);

    }
}

draw_cube :: (pos: Vector3, constant_buffer: Gaco.Buffer, indices_count: u32) {

    model := make_translation_matrix4(pos);
    constant : Constant_Buffer;
    constant.transformation = Camera.proj_view*model;

    Gaco.write_buffer(*constant_buffer, constant);
    Gaco.draw(true, indices_count);
}

#run build_shader("texture");

build_shader :: (shader_name: string) {
    shader_file_name := join("shaders/sources/", shader_name, ".hlsl");
    ok := Gaco.compile_shader(shader_file_name, join("shaders/", shader_name, ".gaco"), .Vertex | .Fragment);
    if !ok {
        compiler_report(tprint("Couldn't compile the shader: %\n", shader_file_name));
        return;
    }
}

#import "String";
#import "Input";
#import "Math";
#import "Window_Creation";
#import "Basic";
#import "Compiler";
#import "stb_image";
#import "File";

Gaco :: #import,dir "../../Gaco";

#load "input.jai";
#load "camera.jai";