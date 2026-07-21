pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/*!
    Calculator.qml — Instant math calculator with zero external dependencies.

    Uses a recursive descent parser (ported from Hax SpotlightView)
    that evaluates expressions synchronously — no external process needed.

    Supports: + - * / ( ) and unary minus.
    Falls back to qalc for advanced operations (^ % units) when available.

    Usage:
        Calculator.evaluate("2 + 2")
        // result via onResultReady signal
*/
Singleton {
    id: root

    signal resultReady(string expression, string result)
    signal error(string expression, string error)

    property bool isAvailable: true
    readonly property bool qalcAvailable: _qalcInstalled

    property bool _qalcInstalled: false
    property string _pendingExpr: ""

    property Process _checkProcess: Process {
        command: ["sh", "-c", "command -v qalc"]
        running: true
        onExited: (code) => {
            root._qalcInstalled = code === 0;
        }
    }

    function evaluate(expression) {
        if (!expression || expression.trim() === "") return;

        // Use the instant parser for simple arithmetic
        var result = safeEval(expression);
        if (result !== null) {
            root.resultReady(expression, formatResult(result));
            return;
        }

        // Fall back to qalc for advanced expressions (^ % units etc.)
        if (root._qalcInstalled) {
            calcProcess.command = ["qalc", "-nocolor", "-t", expression];
            calcProcess.running = true;
            _pendingExpr = expression;
        } else {
            root.error(expression, "Cannot evaluate: " + expression);
        }
    }

    function formatResult(num) {
        if (Number.isInteger(num)) return num.toString();
        var s = num.toFixed(10);
        s = s.replace(/\.?0+$/, "");
        return s;
    }

    // ── Recursive descent calculator (from Hax) ──

    function safeEval(expr) {
        if (!/^[\d+\-*/().\s]+$/.test(expr)) return null;
        try {
            return calcParens(expr.replace(/\s/g, ""));
        } catch (e) { return null; }
    }

    function calcSimple(e) {
        if (e.length === 0) return null;
        var idx;
        idx = e.indexOf("*");
        if (idx > 0) {
            var l = calcSimple(e.substring(0, idx));
            var r = calcSimple(e.substring(idx + 1));
            if (l === null || r === null) return null;
            return l * r;
        }
        idx = e.indexOf("/");
        if (idx > 0) {
            l = calcSimple(e.substring(0, idx));
            r = calcSimple(e.substring(idx + 1));
            if (l === null || r === null || r === 0) return null;
            return l / r;
        }
        idx = e.indexOf("+");
        if (idx > 0) {
            l = calcSimple(e.substring(0, idx));
            r = calcSimple(e.substring(idx + 1));
            if (l === null || r === null) return null;
            return l + r;
        }
        if (e.charAt(0) === "-") {
            var rest = calcSimple(e.substring(1));
            return rest === null ? null : -rest;
        }
        idx = e.lastIndexOf("-");
        if (idx > 0) {
            l = calcSimple(e.substring(0, idx));
            r = calcSimple(e.substring(idx + 1));
            if (l === null || r === null) return null;
            return l - r;
        }
        var num = parseFloat(e);
        return isNaN(num) ? null : num;
    }

    function calcParens(e) {
        var start = e.indexOf("(");
        while (start !== -1) {
            var depth = 1;
            var end = start + 1;
            while (end < e.length && depth > 0) {
                if (e.charAt(end) === "(") depth++;
                else if (e.charAt(end) === ")") depth--;
                end++;
            }
            if (depth !== 0) return null;
            var inner = calcParens(e.substring(start + 1, end - 1));
            if (inner === null) return null;
            e = e.substring(0, start) + inner + e.substring(end);
            start = e.indexOf("(");
        }
        return calcSimple(e);
    }

    // ── qalc fallback (advanced expressions) ──

    property Process calcProcess: Process {
        running: false
        stdout: SplitParser {
            onRead: (data) => {
                if (data) {
                    const result = data.trim().replace(/\n/g, " → ");
                    if (result && result !== root._pendingExpr) {
                        root.resultReady(root._pendingExpr, result);
                    }
                }
            }
        }
    }
}
