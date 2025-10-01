import QtQuick
import QtQuick.Controls

Item{
    property alias menuTitle: menuTitle
    property string title

    property int buttonX: groupsMenu.x + newGroupButton.x + 6
    property int buttonY: groupsMenu.y + newGroupButton.y + newGroupButton.height

    property bool group

    Rectangle{
        id: buttons
        anchors.fill: parent
        color: dark_2
        radius:window.radius


        Item{
            id: menuTitle
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            height: window.mobile ? 25 : 35

            z: 10

            Text {
                id: name
                text: title
                color:light
                font.pointSize: 10
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left; anchors.leftMargin:12
            }

            Button {
                id: newGroupButton

                visible: group
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: 10
                height: 20
                width: 20

                background: Rectangle{
                    anchors.fill:parent
                    color: newGroupButton.pressed? Qt.darker(dark_3,1.3) : dark_3
                    radius: 2
                }

                contentItem: Image{
                    anchors.fill: parent
                    anchors.margins: 3
                    source: "qrc:/icons/light/plus.png"
                }

                scale: hovered? 0.9: 1

                onClicked: {
                    popup.visible = true
                    popup.active = true
                    popup.nameInput.forceActiveFocus();
                }
            }

            Loader{
                sourceComponent: horizontalLine
                width: parent.width - 20
                anchors.bottom: parent.bottom
                z:15
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }


        MouseArea{
            anchors.top: menuTitle.bottom
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right

            ListView {
                id: buttonView
                anchors.fill: parent
                orientation: ListView.Vertical
                clip:true
                model: group ? groupButtonList : blockButtonList
                delegate: Button{
                    id: button
                    parent: buttonView

                    height:40
                    width:parent.width

                    display: AbstractButton.TextBesideIcon

                    background : Rectangle{
                        id: bgButton
                        color: "transparent"
                    }

                    contentItem: Item {
                        anchors.fill: parent
                        anchors.margins: 10
                        Image{
                            id: icon
                            anchors.verticalCenter: parent.verticalCenter
                            source:iconSource
                            width: 15
                            height: width
                        }
                        Text{
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: icon.right; anchors.leftMargin: 10
                            color: light
                            text: buttonText
                            font.bold: true
                            font.pointSize: buttonTextSize
                        }
                    }

                    MouseArea {
                        id: buttonArea
                        hoverEnabled: true
                        anchors.fill: parent
                        onClicked: {
                            blockSeq.displayedMenu = -1;

                            // Default values ------
                            var duration = "1e-3";
                            var lines = "64";
                            var samples = "64";
                            var adcDelay = "0";
                            var adcPhase = "0";
                            var fov = "0.2";
                            var select = 0;
                            var shape = 0;
                            var b1Module = "1e-6";
                            var flipAngle = "10";
                            var deltaf = "0";
                            var gDelay = "0";
                            var gRise = "5e-4";
                            var gFlatTop = "1e-3";
                            var gAmplitude = "1e-3";
                            var te = "20e-3";
                            var tr = "100e-3";
                            var repetitions = "1";
                            var iterator = "";
                            // ------------------

                            // Single block
                            if(code<=blockButtonList.count){

                                var durationActive =    [1,2,4].includes(code);
                                var linesActive =       [5,6].includes(code);
                                var samplesActive =     [4,5,6].includes(code);
                                var adcActive =         [4].includes(code);
                                var fovActive =         [5,6].includes(code);
                                var rfActive =          [1,6].includes(code);
                                var gradientsActive =   [1,3,4].includes(code);
                                var tActive =           [6].includes(code);
                                var groupActive =       [0].includes(code);

                                blockList.append(  {"cod": code,
                                                    "name": "",
                                                    "collapsed": false,
                                                    "ngroups": 0,
                                                    "children": [],
                                                    "grouped": false,
                                                    "rf": [],
                                                    "gradients": [],
                                                    "t": []
                                                });

                                if(durationActive)  {blockList.setProperty(blockList.count-1,           "duration", duration);}
                                if(linesActive)     {blockList.setProperty(blockList.count-1,           "lines", lines);}
                                if(samplesActive)   {blockList.setProperty(blockList.count-1,           "samples", samples);}
                                if(adcActive)       {blockList.setProperty(blockList.count-1,           "adcDelay", adcDelay);
                                                     blockList.setProperty(blockList.count-1,           "adcPhase", adcPhase);}
                                if(fovActive)       {blockList.setProperty(blockList.count-1,           "fov", fov);}
                                if(rfActive)        {blockList.get(blockList.count-1).rf.append(       {"select":select,
                                                                                                        "shape":shape,
                                                                                                        "b1Module": b1Module,
                                                                                                        "flipAngle": flipAngle,
                                                                                                        "deltaf": deltaf});}
                                if(gradientsActive) {blockList.get(blockList.count-1).gradients.append({"axis":"x",
                                                                                                        "delay": gDelay,
                                                                                                        "rise": gRise,
                                                                                                        "flatTop": gFlatTop,
                                                                                                        "amplitude": gAmplitude});
                                                     blockList.get(blockList.count-1).gradients.append({"axis":"y",
                                                                                                        "delay": "0",
                                                                                                        "rise": "0",
                                                                                                        "flatTop": "0",
                                                                                                        "amplitude": "0"});
                                                     blockList.get(blockList.count-1).gradients.append({"axis":"z",
                                                                                                        "delay": "0",
                                                                                                        "rise": "0",
                                                                                                        "flatTop": "0",
                                                                                                        "amplitude": "0"});}
                                if(tActive)         {blockList.get(blockList.count-1).t.append(        {"te": te,
                                                                                                        "tr": tr});}
                                if(groupActive)     {blockList.setProperty(blockList.count-1,           "repetitions", repetitions,
                                                                                                        "iterator", assignIterator());}

                            // Group of blocks
                            } else if(code>blockButtonList.count){

                                var index;
                                for(var i=0; i<groupList.count; i++){
                                    if(groupList.get(i).group_cod == code){
                                        index = i;
                                    }
                                }
                                var num;
                                var counter = 0;

                                do{
                                    var cod = groupList.get(index).cod;

                                    durationActive =    [1,2,3,4].includes(cod);
                                    linesActive =       [5,6].includes(cod);
                                    samplesActive =     [4,5,6].includes(cod);
                                    adcActive =    [4].includes(cod);
                                    fovActive =         [5,6].includes(cod);
                                    rfActive =          [1,6].includes(cod);
                                    gradientsActive =   [1,3,4].includes(cod);
                                    tActive =           [6].includes(cod);
                                    groupActive =       [0].includes(cod);

                                    blockList.append({  "cod": cod,
                                                        "name": groupList.get(index).name,
                                                        "collapsed": counter==0?false:true,
                                                        "ngroups": groupList.get(index).ngroups,
                                                        "children": [],
                                                        "grouped": false,
                                                        "rf": [],
                                                        "gradients": [],
                                                        "t": []});

                                    if(durationActive)  {blockList.setProperty(blockList.count-1,           "duration",     groupList.get(index).duration);}
                                    if(linesActive)     {blockList.setProperty(blockList.count-1,           "lines",        groupList.get(index).lines);}
                                    if(samplesActive)   {blockList.setProperty(blockList.count-1,           "samples",      groupList.get(index).samples);}
                                    if(adcActive)  {blockList.setProperty(blockList.count-1,           "adcDelay",     groupList.get(index).adcDelay);}
                                    if(fovActive)       {blockList.setProperty(blockList.count-1,           "fov",          groupList.get(index).fov);}
                                    if(rfActive)        {blockList.get(blockList.count-1).rf.append(       {"select":       groupList.get(index).rf.get(0).select,
                                                                                                            "shape":        groupList.get(index).rf.get(0).shape,
                                                                                                            "b1Module":     groupList.get(index).rf.get(0).b1Module,
                                                                                                            "flipAngle":    groupList.get(index).rf.get(0).flipAngle,
                                                                                                            "deltaf":       groupList.get(index).rf.get(0).deltaf});}
                                    if(gradientsActive) {
                                        var gradients = groupList.get(index).gradients
                                        for(i=0; i<gradients.count; i++){
                                            var grad = gradients.get(i);
                                            blockList.get(blockList.count-1).gradients.append(             {"axis":         grad.axis,
                                                                                                            "delay":        grad.delay,
                                                                                                            "rise":         grad.rise,
                                                                                                            "flatTop":      grad.flatTop,
                                                                                                            "amplitude":    grad.amplitude});}
                                    }
                                    if(tActive)         {blockList.get(blockList.count-1).t.append(        {"te":           groupList.get(index).t.get(0).te,
                                                                                                            "tr":           groupList.get(index).t.get(0).tr});}
                                    if(groupActive)     {
                                        blockList.setProperty(blockList.count-1,           "repetitions",  groupList.get(index).repetitions);
                                        blockList.setProperty(blockList.count-1,           "iterator",     assignIterator());
                                    }

                                    num = groupList.get(index).children.count;
                                    for(i=0;i<num;i++){
                                        blockList.get(blockList.count-1).children.append({"number":groupList.get(index).children.get(i).number+(-index+blockList.count-1)});
                                    }
                                    index ++;
                                    counter ++;
                                } while((index<groupList.count)&&(groupList.get(index).group_cod === -1));
                                index--;
                            }

                            for (var j=1; j<100; j++){
                               seqScrollBar.increase();
                            }
                        }

                        states: [
                            State{
                                when: buttonArea.pressed
                                PropertyChanges{
                                    target: bgButton
                                    color: Qt.darker(dark_3,1.3)
                                }
                            },
                            State{
                                when: buttonArea.containsMouse
                                PropertyChanges{
                                    target: bgButton
                                    color: dark_3
                                }
                            }
                        ]
                    } // MouseArea
                } // Button
            } // ListView
        } // MouseArea
    }
}

