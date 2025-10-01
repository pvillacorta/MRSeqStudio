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

    Rectangle{
        anchors.fill: parent
        border.width: 1
        border.color: "gray"
        color: textInput.text=="nan"||textInput.text=="NaN"? "#fc8383": (readOnly ? "#c9c9c9" : "white")
        TextInput{
            id: textInput
            anchors.fill: parent
            anchors.margins:3
            selectByMouse: true
            clip: true
            font.pointSize: window.fontSize

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
}


