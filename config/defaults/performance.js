.pragma library

var data = {
    // ─── Rendering ─────────────────────────────────────
    "renderBackend": "auto",           // "auto" | "opengl" | "vulkan"
    "maxRenderThreads": 6,             // Qt render thread pool (4-16)
    "gpuAcceleratedEffects": true,     // Usar GPU para efectos visuales
    "layerEffects": true,              // layer.enabled global (StyledRect shadows, etc)

    // ─── Video Wallpaper ───────────────────────────────
    "videoDecoder": "auto",            // "auto" | "hardware" | "software"
    "videoTargetFps": 24,              // FPS target para video wallpaper
    "videoResolutionLimit": "native",  // "native" | "720p" | "1080p" | "1440p"

    // ─── Visual Quality ────────────────────────────────
    "shadowQuality": "high",           // "off" | "low" | "medium" | "high"
    "blurQuality": "medium",           // "off" | "low" | "medium" | "high"
    "cornerRendering": true,           // Mostrar esquinas redondeadas
    "frameEffect": false,               // Mostrar frame alrededor de pantalla
    "thumbnailCacheSize": 50,          // Max thumbnails en cache LRU

    // ─── Animation ────────────────────────────────────
    "blurTransition": true,            // Blur animado al abrir paneles
    "windowPreview": true,              // Thumbnails en overview
    "wavyLine": true,                   // Línea wave en el reproductor
    "rotateCoverArt": true,             // Rotación de cover art

    // ─── Game Mode ─────────────────────────────────────
    // Preset applied when GameModeService.toggled = true
    "gameMode": {
        "zeroGaps": true,              // gapsIn/out = 0
        "reduceBorder": true,          // borderSize -> 1, rounding -> 0
        "disableBlur": true,           // compositor.blurEnabled = false
        "disableShadows": true,        // compositor.shadowEnabled = false
        "disableAnimations": true,     // compositor.animationsEnabled = false + Anim.instantMode
        "pauseVideoWallpaper": true,   // pause video wallpaper playback
        "suppressNotifications": true  // GlobalStates.notificationsDnd = true
    },

    // ─── Dashboard ────────────────────────────────────
    "dashboardPersistTabs": false,      // Mantener tabs abiertos en memoria
    "dashboardMaxPersistentTabs": 2,    // Max tabs persistentes

    // ─── Monitoring ────────────────────────────────────
    "systemMonitorInterval": 2000,      // ms, poll rate de system_monitor.py
    "backgroundServicePolling": 5000,   // ms, polling de servicios en background

    // ─── Boot ───────────────────────────────────────────
    "showSplash": true,                 // Mostrar splash al iniciar
    "splashDuration": 3000              // ms, duración del splash
}
