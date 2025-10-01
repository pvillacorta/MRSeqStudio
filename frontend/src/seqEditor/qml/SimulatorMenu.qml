import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects

Rectangle{
    id: simulatorMenu
    color: "#492859"

    function applyPhantomChanges(){
        const fileNames = ["brain2D", "brain3D", "pelvis2D", "flow_cylinder", "aorta3D"]
        backend.displayPhantom(fileNames[phantomInput.currentIndex])
    }

    RectangularGlow {
        anchors.fill: parent
        visible: parent.visible & !popup.visible
        glowRadius: 6
        spread: 0.2
        color: parent.color
        opacity: 0.6
        cornerRadius: parent.radius + glowRadius
    }

    Item{
        id: simulator
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        height: window.mobile ? 25 : 35

        z: 10

        Text{
            id: simulatorTitleText
            text: "Simulation Launcher"
            color:"white"
            font.pointSize: 10
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left; anchors.leftMargin:12
        }
    }

    Row{
        id: simulatorRow
        x: 20
        y: 35
        spacing: 5
        MenuLabel { text: "Phantom:"; fontColor: "white"}
        ComboBoxItem{
            id: phantomInput;
            idNumber: -3;
            model: [ "Brain 2D", "Brain 3D", "Pelvis 2D", "Flow Cylinder", "Aorta 3D" ]
        }
    }

    Button{
        id : simulateButton
        text: "Simulate"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 15
        height: 25
        width: 100
        font.pointSize: window.fontSize
        font.bold: true

        background: Rectangle {
            id: simulateButtonBackground
            color: simulateButton.hovered ? "#046642" : "#1d9bf0"
            radius: 6
        }

        contentItem: Text {
            text: simulateButton.text
            font: simulateButton.font
            color: "white"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        onClicked: {
            simulate()
        }

        states: [
                State{
                    when: !simulateButton.hovered
                    PropertyChanges {
                        target: simulateButtonBackground
                        color: "#1d9bf0"
                    }
                },
                State{
                    when: simulateButton.hovered
                    PropertyChanges {
                        target: simulateButtonBackground
                        color: "#046642"
                    }
                }
            ] // states

        transitions: [
            Transition{
                PropertyAnimation {property: "color"; duration: 200}
            }
        ]
    }
}
