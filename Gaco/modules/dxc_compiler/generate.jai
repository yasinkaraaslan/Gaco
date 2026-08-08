AT_COMPILE_TIME :: true;

DXC_PATH :: "lib";

#if AT_COMPILE_TIME {
    #run,stallable {
        set_build_options_dc(.{do_output=false});
        if !generate_bindings() {
            compiler_set_workspace_status(.FAILED);
        }
    }
} else {
    #import "System";

    main :: () {
        set_working_directory(path_strip_filename(get_path_of_running_executable()));
        if !generate_bindings() {
            exit(1);
        }
    }
}

generate_bindings :: () -> bool {
    output_filename: string;
    options: Generate_Bindings_Options;
    {
        using options;

        #if OS == .WINDOWS {
            output_filename = "dxc_compiler_bindings.jai";
        } else {
            assert(false, "DXC bindings generation from this OS is not supported yet.");
        }
        array_add(*library_search_paths, DXC_PATH);
        #if OS == .WINDOWS {
            array_add(*libraries, .{filename="dxcompiler"});
        }
        else {
            array_add(*libraries, .{filename="libdxcompiler"});
        }

        array_add(*source_files, "d3dcompiler.h");
        //array_add(*source_files, "d3dcommon.h");
        array_add(*source_files, tprint("%/dxcapi.h", DXC_PATH));

        array_add(*extra_clang_arguments, "-x", "c++", "-DWIN32_LEAN_AND_MEAN");

        mimic_spacing_flags &= ~(Mimic_Spacing_Flags.VTABLE);
        log_stripped_declarations = false;
        generate_library_declarations = false;
        footer = DXC_FOOTER;
    }

    return generate_bindings(options, output_filename);
}

#scope_file

DXC_FOOTER :: #string END
#if OS == .WINDOWS {
    dxcompiler :: #library "lib/dxcompiler";
} else  {
    dxcompiler :: #library "lib/libdxcompiler";
}
END

#import "Basic";
#import "Bindings_Generator";
#import "Compiler";
#import "File";
#import "String";
