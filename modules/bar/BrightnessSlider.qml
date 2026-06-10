import QtQuick
import qs.modules.services
import qs.modules.components
import qs.modules.theme
import qs.config

BarSliderBase {
    id: root
    bar: bar
    icon: Icons.sun
    iconRotation: (slider.value / 1.0) * 180
    iconScale: 0.8 + (slider.value / 1.0) * 0.2
    progressColor: Styling.srItem("overprimary")
    iconPos: vertical ? "end" : "start"
    scroll: isExpanded
    iconClickable: isExpanded

    property var currentMonitor: Brightness.getMonitorForScreen(bar.screen)

    onValueChangedCallback: function(value) {
        if (currentMonitor && currentMonitor.ready) {
            currentMonitor.setBrightness(value);
        }
    }

    Component.onCompleted: updateSliderFromMonitor(false)
    onCurrentMonitorChanged: updateSliderFromMonitor(false)

    function updateSliderFromMonitor(forceAnimation: bool): void {
        if (!currentMonitor || !currentMonitor.ready || slider.isDragging)
            return;
        slider.value = currentMonitor.brightness;
        if (forceAnimation) {
            notifyExternalChange();
        }
    }

    Connections {
        target: currentMonitor
        enabled: currentMonitor !== null
        ignoreUnknownSignals: true
        function onBrightnessChanged() {
            updateSliderFromMonitor(true);
        }
        function onReadyChanged() {
            updateSliderFromMonitor(false);
        }
    }
}
