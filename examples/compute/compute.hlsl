StructuredBuffer<float> input : register(t0);
RWStructuredBuffer<float> output : register(u0);

static const uint NumX = 69;
static const uint NumY = 105;
[numthreads(1,1,1)]
void compute_main(uint3 DTid : SV_DispatchThreadID ) {
   uint index = DTid.x + DTid.y * NumX;

   float other_num1 = input[index] * input[index];
   float other_num2 = other_num1 * (input[index] + input[index]);
   output[index] = other_num1 + other_num2;
}