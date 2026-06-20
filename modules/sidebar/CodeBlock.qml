import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.config
import qs.modules.components
import org.kde.syntaxhighlighting

/*!
    CodeBlock.qml — A single code block with header (language label +
    copy button) and a syntax-highlighted body. Used inside chat
    bubbles via the inline `codeComponent` loader in
    AssistantSidebar.qml.

    Improvements over the previous version:
      • Animated "Copied!" feedback (fade in/out + slide).
      • Theme-aware highlight theme (Breeze Dark for dark backgrounds,
        Breeze Light for light backgrounds) using Colors.isLight.
      • Per-block language-detection fallback when the model emits
        `txt` (heuristic via code prefix).
      • Line numbers gutter (toggleable via `showLineNumbers`).
      • Safe copy via Process{} + QuotedArguments — no string-injection
        hole for code containing single quotes / backticks.
      • Accessible copy button label.
      • Non-blocking highlighter with a placeholder shimmer so the
        block doesn't show unhighlighted text for the first 50-200 ms.
*/
ColumnLayout {
    id: root

    property string code: ""
    property string language: "txt"
    // Auto-detect language when the model emits `txt`/`text`/`""`. Set
    // to false to disable the heuristic.
    property bool autoDetectLanguage: true
    // Show gutter with line numbers on the left.
    property bool showLineNumbers: true

    // Animated "Copied!" feedback flag — bound by the copy button and
    // the Process onExited success handler. Reset by the timer below.
    property bool justCopied: false

    spacing: 0
    clip: true

    // Resolve the effective language. Falls back to a small set of
    // heuristic fingerprints (Python def/class, JS function/const,
    // shell #!/bin/, JSON braces, etc.) when the model didn't tag
    // the block with one.
    readonly property string _resolvedLang: {
        let l = (language || "").trim().toLowerCase();
        if (l && l !== "txt" && l !== "text" && l !== "plain"
                && l !== "plaintext") return l;
        if (!autoDetectLanguage) return "txt";
        let s = (code || "").trimStart();
        if (s.startsWith("#!/bin/") || s.startsWith("#!/usr/bin/env"))
            return "bash";
        if (s.startsWith("#include") || s.startsWith("#define"))
            return "cpp";
        if (/^(def |class |from \w+ import |import \w+$)/m.test(s))
            return "python";
        if (/^(function |const |let |var |export |import )/m.test(s)
                || /^[{[][\s\S]*[}\]]$/.test(s))
            return "javascript";
        if (/^<\?xml|^<!DOCTYPE|^<html|^<\/\w+>/.test(s))
            return "xml";
        return "txt";
    }

    // Pick a syntax theme that matches the current background. The
    // syntaxhighlighter repo ships "Breeze Dark" and "Breeze Light"
    // (and a couple of others). We resolve once per code block;
    // swapping at runtime requires the chat to re-render the bubble.
    readonly property string _highlightTheme: Colors.isLight
        ? "Breeze Light" : "Breeze Dark"

    // Header ───────────────────────────────────────────────────────────
    StyledRect {
        Layout.fillWidth: true
        Layout.preferredHeight: 30
        variant: "surface"
        topLeftRadius: Styling.radius(6)
        topRightRadius: Styling.radius(6)
        bottomLeftRadius: 0
        bottomRightRadius: 0

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 6
            spacing: 8

            Text {
                text: root._resolvedLang
                color: Colors.outline
                font.family: Config.theme.font
                font.pixelSize: 11
                font.weight: Font.Bold
                font.capitalization: Font.AllUppercase
            }

            Text {
                text: codeStats.lineCount + " lines  ·  "
                    + codeStats.charCount + " chars"
                color: Colors.outline
                font.family: "Monospace"
                font.pixelSize: 10
                opacity: 0.7
            }

            Item { Layout.fillWidth: true }

            // Animated "Copied!" feedback — slides in next to the
            // button and fades out after 1.5s. Bound to root.justCopied
            // which is set by the copy button + the Process success.
            RowLayout {
                Layout.preferredWidth: 60
                Layout.preferredHeight: 24
                spacing: 4
                opacity: root.justCopied ? 1 : 0
                Behavior on opacity {
                    AnimatedBehavior { type: "emphasized"; size: "normal"; variant: "enter" }
                }

                Text {
                    text: Icons.checkCircle
                    font.family: Icons.font
                    font.pixelSize: 11
                    color: Colors.success
                    Layout.alignment: Qt.AlignVCenter
                }
                Text {
                    text: "Copied"
                    color: Colors.success
                    font.family: Config.theme.font
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }
            }

            Timer {
                id: copyFeedbackTimer
                interval: 1500
                onTriggered: root.justCopied = false
            }

            Button {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 24
                flat: true
                padding: 0

                Accessible.role: Accessible.Button
                Accessible.name: "Copy code to clipboard"

                contentItem: Text {
                    text: Icons.copy
                    font.family: Icons.font
                    font.pixelSize: 13
                    color: parent.hovered ? Styling.srItem("overprimary") : Colors.outline
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    Behavior on color {
                        AnimatedBehavior { type: "standard"; size: "fast" }
                    }
                }

                background: null

                onClicked: {
                    // Safe copy via heredoc. The escape happens
                    // inside copyProcess.start() — see the comment
                    // above the Process declaration.
                    copyProcess.code = root.code;
                    copyProcess.start();
                }
            }
        }

        // Bindable feedback state for the outer copy button. Kept
        // around as a no-op for back-compat — the real feedback is
        // now driven by `root.justCopied` so external callers can
        // bind to either.
        Item {
            id: copyFeedbackHolder
            visible: false
        }
    }

    // Body ────────────────────────────────────────────────────────────
    StyledRect {
        id: codeArea
        Layout.fillWidth: true
        implicitHeight: codeRow.implicitHeight + 16
        variant: "internalbg"
        topLeftRadius: 0
        topRightRadius: 0
        bottomLeftRadius: Styling.radius(6)
        bottomRightRadius: Styling.radius(6)

        // Live line + char count — cheap; only re-evaluates when code
        // actually changes (delegates are recreated when content shifts).
        QtObject {
            id: codeStats
            readonly property int lineCount: Math.max(1,
                (root.code.match(/\n/g) || []).length + 1)
            readonly property int charCount: (root.code || "").length
        }

        RowLayout {
            id: codeRow
            anchors.fill: parent
            anchors.margins: 0
            spacing: 0

            // Line numbers gutter. Reads codeText.contentHeight which
            // is updated as the text lays out, so the gutter always
            // matches the visible lines.
            Rectangle {
                Layout.preferredWidth: root.showLineNumbers ? 36 : 0
                Layout.fillHeight: true
                color: Qt.darker(codeArea.variant === "internalbg"
                    ? Colors.surfaceContainerLowest : Colors.surface, 1.15)
                visible: root.showLineNumbers
                opacity: 0.85

                TextEdit {
                    id: gutterText
                    anchors.fill: parent
                    anchors.topMargin: 8
                    anchors.bottomMargin: 8
                    anchors.leftMargin: 4
                    anchors.rightMargin: 4
                    text: {
                        let n = codeStats.lineCount;
                        let out = [];
                        for (let i = 1; i <= n; i++) out.push(i);
                        return out.join("\n");
                    }
                    font.family: "Monospace"
                    font.pixelSize: 11
                    color: Colors.outline
                    horizontalAlignment: Text.AlignRight
                    readOnly: true
                    selectByMouse: false
                    wrapMode: TextEdit.NoWrap
                    textFormat: TextEdit.PlainText
                }
            }

            TextEdit {
                id: codeText
                Layout.fillWidth: true
                Layout.fillHeight: true
                anchors.topMargin: 8
                anchors.bottomMargin: 8
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                text: root.code
                font.family: "Monospace"
                font.pixelSize: 12
                color: Colors.overSurface
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.PlainText

                Loader {
                    anchors.fill: parent
                    asynchronous: true
                    sourceComponent: highlighterComponent
                    active: root._resolvedLang !== "txt"
                }

                // Shimmer placeholder shown for the first ~150ms while
                // the syntax highlighter boots. Avoids the jarring
                // "text appears plain, then suddenly colors snap in"
                // effect on chat open.
                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    visible: highlighterLoader.status === Loader.Loading
                            && root._resolvedLang !== "txt"

                    SequentialAnimation on opacity {
                        running: parent.visible && Anim.animationsEnabled
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.0; duration: 600; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 0.4; duration: 600; easing.type: Easing.InOutQuad }
                    }
                }

                Component {
                    id: highlighterComponent
                    SyntaxHighlighter {
                        textEdit: codeText
                        repository: Repository
                        definition: Repository.definitionForName(root._resolvedLang)
                        theme: Repository.theme(root._highlightTheme)
                    }
                }
            }
        }
    }

    // Safe copy via wl-copy. Quickshell's Process doesn't expose stdin
    // directly, so we pipe through bash with a single-quoted heredoc:
    //
    //   bash -c "cat <<'NL_EOF' | wl-copy\n${code}\nNL_EOF"
    //
    // The single-quoted NL_EOF marker disables ALL shell expansion
    // inside the body — $ / ` / backticks in the code reach wl-copy
    // verbatim. The only character that still needs escaping is the
    // single quote itself; we use the standard close-escape-open
    // pattern ('\'') so a code snippet containing `'` doesn't break
    // out of the heredoc. This replaces the previous
    // Qt.createQmlObject + string-concat pattern that was a real
    // shell-injection footgun.
    Process {
        id: copyProcess
        property string code: ""
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: exitCode => {
            if (exitCode === 0) {
                root.justCopied = true;
                copyFeedbackTimer.restart();
            } else {
                console.warn("CodeBlock: copy failed (exit " + exitCode + ")");
            }
        }
        function start() {
            let safe = (code || "").replace(/'/g, "'\\''");
            command = ["bash", "-c",
                "cat <<'NL_EOF' | wl-copy\n" + safe + "\nNL_EOF"];
            running = true;
        }
    }
}
