struct Vertex_Input {
    float3 pos: POSITION;
    float2 tex: TEXCOORD;
};

struct Fragment_Input {
    float4 pos: SV_Position;
    float2 tex: TEXCOORD;
};

Fragment_Input vertex_main(Vertex_Input input) {
    Fragment_Input pixel_input;
    pixel_input.pos = float4(input.pos, 1);
    pixel_input.tex = input.tex;
    return pixel_input;
}

Texture2D shader_texture: register(t0);
SamplerState texture_sampler: register(s0);

float4 fragment_main(Fragment_Input input) : SV_Target {
    return shader_texture.Sample(texture_sampler, input.tex);
}
