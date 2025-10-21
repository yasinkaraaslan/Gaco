// Vertex Shader
cbuffer Transform_Buffer : register(b0) {
    matrix transformation;
}

float4 vertex_main(float3 Pos : POSITION) : SV_Position {
    return mul(float4(Pos, 1), transformation);
}

// Fragment Shader
cbuffer Colors_Buffer : register(b1) {
    float4 face_colors[6];
}

float4 fragment_main(uint triangle_id: SV_PrimitiveID) : SV_Target {
    return face_colors[triangle_id/2];
}