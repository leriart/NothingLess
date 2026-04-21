#version 440
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

// Fast exp(-k*x) approximation using Padé [1/2]
// f(x) = 1 / (1 + x + 0.5*x^2) with x = k * distSq
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

    const float distributionSharpness = 20.0;     // Same as original
    const float weightThreshold = 0.001;          // Skip negligible contributions
    // Precomputed max squared distance: -ln(threshold)/sharpness ≈ 0.3454
    const float maxDistSq = 0.3454;

    vec3 accumulatedColor = vec3(0.0);
    float totalWeight = 0.0;

    // Nearest neighbor fallback for colors far from any palette entry
    float minDistSq = 1e10;
    vec3 closestColor = vec3(0.0);

    float invSize = 1.0 / float(size);
    float halfInv = 0.5 * invSize;

    for (int i = 0; i < 128; i++) {
        if (i >= size) break;

        float u = float(i) * invSize + halfInv;
        vec3 pColor = texture(paletteTexture, vec2(u, 0.5)).rgb;

        vec3 diff = color - pColor;
        float distSq = diff.x * diff.x + diff.y * diff.y + diff.z * diff.z;

        // Track closest color (for fallback)
        if (distSq < minDistSq) {
            minDistSq = distSq;
            closestColor = pColor;
        }

        // Skip if contribution would be below threshold
        if (distSq > maxDistSq) continue;

        // Use fast approximate Gaussian weight
        float weight = fastExpWeight(distributionSharpness, distSq);

        accumulatedColor += pColor * weight;
        totalWeight += weight;
    }

    vec3 finalColor;
    // Fallback: if total weight is near zero, snap to nearest palette color
    // Prevents bright saturated colors from becoming dark
    if (totalWeight < 0.001) {
        finalColor = closestColor;
    } else {
        finalColor = accumulatedColor / (totalWeight + 0.00001);
    }

    // Pre-multiply alpha for proper blending in Qt Quick
    fragColor = vec4(finalColor * tex.a, tex.a) * ubuf.qt_Opacity;
}