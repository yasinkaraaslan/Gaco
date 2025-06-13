
float4 vertex_main(float3 Pos : POSITION) : SV_Position {
    return float4(Pos, 1);
}

float4 fragment_main(float4 Pos : SV_Position) : SV_Target {
    return float4(0.2, 0.5, 0.5, 1);
}