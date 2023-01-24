/// An absolutely simple shader taking a single texture.

#version 450

layout(binding=0,set=1)uniform sampler2D currentTexture;

layout(location=0)in vec2 fragUv;
layout(location=0)out vec4 outColor;

void main(){
    vec4 texColor=texture(currentTexture,fragUv);
    outColor=texColor;
}