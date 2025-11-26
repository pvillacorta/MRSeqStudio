import QtQuick
import QtQuick.Controls

Dialog {
    title: "Select Preset Sequence"
    width: 400
    height: 500
    modal: true

    property var sequences: []

    contentItem: ListView {
        id: sequenceListView
        model: menuPresets.sequences
        delegate: ItemDelegate {
            width: sequenceListView.width
            text: modelData
            onClicked: {
                backend.loadPresetSequence(modelData);
                menuPresets.close();
            }
        }
    }
}
