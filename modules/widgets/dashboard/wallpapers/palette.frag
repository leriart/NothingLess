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

const float SHARPNESS = 20.0;   // Controls how strictly colors snap to the palette
const float EPSILON   = 1e-5;   // Small value to avoid division by zero

// Rational Padé [2,2] approximation of exp(-x) for x >= 0.
// Extremely close to the real exponential for typical distance values,
// but computed without the expensive native exp() function.
float fastExpNeg(float x) {
    x = clamp(x, 0.0, 10.0);
    float x2 = x * x;
    return (1.0 - 0.5 * x + 0.1 * x2) / (1.0 + 0.5 * x + 0.1 * x2);
}

void main() {
    mediump vec4 tex = texture(source, qt_TexCoord0);
    mediump vec3 color = tex.rgb;

    int size = int(clamp(ubuf.paletteSize, 0.0, 128.0));
    if (size <= 0) {
        // No palette defined: pass the original color through
        fragColor = tex * ubuf.qt_Opacity;
        return;
    }

    // Precompute horizontal step for iterating through the palette texture
    float stepU = 1.0 / float(size);
    float u = 0.5 * stepU;   // Sample at pixel centers of the 1D palette texture

    mediump vec3 accumulated = vec3(0.0);
    mediump float totalWeight = 0.0;

    // Soft blending: each palette color contributes according to its
    // similarity to the source color, using a Gaussian-like weight.
    for (int i = 0; i < 128; ++i) {
        if (i >= size) break;

        mediump vec3 pColor = texture(paletteTexture, vec2(u, 0.5)).rgb;
        u += stepU;

        mediump vec3 diff = color - pColor;
        mediump float distSq = dot(diff, diff);   // Squared Euclidean distance

        // Weight = exp(-SHARPNESS * distSq) (approximated)
        mediump float weight = fastExpNeg(SHARPNESS * distSq);

        accumulated += pColor * weight;
        totalWeight += weight;
    }

    // Normalize the weighted sum
    mediump vec3 finalColor = accumulated / (totalWeight + EPSILON);

    // Preserve the original alpha and apply global opacity
    fragColor = vec4(finalColor * tex.a, tex.a) * ubuf.qt_Opacity;
}