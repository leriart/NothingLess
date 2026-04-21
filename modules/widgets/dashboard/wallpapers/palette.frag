#version 440

layout(location = 0) in mediump vec2 qt_TexCoord0;
layout(location = 0) out mediump vec4 fragColor;

layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D paletteTexture;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float paletteSize;
    float texWidth;
    float texHeight;
} ubuf;

const float SHARPNESS = 20.0;
const float EPSILON   = 1e-5;

// Fast rational approximation of exp(-x) for x >= 0.
float fastExpNeg(float x) {
    x = clamp(x, 0.0, 10.0);
    return 1.0 / (1.0 + x + 0.5 * x * x);
}

void main() {
    mediump vec4 tex = texture(source, qt_TexCoord0);
    mediump vec3 color = tex.rgb;

    int size = int(clamp(ubuf.paletteSize, 0.0, 128.0));
    if (size <= 0) {
        fragColor = tex * ubuf.qt_Opacity;
        return;
    }

    // Precompute UV step to avoid divisions inside loop
    float stepU = 1.0 / float(size);
    float u = 0.5 * stepU;

    mediump vec3 accumulated = vec3(0.0);
    mediump float totalWeight = 0.0;

    for (int i = 0; i < 128; ++i) {
        if (i >= size) break;

        mediump vec3 pColor = texture(paletteTexture, vec2(u, 0.5)).rgb;
        u += stepU;

        mediump vec3 diff = color - pColor;
        mediump float distSq = diff.x*diff.x + diff.y*diff.y + diff.z*diff.z;

        mediump float weight = fastExpNeg(SHARPNESS * distSq);

        accumulated += pColor * weight;
        totalWeight += weight;
    }

    mediump vec3 finalColor = accumulated / (totalWeight + EPSILON);
    fragColor = vec4(finalColor * tex.a, tex.a) * ubuf.qt_Opacity;
}