// Code mostly taken from other modules that also have binding generators.
AT_COMPILE_TIME :: true;
SOURCE_PATH :: "source";
LIB_BASE_NAME :: "spirv_reflect";

#if AT_COMPILE_TIME {
    #run,stallable {
        set_build_options_dc(.{do_output=false});
        options := get_build_options();
        args := options.compile_time_command_line;
        if !generate_bindings(args) {
            compiler_set_workspace_status(.FAILED);
        }
    }
} else {
    #import "System";

    main :: () {
        set_working_directory(path_strip_filename(get_path_of_running_executable()));
        if !generate_bindings(get_command_line_arguments()) {
            exit(1);
        }
    }
}

generate_bindings :: (args: [] string) -> bool {
	compile := array_find(args, "-compile");
	compile_debug := array_find(args, "-debug");
	os_target  := OS;

	assert(os_target == .WINDOWS || os_target == .LINUX);

	cpu_target := CPU;

	lib_directory: string;
    if os_target == {
   	case .WINDOWS;
        lib_directory = "lib/windows";
    case .LINUX;
        lib_directory = "lib/linux";
	}
	if compile {
        source_file := tprint("%/spirv_reflect.c", SOURCE_PATH);

        make_directory_if_it_does_not_exist(lib_directory, recursive = true);
        lib_path := tprint("%/%", lib_directory, LIB_BASE_NAME);
        success := build_cpp_dynamic_lib(lib_path, source_file, target=os_target, debug=compile_debug);
        success &&= build_cpp_static_lib(lib_path, source_file, target=os_target, debug=compile_debug);
        if !success return false;
    }
    options: Generate_Bindings_Options;
    options.os = os_target;
    options.cpu = cpu_target;
    {
        using options;
        generate_library_declarations = true;
        array_add(*libpaths, lib_directory);
        array_add(*libpaths, "./lib/windows/");
        array_add(*libnames, tprint("%.lib", LIB_BASE_NAME));

        array_add(*source_files, tprint("%/spirv_reflect.h", SOURCE_PATH));
        array_add(*typedef_prefixes_to_unwrap, "spv");


        footer = tprint(FOOTER_TEMPLATE, LIB_BASE_NAME);
        auto_detect_enum_prefixes = true;
        log_stripped_declarations = true;
        log_unsupported = true;
    }

    output_filename := "bindings.jai";
    return generate_bindings(options, output_filename);
}

FOOTER_TEMPLATE :: #string DONE
#if OS == .WINDOWS {
    %1 :: #library "windows/%1";
}
else #if OS == .LINUX {
    %1 :: #library "linux/%1";
}
DONE

#import "String";
#import "File";
#import "Basic";
#import "Compiler";
#import "BuildCpp";
#import "Bindings_Generator";