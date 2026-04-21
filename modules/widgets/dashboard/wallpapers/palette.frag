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
    // Salida inmediata para píxeles transparentes (ahorro masivo)
    if (tex.a < 0.001) {
        fragColor = vec4(0.0);
        return;
    }
    
    vec3 color = tex.rgb;
    int size = int(ubuf.paletteSize);
    
    // Factor de nitidez (ajustable, mismo valor que original)
    const float sharpness = 20.0;
    // Umbral de peso mínimo: cuando exp(-sharpness*distSq) < 0.001, ignoramos
    const float weightThreshold = 0.001;
    // distSq máxima correspondiente: d² = -ln(threshold)/sharpness ≈ 0.3454
    const float maxDistSq = 0.3454;
    
    vec3 accumulatedColor = vec3(0.0);
    float totalWeight = 0.0;
    
    // Precalcular constantes para el cálculo de coordenada U
    float invSize = 1.0 / float(size);
    float halfInv = 0.5 * invSize;
    
    // Bucle con límite estático 128 (máximo esperado)
    for (int i = 0; i < 128; ++i) {
        if (i >= size) break;
        
        // Coordenada U optimizada: i*invSize + 0.5*invSize
        float u = float(i) * invSize + halfInv;
        vec3 pColor = texture(paletteTexture, vec2(u, 0.5)).rgb;
        
        // Diferencia manual (evita función built-in)
        vec3 diff = color - pColor;
        float distSq = diff.x*diff.x + diff.y*diff.y + diff.z*diff.z;
        
        // Early skip si el peso sería insignificante
        if (distSq > maxDistSq) continue;
        
        // Aproximación rápida de exp(-sharpness * distSq) usando Padé [1/2]
        // f(x) = 1 / (1 + x + 0.5*x^2)  con x = sharpness * distSq
        // Evaluada con Horner para reducir multiplicaciones
        float x = sharpness * distSq;
        float weight = 1.0 / (1.0 + x * (1.0 + 0.5 * x));
        
        // Acumulación (puede ser FMA en hardware moderno)
        accumulatedColor += pColor * weight;
        totalWeight += weight;
    }
    
    // Normalización segura con épsilon
    vec3 finalColor = accumulatedColor / (totalWeight + 1e-5);
    
    // Pre‑multiplicación de alpha y opacidad global
    fragColor = vec4(finalColor * tex.a, tex.a) * ubuf.qt_Opacity;
}