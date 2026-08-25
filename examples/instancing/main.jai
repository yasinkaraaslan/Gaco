SKYBOX_FILE_NAMES :: string.["images/skybox/0.jpg", "images/skybox/1.jpg", "images/skybox/2.jpg", "images/skybox/3.jpg", "images/skybox/4.jpg", "images/skybox/5.jpg"];

FOV :: 60;

INSTANCE_COUNT :: 10000;
INSTANCE_DISTANCE :: 5;

Constant_Buffer :: struct {
    transformation := Matrix4_Identity;
}

FrameInfo : struct {
    delta: float;
    last: float64;
}

Skybox : struct {
    mesh: Mesh;
    texture: Gaco.Texture;
    shader: Gaco.Shader;
    index_count: u32;
}

instance_shader: Gaco.Shader;

WindowWidth, WindowHeight := 1280, 720;
ControllingCamera := false;

transform_buffer: Gaco.Buffer(.Constant);
instance_buffer: Gaco.Buffer(.Vertex);

main :: () {
    window := create_window(WindowWidth, WindowHeight, "Instancing!");

    Gaco.init(window);
    defer Gaco.deinit();
    instance_shader = Gaco.load_shader("shaders/instance.gaco");

    white_texture = Gaco.create_texture(.[ u8.[0xFF, 0xFF, 0xFF, 0xFF].data ], 1, 1);
    container_model := load_obj("models/container.obj");

    instances := NewArray(INSTANCE_COUNT, Vector3);
    SQRT_INST := #run cast(s64)sqrt(INSTANCE_COUNT);
    for y: 0..SQRT_INST-1 {
        for x: 0..SQRT_INST-1 {
            index := x + y * SQRT_INST;
            instances[index] = .{xx (x - SQRT_INST/2), 0, xx (y - SQRT_INST/2)};
        }
    }

    instance_buffer = Gaco.create_buffer(instances, .Vertex);
    transform_buffer = Gaco.create_buffer(Matrix4_Identity, .Constant, .Dynamic);

    default_sampler := Gaco.create_sampler();
    Gaco.bind_sampler(default_sampler, 0);

    create_skybox();

    quit := false;

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
            Camera.proj = make_projection_matrix(PI * FOV / 180.0, cast(float)it.width/cast(float)it.height, 0.01, 1000, depth_range_01 = true);
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

        Gaco.clear(.{0.2, 0.1, 0.3, 1.0});

        draw_skybox();
        draw_model(container_model);
        Gaco.present(0);
    }
}

create_skybox :: () {
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

    Skybox.mesh.vertex_buffer = Gaco.create_buffer(vertices, .Vertex, .Immutable);
    Skybox.mesh.index_buffer = Gaco.create_buffer(indices, .Index, .Immutable);
    Skybox.mesh.index_count = indices.count.(u32);

    Skybox.texture = Gaco.create_texture_array_from_files(SKYBOX_FILE_NAMES, flags=.Cubemap | .Sampled);
    Skybox.shader = Gaco.load_shader("shaders/skybox.gaco");
}

draw_skybox :: () {
    Gaco.set_shader(Skybox.shader);

    Gaco.bind_buffer(Skybox.mesh.vertex_buffer);
    Gaco.bind_buffer(Skybox.mesh.index_buffer);
    Gaco.bind_texture(Skybox.texture, 0);

    view := Camera.view;
    // remove translation so the skybox doesn't move when we move
    view._14 = 0.0;
    view._24 = 0.0;
    view._34 = 0.0;

    Gaco.write_buffer(*transform_buffer, Camera.proj * view);

    Gaco.bind_buffer(transform_buffer, 0, .Vertex);

    Gaco.push_rasterizer_state(.{cull_mode=.Front});
    Gaco.push_depth_stencil_state(.{depth_write=false});

    Gaco.draw(true, Skybox.mesh.index_count);
}

draw_model :: (using model: Obj_Model) {
    Gaco.set_shader(instance_shader);
    Gaco.bind_buffer(mesh.vertex_buffer, 0);
    Gaco.bind_buffer(instance_buffer, 1);
    Gaco.bind_buffer(mesh.index_buffer);

    Gaco.bind_texture(model.textures[1], 0);

    Gaco.write_buffer(*transform_buffer, Camera.proj_view);
    Gaco.bind_buffer(transform_buffer, 0, .Vertex);

    Gaco.draw_instanced(true, mesh.index_count, INSTANCE_COUNT);
}

#run {
    build_shader("instance");
    build_shader("skybox");
}

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

Gaco :: #import,dir "../../Gaco"(DEBUG=true);
#if OS == .WINDOWS #import "d3d11"()(INCLUDE_DEBUG_BINDINGS=true);

#load "input.jai";
#load "camera.jai";
#load "obj_loading.jai";