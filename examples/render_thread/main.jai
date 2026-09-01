// This is an example on how to use a seperate render thread with this library (to make drawing while resizing easy etc.)

// Note that Gaco procedures are not thread-safe.
// If you need to call them from other threads, you'd have to roll your own command buffer system.

#if OS == .WINDOWS {

// This is Input module's window proc
default_window_proc: (hwnd: HWND, message: u32, wParam: WPARAM, lParam: LPARAM) -> s64 #c_call;

// You can remove this and use the get_window_resizes() method below if you don't care about drawing while resizing.
window_proc :: (hwnd: HWND, message: u32, wParam: WPARAM, lParam: LPARAM) -> s64 #c_call {
    push_context,defer_pop;
    if message == {
    case WM_SIZE;
        lock(*shared_mutex);
        shared.width  = lParam & 0xFFFF;
        shared.height = (lParam >> 16) & 0xFFFF;
        shared.size_changed = true;
        unlock(*shared_mutex);
        return 0;

    // Some windows shenanigans to not flicker when resizing or moving
    // To get the same effect on Linux, you have to use _NET_WM_SYNC_REQUEST (Window_Creation module doesn't provide this by default)
    case WM_PAINT;
        BeginPaint(hwnd, null);
        lock(*shared_mutex);

        shared.frame_requested = true;
        wake(*shared_cv);                 // In case the render thread is idle-waiting
        wait(*shared_cv, *shared_mutex);

        unlock(*shared_mutex);
        EndPaint(hwnd, null);
        return 0;
    }
    return default_window_proc(hwnd, message, wParam, lParam);
}

}

Shared_State :: struct {
    quit: bool;
    width: int;
    height: int;

    size_changed: bool;
    frame_requested: bool;
}

shared: Shared_State;
shared_mutex: Mutex;
shared_cv: Condition_Variable;

#run {
    ok := Gaco.compile_shader("triangle.hlsl", "triangle.gaco", .Vertex | .Fragment);
    if !ok {
        compiler_report("Couldn't compile triangle.hlsl");
    }
    #import "Compiler";
}

render_thread_proc :: (thread: *Thread) -> s64 {
    window := cast(*Window_Type) thread.data;

    Gaco.init(window.*);
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

    last_width, last_height: int = -1, -1;
    transform_buffer := Gaco.create_buffer(Matrix4.{}, .Constant, .Dynamic);

    while true {
        reset_temporary_storage();

        local: Shared_State;
        frame_was_requested := false;

        lock(*shared_mutex);
        local = shared;
        shared.size_changed = false;
        unlock(*shared_mutex);

        if local.quit break;

        if local.size_changed && local.width > 0 && local.height > 0 &&
           (local.width != last_width || local.height != last_height) {
            Gaco.resize(local.width, local.height);
            last_width  = local.width;
            last_height = local.height;
        }


        q: Quaternion;
        time := seconds_since_init();
        set_from_axis_and_angle(*q, 0, 0, 1, cast(float)time);
        matrix := rotation_matrix(Matrix4, q);
        Gaco.write_buffer(*transform_buffer, matrix);

        Gaco.clear(.{1.0, 0.5, 0.3, 1.0});
        Gaco.bind_buffer(transform_buffer, 0, .Vertex);
        Gaco.draw(false, 3);
        Gaco.present(1);

        if local.frame_requested {
            lock(*shared_mutex);
            shared.frame_requested = false;
            wake(*shared_cv);              // let WM_PAINT's wait() return
            unlock(*shared_mutex);
        }
    }

    return 0;
}

main :: () {
    #if OS == .WINDOWS {
        SetProcessDPIAware();
        timeBeginPeriod(1); // Windows is very bad at thread-switching by default unless you do this. Sad.
    }

    init(*shared_mutex);
    defer destroy(*shared_mutex);
    init(*shared_cv);
    defer destroy(*shared_cv);

    #if OS == .WINDOWS {
        default_window_proc = context.input_handler.window_proc;
        context.input_handler.window_proc = window_proc;
    }
    window := create_window(1280, 720, "Render Thread Example!");

    thread: Thread;
    thread_init(*thread, render_thread_proc, name="Render Thread");
    defer thread_deinit(*thread);

    thread.data = *window;
    thread_start(*thread);

    quit := false;
    while !quit {
        reset_temporary_storage();
        update_window_events();

        for events_this_frame {
            if it.type == .QUIT { quit = true; }
        }

        lock(*shared_mutex);
        #if OS != .WINDOWS { // We handle it on WM_SIZE for Windows
            resizes := get_window_resizes();
            if resizes {
                resize := resizes[resizes.count - 1];
                shared.width  = resize.width;
                shared.height = resize.height;
                shared.size_changed = true;
            }
        }
        shared.quit = quit;
        unlock(*shared_mutex);
    }

    while !thread_is_done(*thread) {
        sleep_milliseconds(1);
    }
}

Gaco :: #import,dir "../../Gaco";

#import "Math";
#if OS == .WINDOWS {
    #import "Windows";

    BeginPaint :: (hWnd: HWND, lpPaint: *void) -> *void #foreign user32;
    EndPaint :: (hWnd: HWND, lpPaint: *void) -> s32 #foreign user32;

    user32 :: #library,system "user32";
}
#import "Window_Creation";
#import "Input";
#import "Basic";
#import "Thread";
