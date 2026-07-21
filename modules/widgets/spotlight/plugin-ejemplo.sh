#!/bin/bash
# Plugin de ejemplo para Hax
# Protocolo:
#   --hax-info    → info del plugin (JSON)
#   "query"       → resultados de búsqueda (JSON Lines)
#   --hax-exec ID → ejecuta una acción (devuelve texto por stdout)

if [ "$1" = "--hax-info" ]; then
  echo '{"name":"Ejemplo","icon":"🌟","keywords":["ejemplo","test","demo"],"description":"Plugin de ejemplo para probar el sistema de plugins de Hax"}'
  exit 0
fi

if [ "$1" = "--hax-exec" ]; then
  ACTION="$2"
  case "$ACTION" in
    info)
      echo "🌟 Plugin de ejemplo funcionando correctamente"
      ;;
    saludar)
      echo "👋 ¡Hola desde Hax! ¿Cómo estás?"
      ;;
    hora)
      echo "🕐 Hora actual: $(date '+%H:%M:%S')"
      ;;
    firefox)
      if [ -n "$3" ]; then
        firefox "https://www.google.com/search?q=$3" 2>/dev/null &
        echo "🔍 Buscando \"$3\" en Firefox..."
      else
        echo "❌ No hay texto de búsqueda"
      fi
      ;;
    *)
      echo "🧩 Acción ejecutada: $ACTION"
      ;;
  esac
  exit 0
fi

# Catálogo completo de resultados (el filtro lo hace QML en memoria)
QUERY="$1"

# Siempre devolvemos todos los resultados posibles; QML filtra por keyword/name
echo "{\"name\":\"¿Qué es esto?\",\"description\":\"Plugin de Hax funcionando\",\"actionId\":\"info\",\"icon\":\"🌟\"}"
echo "{\"name\":\"Saludar\",\"description\":\"Muestra un saludo desde el plugin\",\"actionId\":\"saludar\",\"icon\":\"👋\"}"
echo "{\"name\":\"Decir hora\",\"description\":\"Muestra la hora actual: $(date '+%H:%M')\",\"actionId\":\"hora\",\"icon\":\"🕐\"}"
echo "{\"name\":\"Buscar en Google\",\"description\":\"Abre Firefox con el texto buscado\",\"actionId\":\"firefox\",\"actionData\":\"$QUERY\",\"icon\":\"🔍\"}"
