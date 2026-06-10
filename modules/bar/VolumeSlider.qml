import QtQuick
import qs.modules.services
import qs.modules.components
import qs.modules.theme
import qs.config

BarSliderBase {
    id: root
    bar: bar
    icon: {
        if (Audio.sink?.audio?.muted)
            return Icons.speakerSlash;
        const vol = Audio.sink?.audio?.volume ?? 0;
        if (vol < 0.01)
            return Icons.speakerX;
        if (vol < 0.19)
            return Icons.speakerNone;
        if (vol < 0.49)
            return Icons.speakerLow;
        return Icons.speakerHigh;
    }
    progressColor: Audio.sink?.audio?.muted ? Colors.outline : Styling.srItem("overprimary")
    iconPos: vertical ? "end" : "start"
    scroll: isExpanded
    iconClickable: isExpanded

    onValueChangedCallback: function(value) {
        if (Audio.sink?.audio) {
            Audio.sink.audio.volume = value;
        }
    }
    onIconClickedCallback: function() {
        if (Audio.sink?.audio) {
            Audio.sink.audio.muted = !Audio.sink.audio.muted;
        }
    }

    Component.onCompleted: slider.value = Audio.sink?.audio?.volume ?? 0

    Connections {
        target: Audio.sink?.audio ?? null
        enabled: Audio.sink?.audio !== null
        ignoreUnknownSignals: true
        function onVolumeChanged() {
            if (Audio.sink?.audio) {
                slider.value = Audio.sink.audio.volume;
                notifyExternalChange();
            }
        }
    }
}
