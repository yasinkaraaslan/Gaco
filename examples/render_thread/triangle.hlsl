cbuffer TransformBuffer : register(b0) {
    float4x4 rotation_matrix;
};

struct Fragment_Input {
    float3 color : COLOR;
    float4 sv_pos: SV_Position;
};

Fragment_Input vertex_main(float3 Pos : POSITION) {
    Fragment_Input output;
    output.color = Pos + 0.5;
    output.sv_pos = mul(float4(Pos, 1.0), rotation_matrix);
    return output;
};

float4 fragment_main(Fragment_Input input) : SV_Target {
    return float4(input.color, 1);
}