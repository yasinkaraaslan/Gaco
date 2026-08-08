#import "Compiler";
#import "Basic";
#import "String";

#run run_example_tests();

run_example_tests :: () {
    set_build_options_dc(.{do_output=false});

    examples := string.[
        "triangle",
        "text_rendering",
        "get_rect",
        "compute",
        "skybox",
        "screenshot",
        "colored_cube",
        "camera",
        "jon_cube",
    ];

    log("Starting compilation tests for % examples...", examples.count);

    base_dir := path_strip_filename(#filepath);
    success_count := 0;

    for example_name: examples {
        dir_path  := tprint("%1%2", base_dir, example_name);
        file_path := tprint("%1/main.jai", dir_path);

        set_working_directory(dir_path);

        w := compiler_create_workspace(example_name);

        options := get_build_options(w);
        options.output_executable_name = example_name;
        options.output_type = .NO_OUTPUT;
        set_build_options(options, w);

        compiler_begin_intercept(w);

        add_build_file(file_path, w);

        has_errors := false;

        // We do it sequentially unfortunately because set_working_directory is process-wide
        while true {
            message := compiler_wait_for_message();
            if message.workspace == w {
                if message.kind == .ERROR {
                    has_errors = true;
                } else if message.kind == .COMPLETE {
                    break;
                }
            }
        }
        if has_errors {
            log("[FAILED] %", example_name);
        } else {
            log("[OK]     %", example_name);
            success_count += 1;
        }
    }

    set_working_directory(base_dir);

    log("\n--- TEST RESULTS ---");
    log("%/% examples compiled successfully.", success_count, examples.count);

    if success_count < examples.count {
        compiler_set_workspace_status(.FAILED);
    }
}