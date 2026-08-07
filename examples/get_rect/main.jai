WindowWidth, WindowHeight := 1280, 720;
main :: () {
    window := create_window(WindowWidth, WindowHeight, "Gaco GetRect");
    Gaco.init(window);
    fonts_init();
    font := load_font("fonts/OpenSans-Regular.ttf", 32);

    gr_init();
    current_time, last_time: float64;

    quit := false;
    current_theme := default_theme_procs[Default_Themes.Default]();
    set_default_theme(current_theme);
    Values :: enum {
        Yeah;
        No;
        Ok;
        Why_Not;
    }

    checkbox_selected: bool;
    current_value: Values;
    while !quit {
        current_time = seconds_since_init();
        // delta = ...
        last_time = current_time;
        reset_temporary_storage();
        update_window_events();
        for get_window_resizes() {
            WindowWidth, WindowHeight = it.width, it.height;
            Gaco.resize(it.width, it.height);
            fonts_window_resize(it.width, it.height);
        }
        for events_this_frame {
            getrect_handle_event(it);
            if it.type == .QUIT || (it.type == .KEYBOARD && it.key_code == .ESCAPE)
                quit = true;
        }
        ui_per_frame_update(window, xx WindowWidth, xx WindowHeight, current_time);

        Gaco.clear(.{0.3, 0.4, 0.4, 1.0});


        k := WindowHeight * .1;
        r := get_rect(k*.5, 2.1*k, 4*k, k);
        button_theme := current_theme.button_theme;
        button_theme.font = font;
        button_theme.enable_variable_frame_thickness = true;

        button_theme.label_theme.alignment = .Left;
        pressed := button(r, "What do you do", *button_theme);

        r.y += k;
        button_theme.label_theme.alignment = .Center;
        pressed  = button(r, "With a", *button_theme);

        r.y += k;
        button_theme.label_theme.alignment = .Right;
        pressed  = button(r, "Drunken sailor?", *button_theme);


        r = get_rect(10*k, 1.8*k, 2*k, xx font.character_height);

        vertical_pad := r.h * .35;
        changed := base_checkbox(r, "Checkbox", checkbox_selected);
        if changed  checkbox_selected = !checkbox_selected;

        r.y += font.character_height + vertical_pad;

        // Why do radio buttons look like checkboxes by default??
        radio_theme := current_theme.checkbox_theme;
        radio_theme.is_radio_button = true;

        radio_button(r, *current_value, .Yeah, *radio_theme);
        r.y += font.character_height + vertical_pad;
        radio_button(r, *current_value, .No, *radio_theme);
        r.y += font.character_height + vertical_pad;
        radio_button(r, *current_value, .Ok, *radio_theme);
        r.y += font.character_height + vertical_pad;
        radio_button(r, *current_value, .Why_Not, *radio_theme);
        r.y += font.character_height + vertical_pad;

        Gaco.present();
    }
}

#load "get_rect.jai";
#load "font.jai";

#import "Math";
#import "Basic";
#import "File";
#import "Input";
#import "Window_Creation";

Gaco :: #import,dir "../../Gaco"(DEBUG=true);
#if OS == .WINDOWS {
    __d3d11 :: #import "d3d11"()(INCLUDE_DEBUG_BINDINGS=true);
}