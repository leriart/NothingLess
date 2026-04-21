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

// Matriz de dithering Bayer 8x8 normalizada (valores 0..1)
const float ditherMatrix[64] = float[64](
     0.0/64.0, 32.0/64.0,  8.0/64.0, 40.0/64.0,  2.0/64.0, 34.0/64.0, 10.0/64.0, 42.0/64.0,
    48.0/64.0, 16.0/64.0, 56.0/64.0, 24.0/64.0, 50.0/64.0, 18.0/64.0, 58.0/64.0, 26.0/64.0,
    12.0/64.0, 44.0/64.0,  4.0/64.0, 36.0/64.0, 14.0/64.0, 46.0/64.0,  6.0/64.0, 38.0/64.0,
    60.0/64.0, 28.0/64.0, 52.0/64.0, 20.0/64.0, 62.0/64.0, 30.0/64.0, 54.0/64.0, 22.0/64.0,
     3.0/64.0, 35.0/64.0, 11.0/64.0, 43.0/64.0,  1.0/64.0, 33.0/64.0,  9.0/64.0, 41.0/64.0,
    51.0/64.0, 19.0/64.0, 59.0/64.0, 27.0/64.0, 49.0/64.0, 17.0/64.0, 57.0/64.0, 25.0/64.0,
    15.0/64.0, 47.0/64.0,  7.0/64.0, 39.0/64.0, 13.0/64.0, 45.0/64.0,  5.0/64.0, 37.0/64.0,
    63.0/64.0, 31.0/64.0, 55.0/64.0, 23.0/64.0, 61.0/64.0, 29.0/64.0, 53.0/64.0, 21.0/64.0
);

void main() {
    vec4 tex = texture(source, qt_TexCoord0);
    if (tex.a < 0.001) {
        fragColor = vec4(0.0);
        return;
    }
    
    // Obtener el valor de dithering para este píxel
    ivec2 fragCoord = ivec2(gl_FragCoord.xy);
    int index = (fragCoord.x & 7) + ((fragCoord.y & 7) << 3);
    float dither = ditherMatrix[index] - 0.5;  // Rango -0.5 .. 0.5
    
    // Aplicar dithering al color de entrada (sutil, escala reducida)
    vec3 color = tex.rgb + dither * 0.03;  // 0.03 ≈ 7/255, apenas perceptible pero rompe bandas
    
    int size = int(ubuf.paletteSize);
    const float sharpness = 20.0;
    const float weightThreshold = 0.001;
    const float maxDistSq = 0.3454;  // -ln(0.001)/20.0
    
    vec3 accumulatedColor = vec3(0.0);
    float totalWeight = 0.0;
    
    float invSize = 1.0 / float(size);
    float halfInv = 0.5 * invSize;
    
    // Bucle con early skip + aproximación de exp
    for (int i = 0; i < 128; ++i) {
        if (i >= size) break;
        
        float u = float(i) * invSize + halfInv;
        vec3 pColor = texture(paletteTexture, vec2(u, 0.5)).rgb;
        
        vec3 diff = color - pColor;
        float distSq = diff.x*diff.x + diff.y*diff.y + diff.z*diff.z;
        
        if (distSq > maxDistSq) continue;
        
        float x = sharpness * distSq;
        float weight = 1.0 / (1.0 + x * (1.0 + 0.5 * x));
        
        accumulatedColor += pColor * weight;
        totalWeight += weight;
    }
    
    vec3 finalColor = accumulatedColor / (totalWeight + 1e-5);
    
    // Re-multiplicar alpha y opacidad global
    fragColor = vec4(finalColor * tex.a, tex.a) * ubuf.qt_Opacity;
}