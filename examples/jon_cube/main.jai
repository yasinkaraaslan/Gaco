FOV :: 70;

Width, Height: int;

RotationZ : struct {
   current,target,time: float;
}
RotX, RotY: float;
Frame_Info : struct {
   last, delta: float;
}

#run {
   Gaco.compile_shader("jon_cube.hlsl", "jon_cube.gaco", .Vertex | .Fragment);
}

Transform_Buffer :: struct {
   transformation := Matrix4_Identity;
}

main :: () {
   window := create_window(1280, 720, "Jon Cube!");
   Gaco.init(window);

   shader := Gaco.load_shader("jon_cube.gaco");
   Gaco.set_shader(shader);

   Vertex_Input :: struct {
      vertex: Vector3;
      uv: Vector2;
   }

   vertex_inputs := Vertex_Input.[
      // Front
      .{.{-0.5,  0.5,  0.5}, .{0.0, 0.0}},
      .{.{ 0.5,  0.5,  0.5}, .{1.0, 0.0}},
      .{.{ 0.5, -0.5,  0.5}, .{1.0, 1.0}},
      .{.{-0.5, -0.5,  0.5}, .{0.0, 1.0}},

      // Back
      .{.{ 0.5,  0.5, -0.5}, .{0.0, 0.0}},
      .{.{-0.5,  0.5, -0.5}, .{1.0, 0.0}},
      .{.{-0.5, -0.5, -0.5}, .{1.0, 1.0}},
      .{.{ 0.5, -0.5, -0.5}, .{0.0, 1.0}},

      // Left
      .{.{-0.5,  0.5, -0.5}, .{0.0, 0.0}},
      .{.{-0.5,  0.5,  0.5}, .{1.0, 0.0}},
      .{.{-0.5, -0.5,  0.5}, .{1.0, 1.0}},
      .{.{-0.5, -0.5, -0.5}, .{0.0, 1.0}},

      // Right
      .{.{ 0.5,  0.5,  0.5}, .{0.0, 0.0}},
      .{.{ 0.5,  0.5, -0.5}, .{1.0, 0.0}},
      .{.{ 0.5, -0.5, -0.5}, .{1.0, 1.0}},
      .{.{ 0.5, -0.5,  0.5}, .{0.0, 1.0}},

      // Top
      .{.{-0.5,  0.5, -0.5}, .{0.0, 0.0}},
      .{.{ 0.5,  0.5, -0.5}, .{1.0, 0.0}},
      .{.{ 0.5,  0.5,  0.5}, .{1.0, 1.0}},
      .{.{-0.5,  0.5,  0.5}, .{0.0, 1.0}},

      // Bottom
      .{.{-0.5, -0.5,  0.5}, .{0.0, 0.0}},
      .{.{ 0.5, -0.5,  0.5}, .{1.0, 0.0}},
      .{.{ 0.5, -0.5, -0.5}, .{1.0, 1.0}},
      .{.{-0.5, -0.5, -0.5}, .{0.0, 1.0}},
   ];

    Index_Input :: struct {
        indices: []u16;
    }

   index_input: Index_Input;
   indices := u16.[
      0,  1,  2,  2,  3,  0,
      4,  5,  6,  6,  7,  4,
      8,  9,  10, 10, 11,  8,
      12, 13, 14, 14, 15, 12,
      16, 17, 18, 18, 19, 16,
      20, 21, 22, 22, 23, 20,
   ];

   vertex_buffer := Gaco.create_buffer(vertex_inputs, .Vertex);
   index_buffer := Gaco.create_buffer(indices, .Index);
   transform_cb := Gaco.create_buffer(null, size_of(Transform_Buffer), 1, .Constant, .Dynamic);

   texture := Gaco.create_texture_from_file("jon.png");

   Frame_Info.last = cast(float32)seconds_since_init();

   proj := Matrix4_Identity;
   quit := false;
   while !quit {
      reset_temporary_storage();

      current := cast(float32)seconds_since_init();
        Frame_Info.delta = current - Frame_Info.last;
        Frame_Info.last = current;

      update_window_events();
      for get_window_resizes() {
         Gaco.resize(it.width, it.height);
         Width, Height = it.width, it.height;

         proj = make_projection_matrix(70 * PI / 180.0, cast(float)it.width / cast(float)it.height, 0.001, 1000.0, depth_range_01 = true);
      }
      for events_this_frame if it.type == .QUIT quit = true;
      Gaco.clear(1.0, 0.5, 0.3, 1.0);

      Gaco.bind_buffer(vertex_buffer);
      Gaco.bind_buffer(index_buffer);
      Gaco.bind_buffer(transform_cb, 0, .Vertex);
      Gaco.bind_texture(texture, 0);

      draw_cube(.{0, 0, -3}, *transform_cb, proj, indices.count);

      Gaco.present();
   }
}

draw_cube :: (position: Vector3, buffer: *Gaco.Buffer, proj: Matrix4, indices_count: u32) {
   delta_z :=  cast(float)mouse_delta_z / 20.0;
   if delta_z != 0 {
      RotationZ.target += delta_z * PI / 180.0;
      RotationZ.time = 0;
   }

   RotationZ.current = lerp(RotationZ.current, RotationZ.target, RotationZ.time);
   RotationZ.time += Frame_Info.delta / 1.5;
   RotationZ.time = clamp(RotationZ.time, 0.0, 1.0);


   rot_x, rot_y, rot_z : Quaternion;
   MOUSE_DELTA_MULTIPLIER :: 0.0005;
   delta_x := cast(float)mouse_delta_x;
   delta_y := cast(float)mouse_delta_y;
   RotX += delta_x * MOUSE_DELTA_MULTIPLIER;
   RotY += delta_y * MOUSE_DELTA_MULTIPLIER;
   if RotX == 0 RotX = 1;
   set_from_axis_and_angle(*rot_x, .{1, 0, 0}, RotY);
   set_from_axis_and_angle(*rot_y, .{0, 1, 0}, RotX);
   set_from_axis_and_angle(*rot_z, .{0, 0, 1}, RotationZ.current);

   rotation := rot_x * rot_y * rot_z;
   model := make_translation_matrix4(position) * rotation_matrix(Matrix4, rotation);
   transform_b : Transform_Buffer;
   transform_b.transformation = proj * model;
   Gaco.write_buffer(buffer, transform_b);

   Gaco.draw(true, indices_count);
}


#import "Window_Creation";
#import "Input";
#import "Math";
#import "Basic";

// You should, again, put Gaco into your local modules folder
// instead of importing it as a directory. This is just an example.
Gaco :: #import,dir "../../Gaco"(DEBUG=true);
#if Gaco.BACKEND == .D3D11 #import "d3d11"()(INCLUDE_DEBUG_BINDINGS=true);