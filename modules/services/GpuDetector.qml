pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * GpuDetector.qml — GPU vendor detection singleton.
 *
 * Detects GPU vendor synchronously at initialization time so that
 * VideoWallpaperService and other consumers can rely on the vendor
 * being already detected when they first query it.
 */
Singleton {
    id: root

    // Synchronous vendor detection. Set during component initialization.
    property string vendor: "unknown"

    readonly property bool hasHardwareDecoder: root.vendor !== "unknown" && root.vendor !== ""
    readonly property bool isNvidia: root.vendor === "nvidia"
    readonly property bool isAmd:    root.vendor === "amd"
    readonly property bool isIntel:  root.vendor === "intel"

    // Run synchronous detection at component creation time
    Component.onCompleted: {
        const dirs = ["card0", "card1", "card2"];
        for (let i = 0; i < dirs.length; i++) {
            try {
                const req = new XMLHttpRequest();
                req.open("GET", "file:///sys/class/drm/" + dirs[i] + "/device/vendor", false); // synchronous
                req.send();
                const raw = req.responseText ? req.responseText.trim() : "";
                if (raw === "0x10de") { root.vendor = "nvidia"; break; }
                if (raw === "0x1002") { root.vendor = "amd"; break; }
                if (raw === "0x8086") { root.vendor = "intel"; break; }
            } catch(e) {
                // card[0-2] may not exist, keep trying
            }
        }
        console.log("GpuDetector:", root.vendor);

        // If synchronous detection failed, try async fallback
        if (root.vendor === "unknown") {
            gpuDetect.running = true;
        }
    }

    // Async fallback detection for non-standard card numbering
    property Process gpuDetect: Process {
        command: ["bash", "-c",
            "v=$(for f in /sys/class/drm/card*/device/vendor; do cat \"$f\" 2>/dev/null && break; done); " +
            "case $v in " +
            "  0x10de) echo nvidia;; " +
            "  0x1002) echo amd;; " +
            "  0x8086) echo intel;; " +
            "  *) echo unknown;; " +
            "esac"]
        running: false  // started by Component.onCompleted if sync failed
        stdout: StdioCollector {
            onStreamFinished: {
                let result = String(text).trim();
                if (result && result.length > 0 && root.vendor === "unknown") {
                    root.vendor = result;
                    console.log("GpuDetector (async fallback):", result);
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
