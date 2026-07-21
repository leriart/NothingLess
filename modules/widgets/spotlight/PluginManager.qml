// PluginManager.qml — Sistema de plugins para Hax
// Soporta:
//   N2 - Script plugins (.sh, .py, .js, etc.)
//   N3 - QML plugins (.qml)
//
// Los plugins se guardan en ~/.config/hax/plugins/
//
// Protocolo para script plugins:
//   ./plugin.sh --hax-info    → JSON con {name, icon, keywords[], description}
//   ./plugin.sh "query"       → JSON Lines con resultados
//   ./plugin.sh --hax-exec ID → ejecuta una accion

import QtQuick
import Quickshell
import Quickshell.Io
import QtQml

QtObject {
    id: root

    // ── Propiedades ──
    property var plugins: []              // Array de plugins cargados
    property var pluginMap: ({})          // id → plugin
    property string pluginsDir: Quickshell.env("HOME") + "/.config/hax/plugins"
    property var haxAPI: null             // API reference for QML plugins
    property var scriptCache: ({})        // Cache de resultados (id -> [{...}])

    // ── Señales ──
    signal pluginListChanged()            // Se dispara cuando cambia la lista de plugins
    signal pluginResultsUpdated(string pluginId, var results)  // Script plugin results ready
    signal pluginActionMessage(string pluginId, string title, string message)  // Mensaje de ejecución

    // ── Inicialización ──
    function initialize(api) {
        haxAPI = api;
        discover();
    }

    // ── Descubrimiento de plugins ──
    function discover() {
        // Escanea el directorio de plugins
        var pr = Qt.createQmlObject('import Quickshell.Io; Process { stdout: StdioCollector {} }', root);
        pr.command = ["bash", "-c",
            'if [ -d "' + pluginsDir + '" ]; then ' +
            '  for f in "' + pluginsDir + '"/*; do ' +
            '    [ -f "$f" ] && echo "file:$f"; ' +
            '    [ -d "$f" ] && [ -f "$f/manifest.json" ] && echo "dir:$f"; ' +
            '  done; ' +
            'else ' +
            '  mkdir -p "' + pluginsDir + '"; ' +
            'fi'];
        pr.onExited.connect(function() {
            var output = pr.stdout ? pr.stdout.text.trim() : "";
            if (output.length > 0) {
                var lines = output.split('\n');
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i].trim();
                    if (line.length === 0) continue;
                    var type = line.substring(0, 5);
                    var path = line.substring(5);
                    if (type === "file:") {
                        registerFilePlugin(path);
                    } else if (type === "dir:") {
                        registerDirPlugin(path);
                    }
                }
            }
            pluginListChanged();
            try { pr.destroy(); } catch(e) {}
            // Si no hay ningún plugin, copiar el de ejemplo para demostrar el sistema
            if (plugins.length === 0) {
                createDefaultPlugins();
            }
            // Cargar estado guardado después de que los plugins terminen de cargarse
            _delay(function() {
                loadPluginState();
            }, 500);
        });
        pr.running = true;
    }

    function registerFilePlugin(filePath) {
        var name = filePath.split('/').pop();
        if (name.startsWith('.')) return;
        if (name === "manifest.json") return;
        if (name === "plugin-state.json") return;
        if (pluginMap[filePath]) return;

        var ext = name.includes('.') ? name.split('.').pop().toLowerCase() : "";
        var baseName = name.includes('.') ? name.substring(0, name.lastIndexOf('.')) : name;

        var plugin = {
            type: ext === "qml" ? "qml" : "script",
            path: filePath,
            
            id: ext === "qml" ? baseName : "script_" + baseName,
            name: baseName,
            icon: "🧩",
            keywords: [],
            description: "Plugin: " + baseName,
            enabled: true,
            instance: null,       // QML plugin instance
            component: null,      // QML component reference
            results: [],          // Current results cache
            lastQuery: "",
            error: null,
            loaded: false
        };

        pluginMap[filePath] = plugin;
        // Reassign to trigger QML change detection (push doesn't work with var)
        plugins = plugins.concat([plugin]);

        if (ext === "qml") {
            loadQMLPlugin(plugin);
        } else {
            // Script plugin — fetch metadata
            fetchScriptInfo(plugin);
        }
    }

    function registerDirPlugin(dirPath) {
        // Plugin with manifest.json
        // For now, scan the directory for executable files
        var pr = Qt.createQmlObject('import Quickshell.Io; Process { stdout: StdioCollector {} }', root);
        pr.command = ["bash", "-c",
            'for f in "' + dirPath + '"/*; do ' +
            '  if [ -f "$f" ] && [ -x "$f" ]; then echo "$f"; ' +
            '  elif [ -f "$f" ] && echo "$f" | grep -qE "\\.(sh|py|js|pl|lua)$"; then echo "$f"; ' +
            '  fi; ' +
            'done'];
        pr.onExited.connect(function() {
            var output = pr.stdout ? pr.stdout.text.trim() : "";
            if (output.length > 0) {
                var lines = output.split('\n');
                for (var i = 0; i < lines.length; i++) {
                    registerFilePlugin(lines[i].trim());
                }
            }
            try { pr.destroy(); } catch(e) {}
        });
        pr.running = true;
    }

    // ── Script Plugin: fetch metadata ──
    function fetchScriptInfo(plugin) {
        var pr = Qt.createQmlObject(
            'import Quickshell.Io; Process { stdout: StdioCollector {} }', root);
        pr.pluginId = plugin.id;
        pr.command = [plugin.path, "--hax-info"];
        pr.onExited.connect(function() {
            var output = pr.stdout ? pr.stdout.text.trim() : "";
            if (output.length > 0) {
                try {
                    var info = JSON.parse(output);
                    if (info.name) plugin.name = info.name;
                    if (info.icon) plugin.icon = info.icon;
                    if (info.keywords) plugin.keywords = info.keywords;
                    if (info.description) plugin.description = info.description;
                } catch(e) {
                    plugin.error = "Invalid manifest JSON";
                }
            }
            plugin.loaded = true;
            pluginListChanged();
            try { pr.destroy(); } catch(e) {}
            // Precargar el catálogo completo del script (se ejecuta UNA VEZ)
            fetchScriptCatalog(plugin);
        });
        pr.running = true;
    }

    // ── Script Plugin: precargar catálogo completo ──
    function fetchScriptCatalog(plugin) {
        var pr = Qt.createQmlObject(
            'import Quickshell.Io; Process { stdout: StdioCollector {} }', root);
        pr.pluginId = plugin.id;
        pr.command = [plugin.path, ""];  // query vacío → el script devuelve su catálogo
        pr.onExited.connect(function() {
            var output = pr.stdout ? pr.stdout.text.trim() : "";
            var results = [];
            if (output.length > 0) {
                var lines = output.split('\n');
                for (var li = 0; li < lines.length; li++) {
                    var line = lines[li].trim();
                    if (line.length > 0 && line.startsWith('{')) {
                        try {
                            results.push(JSON.parse(line));
                        } catch(e) {}
                    }
                }
            }
            // Guardar catálogo completo
            plugin.results = results;
            plugin.lastQuery = "";
            pluginResultsUpdated(plugin.id, results);
            try { pr.destroy(); } catch(e) {}
        });
        pr.running = true;
    }

    // ── Helper: find plugin by id ──
    function findPlugin(id) {
        for (var i = 0; i < plugins.length; i++) {
            if (plugins[i].id === id) return plugins[i];
        }
        return null;
    }

    // ── QML Plugin: dynamic loading ──
    function loadQMLPlugin(plugin) {
        var fileUrl = Qt.resolvedUrl(plugin.path);
        if (!fileUrl || fileUrl === "") {
            fileUrl = "file://" + plugin.path;
        }

        var component = Qt.createComponent(fileUrl);
        if (component === null) {
            plugin.error = "Failed to create component (null)";
            plugin.loaded = true;
            pluginListChanged();
            return;
        }

        if (component.status === Component.Error) {
            plugin.error = component.errorString();
            plugin.loaded = true;
            pluginListChanged();
            return;
        }

        if (component.status === Component.Ready) {
            finishLoadQML(plugin, component);
        } else {
            component.statusChanged.connect(function() {
                if (component.status === Component.Ready) {
                    finishLoadQML(plugin, component);
                } else if (component.status === Component.Error) {
                    plugin.error = component.errorString();
                    plugin.loaded = true;
                    pluginListChanged();
                }
            });
        }
    }

    function finishLoadQML(plugin, component) {
        var obj = component.createObject(root, {});
        if (obj === null) {
            plugin.error = "Failed to create QML plugin object";
            plugin.loaded = true;
            pluginListChanged();
            return;
        }

        plugin.instance = obj;
        plugin.component = component;

        // Copy metadata from plugin instance
        if (obj.pluginId) plugin.id = obj.pluginId;
        if (obj.pluginName) plugin.name = obj.pluginName;
        if (obj.pluginIcon) plugin.icon = obj.pluginIcon;
        if (obj.pluginKeywords) plugin.keywords = obj.pluginKeywords;
        if (obj.pluginDescription) plugin.description = obj.pluginDescription;
        if (obj.pluginEnabled !== undefined) plugin.enabled = obj.pluginEnabled;

        // Call onLoad with API
        if (typeof obj.onLoad === "function") {
            obj.onLoad(haxAPI);
        }

        plugin.loaded = true;
        pluginListChanged();
    }

    // ── Búsqueda en todos los plugins ──
    function queryAll(query) {
        var allResults = [];
        var queryLower = (query || "").toLowerCase().trim();

        if (queryLower.length === 0) return allResults;

        var debugInfo = "🔍 qAll: q=" + query + " nPlugins=" + plugins.length;
        for (var i = 0; i < plugins.length; i++) {
            var p = plugins[i];
            debugInfo += " | p" + i + "=" + p.id + " en=" + p.enabled + " ld=" + p.loaded + " inst=" + (p.instance ? "yes" : "no") + " res=" + (p.results ? p.results.length : "0");
            if (!p.enabled || !p.loaded) continue;

            try {
                var results = [];

                if (p.type === "qml" && p.instance) {
                    if (typeof p.instance.onSearch === "function") {
                        results = p.instance.onSearch(queryLower) || [];
                    }
                } else if (p.type === "script") {
                    if (p.results && p.results.length > 0) {
                        var keywordMatch = false;
                        for (var ki = 0; ki < p.keywords.length; ki++) {
                            if (queryLower.indexOf(p.keywords[ki].toLowerCase()) >= 0
                                || p.keywords[ki].toLowerCase().indexOf(queryLower) >= 0) {
                                keywordMatch = true;
                                break;
                            }
                        }
                        if (!keywordMatch && p.name && queryLower.indexOf(p.name.toLowerCase()) >= 0) {
                            keywordMatch = true;
                        }

                        for (var ri = 0; ri < p.results.length; ri++) {
                            var r = p.results[ri];
                            var rName = (r.name || "").toLowerCase();
                            var rDesc = (r.description || "").toLowerCase();
                            var rAction = (r.actionId || "").toLowerCase();

                            if (keywordMatch) {
                                results.push(r);
                            } else {
                                if (rName.indexOf(queryLower) >= 0
                                    || rDesc.indexOf(queryLower) >= 0
                                    || rAction.indexOf(queryLower) >= 0) {
                                    results.push(r);
                                }
                            }
                        }
                    }
                }

                for (var ri = 0; ri < results.length; ri++) {
                    results[ri]._pluginId = p.id;
                    results[ri]._pluginName = p.name;
                    results[ri]._pluginIcon = p.icon;
                    results[ri].type = results[ri].type || "plugin";
                }

                if (results.length > 0) {
                    allResults = allResults.concat(results);
                }
            } catch(e) {
                console.log("Plugin error [" + (p ? p.id : '?') + "]:", e);
                if (p) p.error = String(e);
            }
        }

        return allResults;
    }

    // ── Ejecutar acción de plugin ──
    function executeAction(pluginId, actionId, context) {
        for (var i = 0; i < plugins.length; i++) {
            if (plugins[i].id === pluginId) {
                var p = plugins[i];

                // QML plugin
                if (p.type === "qml" && p.instance && typeof p.instance.onExecute === "function") {
                    return p.instance.onExecute(actionId, context);
                }

                // Script plugin: execute with --hax-exec [actionId] [actionData]
                if (p.type === "script") {
                    var pr = Qt.createQmlObject(
                        'import Quickshell.Io; Process { stdout: StdioCollector {} }', root);
                    var cmdArgs = [p.path, "--hax-exec", actionId];
                    // Pasar actionData si existe (ej: query de búsqueda)
                    if (context && typeof context === "object" && context.data) {
                        cmdArgs.push(String(context.data));
                    } else if (typeof context === "string") {
                        cmdArgs.push(context);
                    }
                    pr.command = cmdArgs;
                    pr.onExited.connect(function() {
                        var output = pr.stdout ? pr.stdout.text.trim() : "";
                        if (output.length > 0) {
                            // Emitir mensaje para que Hax lo muestre inline
                            root.pluginActionMessage(p.id, p.name, output);
                        }
                        try { pr.destroy(); } catch(e) {}
                    });
                    pr.running = true;
                    return true;
                }

                break;
            }
        }
        return false;
    }

    // ── Gestión de plugins (enable/disable/reload) ──
    function setPluginEnabled(pluginId, enabled) {
        var arr = plugins.slice();
        for (var i = 0; i < arr.length; i++) {
            if (arr[i].id === pluginId) {
                arr[i].enabled = enabled;  // Mutar in-place (referencia original intacta)
                plugins = arr;  // Reassign para QML change detection
                pluginListChanged();
                savePluginState();  // Persistir el cambio
                return true;
            }
        }
        return false;
    }

    // ── Persistencia: guardar estado enable/disable ──
    function savePluginState() {
        var state = {};
        for (var i = 0; i < plugins.length; i++) {
            state[plugins[i].id] = { enabled: plugins[i].enabled };
        }
        var json = JSON.stringify(state);
        // Escribir a ~/.config/hax/plugins/plugin-state.json
        var pr = Qt.createQmlObject('import Quickshell.Io; Process { }', root);
        pr.command = ["bash", "-c",
            'mkdir -p "' + pluginsDir + '" && cat > "' + pluginsDir + '/plugin-state.json" << \'EOF\'\n' +
            json + '\nEOF'];
        pr.onExited.connect(function() { try { pr.destroy(); } catch(e) {} });
        pr.running = true;
    }

    // ── Persistencia: cargar estado enable/disable ──
    function loadPluginState(callback) {
        var pr = Qt.createQmlObject('import Quickshell.Io; Process { stdout: StdioCollector {} }', root);
        pr.command = ["bash", "-c",
            'if [ -f "' + pluginsDir + '/plugin-state.json" ]; then cat "' + pluginsDir + '/plugin-state.json"; fi'];
        pr.onExited.connect(function() {
            var output = pr.stdout ? pr.stdout.text.trim() : "";
            if (output.length > 0) {
                try {
                    var state = JSON.parse(output);
                    // Aplicar estado a los plugins YA CARGADOS (no crear copias)
                    for (var i = 0; i < plugins.length; i++) {
                        var pid = plugins[i].id;
                        if (state[pid] !== undefined && state[pid].enabled !== undefined) {
                            plugins[i].enabled = state[pid].enabled;
                        }
                    }
                    pluginListChanged();
                } catch(e) {
                    console.log("loadPluginState: error parsing state:", e);
                }
            }
            if (typeof callback === "function") callback();
            try { pr.destroy(); } catch(e) {}
        });
        pr.running = true;
    }

    function reloadPlugin(pluginId) {
        for (var i = 0; i < plugins.length; i++) {
            if (plugins[i].id === pluginId) {
                var p = plugins[i];
                if (p.type === "qml" && p.component) {
                    p.enabled = false;
                    if (p.instance) {
                        if (typeof p.instance.onUnload === "function") p.instance.onUnload();
                        p.instance.destroy();
                    }
                    p.component.destroy();
                    p.instance = null;
                    p.component = null;
                    p.loaded = false;
                    _delay(function() {
                        loadQMLPlugin(p);
                    }, 100);
                }
                return true;
            }
        }
        return false;
    }

    function reloadAll() {
        // Unload all QML plugins
        for (var i = 0; i < plugins.length; i++) {
            var p = plugins[i];
            if (p.type === "qml") {
                if (p.instance) {
                    if (typeof p.instance.onUnload === "function") p.instance.onUnload();
                    p.instance.destroy();
                }
                if (p.component) p.component.destroy();
                p.instance = null;
                p.component = null;
                p.loaded = false;
            }
            p.results = [];
            p.lastQuery = "";
        }

        // Re-discover
        plugins = [];
        pluginMap = {};
        pluginListChanged();
        _delay(function() { discover(); }, 200);
    }

    // ── Utilidad para crear plugins por defecto ──
    function createDefaultPlugins() {
        var pluginsDir2 = pluginsDir;  // capturar para closures
        var srcDir = Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "");  // carpeta del propio módulo Hax
        var defaultPlugins = [
            { src: srcDir + "/plugin-ejemplo.sh", dest: pluginsDir2 + "/ejemplo.sh" }
        ];

        function copyNext(idx) {
            if (idx >= defaultPlugins.length) {
                // Re-descubrir para que aparezcan inmediatamente
                _delay(function() { discover(); }, 300);
                return;
            }
            var pl = defaultPlugins[idx];
            var pr = Qt.createQmlObject('import Quickshell.Io; Process { }', root);
            pr.command = ["cp", pl.src, pl.dest];
            pr.onExited.connect(function() {
                // Make executable
                var pr2 = Qt.createQmlObject('import Quickshell.Io; Process { }', root);
                pr2.command = ["chmod", "+x", pl.dest];
                pr2.onExited.connect(function() {
                    try { pr2.destroy(); } catch(e) {}
                    copyNext(idx + 1);
                });
                pr2.running = true;
                try { pr.destroy(); } catch(e) {}
            });
            pr.running = true;
        }

        copyNext(0);
    }

    // ── Hot-reload: vigilar cambios en el directorio de plugins ──
    property var _knownFiles: ({})
    property var _hotReloadTimer: (function() {
        var t = Qt.createQmlObject('import QtQuick; Timer { interval: 5000; repeat: true; running: true; }', root);
        t.triggered.connect(function() { scanForChanges(); });
        return t;
    })()

    function scanForChanges() {
        var pr = Qt.createQmlObject('import Quickshell.Io; Process { stdout: StdioCollector {} }', root);
        pr.command = ["bash", "-c",
            'if [ -d "' + pluginsDir + '" ]; then ' +
            '  ls -1 -a "' + pluginsDir + '" 2>/dev/null; ' +
            'fi'];
        pr.onExited.connect(function() {
            var output = pr.stdout ? pr.stdout.text.trim() : "";
            var currentFiles = {};
            if (output.length > 0) {
                var lines = output.split('\n');
                for (var i = 0; i < lines.length; i++) {
                    var f = lines[i].trim();
                    if (f.length === 0 || f === "." || f === ".." || f === "plugin-state.json") continue;
                    if (f.startsWith('.')) continue;
                    currentFiles[f] = true;
                    var fullPath = pluginsDir + "/" + f;
                    if (!_knownFiles[f]) {
                        // Archivo nuevo — registrar plugin
                        _knownFiles[f] = true;
                        if (!pluginMap[fullPath]) {
                            registerFilePlugin(fullPath);
                        }
                    }
                }
            }
            // Detectar archivos eliminados
            for (var old in _knownFiles) {
                if (!currentFiles[old]) {
                    delete _knownFiles[old];
                    var oldPath = pluginsDir + "/" + old;
                    if (pluginMap[oldPath]) {
                        removePlugin(oldPath);
                    }
                }
            }
            try { pr.destroy(); } catch(e) {}
        });
        pr.running = true;
    }

    // ── Eliminar plugin ──
    function removePlugin(filePath) {
        if (!pluginMap[filePath]) return;
        var p = pluginMap[filePath];
        if (p.type === "qml" && p.instance) {
            if (typeof p.instance.onUnload === "function") p.instance.onUnload();
            try { p.instance.destroy(); } catch(e) {}
        }
        if (p.component) try { p.component.destroy(); } catch(e) {}
        delete pluginMap[filePath];
        plugins = plugins.filter(function(pl) { return pl.id !== p.id; });
        pluginListChanged();
    }

    // ── Helper: delay usando Timer ──
    function _delay(callback, ms) {
        var timer = Qt.createQmlObject('import QtQuick; Timer { repeat: false }', root);
        timer.interval = ms;
        timer.triggered.connect(function() {
            try {
                callback();
            } catch(e) {
                console.log("_delay error:", e);
            }
            try { timer.destroy(); } catch(e) {}
        });
        timer.start();
    }
}
