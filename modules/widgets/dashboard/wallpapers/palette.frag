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

void main() {
    vec4 tex = texture(source, qt_TexCoord0);
    // Early exit for fully transparent pixels (massive savings)
    if (tex.a < 0.001) {
        fragColor = vec4(0.0);
        return;
    }
    
    vec3 color = tex.rgb;
    int size = int(ubuf.paletteSize);
    
    // Sharpness factor (adjustable, same as original)
    const float sharpness = 20.0;
    // Minimum weight threshold: when exp(-sharpness*distSq) < 0.001, we skip
    const float weightThreshold = 0.001;
    // Corresponding maximum squared distance: d² = -ln(threshold)/sharpness ≈ 0.3454
    const float maxDistSq = 0.3454;
    
    vec3 accumulatedColor = vec3(0.0);
    float totalWeight = 0.0;
    
    // Precompute constants for U coordinate calculation
    float invSize = 1.0 / float(size);
    float halfInv = 0.5 * invSize;
    
    // Loop with static bound 128 (maximum expected)
    for (int i = 0; i < 128; ++i) {
        if (i >= size) break;
        
        // Optimized U coordinate: i*invSize + 0.5*invSize
        float u = float(i) * invSize + halfInv;
        vec3 pColor = texture(paletteTexture, vec2(u, 0.5)).rgb;
        
        // Manual difference (avoids built-in function)
        vec3 diff = color - pColor;
        float distSq = diff.x*diff.x + diff.y*diff.y + diff.z*diff.z;
        
        // Early skip if weight would be negligible
        if (distSq > maxDistSq) continue;
        
        // Fast approximation of exp(-sharpness * distSq) using Padé [1/2]
        // f(x) = 1 / (1 + x + 0.5*x^2)  with x = sharpness * distSq
        // Evaluated using Horner's method to reduce multiplications
        float x = sharpness * distSq;
        float weight = 1.0 / (1.0 + x * (1.0 + 0.5 * x));
        
        // Accumulation (may become FMA on modern hardware)
        accumulatedColor += pColor * weight;
        totalWeight += weight;
    }
    
    // Safe normalization with epsilon
    vec3 finalColor = accumulatedColor / (totalWeight + 1e-5);
    
    // Pre-multiplied alpha and global opacity
    fragColor = vec4(finalColor * tex.a, tex.a) * ubuf.qt_Opacity;
}