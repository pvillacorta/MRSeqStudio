import QtQuick
import QtQuick.Controls

Item{
    property int idNumber
    property alias textInput: textInput
    property alias text:      textInput.text
    property alias readOnly:  textInput.readOnly
    width: window.fieldWidth
    height:window.fieldHeight

    function nextInput(){
        parent.nextInput();
    }

    TextField{
        id: textInput
        anchors.fill: parent

        topPadding: 0
        bottomPadding: 0
        leftPadding: 2
        rightPadding: 2

        background: Rectangle {
            color: textInput.text=="nan"||textInput.text=="NaN"? "#fc8383": (readOnly ? "#c9c9c9" : "white")
            border.color: textInput.focus ? "blue" : "#c9c9c9"
            border.width: 1
        }

        font.pointSize: window.fontSize
        color: dark_1

        onActiveFocusChanged: {
            if (activeFocus && idNumber < 0) {
                KeyNavigation.tab = nextInput()
            }
        }

        onEditingFinished:{
            // Only call applyChanges for non-variable contexts (idNumber >= 0)
            // For variables (idNumber < 0), the model is updated directly via onTextChanged
            if (idNumber >= 0) {
                applyChanges(idNumber)
            }
        }
    }
}


