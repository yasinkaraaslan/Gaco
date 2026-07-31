// Vertex Shader
cbuffer Constant_Buffer : register(b0) {
    matrix proj;
};

struct Vertex_Input {
    float2 pos: POSITION;
    float4 color: COLOR;
    float2 tex: TEXCOORD0;
};

struct Fragment_Input {
    float4 pos: SV_Position;
    float4 color: COLOR;
    float2 tex: TEXCOORD0;
};

Fragment_Input vertex_main(Vertex_Input input) {
    Fragment_Input fragment_input;
    fragment_input.pos = mul(float4(input.pos, 0, 1), proj);
    fragment_input.tex = input.tex;
    fragment_input.color = input.color;
    return fragment_input;
};


// Fragment Shader
Texture2D shader_texture: register(t0);
SamplerState texture_sampler: register(s0);

float4 fragment_main(Fragment_Input input) : SV_Target {

    float4 texture_color = shader_texture.Sample(texture_sampler, input.tex);
    return texture_color * input.color;
}