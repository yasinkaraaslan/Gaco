SIZE :: 69 * 105;

main :: () {
    random_seed(420);

    Gaco.init(null); // We can pass null here if we do not plan to render anything.

    shader := Gaco.load_shader("compute.gaco");
    Gaco.set_shader(shader);

    init_data := NewArray(SIZE, float);

    for * init_data {
        it.* = random_get_zero_to_one();
    }

    compute_input_buffer := Gaco.create_buffer(init_data, .Structured);

    out_buffer := Gaco.create_buffer(null, SIZE, size_of(float), .Structured_RW);
    Gaco.bind_buffer(compute_input_buffer, 0, .Compute);
    Gaco.bind_buffer(out_buffer, 1);

    Gaco.dispatch_compute(69, 105, 1);

    output : []float;
    output.count = SIZE;
    output.data = Gaco.read_buffer(*out_buffer);

    print("--------- INIT DATA -------\n");
    print("%\n\n", init_data);
    print("--------- OUT DATA  -------\n");
    print("%\n\n", output);
}

#run {
    Gaco.compile_shader("compute.hlsl", "compute.gaco", .Compute);
}

#import "Basic";
#import "Random";
Gaco :: #import,dir "../../Gaco"(DEBUG=true);

#if OS == .WINDOWS #import "d3d11"()(INCLUDE_DEBUG_BINDINGS=true);