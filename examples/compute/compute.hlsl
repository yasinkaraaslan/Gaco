StructuredBuffer<float> input : register(t0);

// NOTE(Yasin): OpenGL's GL_SHADER_STORAGE_BUFFER binding points are shared between
// read-only and read-write buffers, so 't' and 'u' registers must not overlap
// when both are bound to the compute stage.
RWStructuredBuffer<float> output : register(u1);

static const uint NumX = 69;
static const uint NumY = 105;
[numthreads(1,1,1)]
void compute_main(uint3 DTid : SV_DispatchThreadID) {
   uint index = DTid.x + DTid.y * NumX;

   // We do some stuff to see the result
   float value = input[index];
   float squared = value * value;
   float doubled = value + value;

   output[index] = squared + squared * doubled;
}