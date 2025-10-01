import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects

Rectangle{
    id: variablesMenu
    color: "#016b6b"
    property int menuID: -2

    function recalculateAllVariables(){
        // Recalculate all variables to handle dependencies
        for (var i = 0; i < variablesList.count; i++) {
            var item = variablesList.get(i)
            if (item && item.expression) {
                var newValue = evalExpression(item.expression)
                if (isNaN(newValue) || !isFinite(newValue)) {
                    console.warn("Invalid expression result for variable '" + item.name + "': " + item.expression)
                    newValue = 0
                }
                variablesList.setProperty(i, "value", newValue)
            }
        }
    }

    function getViewIndexes(){ // Fixed: correct mapping between ListModel and view indices
        var indexes = []
        for (var i = 0; i < variablesList.count; i++){
            indexes.push(i) // Direct 1:1 mapping
        }
        return indexes
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
        id: variablesTitle
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        height: window.mobile ? 25 : 35

        z: 10

        Text{
            id: variablesTitleText
            text: "Global Variables"
            color:"white"
            font.pointSize: 10
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left; anchors.leftMargin:12
        }

        Button {
            id: newVariableButton
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: variablesTitleText.right; anchors.leftMargin: 10
            height: 18
            width:  18

            background: Rectangle{
                anchors.fill:parent
                color: newVariableButton.pressed? Qt.darker(dark_3,1.3) : dark_3
                radius: 2
            }

            contentItem: Image{
                anchors.fill: parent
                anchors.margins: 3
                source: "qrc:/icons/light/plus.png"
            }

            scale: hovered? 0.9: 1

            onClicked: { 
                variablesList.append({"name":"", "expression":"", "value":0, "readonly":false})
            }
        }

        Text{
            id: variablesFieldNames
            text: " Name                Expression          Value"
            anchors.top: variablesTitleText.bottom; anchors.topMargin: 5
            color:"white"
            font.pointSize: 10
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left; anchors.leftMargin:12
        }
    }

    Item{
        id: variablesArea
        anchors.fill: parent
        anchors.bottomMargin:10
        anchors.topMargin: 45
        anchors.leftMargin: 15
        anchors.rightMargin: 15

        ListView{
            id: variablesView
            anchors.fill: parent
            orientation: ListView.Vertical
            clip: true
            model: variablesList
            boundsBehavior: Flickable.StopAtBounds 
            
            ScrollBar.vertical: ScrollBar{
                id: varScrollBar
                active: true
                orientation: Qt.Vertical
                policy: ScrollBar.AlwaysOn
            }

            delegate: GridLayout{ 
                height: 25
                columns:4
                columnSpacing: 5
                
                // Name input - updates model directly
                TextInputItem{
                    id: nameInput;  
                    idNumber: menuID; 
                    text: name; 
                    width: 100; 
                    readOnly: readonly
                    function nextInput(){
                        return expressionInput.textInput
                    }
                    onTextChanged: {
                        if (text !== name) {
                            variablesList.setProperty(index, "name", text)
                            // Recalculate all variables in case any depend on this variable name
                            recalculateAllVariables()
                        }
                    }
                }
                
                // Expression input - updates model directly and recalculates value
                TextInputItem{
                    id: expressionInput;  
                    idNumber: menuID; 
                    text: expression; 
                    width: 100; 
                    function nextInput(){
                        if (index < variablesList.count - 1) {
                            return valueInput.textInput
                        }
                        return null; 
                    }
                    onTextChanged: {
                        if (text !== expression) {
                            variablesList.setProperty(index, "expression", text)
                            // Recalculate this variable's value
                            var newValue = evalExpression(text)
                            if (isNaN(newValue) || !isFinite(newValue)) {
                                console.warn("Invalid expression result for variable '" + name + "': " + text)
                                newValue = 0
                            }
                            variablesList.setProperty(index, "value", newValue)
                            
                            // Recalculate ALL variables that might depend on this one
                            recalculateAllVariables()
                        }
                    }
                }
                
                // Value input - read-only, displays calculated value
                TextInputItem{
                    id: valueInput; 
                    idNumber: menuID; 
                    text: value; 
                    width: 100; 
                    readOnly: true
                    function nextInput(){
                        if (index < variablesList.count - 1) {
                            return variablesView.itemAt(0, (index + 1) * 25 + 12.5).children[0].textInput
                        }
                        return null; 
                    }
                }
                
                DeleteButton{
                    visible: !readonly
                    function clicked(){
                        variablesList.remove(index)
                    }
                    height: 15
                    width: height
                }
            } 
        }
    }
}
