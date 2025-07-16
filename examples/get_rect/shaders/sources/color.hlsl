// Vertex Shader
cbuffer CBuffer : register(b0) {
    matrix proj;
};

struct Vertex_Input {
    float2 pos: POSITION;
    float4 color: COLOR;
};

struct Fragment_Input {
    float4 pos: SV_Position;
    float4 color: COLOR;
};

Fragment_Input vertex_main(Vertex_Input input) {
    Fragment_Input fragment_input;
    fragment_input.pos = mul(float4(input.pos, 0, 1), proj);
    fragment_input.color = input.color;
    return fragment_input;
}

// Fragment Shader

float4 fragment_main(Fragment_Input input) : SV_Target {
    return input.color;
}