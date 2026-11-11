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
        Component.onCompleted: web.url = startUrl
    }
}
