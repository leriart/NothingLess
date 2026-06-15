pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.globals

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
     * Supports concurrent calls from multiple screens by queuing callbacks.
     * @param cachePath The cache file path to check
     * @param callback Function(bool exists)
     */
    function checkCache(cachePath, callback) {
        if (!cachePath || cachePath === root.currentWallpaper) {
            if (callback) callback(false);
            return;
        }

        // ─── Multi-screen support: queue callbacks ──────────────────
        // If already checking the same path, just enqueue the callback
        if (checkProc.running && root._checkingPath === cachePath) {
            root._checkCallbacks.push(callback);
            return;
        }

        // Enqueue and set target path
        root._checkCallbacks.push(callback);
        root._checkingPath = cachePath;

        // If already running for a different path, wait — the new path
        // will be picked up when the current check finishes.
        if (checkProc.running) return;

        root._startCheckProcess();
    }

    /** Internal: launch checkProc for the current _checkingPath */
    function _startCheckProcess() {
        const cachePath = root._checkingPath;
        if (!cachePath) return;

        // Disconnect previous handler to avoid leaks
        try { checkProc.exited.disconnect(root._checkProcHandler); } catch(e) {}

        root._checkProcHandler = (code) => {
            checkProc.exited.disconnect(root._checkProcHandler);

            // Notify ALL queued callbacks for this path
            const cbs = root._checkCallbacks.slice();
            root._checkCallbacks = [];
            root._checkingPath = "";
            for (let i = 0; i < cbs.length; i++) {
                if (cbs[i]) cbs[i](code === 0);
            }

            // If new requests queued while we were busy, start the next
            if (root._checkCallbacks.length > 0 && root._checkingPath) {
                root._startCheckProcess();
            }
        };
        checkProc.exited.connect(root._checkProcHandler);

        checkProc.command = ["test", "-f", cachePath];
        checkProc.running = true;
    }

    property Process checkProc: Process {
        running: false
    }
    property var _checkProcHandler: null
    property var _checkCallbacks: []
    property string _checkingPath: ""

    /**
     * Generate a downscaled cache of a video file using ffmpeg.
     * Uses hardware acceleration when available.
     * Supports concurrent calls from multiple screens by queuing callbacks
     * and avoiding duplicate ffmpeg processes for the same cache path.
     * @param originalPath Absolute path to the original video
     * @param cachePath Target cache path
     * @param callback Function(bool success)
     */
    function generateCache(originalPath, cachePath, callback) {
        if (!originalPath || !cachePath) {
            if (callback) callback(false);
            return;
        }

        // ─── Multi-screen support: avoid duplicate generation ───────
        // If already generating the same cache path, just enqueue
        if (genProc.running && root._generatingPath === cachePath) {
            root._genCallbacks.push(callback);
            return;
        }

        // Enqueue and set target path
        root._genCallbacks.push(callback);
        root._generatingPath = cachePath;
        root._genOriginalPath = originalPath;

        // If already running for a different path, wait — the new
        // generation will be picked up when the current one finishes.
        if (genProc.running) return;

        root._startGenProcess();
    }

    /** Internal: launch genProc for the current _generatingPath */
    function _startGenProcess() {
        const cachePath = root._generatingPath;
        if (!cachePath || !root._genOriginalPath) return;

        // Build ffmpeg command with optimal HW acceleration
        let cmd = [];

        if (root._hwEncoder && root._hwScaleFilter) {
            // Hardware-accelerated path
            if (GpuDetector.isIntel) {
                cmd = ["ffmpeg", "-hwaccel", "qsv", "-hwaccel_output_format", "qsv",
                       "-i", root._genOriginalPath,
                       "-vf", root._hwScaleFilter + "=-1:" + root.targetHeight,
                       "-c:v", root._hwEncoder, "-preset", "veryfast",
                       "-an", "-y", cachePath];
            } else if (GpuDetector.isAmd) {
                cmd = ["ffmpeg", "-hwaccel", "vaapi", "-hwaccel_output_format", "vaapi",
                       "-i", root._genOriginalPath,
                       "-vf", "format=nv12,hwupload," + root._hwScaleFilter + "=-1:" + root.targetHeight,
                       "-c:v", root._hwEncoder, "-preset", "veryfast",
                       "-an", "-y", cachePath];
            } else if (GpuDetector.isNvidia) {
                cmd = ["ffmpeg", "-hwaccel", "cuda", "-hwaccel_output_format", "cuda",
                       "-i", root._genOriginalPath,
                       "-vf", root._hwScaleFilter + "=-1:" + root.targetHeight,
                       "-c:v", root._hwEncoder, "-preset", "p1",
                       "-an", "-y", cachePath];
            }
        }

        // Fallback: software encoding
        if (cmd.length === 0) {
            cmd = ["ffmpeg", "-i", root._genOriginalPath,
                   "-vf", "scale=-1:" + root.targetHeight,
                   "-c:v", "libx264", "-preset", "ultrafast", "-crf", "28",
                   "-an", "-y", cachePath];
        }

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

            // Notify ALL queued callbacks for this generation
            const cbs = root._genCallbacks.slice();
            root._genCallbacks = [];
            root._generatingPath = "";
            for (let i = 0; i < cbs.length; i++) {
                if (cbs[i]) cbs[i](success);
            }

            // If new requests queued while we were busy, start the next
            if (root._genCallbacks.length > 0 && root._generatingPath) {
                root._startGenProcess();
            }
        }
    }

    property var _genCallbacks: []
    property string _generatingPath: ""
    property string _genOriginalPath: ""

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
            paused: root.screenLocked || !root.videoPlaying || (typeof GlobalStates !== "undefined" && GlobalStates.gameModeActive),
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
Component.onDestruction: {
    genProc.stop ? genProc.stop() : undefined;
    genProc.running !== undefined ? genProc.running = false : undefined;
    genProc.destroy !== undefined ? genProc.destroy() : undefined;
}
}
