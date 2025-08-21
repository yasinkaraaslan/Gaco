FOV :: 60;

Proj := Matrix4_Identity;

Rotation_Scale : float;
Position := Vector3.{0, 0, -3};

Width, Height : int;

Transform_Buffer :: struct {
    transformation := Matrix4_Identity;
}

Colors_Buffer :: struct {
    face_colors: [6]Vector4;
}

main :: () {
    window := create_window(1280, 720, "Colored Cube");
    Gaco.init(window);
    shader := Gaco.load_shader("colored_cube", .Vertex | .Fragment);
    Gaco.set_shader(shader);

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
    colors := Colors_Buffer.{
        face_colors = .[
            .{1,0,0,1},
            .{0,1,0,1},
            .{0,0,1,1},
            .{1,0,1,1},
            .{1,1,0,1},
            .{1,1,1,1},
        ]
    };

    vertex_buffer := Gaco.create_buffer(vertices, .Vertex);
    index_buffer := Gaco.create_buffer(indices, .Index);

    vertex_cb := Gaco.create_buffer(Transform_Buffer.{}, .Constant, .Dynamic);
    fragment_cb := Gaco.create_buffer(colors, .Constant);

    quit := false;
    while !quit {
        update_window_events();
        for get_window_resizes() {
            Gaco.resize(it.width, it.height);
            DEPTH_RANGE_01 :: Gaco.BACKEND != .OpenGL;
            Proj = make_projection_matrix(FOV * PI / 180.0, cast(float)it.width / cast(float)it.height, 0.001, 1000, depth_range_01 = DEPTH_RANGE_01);
            Width, Height = it.width, it.height;
        }
        for events_this_frame if it.type == .QUIT  quit = true;

        Gaco.bind_buffer(vertex_buffer);
        Gaco.bind_buffer(index_buffer);
        Gaco.bind_buffer(fragment_cb, bind_to=.Fragment);

        Gaco.clear(0.3, 0.5, 0.3, 1.0);
        draw_the_cube(vertex_cb, indices.count);
        Gaco.present();
    }
}

draw_the_cube :: (transform_cb: Gaco.Buffer, indices_count: u32) {
    delta_x := cast(float)mouse_delta_x / cast(float)Width;
    delta_y := cast(float)mouse_delta_y / cast(float)Height;
    Position += .{delta_x, -delta_y, 0};

    scroll_delta := cast(float)mouse_delta_z / 20.0;
    Rotation_Scale += scroll_delta * PI / 180.0;
    rotation: Quaternion;

    set_from_axis_and_angle(*rotation, .{1, 0, 0}, Rotation_Scale);
    model := make_translation_matrix4(Position) * rotation_matrix(Matrix4, rotation);

    transform_buffer: Transform_Buffer;
    transform_buffer.transformation = Proj * model;

    Gaco.write_buffer(*transform_cb, transform_buffer);

    Gaco.bind_buffer(transform_cb, bind_to=.Vertex);
    Gaco.draw(true, indices_count);
}

#import "Math";
#import "Window_Creation";
#import "Input";
Gaco :: #import,dir "../../Gaco"; // In a real project you should put Gaco into your local modules folder.

#run {
    Gaco.compile_shader("colored_cube.hlsl", "colored_cube", .Vertex | .Fragment);
}