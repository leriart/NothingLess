pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

/**
 * VideoWallpaperService.qml — Runtime optimizer for video wallpapers.
 *
 * Handles:
 * - Optimal FPS based on GPU capability
 * - Video downscale caching for 4K/1440p wallpapers
 * - Pause/resume on screen lock
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

    // Max threads for software decoding (0 = hardware decoder handles it)
    readonly property int maxSoftwareThreads: {
        if (GpuDetector.isNvidia) return 0;
        if (GpuDetector.isAmd)    return 0;
        if (GpuDetector.isIntel)  return 0;
        return 4;
    }

    // Current state
    property bool videoPlaying: false
    property bool screenLocked: false
    property string currentWallpaper: ""

    // ─── Downscale Cache ────────────────────────────────────────────

    // Cache directory for downscaled videos
    readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/nothingless/video-cache"

    // Parse resolution limit from config into a height number
    // "native" → 0 (no limit), "720p" → 720, "1080p" → 1080, "1440p" → 1440
    readonly property int targetHeight: {
        const limit = Config.performance.videoResolutionLimit || "native";
        switch (limit) {
        case "720p":  return 720;
        case "1080p": return 1080;
        case "1440p": return 1440;
        default:      return 0; // native
        }
    }

    // FFmpeg hwaccel encoder per GPU vendor
    readonly property string _hwEncoder: {
        if (GpuDetector.isIntel)  return "h264_qsv";
        if (GpuDetector.isAmd)    return "h264_vaapi";
        if (GpuDetector.isNvidia) return "h264_nvenc";
        return "";
    }

    readonly property string _hwScaleFilter: {
        if (GpuDetector.isIntel)  return "scale_qsv";
        if (GpuDetector.isAmd)    return "scale_vaapi";
        if (GpuDetector.isNvidia) return "scale_cuda";
        return "scale";
    }

    // Simple hash from file path (djb2) for unique cache filenames
    function _hashPath(path) {
        let hash = 5381;
        for (let i = 0; i < path.length; i++) {
            hash = ((hash << 5) + hash) + path.charCodeAt(i);
            hash = hash & hash; // Convert to 32-bit integer
        }
        return Math.abs(hash).toString(16);
    }

    /**
     * Get the expected cache path for a video file at the target resolution.
     * @param originalPath Absolute path to the original video
     * @returns Cache file path, or originalPath if resolutionLimit is "native"
     */
    function getEffectivePath(originalPath) {
        if (!originalPath || root.targetHeight === 0) return originalPath;

        // Only process actual videos
        if (!/\.(mp4|webm|mkv|mov|avi)$/i.test(originalPath)) return originalPath;

        const ext = originalPath.toLowerCase().split(".").pop();
        const hash = root._hashPath(originalPath);
        return root.cacheDir + "/" + hash + "-" + root.targetHeight + "p." + ext;
    }

    /**
     * Check if a cached version exists using a quick test process.
     * Returns a bool-ish result via callback (QML async limitation).
     * @param cachePath The cache file path to check
     * @param callback Function(bool exists)
     */
    function checkCache(cachePath, callback) {
        if (!cachePath || cachePath === root.currentWallpaper) {
            if (callback) callback(false);
            return;
        }

        // Disconnect previous handler to avoid leaks
        try { checkProc.exited.disconnect(root._checkProcHandler); } catch(e) {}

        root._checkProcHandler = (code) => {
            checkProc.exited.disconnect(root._checkProcHandler);
            if (callback) callback(code === 0);
        };
        checkProc.exited.connect(root._checkProcHandler);

        checkProc.command = ["test", "-f", cachePath];
        checkProc.running = true;
    }

    property Process checkProc: Process {
        running: false
    }
    property var _checkProcHandler: null

    /**
     * Generate a downscaled cache of a video file using ffmpeg.
     * Uses hardware acceleration when available.
     * @param originalPath Absolute path to the original video
     * @param cachePath Target cache path
     * @param callback Function(bool success)
     */
    function generateCache(originalPath, cachePath, callback) {
        if (!originalPath || !cachePath) {
            if (callback) callback(false);
            return;
        }

        // Build ffmpeg command with optimal HW acceleration
        let cmd = [];

        if (root._hwEncoder && root._hwScaleFilter) {
            // Hardware-accelerated path
            if (GpuDetector.isIntel) {
                cmd = ["ffmpeg", "-hwaccel", "qsv", "-hwaccel_output_format", "qsv",
                       "-i", originalPath,
                       "-vf", root._hwScaleFilter + "=-1:" + root.targetHeight,
                       "-c:v", root._hwEncoder, "-preset", "veryfast",
                       "-an", "-y", cachePath];
            } else if (GpuDetector.isAmd) {
                cmd = ["ffmpeg", "-hwaccel", "vaapi", "-hwaccel_output_format", "vaapi",
                       "-i", originalPath,
                       "-vf", "format=nv12,hwupload," + root._hwScaleFilter + "=-1:" + root.targetHeight,
                       "-c:v", root._hwEncoder, "-preset", "veryfast",
                       "-an", "-y", cachePath];
            } else if (GpuDetector.isNvidia) {
                cmd = ["ffmpeg", "-hwaccel", "cuda", "-hwaccel_output_format", "cuda",
                       "-i", originalPath,
                       "-vf", root._hwScaleFilter + "=-1:" + root.targetHeight,
                       "-c:v", root._hwEncoder, "-preset", "p1",
                       "-an", "-y", cachePath];
            }
        }

        // Fallback: software encoding
        if (cmd.length === 0) {
            cmd = ["ffmpeg", "-i", originalPath,
                   "-vf", "scale=-1:" + root.targetHeight,
                   "-c:v", "libx264", "-preset", "ultrafast", "-crf", "28",
                   "-an", "-y", cachePath];
        }

        root._currentGenCallback = callback;
        genProc.command = cmd;
        genProc.running = true;
    }

    property Process genProc: Process {
        id: genProc
        running: false
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: (code) => {
            const success = code === 0;
            if (!success) {
                console.warn("VideoWallpaper: cache generation failed (exit", code + ")");
            } else {
                console.log("VideoWallpaper: cache generated");
            }
            if (root._currentGenCallback) {
                root._currentGenCallback(success);
                root._currentGenCallback = null;
            }
        }
    }

    property var _currentGenCallback: null

    /**
     * Ensure cache directory exists.
     */
    property Process _mkdirProc: Process {
        command: ["mkdir", "-p", root.cacheDir]
        running: true
    }

    // ─── Original API ───────────────────────────────────────────────

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

    function onScreenLocked() {
        root.screenLocked = true;
    }

    function onScreenUnlocked() {
        root.screenLocked = false;
    }

    function getDecoderConfig(filePath) {
        const codec = GpuDetector.detectCodecFromPath(filePath);
        return GpuDetector.getBestDecoder(codec);
    }
}
