is_key_down :: inline (key : Key_Code) -> bool
{
    return (input_button_states[cast (s64) key] & .DOWN) != 0;
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
    #if OS == .WINDOWS {
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
    #if OS == .WINDOWS {
        win32 :: #import "Windows";
        win32.ClipCursor(null);
    }
}

