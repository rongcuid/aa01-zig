/// An absolutely simple shader taking vertices in NDC and UV.
#version 450

layout(location=0)out vec2 fragUv;

//const array of positions for the triangle
const vec2 positions[3]=vec2[3](
    vec2(1.f,1.f),
    vec2(-1.f,1.f),
    vec2(0.f,-1.f)
);
const vec2 uvs[3]=vec2[3](
    vec2(1.f,1.f),
    vec2(-1.f,1.f),
    vec2(0.f,-1.f)
);

void main(){
    gl_Position=vec4(positions[gl_VertexIndex],0.f,1.f);
    fragUv=uvs[gl_VertexIndex];
}
