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

    lib_directory := "lib";

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
        array_add(*library_search_paths, lib_directory);
        array_add(*libraries, .{filename=LIB_BASE_NAME});

        array_add(*source_files, tprint("%/spirv_reflect.h", SOURCE_PATH));
        array_add(*typedef_prefixes_to_unwrap, "spv");


        generate_library_declarations = true;
        generate_compile_time_struct_checks = false;
        log_stripped_declarations = true;
        log_unsupported = true;
    }

    output_filename := "bindings.jai";
    return generate_bindings(options, output_filename);
}

#import "String";
#import "File";
#import "Basic";
#import "Compiler";
#import "BuildCpp";
#import "Bindings_Generator";