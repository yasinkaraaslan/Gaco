// This is an example on how to use a seperate render thread with this library (to make drawing while resizing easy etc.
// Though, if you want that on Windows you will have to catch WM_SIZE since update_window_events blocks while resizing)

// Note that Gaco procedures are not thread-safe.
// If you need to call them from other threads, you'd have to roll your own command buffer system.

// NOTE(Yasin): This creates a flickering issue when resizing for OpenGL on Windows, especially noticable when interval is set to 1.
// This doesn't happen if we try to render to back buffer directly.
// Trying to deal with window_proc (WM_ERASEBKGND etc.) didn't solve it.
// I tried implementing WGL_NV_DX_interop2 at some point to solve this but that came with a big performance degredation and made RenderDoc practically useless.
// May be helpful: https://stackoverflow.com/questions/53000291/how-to-smooth-ugly-jitter-flicker-jumping-when-resizing-windows-especially-drag/53000292#53000292

Shared_State :: struct {
    quit: bool;
    width: int;
    height: int;
}

shared: Shared_State;
shared_mutex: Mutex;

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

    while true {
        reset_temporary_storage();

        local: Shared_State;
        lock(*shared_mutex);
        local = shared;
        unlock(*shared_mutex);

        if local.quit break;

        if local.width != last_width || local.height != last_height {
            Gaco.resize(local.width, local.height);
            last_width  = local.width;
            last_height = local.height;
        }

        Gaco.clear(.{1.0, 0.5, 0.3, 1.0});
        Gaco.draw(false, 3);
        Gaco.present(0);
    }

    return 0;
}

main :: () {
    #if OS == .WINDOWS {
        Windows.SetProcessDPIAware();
        Windows.timeBeginPeriod(1); // Windows is very bad at thread-switching by default unless you do this. Sad.
    }

    init(*shared_mutex);
    defer destroy(*shared_mutex);
    window := create_window(1280, 720, "Render Thread!");

    thread: Thread;
    thread_init(*thread, render_thread_proc);
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

        resizes := get_window_resizes();
        if resizes {
            resize := resizes[resizes.count - 1];
            shared.width = resize.width;
            shared.height = resize.height;
        }
        shared.quit = quit;
        unlock(*shared_mutex);
    }

}

Gaco :: #import,dir "../../Gaco"(DEBUG=true);

#import "Math";
#if OS == .WINDOWS {
    #import "d3d11"()(INCLUDE_DEBUG_BINDINGS=true);
    Windows :: #import "Windows";
}
#import "Window_Creation";
#import "Input";
#import "Basic";
#import "Thread";
