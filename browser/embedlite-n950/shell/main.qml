import QtQuick 2.6
import Qt5MozillaNext153 1.0

Rectangle {
    id: root
    color: "white"
    width: 854
    height: 480

    Rectangle {
        id: bar
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 48
        color: "#202020"

        Row {
            id: buttons
            anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 6 }
            spacing: 6
            Repeater {
                model: [
                    { label: "‹", act: function() { web.goBack() } },
                    { label: "›", act: function() { web.goForward() } },
                    { label: web.loading ? "×" : "↻", act: function() { web.loading ? web.stop() : web.reload() } }
                ]
                Rectangle {
                    width: 40; height: 36; radius: 4; color: "#404040"
                    Text { anchors.centerIn: parent; text: modelData.label; color: "white"; font.pixelSize: 24 }
                    MouseArea { anchors.fill: parent; onClicked: modelData.act() }
                }
            }
        }

        Rectangle {
            anchors { left: buttons.right; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 6; rightMargin: 6 }
            height: 36; radius: 4; color: "white"
            TextInput {
                id: address
                anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                verticalAlignment: TextInput.AlignVCenter
                font.pixelSize: 20
                clip: true
                text: web.url
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                onAccepted: {
                    var u = text.trim()
                    if (u.indexOf("://") < 0 && u.indexOf("about:") !== 0)
                        u = "https://" + u
                    web.url = u
                    web.forceActiveFocus()
                }
            }
        }

        Rectangle {
            anchors { left: parent.left; bottom: parent.bottom }
            height: 3; color: "#3080ff"
            width: web.loading ? parent.width * web.loadProgress / 100 : 0
        }
    }

    QmlMozView {
        id: web
        anchors { left: parent.left; right: parent.right; top: bar.bottom; bottom: parent.bottom }
        active: true
        focus: true
        // The N950's screen is landscape; qtmozembed otherwise sizes Gecko's
        // window for a portrait-native (Sailfish) screen, transposed.
        orientation: Qt.LandscapeOrientation
        Component.onCompleted: web.url = startUrl
    }

    Timer {
        id: swipeStep
        property int step: 0
        interval: 30
        repeat: true
        onTriggered: {
            var x = web.width / 2, y0 = web.height - 40, y1 = 40
            if (step === 0) {
                web.synthTouchBegin([Qt.point(x, y0)])
            } else if (step < 10) {
                web.synthTouchMove([Qt.point(x, y0 + (y1 - y0) * step / 10)])
            } else {
                web.synthTouchEnd([Qt.point(x, y1)])
                stop()
            }
            step++
        }
    }
    Timer {
        id: swipes
        property int left: scrollTestSwipes
        interval: 2000
        repeat: true
        onTriggered: {
            if (left-- <= 0) {
                stop()
                return
            }
            swipeStep.step = 0
            swipeStep.start()
        }
    }
    Timer {
        interval: scrollTestStart * 1000
        running: scrollTestSwipes > 0
        onTriggered: swipes.start()
    }
}
