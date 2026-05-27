IMPORTANT_TEXT :: #string DONE
The answer to the
ultimate question of
life, the universe and
consciousness is
the following:
DONE

FrameInfo : struct {
    last: float64;
    delta: float;
    latency: float;
}

WindowWidth, WindowHeight := 1280, 720;

main :: () {
    window := create_window(WindowWidth, WindowHeight, "Text Rendering", background_color_rgb=.[4.0 / 0xFF, 15.0 / 0xFF, 22.0 / 0xFF]);
    Gaco.init(window);

    fonts_init();
    font := load_font("fonts/OpenSans-Regular.ttf", 32);
    big_font := load_font("fonts/OpenSans-Regular.ttf", 128);
    FrameInfo.last = cast(float32)seconds_since_init();

    frames := 0.0;
    fps := 0;
    time_between_measure := 0.0;
    FPS_MEASURE_TIME :: 0.25;

    quit := false;
    while !quit {
        reset_temporary_storage();

        {
            current := seconds_since_init();
            FrameInfo.delta = cast(float32) (current - FrameInfo.last);
            frames += 1;
            time_between_measure += FrameInfo.delta;
            if time_between_measure >= FPS_MEASURE_TIME {
                fps = xx (frames / FPS_MEASURE_TIME);
                frames = 0;
                time_between_measure = 0;
                FrameInfo.latency = FrameInfo.delta;
            }
            FrameInfo.last = current;
        }

        update_window_events();
        for get_window_resizes() {
            WindowWidth, WindowHeight = it.width, it.height;
            Gaco.resize(it.width, it.height);
            fonts_window_resize(it.width, it.height);
        }
        for events_this_frame {
            if it.type == {
            case .QUIT; quit = true;
            case .KEYBOARD;
                if it.key_code == {
                case .ESCAPE; quit = true;
                }
            }
        }

        Gaco.clear(50.0 / 0xFF, 15.0 / 0xFF, 22.0 / 0xFF, 1.0);

        draw_shadowed_text(*font, tprint("Latency: % ms", FrameInfo.latency*1000), .{0, xx (WindowHeight - font.size)});
        draw_shadowed_text(*font, tprint("FPS: %", fps), .{0, 0});

        draw_shadowed_text(*big_font, IMPORTANT_TEXT, .{0, WindowHeight * 0.1});
        Gaco.present(0);

    }
}

draw_shadowed_text :: (font: *Font, text: string, pos: Vector2) {
    draw_text(font, text, pos + .{font.size * 0.05, font.size * 0.05}, .{0, 0, 0, 1});
    draw_text(font, text, pos);
}

#run build_shader("text");


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
#import "Window_Creation";
#import "Basic";
#import "Compiler";
#import "File";
#import "Math";

Gaco :: #import,dir "../../Gaco";

#load "font.jai";