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
// Slightly rewritten to minimize operations
float fastExpWeight(float k, float distSq) {
    float x = k * distSq;
    return 1.0 / (1.0 + x * (1.0 + 0.5 * x));
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

    // Use mediump for accumulators to save registers/cycles
    mediump vec3 accum  = vec3(0.0);
    mediump float sumW = 0.0;

    mediump float minDist = 1e10;
    lowp vec3  nearest = vec3(0.0);   // lowp sufficient for palette colors

    // Precompute stepping factors to avoid division inside loop
    float invSize = 1.0 / float(size);
    float uStep   = invSize;
    float uStart  = 0.5 * invSize;

    // Hint to compiler to unroll the loop for better pipelining
    #pragma unroll
    for (int i = 0; i < 128; ++i) {
        if (i >= size) break;

        float u = float(i) * uStep + uStart;
        // Use texelFetch instead of texture() – avoids UV filtering & derivative overhead
        // Assumes paletteTexture is a 2D texture with height=1.
        lowp vec3 pColor = texelFetch(paletteTexture, ivec2(i, 0), 0).rgb;

        // Difference and squared distance (dot product is hardware accelerated)
        mediump vec3 diff = color - pColor;
        mediump float distSq = dot(diff, diff);

        // Nearest neighbor tracking (for fallback)
        if (distSq < minDist) {
            minDist = distSq;
            nearest = pColor;
        }

        // Skip if contribution < threshold
        if (distSq > maxDistSq) continue;

        // Weight using fast approximation
        mediump float w = fastExpWeight(sharpness, distSq);

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