pragma Singleton
import QtQuick
import Quickshell
import qs.config

/**
 * VideoWallpaperService.qml — Runtime optimizer for video wallpapers.
 *
 * Uses GpuDetector (same module, no import needed) to configure optimal playback:
 * - HW decoder available → native FPS, full resolution
 * - SW decoder only → lower FPS, limited threads
 * - Screen locked → pause video to save decode threads
 */
Singleton {
    id: root

    // Optimal FPS based on hardware capability
    readonly property int optimalFps: {
        if (GpuDetector.hasHardwareDecoder) return Config.performance.videoTargetFps || 24;
        return Math.min(Config.performance.videoTargetFps || 15, 15);
    }

    // Whether we're using hardware decoding
    readonly property bool usingHardware: GpuDetector.hasHardwareDecoder

    // Max threads for software decoding
    readonly property int maxSoftwareThreads: {
        if (GpuDetector.isNvidia) return 0;  // HW only
        if (GpuDetector.isAmd)    return 0;  // HW via VA-API
        if (GpuDetector.isIntel)  return 0;  // HW via QSV
        return 4;  // Software fallback
    }

    // Current state
    property bool videoPlaying: false
    property bool screenLocked: false
    property string currentWallpaper: ""

    /**
     * Configure video playback for a wallpaper path.
     * @param wallpaperPath Path to the video file
     * @returns { fps: int, paused: bool } optimized config
     */
    function optimize(wallpaperPath) {
        root.currentWallpaper = wallpaperPath;

        const isVideo = /\.(mp4|webm|mkv|mov|avi)$/i.test(String(wallpaperPath));

        return {
            fps: root.optimalFps,
            useHardware: root.usingHardware,
            maxThreads: root.maxSoftwareThreads,
            paused: root.screenLocked || !root.videoPlaying,
            isVideo: isVideo
        };
    }

    /**
     * Pause video when screen is locked.
     * Saves 26+ h264 decoder threads immediately.
     */
    function onScreenLocked() {
        root.screenLocked = true;
    }

    function onScreenUnlocked() {
        root.screenLocked = false;
    }

    /**
     * Detect codec from path and get best decoder config.
     */
    function getDecoderConfig(filePath) {
        const codec = GpuDetector.detectCodecFromPath(filePath);
        return GpuDetector.getBestDecoder(codec);
    }
}
