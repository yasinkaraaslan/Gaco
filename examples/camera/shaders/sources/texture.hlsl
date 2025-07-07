// Vertex Shader
cbuffer Constant_Buffer : register(b0) {
    matrix transformation;
};

struct Vertex_Input {
    float3 pos: POSITION;
    float2 tex: TEXCOORD0;
};

struct Pixel_Input {
    float4 pos: SV_Position;
    float2 tex: TEXCOORD0;
};

Pixel_Input vertex_main(Vertex_Input input) {
    Pixel_Input pixel_input;
    pixel_input.pos = mul(float4(input.pos, 1), transformation);
    pixel_input.tex = input.tex;
    return pixel_input;
};


// Fragment Shader
Texture2D shader_texture: register(t0);
SamplerState texture_sampler: register(s0);

float4 fragment_main(Pixel_Input input, uint tid: SV_PrimitiveID) : SV_Target {

    float4 color = shader_texture.Sample(texture_sampler, input.tex);
    return color;
}