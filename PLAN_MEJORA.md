# Plan de Mejora — NothingLess

> Basado en análisis de:
> - [caelestia-dots/shell](https://github.com/caelestia-dots/shell) — Material 3 shell con ripple, animaciones, color dinámico
> - [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) — Material You, wallpaper-driven theming, AI integrado

---

## Fase 1: Nueva Apariencia — Nothing Phone × Material 3

### 1.1 Sistema de Color Dinámico (Material You / M3)
**Inspiración:** end-4/dots-hyprland + caelestia-dots/shell

- **Color Quantizer desde wallpaper**
  - Usar `ColorQuantizer` de Quickshell para extraer color dominante del wallpaper a baja resolución (rescaleSize: 10)
  - Generar paleta M3 completa: primary, secondary, tertiary, error, surface hierarchy (surface → surfaceContainerHighest), on-colors
  - Medir vibranza del wallpaper y ajustar transparencia dinámicamente
- **Tema Nothing Phone**
  - Monocromático (blanco, grises, rojo) como base
  - Opción de "dynamic" que tome colores del wallpaper
  - Presets de color: Nothing (current), Dynamic M3, Pure Monochrome, Dot Matrix
- **Modo claro/oscuro por sensor de ambiente** (wlsunset lookup)
- Esquemas por wallpaper que se regeneren en caliente sin reiniciar

### 1.2 Sistema de Superficies con Elevación M3
**Inspiración:** caelestia-dots/shell (StyledRect + StateLayer)

- **5 niveles de superficie** (Layer 0-4 según spec M3)
- Cada nivel con hover/active/disabled variants
- **StateLayer** en todos los interactive:
  - Ripple en QML nativo con `RadialGradient` + `Shape.PathArc` (como caelestia)
  - Animación de ripple que sigue el punto de click
  - Opacity state por hover/press/drag
- **Elevación por sombras**: sombras suaves con depth dinámico según nivel

### 1.3 Tipografía Nothing Phone
- Expandir uso de **Ndot** (dot-matrix font)
- Sistema de **Material Symbols Variable** (ttf-material-symbols-variable)
  - Reemplazar Phosphor Icons con Material Symbols
  - Usar ejes variables: FILL, GRAD, opsz, wght para animación de iconos
- **Jerarquía tipográfica M3**: headline, title, label, body con sizing system

### 1.4 Preset "Nothing M3"
- Nuevo preset basado en Nothing Phone (3a) + Material 3
- Paleta: Dot Matrix (blanco/rojo/gris) + variante Dynamic Color
- Config de animaciones M3 (emphasized, spatial, standard)
- Half-tone patterns como textura de fondo (ya existe en NothingLess)
- Opción "glyph interface" — barras con estilo Nothing Phone

---

## Fase 2: Rendimiento

### 2.1 Optimizaciones de Inicio
- **Deferred initialization**: servicios no críticos diferidos 2s (ya existe parcialmente)
- **Lazy loading** de widgets:
  - Dashboard tabs con carga bajo demanda (LRU)
  - Overview solo se carga al abrirse
  - Sidebar AI bajo demanda
- **Pooling de conexiones** en servicios IPC (evitar múltiples hyprctl calls)

### 2.2 Optimizaciones de Renderizado
- Usar `QSG_RENDER_LOOP=threaded` ya configurado — verificar
- `QS_DROP_EXPENSIVE_FONTS=1` para evitar fallback costoso
- **Precompilar shaders** GLSL → `.qsb` (ya existe, verificar que estén actualizados)
- Reemplazar opacidad/clip QML con shaders GLSL donde sea crítico
- **Debounce en reload de reglas**: timer 300ms para cambios de configuración

### 2.3 Optimizaciones de Memoria
- **Pool de objetos**: reutilizar delegates en lugar de crear/destruir
- **Garbage collection**: liberar ScreencopyViews cuando no se usan (overview cerrado)
- **Unified pass shader**: combinar múltiples efectos en un solo pass

### 2.4 Optimizaciones de Config
- **json5 / toml**: migrar de JSON a formato más rápido de parsear
- **ConfigValidator lazy**: solo validar al cambiar, no en startup
- **watchFiles: false** en release build (solo recargar manual)

---

## Fase 3: Animaciones

### 3.1 Sistema de Animación M3
**Inspiración:** caelestia-dots/shell (Anim.qml)

- Crear `Anim.qml` unificado con tipos M3:
  - **Standard** (small/normal/large/extraLarge) — UI transitions
  - **Emphasized** (small/normal/large) — feedback visual fuerte
  - **Spatial** (fast/default/slow) — cambios de layout/orientación
- Cada tipo con easing curves y duraciones configurables
- **Escalado global** de velocidad de animación (Config → anim.durations.scale)

### 3.2 Animaciones Específicas
- **Overview**: transiciones suaves de workspace, fade de previews, scale de ventanas
- **Notch/Dynamic Island**: expand/contract con easing emphasized
- **Bar**: auto-hide con fade + slide, icon fill transitions
- **Dashboard**: swipe open/close con física de inercia
- **Dock**: item hover scale, popup fade, app open animation
- **Transition de wallpaper**: crossfade entre wallpapers con shader

### 3.3 Micro-interacciones
- **Ripple en clicks** (como caelestia StateLayer)
- **Icon fill animation** en Material Symbols (eje FILL animado)
- **Corner radius morphing** en botones
- **Smooth color transitions** en todos los elementos interactivos

---

## Fase 4: Funcionalidades Nuevas

### 4.1 Del Sistema de Ia (end-4/dots-hyprland)
- Mejorar AI sidebar con múltiples providers (ya existe Ai.qml)
- **Gemini / Ollama / DeepSeek** switcher
- **Chat contexto**: mantener historial por sesión
- **Screen translation**: traducir texto en pantalla (translate-shell)
- **Music recognition**: SongRec / Shazam integration
- **Google Lens**: OCR de imágenes avanzado
- **Math calculation** en search bar (libqalculate)

### 4.2 Del Sistema (caelestia-dots/shell)
- **IPC CLI completo**: cada función del shell accesible por comando
- **Notification Center**: grouped notifications con history y per-app settings
- **Per-monitor configuration**: overrides de config por pantalla
- **Screen region picker** nativo en QML
- **Desktop widgets**: sticky notes, clock overlay, audio visualizer
- **Lyrics view**: letras sincronizadas en dashboard
- **Battery alert service**: notificaciones a threshold configurables

### 4.3 Mejoras al Overview
- **Drag-drop entre workspaces** (ya existe parcialmente)
- **Live preview** con ScreencopyView (ya existe)
- **Fuzzy search** de ventanas (ya existe)
- **Overview gestures**: swipe para cambiar workspace en scrolling mode
- **Workspace groups**: agrupar espacios de trabajo visualmente
- **Persistent layout**: recordor posición de ventanas arrastradas

### 4.4 Utilidades
- **Clipboard manager** con historial y preview (cliphist)
- **Color picker** nativo (ya existe hyprpicker wrapper)
- **Screen recorder** con selector de región
- **Quick settings**: toggle WiFi, Bluetooth, VPN desde dashboard
- **Battery profile switcher**: power-saver / balanced / performance

---

## Fase 5: Refactor y Limpieza

### 5.1 Código
- **Migrar de JSON a toml** para config (más rápido, más legible)
- **Unificar imports**: limpiar dependencias cruzadas entre módulos
- **Eliminar dead code** detectado por linting
- **Componentes compartidos**: mover patrones repetidos a `modules/components/`

### 5.2 Gestión de Estado
- **StateManager** unificado (reemplazar múltiples singletons)
- **Propiedades reactivas**: migrar de signals a Qt.bindings donde sea posible
- **Error boundaries** para evitar crashes por null references

### 5.3 Presets
- Limpiar presets existentes (algunos tienen archivos no usados)
- Agregar preset "Nothing M3"
- Agregar preset "Caelestia-inspired" (M3 suave)
- Agregar preset "Minimal" (máximo rendimiento, sin animaciones)

---

## Prioridades Recomendadas

```
Semana 1:   Fase 1.1 (Color dinámico) + Fase 2 (Rendimiento básico)
Semana 2:   Fase 1.2-1.3 (Superficies, tipografía) + Fase 3.1 (Anim system)
Semana 3:   Fase 1.4 (Preset Nothing M3) + Fase 3.2 (Animaciones específicas)
Semana 4:   Fase 4.1 (AI) + Fase 4.2 (caelestia features)
Semana 5:   Fase 4.3-4.4 (Overview, utilidades)
Semana 6:   Fase 5 (Refactor, limpieza, presets)
```

---

## Prompt para Asistente de Código

> **Contexto:** NothingLess es un shell para Hyprland en Quickshell/QML.
>
> **Objetivo:** Implementar una nueva apariencia Nothing Phone + Material 3, mejorar rendimiento, animaciones y funcionalidades.
>
> **Inspiración:**
> - [caelestia-dots/shell](https://github.com/caelestia-dots/shell) — Anim system M3, StateLayer con ripple, StyledRect con variantes, color dinámico por wallpaper
> - [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) — Material You palette generator, ColorQuantizer, 5-layer surface hierarchy, transparency por vibranza
>
> **Prioridades en orden:**
> 1. Sistema de color dinámico M3 desde wallpaper (ColorQuantizer de Quickshell, generar paleta primary/secondary/tertiary/error/surface hierarchy)
> 2. Sistema de superficies con 5 niveles de elevación + StateLayer con ripple
> 3. Migrar de Phosphor Icons a Material Symbols Variable con ejes animables (FILL, GRAD, opsz, wght)
> 4. Sistema de animaciones M3 (Anim.qml con tipos Standard/Emphasized/Spatial, easing configurable, escala global)
> 5. Nuevo preset "Nothing M3" con dot-matrix + colores dinámicos
> 6. Lazy loading y deferred init para mejorar startup
> 7. IPC CLI completo para todas las funciones del shell
> 8. Notification center con grouping, history, per-app settings
> 9. Per-monitor configuration overrides
> 10. Optimizaciones de renderizado: precompilar shaders, unified pass, debounce reloads
>
> **Archivos clave:**
> - `modules/theme/Colors.qml` — sistema de color actual (FileView → colors.json)
> - `modules/theme/Styling.qml` — radius, fontSize, getStyledRectConfig
> - `modules/components/StyledRect.qml` — componente base con themed container
> - `config/Config.qml` — config central con JsonAdapter
> - `config/defaults/*.js` — defaults para cada dominio
> - `modules/globals/GlobalStates.qml` — runtime state no persistente
> - `modules/services/Ai.qml` — AI service ya existente
> - `assets/presets/Nothing/` — preset Nothing actual
> - `shell.qml` — entry point con Variants por screen
>
> **NO romper:** no eliminar funcionalidades existentes. Cada optimización debe mantener compatibilidad.

---

*Generado el 2026-05-26 para el proyecto NothingLess*
