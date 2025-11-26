import QtQuick
import QtQuick.Controls

Button {
    id: styledButton
    
    property alias buttonText: styledButton.text
    property int buttonWidth: 100
    property int buttonHeight: 25
    property int fontSize: 8
    
    font.pointSize: fontSize
    font.bold: true
    
    height: buttonHeight
    width: buttonWidth
    
    background: Rectangle {
        id: buttonBackground
        color: styledButton.hovered ? "#046642" : "#1d9bf0"
        radius: 6
    }
    
    contentItem: Text {
        text: styledButton.text
        font: styledButton.font
        color: "white"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    
    states: [
        State {
            when: !styledButton.hovered
            PropertyChanges {
                target: buttonBackground
                color: "#1d9bf0"
            }
        },
        State {
            when: styledButton.hovered
            PropertyChanges {
                target: buttonBackground
                color: "#046642"
            }
        }
    ] // states
    
    transitions: [
        Transition {
            PropertyAnimation { property: "color"; duration: 200 }
        }
    ]
}