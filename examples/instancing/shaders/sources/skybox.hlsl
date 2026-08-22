// Vertex Shader
cbuffer Constant_Buffer : register(b0) {
    matrix transformation;
};

struct Vertex_Input {
    float3 pos: POSITION;
};

struct Fragment_Input {
    float4 pos: SV_Position;
    float3 dir: DIRECTION;
};

Fragment_Input vertex_main(Vertex_Input input) {
    Fragment_Input fragment_input;
    fragment_input.pos = mul(float4(input.pos, 1), transformation).xyww;
    fragment_input.dir = input.pos;
    return fragment_input;
};


// Fragment Shader
TextureCube cubemap: register(t0);
SamplerState texture_sampler: register(s0);

float4 fragment_main(Fragment_Input input) : SV_Target {

    float4 color = cubemap.Sample(texture_sampler, input.dir);
    return color;
}