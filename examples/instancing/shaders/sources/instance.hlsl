// Vertex Shader
cbuffer Constant_Buffer : register(b0) {
    matrix transformation;
};

struct Vertex_Input {
    float3 pos: POSITION;
    float4 color: COLOR;
    float3 normal: NORMAL;
    float2 uv: TEXCOORD0;
};

struct Instance_Input {
    float3 pos: INST_POSITION;
};

struct Fragment_Input {
    float4 pos: SV_Position;
    float2 tex: TEXCOORD0;
};

Fragment_Input vertex_main(Vertex_Input vertex, Instance_Input instance) {
    Fragment_Input output;
    output.pos = mul(float4(vertex.pos + instance.pos, 1), transformation);
    output.tex = vertex.uv;
    return output;
};


// Fragment Shader
Texture2D shader_texture: register(t0);
SamplerState texture_sampler: register(s0);

float4 fragment_main(Fragment_Input input) : SV_Target {

    float4 color = shader_texture.Sample(texture_sampler, input.tex);
    return color;
}