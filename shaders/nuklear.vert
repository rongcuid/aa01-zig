/// An absolutely simple shader taking vertices in NDC and UV.
#version 450
#extension GL_EXT_shader_explicit_arithmetic_types:require

layout(location=0)in vec2 position;
layout(location=1)in vec2 uv;
layout(location=2)in uint color;

layout(location=0)out vec2 fragUv;
layout(location=1)out vec4 fragColor;

void main(){
    gl_Position=vec4(position,0.f,1.f);
    fragUv=uv;
    fragColor=unpackUnorm4x8(color);
}
