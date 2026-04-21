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
    
    // Early exit for fully transparent pixels
    if (tex.a < 0.001) {
        fragColor = vec4(0.0);
        return;
    }
    
    vec3 color = tex.rgb;
    int size = int(ubuf.paletteSize);
    
    // Guard against invalid palette size
    if (size <= 0) {
        fragColor = tex * ubuf.qt_Opacity;
        return;
    }
    
    const float sharpness = 20.0;
    const float weightThreshold = 0.001;
    // maxDistSq = -ln(threshold) / sharpness
    const float maxDistSq = 0.3454;
    
    vec3 accumulatedColor = vec3(0.0);
    float totalWeight = 0.0;
    
    // Precompute U coordinate stepping
    float invSize = 1.0 / float(size);
    float halfInv = 0.5 * invSize;
    
    // Maximum loop count matches original bound (128)
    for (int i = 0; i < 128; ++i) {
        if (i >= size) break;
        
        // Palette texture coordinate
        float u = float(i) * invSize + halfInv;
        vec3 pColor = texture(paletteTexture, vec2(u, 0.5)).rgb;
        
        // Squared Euclidean distance
        vec3 diff = color - pColor;
        float distSq = diff.x * diff.x + diff.y * diff.y + diff.z * diff.z;
        
        // Skip if weight would be negligible (optimization)
        if (distSq > maxDistSq) continue;
        
        // Exact Gaussian weight (guarantees color fidelity)
        float weight = exp(-sharpness * distSq);
        
        accumulatedColor += pColor * weight;
        totalWeight += weight;
    }
    
    // Normalize with epsilon to avoid division by zero
    vec3 finalColor = accumulatedColor / (totalWeight + 1e-5);
    
    // Premultiplied alpha and global opacity
    fragColor = vec4(finalColor * tex.a, tex.a) * ubuf.qt_Opacity;
}