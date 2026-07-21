// HaxPlugin.qml — Base interface for QML plugins (N3)
// Todos los plugins QML deben heredar de este tipo.
// 
// Uso:
//   import qs.modules.widgets.spotlight.HaxPlugin
//   HaxPlugin { ... }
//
// O simplemente crear un QtObject con las mismas propiedades.

import QtQuick

QtObject {
    id: root

    // ── Identificación ──
    property string pluginId: ""               // ID único del plugin
    property string pluginName: "Plugin"       // Nombre visible
    property string pluginIcon: "🧩"           // Icono (emoji)
    property string pluginDescription: ""      // Descripción breve
    property var pluginKeywords: []            // Palabras clave que activan el plugin
    property bool pluginEnabled: true          // Si está activo

    // ── API de Hax (la asigna PluginManager al cargar) ──
    property var haxAPI: null

    // ── Ciclo de vida ──

    // Se llama al cargar el plugin. Recibe un objeto API para interactuar con Hax.
    function onLoad(api) {
        haxAPI = api;
    }

    // Se llama al descargar el plugin.
    function onUnload() {}

    // ── Búsqueda ──

    // Se llama cuando el usuario escribe en el buscador.
    // @param query string - texto actual de búsqueda
    // @returns array de objetos resultado:
    //   [{ name, description, icon, actionId, exec }]
    //   - exec puede ser una función (se ejecuta al pulsar Enter)
    //   - O actionId string (se llama a onExecute con ese ID)
    function onSearch(query) {
        return [];
    }

    // Se llama cuando el usuario selecciona un resultado con actionId.
    // @param actionId string - el ID devuelto en onSearch
    // @param context object - contexto adicional
    // @returns boolean - true si se manejó la acción
    function onExecute(actionId, context) {
        return false;
    }

    // ── Utilidades (usando haxAPI) ──

    function copyToClipboard(text) {
        if (haxAPI && haxAPI.copyToClipboard) haxAPI.copyToClipboard(text);
    }

    function runCommand(cmd) {
        if (haxAPI && haxAPI.runCommand) haxAPI.runCommand(cmd);
    }

    function showNotification(title, message) {
        if (haxAPI && haxAPI.showNotification) haxAPI.showNotification(title, message);
    }
}
