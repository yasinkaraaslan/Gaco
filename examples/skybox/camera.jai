FOV :: 70;

Camera : struct {
    transform := Matrix4_Identity;
    proj :=  Matrix4_Identity;
    proj_view := Matrix4_Identity;
    rotation: Vector2;
    controlling: bool;
    first := true;
}



update_camera :: (transform_buffer: Gaco.Buffer(.Constant)) {
    using Camera;
    if first {
        first = false;
    }
    else if !controlling return;
    // We don't handle translation here.
    // If you do, you should disable translation when using the view matrix for the skybox.
    // Since you don't want the skybox to move.

    MOUSE_DELTA_MULTIPLIER :: 0.0005;
    delta_x := -cast(float)mouse_delta_x * MOUSE_DELTA_MULTIPLIER;
    delta_y := -cast(float)mouse_delta_y * MOUSE_DELTA_MULTIPLIER;
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

    Gaco.write_buffer(*transform_buffer, proj * view);
}

set_controlling_camera :: (set: bool, window: Window_Type) {
    Camera.controlling = set;
    if set {
        hide_cursor();
        clip_cursor(window);
    }
    else {
        show_cursor();
        unclip_cursor();
    }
}

// These are only implemented in Windows for now.
show_cursor :: inline ()
{
    #if OS == .WINDOWS
    {
        win32 :: #import "Windows";
        while(win32.ShowCursor(1) < 0){}
    }
    else
    {
    }
}

hide_cursor :: inline ()
{
    #if OS == .WINDOWS
    {
        win32 :: #import "Windows";
        while(win32.ShowCursor(0) > 0){}
    }
    else
    {
    }
}

clip_cursor :: inline (window: Window_Type) {
    if OS == .WINDOWS {
        win32 :: #import "Windows";
        rect: win32.RECT;
        win32.GetClientRect(window, *rect);

        top_left     := win32.POINT.{ rect.left, rect.top };
        bottom_right := win32.POINT.{ rect.right, rect.bottom };

        win32.ClientToScreen(window, *top_left);
        win32.ClientToScreen(window, *bottom_right);

        rect.left = top_left.x;
        rect.top = top_left.y;
        rect.right = bottom_right.x;
        rect.bottom = bottom_right.y;

        win32.ClipCursor(*rect);
    }
    else {
    }
}


unclip_cursor :: inline () {
    if OS == .WINDOWS {
        win32 :: #import "Windows";
        win32.ClipCursor(null);
    }
}

#import "Basic";