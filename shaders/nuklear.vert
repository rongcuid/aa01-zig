/// An absolutely simple shader taking vertices in NDC and UV.
#version 450

layout(location=0)in vec2 position;
layout(location=1)in vec2 uv;
layout(location=0)out vec2 fragUv;

void main(){
    gl_Position=vec4(position,0.f,1.f);
    fragUv=uv;
}