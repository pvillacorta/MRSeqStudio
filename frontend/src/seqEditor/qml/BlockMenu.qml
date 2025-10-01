import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects

Item {
    property int blockID
    property color menuColor
    property string menuTitle   
    property bool menuVisible: false

    // ------- Duration
    property bool durationVisible
    property alias duration:    durationInput.text

    // ------- Lines
    property bool linesVisible
    property alias lines:       linesInput.text

    // ------- Samples
    property bool samplesVisible
    property alias samples:     samplesInput.text

    // ------- ADC 
    property bool adcVisible
    property alias adcDelay:    adcDelayInput.text
    property alias adcPhase:    adcPhaseInput.text

    // ------- FOV
    property bool fovVisible
    property alias fov:         fovInput.text

    // ------- RF
    property bool rfVisible
    property alias select:      rfSelect.currentIndex
    property alias shape:       shapeInput.currentIndex
    property alias b1Module:    b1ModuleInput.text
    property alias flipAngle:   flipAngleInput.text
    property alias deltaf:      deltafInput.text

    // ------- Gradients
    property bool gradientsVisible
    property alias gxDelay:     gxDelayInput.text
    property alias gyDelay:     gyDelayInput.text
    property alias gzDelay:     gzDelayInput.text

    property alias gxRise:      gxRiseInput.text
    property alias gyRise:      gyRiseInput.text
    property alias gzRise:      gzRiseInput.text

    property alias gxFlatTop:   gxFlatTopInput.text
    property alias gyFlatTop:   gyFlatTopInput.text
    property alias gzFlatTop:   gzFlatTopInput.text

    property alias gxAmplitude: gxAmplitudeInput.text
    property alias gyAmplitude: gyAmplitudeInput.text
    property alias gzAmplitude: gzAmplitudeInput.text

    // ------- Times
    property bool tVisible
    property alias te:          teInput.text
    property alias tr:          trInput.text

    // ------- Group
    property bool groupVisible
    property alias repetitions: repsInput.text
    property alias iterator:    iteratorInput.text

    function applyBlockChanges(blockID){
        if(durationVisible) {blockList.setProperty(blockID,          "duration",    duration);}
        if(linesVisible)    {blockList.setProperty(blockID,          "lines",       lines);}
        if(samplesVisible)  {blockList.setProperty(blockID,          "samples",     samples);}
        if(adcVisible)      {blockList.setProperty(blockID,          "adcDelay",    adcDelay);
                             blockList.setProperty(blockID,          "adcPhase",    adcPhase);}
        if(fovVisible)      {blockList.setProperty(blockID,          "fov",         fov);}
        if(rfVisible)       {blockList.get(blockID).rf.set(0,       {"select":      select,
                                                                     "shape":       shape,
                                                                     "b1Module":    b1Module,
                                                                     "flipAngle":   flipAngle,
                                                                     "deltaf":      deltaf});}
        if(gradientsVisible){
            var gradients = blockList.get(blockID).gradients;
            for(var i=0; i<gradients.count; i++){     
                var grad = gradients.get(i);
                blockList.get(blockID).gradients.set(i,             {"axis":         grad.axis,
                                                                     "delay":        eval('g' + grad.axis + 'Delay'),
                                                                     "rise":         eval('g' + grad.axis + 'Rise'),
                                                                     "flatTop":      eval('g' + grad.axis + 'FlatTop'),
                                                                     "amplitude":    eval('g' + grad.axis + 'Amplitude')});}
        }
        if(tVisible)        {blockList.get(blockID).t.set(0,        {"te":           te,
                                                                     "tr":           tr});}
        if(groupVisible)    {blockList.setProperty(blockID,          "repetitions",  repetitions);}

        var blockInfo = blockList.get(blockID);

        duration =      durationVisible ?   blockInfo.duration : "0";
        lines =         linesVisible ?      blockInfo.lines : "0";
        samples =       samplesVisible ?    blockInfo.samples : "0";
        adcDelay =      adcVisible ?        blockInfo.adcDelay : "0";
        adcPhase =      adcVisible ?        blockInfo.adcPhase : "0";
        fov =           fovVisible ?        blockInfo.fov : "0";
        shape =         rfVisible ?         blockInfo.rf.get(0).shape : "0";
        b1Module =      rfVisible ?         blockInfo.rf.get(0).b1Module : "0";
        flipAngle =     rfVisible ?         blockInfo.rf.get(0).flipAngle : "0";
        deltaf =        rfVisible ?         blockInfo.rf.get(0).deltaf : "0";
        gxDelay =       gradientsVisible ?  blockInfo.gradients.get(0).delay : "0";
        gyDelay =       gradientsVisible ?  blockInfo.gradients.get(1).delay : "0";
        gzDelay =       gradientsVisible ?  blockInfo.gradients.get(2).delay : "0";
        gxRise =        gradientsVisible ?  blockInfo.gradients.get(0).rise : "0";
        gyRise =        gradientsVisible ?  blockInfo.gradients.get(1).rise : "0";
        gzRise =        gradientsVisible ?  blockInfo.gradients.get(2).rise : "0";
        gxFlatTop =     gradientsVisible ?  blockInfo.gradients.get(0).flatTop : "0";
        gyFlatTop =     gradientsVisible ?  blockInfo.gradients.get(1).flatTop : "0";
        gzFlatTop =     gradientsVisible ?  blockInfo.gradients.get(2).flatTop : "0";
        gxAmplitude =   gradientsVisible ?  blockInfo.gradients.get(0).amplitude : "0";
        gyAmplitude =   gradientsVisible ?  blockInfo.gradients.get(1).amplitude : "0";
        gzAmplitude =   gradientsVisible ?  blockInfo.gradients.get(2).amplitude : "0";
        te =            tVisible ?          blockInfo.t.get(0).te : "0";
        tr =            tVisible ?          blockInfo.t.get(0).tr : "0";
        repetitions =   groupVisible ?      blockInfo.repetitions : "0";
        iterator    =   groupVisible ?      blockInfo.iterator    : "";
    }

    Rectangle{
        id: rectConfig
        visible: menuVisible
        anchors.fill: parent

        color: menuColor

        radius: window.radius

        RectangularGlow {
            id: configGlow
            anchors.fill: parent
            visible: parent.visible & !popup.visible
            glowRadius: 6
            spread: 0.2
            color: menuColor
            opacity: 0.6
            cornerRadius: parent.radius + glowRadius
        }

        Text{
            id: configText
            text: menuTitle + " (" + blockID + ")"
            anchors.horizontalCenter: parent.horizontalCenter
            y:10
            font.pointSize: 12
        }

        Component{
            id: configPanel
            Rectangle {
                implicitWidth: column.width
                color: Qt.lighter(menuColor,1.3)
                z:-10
            }
        }

        Row{
            visible: rfVisible & !linesVisible
            anchors.right: column.right
            anchors.top: column.top
            anchors.margins: 2
            Label{
                visible: !window.mobile
                text: "Select: "
            }

            ComboBoxItem{
                id: rfSelect;
                idNumber: blockID;
                model: ["Flip angle and duration", "Flip angle and amplitude", "Duration and amplitude"];
            }
        }



        Column {
            id: column
            anchors.top: configText.bottom
            width: parent.width - 20
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: 5
            spacing: 5

            Loader { visible: linesVisible
                sourceComponent: configPanel
                width:200
                height: 26
                GridLayout{ id: linesLayout
                    uniformCellWidths: true
                    anchors.fill: parent
                    anchors.margins:3
                    columns: 4
                    rowSpacing: 3

                    MenuLabel { text: "Lines:";   bold: true;   Layout.columnSpan: 2}
                    TextInputItem{ idNumber: blockID;  id: linesInput; Layout.alignment: Qt.AlignRight }
                    MenuLabel { text: "lines" }
                }
            }

            Loader { visible: samplesVisible
                sourceComponent: configPanel
                width:200
                height: 26
                GridLayout{ id: samplesLayout
                    uniformCellWidths: true
                    anchors.fill: parent
                    anchors.margins:3
                    columns: 4
                    rowSpacing: 3

                    MenuLabel { text: "Samples:";  bold: true;  Layout.columnSpan: 2}
                    TextInputItem{ idNumber: blockID;  id: samplesInput; Layout.alignment: Qt.AlignRight}
                    MenuLabel { text: "samples" }
                }
            }

            Loader { visible: durationVisible
                sourceComponent: configPanel
                width:200
                height: 26
                enabled: rfVisible & rfSelect.currentIndex === 1 ? false : true
                opacity: enabled
                GridLayout{ id: durationLayout
                    uniformCellWidths: true
                    anchors.fill: parent
                    anchors.margins:3
                    columns: 4
                    rowSpacing: 3

                    MenuLabel { text: "Duration:";  bold: true; Layout.columnSpan: 2}
                    TextInputItem{ idNumber: blockID;  id:durationInput; Layout.alignment: Qt.AlignRight}
                    MenuLabel { text: "s"}
                }
            }

            Loader { visible: adcVisible
                sourceComponent: configPanel
                height: 26
                GridLayout{ id: adcDelayLayout
                    uniformCellWidths: true
                    anchors.fill: parent
                    anchors.margins:3
                    columns: 8
                    rowSpacing: 3

                    MenuLabel { text: "ADC Delay:";  bold: true;  Layout.columnSpan: 2}
                    TextInputItem{ idNumber: blockID;  id: adcDelayInput; Layout.alignment: Qt.AlignRight}
                    MenuLabel { text: "s" }
                    MenuLabel { text: "ADC Phase:";  bold: true;  Layout.columnSpan: 2}
                    TextInputItem{ idNumber: blockID;  id: adcPhaseInput; Layout.alignment: Qt.AlignRight}
                    MenuLabel { text: "rad" }
                }
            }

            Loader { visible: fovVisible
                sourceComponent: configPanel
                width:200
                height: 26
                GridLayout{ id: fovLayout
                    uniformCellWidths: true
                    anchors.fill: parent
                    anchors.margins:3
                    columns: 4
                    rowSpacing: 3

                    MenuLabel { text: "FOV:";  bold: true; Layout.columnSpan: 2}
                    TextInputItem{ idNumber: blockID;  id:fovInput; Layout.alignment: Qt.AlignRight}
                    MenuLabel { text: "m" }
                }
            }

            Loader { visible: rfVisible
                sourceComponent: configPanel
                height: 72
                Flickable {
                    anchors.fill:parent
                    anchors.leftMargin: 5; anchors.rightMargin: 5
                    contentHeight: this.height
                    contentWidth: rfLayout.width
                    clip:true
                    GridLayout{ id: rfLayout
                        anchors.fill: parent
                        anchors.margins:3
                        columns: 5
                        rowSpacing: 3

                        MenuLabel { text: "RF:"; bold: true}
                        MenuLabel { text: "RF Shape:"; Layout.alignment: Qt.AlignRight}
                        ComboBoxItem{
                            id: shapeInput;
                            idNumber: blockID;
                            model: linesVisible ? ["Sinc"] : ["Rectangle (hard)", "Sinc"];
                        }

                        MenuLabel { text: "Peak |B1|[T]:";  Layout.alignment: Qt.AlignRight; enabled:b1ModuleInput.enabled; opacity: enabled}
                        TextInputItem{ idNumber: blockID;  id:b1ModuleInput
                                        enabled: rfVisible & rfSelect.currentIndex === 0 ? false : true
                                        opacity: enabled }

                        MenuLabel { text: "Flip Angle [º]:"; Layout.alignment: Qt.AlignRight; Layout.columnSpan: 2; enabled:flipAngleInput.enabled; opacity: enabled}
                        TextInputItem{ idNumber: blockID;   id:flipAngleInput;           Layout.columnSpan: 3
                                        enabled: rfVisible & rfSelect.currentIndex === 2 ? false : true
                                        opacity: enabled }

                        MenuLabel { text: "Δf [Hz]:";  Layout.alignment: Qt.AlignRight; Layout.columnSpan: 2}
                        TextInputItem{ idNumber: blockID;  id:deltafInput}
                    }
                }
            }

            Loader { visible: gradientsVisible
                sourceComponent: configPanel
                height: 90
                Flickable {
                    anchors.fill:parent
                    anchors.leftMargin: 5; anchors.rightMargin: 5
                    contentHeight: this.height
                    contentWidth: gradientsLayout.width
                    clip:true
                    GridLayout{ id: gradientsLayout
                        columns: 5
                        anchors.fill: parent
                        anchors.margins:3
                        anchors.rightMargin: 10
                        rowSpacing: 1

                        MenuLabel { text: "Gradients:";                                 bold: true}
                        MenuLabel { text: "InitialDelay [s]";                           Layout.alignment: Qt.AlignCenter}
                        MenuLabel { text: "Rise/Fall [s]";                              Layout.alignment: Qt.AlignCenter}
                        MenuLabel { text: "FlatTopTime [s]";                            Layout.alignment: Qt.AlignCenter}
                        MenuLabel { text: "Amplitude [T/m]";                            Layout.alignment: Qt.AlignCenter}

                        MenuLabel { text: "Gx:";                                        Layout.alignment: Qt.AlignCenter}
                        TextInputItem{ idNumber: blockID;  id:gxDelayInput;             Layout.alignment: Qt.AlignCenter}
                        TextInputItem{ idNumber: blockID;  id:gxRiseInput;              Layout.alignment: Qt.AlignCenter}
                        TextInputItem{ idNumber: blockID;  id:gxFlatTopInput;           Layout.alignment: Qt.AlignCenter}
                        TextInputItem{ idNumber: blockID;  id:gxAmplitudeInput;         Layout.alignment: Qt.AlignCenter}

                        MenuLabel { text: "Gy:";                                        Layout.alignment: Qt.AlignCenter}
                        TextInputItem{ idNumber: blockID;  id:gyDelayInput;             Layout.alignment: Qt.AlignCenter}
                        TextInputItem{ idNumber: blockID;  id:gyRiseInput;              Layout.alignment: Qt.AlignCenter}
                        TextInputItem{ idNumber: blockID;  id:gyFlatTopInput;           Layout.alignment: Qt.AlignCenter}
                        TextInputItem{ idNumber: blockID;  id:gyAmplitudeInput;         Layout.alignment: Qt.AlignCenter}

                        MenuLabel { text: "Gz:";                                        Layout.alignment: Qt.AlignCenter}
                        TextInputItem{ idNumber: blockID;  id:gzDelayInput;             Layout.alignment: Qt.AlignCenter}
                        TextInputItem{ idNumber: blockID;  id:gzRiseInput;              Layout.alignment: Qt.AlignCenter}
                        TextInputItem{ idNumber: blockID;  id:gzFlatTopInput;           Layout.alignment: Qt.AlignCenter}
                        TextInputItem{ idNumber: blockID;  id:gzAmplitudeInput;         Layout.alignment: Qt.AlignCenter}
                    }
                }
            }

            Loader { visible: tVisible
                sourceComponent: configPanel
                height: 50
                width: 200
                GridLayout{ id:tLayout
                    uniformCellWidths: true
                    anchors.fill: parent
                    anchors.margins:3
                    columns: 4
                    rowSpacing: 1
                    MenuLabel { text: "TE:";  bold: true; Layout.columnSpan: 2}
                    TextInputItem{ idNumber: blockID;  id:teInput; Layout.alignment: Qt.AlignRight}
                    MenuLabel { text: "s" }
                    MenuLabel { text: "TR:";  bold: true; Layout.columnSpan: 2}
                    TextInputItem{ idNumber: blockID;  id:trInput; Layout.alignment: Qt.AlignRight}
                    MenuLabel { text: "s"}
                }
            }

            Loader { visible: groupVisible
                sourceComponent: configPanel
                width: 200
                height: 55
                GridLayout{ id: repsLayout
                    anchors.fill: parent
                    anchors.margins:3
                    columns: 2
                    rowSpacing: 3

                    MenuLabel { text: "Iterator:";  bold: true}
                    TextInputItem{ idNumber: blockID;  id:iteratorInput; Layout.alignment: Qt.AlignRight; readOnly: true}

                    MenuLabel { text: "Repetitions:";  bold: true}
                    TextInputItem{ idNumber: blockID;  id:repsInput; Layout.alignment: Qt.AlignRight}
                }
            }
        }

        // VIEW 3D MODEL OF SELECTED SLICE
        Button{
            id: plotButton
            visible: rfVisible
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 10
            anchors.bottomMargin: 10
            height: 25
            width: 100
            text: "View 3D Model"
            font.pointSize: window.fontSize
            onClicked:{
                backend.plot3D(evalExpression(gxAmplitude), evalExpression(gyAmplitude), evalExpression(gzAmplitude), evalExpression(deltaf), variablesList.get(0).value)
            }
        }
    } // Rectangle

    states: [
        State{
            when: !configMenu.menuVisible
            PropertyChanges {
                target: rectConfig
                scale: 0
            }
        },
        State{
            when: configMenu.menuVisible
            PropertyChanges {
                target: rectConfig
                scale: 1
            }
        }
    ] // states

    transitions:
        Transition{
                 PropertyAnimation {property: "scale"; duration: 75}
        }

} // Item
