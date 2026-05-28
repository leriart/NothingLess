pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * GpuDetector.qml — GPU vendor detection singleton.
 *
 * Detects GPU vendor at startup via Process (async, caches result).
 * Provides best video decoder config per vendor.
 */
Singleton {
    id: root

    readonly property string vendor: _detectedVendor
    property string _detectedVendor: "unknown"

    readonly property bool hasHardwareDecoder: root.vendor !== "unknown"
    readonly property bool isNvidia: root.vendor === "nvidia"
    readonly property bool isAmd:    root.vendor === "amd"
    readonly property bool isIntel:  root.vendor === "intel"

    // Async GPU detection via Process
    // Finds the first DRM card with a vendor file (not just card0)
    property Process gpuDetect: Process {
        command: ["bash", "-c",
            "v=$(for f in /sys/class/drm/card*/device/vendor; do cat \"$f\" 2>/dev/null && break; done); " +
            "case $v in " +
            "  0x10de) echo nvidia;; " +
            "  0x1002) echo amd;; " +
            "  0x8086) echo intel;; " +
            "  *) echo unknown;; " +
            "esac"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let result = String(text).trim();
                if (result && result.length > 0) {
                    root._detectedVendor = result;
                    console.log("GpuDetector:", result);
                }
            }
        }
    }

    function getBestDecoder(codec) {
        const c = codec || "h264";
        switch (root.vendor) {
        case "nvidia":
            return { hardware: true, decoder: c+"_cuvid", encoder: c+"_nvenc", device: "cuda", maxThreads: 2 };
        case "amd":
            return { hardware: true, decoder: c+"_vaapi", encoder: c+"_amf", device: "vaapi", maxThreads: 2 };
        case "intel":
            return { hardware: true, decoder: c+"_qsv", encoder: c+"_qsv", device: "qsv", maxThreads: 2 };
        default:
            return { hardware: false, decoder: c, encoder: null, device: "cpu", maxThreads: 4 };
        }
    }

    function detectCodecFromPath(path) {
        const ext = String(path).toLowerCase().split(".").pop();
        switch (ext) {
        case "mp4": case "mov": case "avi": return "h264";
        case "webm": case "mkv": return "vp9";
        default: return "h264";
        }
    }
}
