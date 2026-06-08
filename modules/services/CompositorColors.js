.pragma library

/**
 * Shared color helpers for compositor integration.
 * Used by CompositorConfig and CompositorTomlWriter to avoid duplication.
 *
 * All functions that need Config accept it as the first argument so that
 * this library can be used from any QML context.
 */

function getColorValue(config, colorName) {
    const resolved = config.resolveColor(colorName);
    return (typeof resolved === 'string') ? Qt.color(resolved) : resolved;
}

function formatColorForCompositor(color) {
    const r = Math.round(color.r * 255).toString(16).padStart(2, '0');
    const g = Math.round(color.g * 255).toString(16).padStart(2, '0');
    const b = Math.round(color.b * 255).toString(16).padStart(2, '0');
    const a = Math.round(color.a * 255).toString(16).padStart(2, '0');

    if (color.a === 1.0) {
        return `rgb(${r}${g}${b})`;
    } else {
        return `rgba(${r}${g}${b}${a})`;
    }
}

function colorToHex(color, includeAlpha) {
    const r = Math.round(color.r * 255).toString(16).padStart(2, '0');
    const g = Math.round(color.g * 255).toString(16).padStart(2, '0');
    const b = Math.round(color.b * 255).toString(16).padStart(2, '0');

    if (includeAlpha) {
        const a = Math.round(color.a * 255).toString(16).padStart(2, '0');
        return `#${r}${g}${b}${a}`;
    }
    return `#${r}${g}${b}`;
}

function calculateIgnoreAlpha(barBgOpacity, bgOpacity) {
    // Calculate ignoreAlpha: higher bar opacity = higher ignoreAlpha threshold
    // At 0% opacity: ignoreAlpha = 0.0 (all transparent pixels blurred)
    // At 100% opacity: ignoreAlpha = 0.5 (only very transparent pixels blurred)
    // Scale linearly between these values
    const barAlpha = barBgOpacity || 0;
    const bgAlpha = bgOpacity || 0;
    const effectiveAlpha = Math.max(barAlpha, bgAlpha);
    return effectiveAlpha * 0.5;
}
