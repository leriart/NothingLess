#version 440

// Precision statement for ES compatibility (ignored by desktop GLSL)
#ifdef GL_ES
precision highp float;
precision mediump int;
#endif

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D paletteTexture;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float paletteSize;
    float texWidth;
    float texHeight;
} ubuf;

// Fast exp(-k*x) approximation: 1 / (1 + x + 0.5*x^2)
float fastExpWeight(float k, float distSq) {
    float x = k * distSq;
    float x2 = x * x;
    return 1.0 / (1.0 + x + 0.5 * x2);
}

void main() {
    vec4 tex = texture(source, qt_TexCoord0);
    vec3 color = tex.rgb;

    // Early exit for fully transparent pixels
    if (tex.a < 0.001) {
        fragColor = vec4(0.0);
        return;
    }

    int size = int(ubuf.paletteSize);
    if (size <= 0) {
        fragColor = tex * ubuf.qt_Opacity;
        return;
    }

    const float sharpness      = 20.0;
    const float weightThresh   = 0.001;
    const float maxDistSq      = 0.3454;          // -ln(0.001)/20.0
    const float epsilon        = 1e-5;

    vec3 accum  = vec3(0.0);
    float sumW = 0.0;

    float minDist = 1e10;
    vec3  nearest = vec3(0.0);

    // Precompute stepping factors to avoid division inside loop
    float invSize = 1.0 / float(size);
    float uStep   = invSize;
    float uStart  = 0.5 * invSize;

    for (int i = 0; i < 128; ++i) {
        if (i >= size) break;

        float u = float(i) * uStep + uStart;
        vec3 pColor = texture(paletteTexture, vec2(u, 0.5)).rgb;

        // Difference and squared distance (unrolled for clarity, compiler optimizes)
        float dx = color.x - pColor.x;
        float dy = color.y - pColor.y;
        float dz = color.z - pColor.z;
        float distSq = dx*dx + dy*dy + dz*dz;

        // Nearest neighbor tracking (for fallback)
        if (distSq < minDist) {
            minDist = distSq;
            nearest = pColor;
        }

        // Skip if contribution < threshold
        if (distSq > maxDistSq) continue;

        // Weight using fast approximation
        float w = fastExpWeight(sharpness, distSq);

        accum += pColor * w;
        sumW += w;
    }

    vec3 finalColor;
    if (sumW < weightThresh) {
        finalColor = nearest;
    } else {
        finalColor = accum / (sumW + epsilon);
    }

    fragColor = vec4(finalColor * tex.a, tex.a) * ubuf.qt_Opacity;
}