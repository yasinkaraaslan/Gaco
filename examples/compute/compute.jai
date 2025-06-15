SIZE :: 69 * 105;

main :: () {
   random_seed(420);

   Gaco.init(null); // We can pass null here if we do not plan to render anything.

   shader := Gaco.load_shader("compute", .Compute);
   Gaco.set_shader(shader);

   init_data : [] float;
   init_data.count = SIZE;
   init_data.data = alloc(SIZE * size_of(float));

   for * init_data {
      it.* = random_get_zero_to_one();
   }

   compute_input_buffer := Gaco.create_buffer(*init_data, .Structured);


   out_buffer := Gaco.create_buffer(null, .RWStructured, overrided_count=SIZE, overrided_stride = size_of(float));
   copy_buffer := Gaco.create_buffer(null, .Copy, overrided_count = SIZE, overrided_stride = size_of(float)); // We cannot directly map the output buffer, so we need a copy buffer.

   Gaco.bind_buffer(compute_input_buffer, bind_to=.Compute);
   Gaco.bind_buffer(out_buffer, bind_to=.Compute);

   Gaco.dispatch_compute(69, 105, 1);


   output : []float;
   output.data = alloc(SIZE * size_of(float));
   output.count = SIZE;

   Gaco.copy_buffer(out_buffer, copy_buffer);

   out_data := Gaco.map_buffer(copy_buffer, true, false);
   memcpy(output.data, out_data, SIZE);
   Gaco.unmap_buffer(copy_buffer);

   print("--------- INIT DATA -------\n");
   print("%\n", init_data);
   print("--------- OUT DATA  -------\n");
   print("%\n", output);
}

#run {
   Gaco.compile_shader("compute.hlsl", "compute", .Compute);
}

#import "Basic";
#import "Random";
Gaco :: #import,dir "../../Gaco"(DEBUG=true);
#import "d3d11"()(INCLUDE_DEBUG_BINDINGS=true);