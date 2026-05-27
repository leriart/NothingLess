import QtQuick
import qs.modules.widgets.overview
import qs.modules.services
import qs.modules.globals
import qs.modules.theme
import qs.config

Item {
    id: root
    property var currentScreen

    // Detect if we're in scrolling layout mode
    readonly property bool isScrollingLayout: GlobalStates.compositorLayout === "scrolling"

    // Expose flickable and scrollbar needs for scrolling mode
    readonly property var flickable: isScrollingLayout && overviewLoader.item ? overviewLoader.item.flickable : null
    readonly property bool needsScrollbar: isScrollingLayout && overviewLoader.item ? overviewLoader.item.needsScrollbar : false

    // Manual scrolling state - passed through to ScrollingOverview
    property bool isManualScrolling: false
    onIsManualScrollingChanged: {
        if (isScrollingLayout && overviewLoader.item) {
            overviewLoader.item.isManualScrolling = isManualScrolling;
        }
    }

    // Dynamic loader for the appropriate overview component
    Loader {
        id: overviewLoader
        anchors.fill: parent
        active: true
        asynchronous: true

        sourceComponent: isScrollingLayout ? scrollingOverviewComponent : standardOverviewComponent

        // Smooth opacity transition with bloom-like entrance
        opacity: status === Loader.Ready ? 1 : 0

        Behavior on opacity {
            enabled: Anim.animationsEnabled
            NumberAnimation {
                duration: Anim.standardNormal
                easing.type: Anim.easing("decelerate").type
                easing.bezierCurve: Anim.easing("decelerate").bezierCurve
            }
        }

        // Elegant scale entrance — starts slightly small and blooms out with spring
        scale: status === Loader.Ready ? 1 : 0.92

        Behavior on scale {
            enabled: Anim.animationsEnabled
            NumberAnimation {
                duration: Anim.emphasizedNormal
                easing.type: Anim.springSnappy().type
                easing.bezierCurve: Anim.springSnappy().bezierCurve
            }
        }

        // Subtle vertical slide — starts slightly below and rises into place
        transform: Translate {
            y: overviewLoader.status === Loader.Ready ? 0 : 24
            Behavior on y {
                enabled: Anim.animationsEnabled
                NumberAnimation {
                    duration: Anim.emphasizedNormal
                    easing.type: Anim.springSnappy().type
                    easing.bezierCurve: Anim.springSnappy().bezierCurve
                }
            }
        }
    }

    // Standard grid overview
    Component {
        id: standardOverviewComponent
        Overview {
            currentScreen: root.currentScreen

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    Visibilities.setActiveModule("");
                    event.accepted = true;
                }
            }

            Component.onCompleted: {
                forceActiveFocus();
            }
        }
    }

    // Scrolling tape overview
    Component {
        id: scrollingOverviewComponent
        ScrollingOverview {
            currentScreen: root.currentScreen

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    Visibilities.setActiveModule("");
                    event.accepted = true;
                }
            }

            Component.onCompleted: {
                forceActiveFocus();
            }
        }
    }

    // Expose search-related properties for parent components (read from child)
    readonly property var matchingWindows: overviewLoader.item ? overviewLoader.item.matchingWindows : []
    readonly property int selectedMatchIndex: overviewLoader.item ? overviewLoader.item.selectedMatchIndex : 0

    // Search query - writable, synced to child
    property string searchQuery: ""
    onSearchQueryChanged: {
        if (overviewLoader.item) {
            overviewLoader.item.searchQuery = searchQuery;
        }
    }

    function resetSearch() {
        searchQuery = "";
        if (overviewLoader.item && overviewLoader.item.resetSearch) {
            overviewLoader.item.resetSearch();
        }
    }

    function navigateToSelectedWindow() {
        if (overviewLoader.item && overviewLoader.item.navigateToSelectedWindow) {
            overviewLoader.item.navigateToSelectedWindow();
        }
    }

    function selectNextMatch() {
        if (overviewLoader.item && overviewLoader.item.selectNextMatch) {
            overviewLoader.item.selectNextMatch();
        }
    }

    function selectPrevMatch() {
        if (overviewLoader.item && overviewLoader.item.selectPrevMatch) {
            overviewLoader.item.selectPrevMatch();
        }
    }
}
