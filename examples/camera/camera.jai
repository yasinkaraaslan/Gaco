Camera : struct {
    rotation: Vector2;
    transform := Matrix4_Identity;
    proj := Matrix4_Identity;
    proj_view := Matrix4_Identity;
}

update_camera :: () {
    using Camera;
    if !ControllingCamera  return;
    movement : Vector3;
    SPEED :: 5;
    speed_multiplier := 1.0;

    if is_key_down(#char "W")  movement.z -= 1;
    if is_key_down(#char "S")  movement.z += 1;
    if is_key_down(#char "A")  movement.x -= 1;
    if is_key_down(#char "D")  movement.x += 1;


    if is_key_down(.SHIFT)     speed_multiplier = 3;


    translate(*transform, movement * SPEED * speed_multiplier * FrameInfo.delta);

    delta_x := -cast(float)mouse_delta_x / cast(float)WindowWidth;
    delta_y := -cast(float)mouse_delta_y / cast(float)WindowHeight;
    if delta_x != 0 || delta_y != 0 {
        rotation += .{delta_y, delta_x};

        // Limit to 72 degrees so we don't get weird stuff like world becoming upside-down
        rotation.x = clamp(rotation.x, -PI / 2.5, PI / 2.5);

        yaw, pitch, rotation_quat: Quaternion = ---;
        set_from_axis_and_angle(*yaw,   1, 0, 0, rotation.x);
        set_from_axis_and_angle(*pitch, 0, 1, 0, rotation.y);

        rotation_quat = pitch*yaw;
        set_rotation(*transform, rotation_quat);
    }
    success, view := inverse(transform);
    if !success {
        log_error("Couldn't inverse camera transform.");
    }
    proj_view = proj * view;
}

set_controlling_camera :: (set: bool, window: Window_Type) {
    ControllingCamera = set;
    if set {
        hide_cursor();
        clip_cursor(window);
    }
    else {
        show_cursor();
        unclip_cursor();
    }
}