// Vertex Shader
cbuffer ProjCBuffer : register(b0) {
    matrix proj;
}

cbuffer PosCBuffer : register(b1) {
    float2 global_pos;
}

struct Vertex_Input {
    float2 pos: POSITION;
    float2 uv: TEXCOORD0;
};

struct Fragment_Input {
    float4 pos: SV_Position;
    float2 tex: TEXCOORD0;
};

Fragment_Input vertex_main(Vertex_Input input) {
    Fragment_Input pixel_input;
    pixel_input.pos = mul(float4(global_pos + input.pos, 0, 1), proj);
    pixel_input.tex = input.uv;
    return pixel_input;
};

// Fragment Shader

cbuffer Fragment_CBuffer : register(b0) {
    float4 text_color : COLOR;
}

Texture2D shader_texture: register(t0);
SamplerState texture_sampler: register(s0);
float4 fragment_main(Fragment_Input input) : SV_Target {
    float4 color = float4(1,1,1, shader_texture.Sample(texture_sampler, input.tex).r);
    return color * text_color;
}