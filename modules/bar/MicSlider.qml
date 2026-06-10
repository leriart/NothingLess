import QtQuick
import qs.modules.services
import qs.modules.components
import qs.modules.theme
import qs.config

BarSliderBase {
    id: root
    bar: bar
    icon: Audio.source?.audio?.muted ? Icons.micSlash : Icons.mic
    progressColor: Audio.source?.audio?.muted ? Colors.outline : Styling.srItem("overprimary")
    iconPos: vertical ? "end" : "start"
    scroll: isExpanded
    iconClickable: isExpanded

    onValueChangedCallback: function(value) {
        if (Audio.source?.audio) {
            Audio.source.audio.volume = value;
        }
    }
    onIconClickedCallback: function() {
        if (Audio.source?.audio) {
            Audio.source.audio.muted = !Audio.source.audio.muted;
        }
    }

    Component.onCompleted: slider.value = Audio.source?.audio?.volume ?? 0

    Connections {
        target: Audio.source?.audio ?? null
        enabled: Audio.source?.audio !== null
        ignoreUnknownSignals: true
        function onVolumeChanged() {
            if (Audio.source?.audio) {
                slider.value = Audio.source.audio.volume;
                notifyExternalChange();
            }
        }
    }
}
