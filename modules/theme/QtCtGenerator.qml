import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

QtObject {
    id: root

    function generate(Colors) {
        if (!Colors) return

        // Helper to format color
        const fmt = (c) => c.toString()

        // Core colors
        const bg = Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, Config.theme.srBg.opacity).toString()
        const fg = fmt(Colors.overBackground)
        const surface = fmt(Colors.surface)
        const surfaceContainer = fmt(Colors.surfaceContainer)
        const surfaceContainerHigh = fmt(Colors.surfaceContainerHigh)
        const primary = fmt(Colors.primary)
        const secondary = fmt(Colors.secondary)
        const error = fmt(Colors.error)
        const inactive = fmt(Colors.outline)
        const link = fmt(Colors.tertiary)
        const selection = fmt(Colors.primary)
        const selectionFg = fmt(Colors.overPrimary)
        const outline = fmt(Colors.outline)

        // Font helpers — format: family,size,-1,5,weight,0,0,0,0,0 (QFont serialization)
        const fontWeight = 50 // Normal
        const uiFont = `${Config.theme.font},${Config.theme.fontSize},-1,5,${fontWeight},0,0,0,0,0`
        const monoFont = `${Config.theme.monoFont},${Config.theme.monoFontSize},-1,5,${fontWeight},0,0,0,0,0`
        const smallFont = `${Config.theme.font},${Math.max(Config.theme.fontSize - 2, 8)},-1,5,${fontWeight},0,0,0,0,0`

        // Construct INI content
        let ini = ""

        ini += "[ColorEffects:Disabled]\n"
        ini += `Color=${bg}\n`
        ini += "ColorAmount=0.5\n"
        ini += "ColorEffect=3\n"
        ini += "ContrastAmount=0\n"
        ini += "ContrastEffect=0\n"
        ini += "IntensityAmount=0\n"
        ini += "IntensityEffect=0\n\n"

        ini += "[ColorEffects:Inactive]\n"
        ini += "ChangeSelectionColor=true\n"
        ini += `Color=${bg}\n`
        ini += "ColorAmount=0.025\n"
        ini += "ColorEffect=0\n"
        ini += "ContrastAmount=0.1\n"
        ini += "ContrastEffect=0\n"
        ini += "Enable=true\n"
        ini += "IntensityAmount=0\n"
        ini += "IntensityEffect=0\n\n"

        const buttonColors = () => {
            let s = ""
            s += `BackgroundAlternate=${surface}\n`
            s += `BackgroundNormal=${surface}\n`
            s += `DecorationFocus=${primary}\n`
            s += `DecorationHover=${primary}\n`
            s += `ForegroundActive=${fg}\n`
            s += `ForegroundInactive=${inactive}\n`
            s += `ForegroundLink=${link}\n`
            s += `ForegroundNegative=${error}\n`
            s += `ForegroundNeutral=${fg}\n`
            s += `ForegroundNormal=${fg}\n`
            s += `ForegroundPositive=${secondary}\n`
            s += `ForegroundVisited=${fmt(Colors.tertiary)}\n`
            return s
        }

        ini += "[Colors:Button]\n" + buttonColors() + "\n"
        ini += "[Colors:Button][Inactive]\n" + buttonColors().replace(`BackgroundAlternate=${surface}\n`, `BackgroundAlternate=${surfaceContainer}\n`).replace(`BackgroundNormal=${surface}\n`, `BackgroundNormal=${surfaceContainer}\n`) + "\n"

        const compColors = () => {
            let s = ""
            s += `BackgroundAlternate=${bg}\n`
            s += `BackgroundNormal=${bg}\n`
            s += `DecorationFocus=${primary}\n`
            s += `DecorationHover=${primary}\n`
            s += `ForegroundActive=${fg}\n`
            s += `ForegroundInactive=${inactive}\n`
            s += `ForegroundLink=${link}\n`
            s += `ForegroundNegative=${error}\n`
            s += `ForegroundNeutral=${fg}\n`
            s += `ForegroundNormal=${fg}\n`
            s += `ForegroundPositive=${secondary}\n`
            s += `ForegroundVisited=${fmt(Colors.tertiary)}\n`
            return s
        }

        ini += "[Colors:Complementary]\n" + compColors() + "\n"
        ini += "[Colors:Complementary][Inactive]\n" + compColors() + "\n"

        ini += "[Colors:Header]\n" + compColors() + "\n"
        ini += "[Colors:Header][Inactive]\n" + compColors() + "\n"

        const selColors = () => {
            let s = ""
            s += `BackgroundAlternate=${selection}\n`
            s += `BackgroundNormal=${selection}\n`
            s += `DecorationFocus=${selection}\n`
            s += `DecorationHover=${selection}\n`
            s += `ForegroundActive=${selectionFg}\n`
            s += `ForegroundInactive=${selectionFg}\n`
            s += `ForegroundLink=${link}\n`
            s += `ForegroundNegative=${error}\n`
            s += `ForegroundNeutral=${selectionFg}\n`
            s += `ForegroundNormal=${selectionFg}\n`
            s += `ForegroundPositive=${secondary}\n`
            s += `ForegroundVisited=${fmt(Colors.tertiary)}\n`
            return s
        }

        ini += "[Colors:Selection]\n" + selColors() + "\n"
        ini += "[Colors:Selection][Inactive]\n" + selColors() + "\n"

        const tooltipColors = () => {
            let s = ""
            s += `BackgroundAlternate=${surface}\n`
            s += `BackgroundNormal=${bg}\n`
            s += `DecorationFocus=${primary}\n`
            s += `DecorationHover=${primary}\n`
            s += `ForegroundActive=${fg}\n`
            s += `ForegroundInactive=${inactive}\n`
            s += `ForegroundLink=${link}\n`
            s += `ForegroundNegative=${error}\n`
            s += `ForegroundNeutral=${fg}\n`
            s += `ForegroundNormal=${fg}\n`
            s += `ForegroundPositive=${secondary}\n`
            s += `ForegroundVisited=${fmt(Colors.tertiary)}\n`
            return s
        }

        ini += "[Colors:Tooltip]\n" + tooltipColors() + "\n"
        ini += "[Colors:Tooltip][Inactive]\n" + tooltipColors() + "\n"

        const viewColors = () => {
            let s = ""
            s += `BackgroundAlternate=${surface}\n`
            s += `BackgroundNormal=${bg}\n`
            s += `DecorationFocus=${primary}\n`
            s += `DecorationHover=${primary}\n`
            s += `ForegroundActive=${fg}\n`
            s += `ForegroundInactive=${inactive}\n`
            s += `ForegroundLink=${link}\n`
            s += `ForegroundNegative=${error}\n`
            s += `ForegroundNeutral=${fg}\n`
            s += `ForegroundNormal=${fg}\n`
            s += `ForegroundPositive=${secondary}\n`
            s += `ForegroundVisited=${fmt(Colors.tertiary)}\n`
            return s
        }

        ini += "[Colors:View]\n" + viewColors() + "\n"
        ini += "[Colors:View][Inactive]\n" + viewColors().replace(`BackgroundAlternate=${surface}\n`, `BackgroundAlternate=${surfaceContainer}\n`) + "\n"

        const windowColors = () => {
            let s = ""
            s += `BackgroundAlternate=${surface}\n`
            s += `BackgroundNormal=${bg}\n`
            s += `DecorationFocus=${primary}\n`
            s += `DecorationHover=${primary}\n`
            s += `ForegroundActive=${fg}\n`
            s += `ForegroundInactive=${inactive}\n`
            s += `ForegroundLink=${link}\n`
            s += `ForegroundNegative=${error}\n`
            s += `ForegroundNeutral=${fg}\n`
            s += `ForegroundNormal=${fg}\n`
            s += `ForegroundPositive=${secondary}\n`
            s += `ForegroundVisited=${fmt(Colors.tertiary)}\n`
            return s
        }

        ini += "[Colors:Window]\n" + windowColors() + "\n"
        ini += "[Colors:Window][Inactive]\n" + windowColors().replace(`BackgroundAlternate=${surface}\n`, `BackgroundAlternate=${surfaceContainer}\n`) + "\n"

        ini += "[General]\n"
        ini += "ColorScheme=NothingLess\n"
        ini += "Name=NothingLess\n"
        ini += "shadeSortColumn=true\n"
        ini += "\n"

        ini += "[Fonts]\n"
        ini += `general=${uiFont}\n`
        ini += `fixed=${monoFont}\n`
        ini += `menu=${uiFont}\n`
        ini += `toolbar=${uiFont}\n`
        ini += `smallestReadableFont=${smallFont}\n`
        ini += "\n"

        ini += "[KDE]\n"
        ini += "contrast=4\n"
        ini += "\n"

        ini += "[WM]\n"
        ini += `activeBackground=${bg}\n`
        ini += "activeBlend=252,252,252\n"
        ini += `activeForeground=${fg}\n`
        ini += `inactiveBackground=${fmt(Colors.surfaceDim)}\n`
        ini += "inactiveBlend=161,169,177\n"
        ini += `inactiveForeground=${inactive}\n`

        const home = Quickshell.env("HOME")
        const qt5Dir = home + "/.config/qt5ct/colors"
        const qt6Dir = home + "/.config/qt6ct/colors"

        writer.text = ini

        // Single command to ensure dirs and write files
        const cmd = `
            mkdir -p "${qt5Dir}" "${qt6Dir}" && \\
            echo "${ini}" | tee "${qt5Dir}/nothingless.colors" "${qt6Dir}/nothingless.colors" > /dev/null
        `

        writerProcess.command = ["sh", "-c", cmd]
        writerProcess.running = true
    }

    property QtObject writer: QtObject {
        id: writer
        property string text
    }

    property Process writerProcess: Process {
        id: writerProcess
        running: false
        stdout: StdioCollector {
            onStreamFinished: console.log("QtCtGenerator: Colors generated.")
        }
        stderr: StdioCollector {
            onStreamFinished: (err) => {
                if (err) console.error("QtCtGenerator Error:", err)
            }
        }
    }
Component.onDestruction: {
    writerProcess.stop ? writerProcess.stop() : undefined;
    writerProcess.running !== undefined ? writerProcess.running = false : undefined;
    writerProcess.destroy !== undefined ? writerProcess.destroy() : undefined;
}
}
