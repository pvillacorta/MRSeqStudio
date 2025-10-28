import QtQuick
import QtQuick.Controls

ComboBox {
    id: comboInput
    property int idNumber
    font.pointSize: window.fontSize;
    model: model
    delegate: ItemDelegate {
        width: comboInput.width
        height: comboInput.height

        background: Rectangle {
            color: (highlighted || hovered) ? "#f0f0f0" : "transparent"
        }

        Item {
            anchors.fill: parent
            anchors.leftMargin: 5
            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 50
                text: modelData
                color: "#292929"
                font: comboInput.font
                elide: Text.ElideRight
            }
        }
        highlighted: comboInput.highlightedIndex === index
    }
    indicator: Canvas {
        id: canvas
        x: comboInput.width - width - comboInput.rightPadding
        y: comboInput.topPadding + (comboInput.availableHeight - height) / 2
        width: 12
        height: 8
        contextType: "2d"

        Connections {
            target: comboInput
            function onPressedChanged() { canvas.requestPaint(); }
        }
        onPaint: {
            context.reset();
            context.moveTo(0, 0);
            context.lineTo(width, 0);
            context.lineTo(width / 2, height);
            context.closePath();
            context.fillStyle = comboInput.pressed ? "black" : "#292929";
            context.fill();
        }
    }
    contentItem: Text {
        leftPadding: 5
        rightPadding: comboInput.indicator.width + comboInput.spacing

        text: comboInput.displayText
        font: comboInput.font
        color: comboInput.pressed ? "black" : "#292929"
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: Rectangle {
        implicitWidth: 120
        implicitHeight: window.fieldHeight
        border.color: comboInput.pressed ? "black" : "#595959"
        border.width: comboInput.visualFocus ? 2 : 1
        radius: 2
    }
    popup: Popup {
        y: comboInput.height - 1
        width: comboInput.width
        implicitHeight: contentItem.implicitHeight
        padding: 1

        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: comboInput.popup.visible ? comboInput.delegateModel : null
            currentIndex: comboInput.highlightedIndex
        }
        background: Rectangle {
            border.color: "#292929"
            radius: 2
        }
    }
    onActivated : { 
        applyChanges(idNumber)
    }
}
