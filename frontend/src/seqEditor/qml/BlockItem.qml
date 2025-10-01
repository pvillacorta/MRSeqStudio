import QtQuick
import QtQuick.Controls
import Qt5Compat.GraphicalEffects


Item{
    id: block

    height: 100
    width: collapsed? 0:100-20*ngroups
    visible:collapsed?false:true

    property int dropIndex: index

    property string blockText:  cod==0? name:
                                cod==1? "Ex":
                                cod==2? "Delay":
                                cod==3? "Dephase":
                                cod==4? "Readout":
                                cod==5? "EPI_ACQ":
                                cod==6? "GRE":
                                undefined

    property string blockColor: cod==0? "#cca454":
                                cod==1? "#ed645a":
                                cod==2? "#61e86f":
                                cod==3? "#e3f56e":
                                cod==4? "#a68ff2":
                                cod==5? "#ffa361":
                                cod==6? "#ffa361":
                                undefined

    function displayFields(index){
        cod = blockList.get(index).cod
        configMenu.durationVisible =    [1,2,4].includes(cod);
        configMenu.linesVisible =       [5,6].includes(cod);
        configMenu.samplesVisible =     [4,5,6].includes(cod);
        configMenu.adcVisible =         [4].includes(cod);
        configMenu.fovVisible =         [5,6].includes(cod);
        configMenu.rfVisible =          [1,6].includes(cod);
        configMenu.gradientsVisible =   [1,3,4].includes(cod);
        configMenu.tVisible =           [6].includes(cod);
        configMenu.groupVisible =       [0].includes(cod);

        // Reset all fields to safe defaults to avoid stale values
        configMenu.duration = "0";
        configMenu.lines = "0";
        configMenu.samples = "0";
        configMenu.adcDelay = "0";
        configMenu.adcPhase = "0";
        configMenu.fov = "0";
        configMenu.shape = 0;
        configMenu.b1Module = "0";
        configMenu.flipAngle = "0";
        configMenu.deltaf = "0";
        configMenu.gxDelay = "0";  configMenu.gyDelay = "0";  configMenu.gzDelay = "0";
        configMenu.gxRise = "0";   configMenu.gyRise = "0";   configMenu.gzRise = "0";
        configMenu.gxFlatTop = "0";configMenu.gyFlatTop = "0";configMenu.gzFlatTop = "0";
        configMenu.gxAmplitude = "0"; configMenu.gyAmplitude = "0"; configMenu.gzAmplitude = "0";
        configMenu.te = "0"; configMenu.tr = "0";
        configMenu.repetitions = "0"; configMenu.iterator = "";

        var blockData = blockList.get(index);

        if(configMenu.durationVisible && blockData.duration !== undefined){
            configMenu.duration = blockData.duration;
        }
        if(configMenu.linesVisible && blockData.lines !== undefined){
            configMenu.lines = blockData.lines;
        }
        if(configMenu.samplesVisible && blockData.samples !== undefined){
            configMenu.samples = blockData.samples;
        }
        if(configMenu.adcVisible){
            if(blockData.adcDelay !== undefined){ configMenu.adcDelay = blockData.adcDelay; }
            if(blockData.adcPhase !== undefined){ configMenu.adcPhase = blockData.adcPhase; }
        }
        if(configMenu.fovVisible && blockData.fov !== undefined){
            configMenu.fov = blockData.fov;
        }
        if (configMenu.rfVisible && blockData.rf && blockData.rf.count > 0){
            var rf0 = blockData.rf.get(0);
            if(rf0.shape !== undefined){ configMenu.shape = rf0.shape; }
            if(rf0.b1Module !== undefined){ configMenu.b1Module = rf0.b1Module; }
            if(rf0.flipAngle !== undefined){ configMenu.flipAngle = rf0.flipAngle; }
            if(rf0.deltaf !== undefined){ configMenu.deltaf = rf0.deltaf; }

            // Use stored select if present; otherwise infer
            if(rf0.select !== undefined){
                configMenu.select = rf0.select;
            } else {
                // Infer select based on available RF fields when select is not persisted in JSON
                // 0: flipAngle & duration; 1: flipAngle & amplitude; 2: duration & amplitude
                var hasFlip = rf0.flipAngle !== undefined;
                var hasAmp = rf0.b1Module !== undefined;
                var hasDuration = (blockData.duration !== undefined);
                var inferredSelect = 0;
                if(hasFlip && hasAmp){ inferredSelect = 1; }
                else if(!hasFlip && hasAmp){ inferredSelect = 2; }
                else if(hasFlip && !hasAmp){ inferredSelect = 0; }
                else { inferredSelect = 0; }
                configMenu.select = inferredSelect;
            }
        }
        if (configMenu.tVisible && blockData.t && blockData.t.count > 0){
            var t0 = blockData.t.get(0);
            if(t0.te !== undefined){ configMenu.te = t0.te; }
            if(t0.tr !== undefined){ configMenu.tr = t0.tr; }
        }
        if (configMenu.groupVisible){
            if(blockData.repetitions !== undefined){ configMenu.repetitions = blockData.repetitions; }
            if(blockData.iterator !== undefined){ configMenu.iterator = blockData.iterator; }
        }
        if (configMenu.gradientsVisible && blockData.gradients){
            var gradients = blockData.gradients;
            for (var i=0; i<gradients.count; i++){
                var grad = gradients.get(i);
                if(grad.axis === 'x'){
                    if(grad.delay !== undefined){ configMenu.gxDelay = grad.delay; }
                    if(grad.rise !== undefined){ configMenu.gxRise = grad.rise; }
                    if(grad.flatTop !== undefined){ configMenu.gxFlatTop = grad.flatTop; }
                    if(grad.amplitude !== undefined){ configMenu.gxAmplitude = grad.amplitude; }
                } else if(grad.axis === 'y'){
                    if(grad.delay !== undefined){ configMenu.gyDelay = grad.delay; }
                    if(grad.rise !== undefined){ configMenu.gyRise = grad.rise; }
                    if(grad.flatTop !== undefined){ configMenu.gyFlatTop = grad.flatTop; }
                    if(grad.amplitude !== undefined){ configMenu.gyAmplitude = grad.amplitude; }
                } else if(grad.axis === 'z'){
                    if(grad.delay !== undefined){ configMenu.gzDelay = grad.delay; }
                    if(grad.rise !== undefined){ configMenu.gzRise = grad.rise; }
                    if(grad.flatTop !== undefined){ configMenu.gzFlatTop = grad.flatTop; }
                    if(grad.amplitude !== undefined){ configMenu.gzAmplitude = grad.amplitude; }
                }
            }
        }
    }

    MouseArea {
        id: dragArea
        property bool held: false
        property bool hovered: false
        property bool selected: blockSeq.displayedMenu == dropIndex? true: false
        property bool dragged: false

        anchors.horizontalCenter: held? undefined: parent.horizontalCenter
        anchors.bottom: held? undefined: parent.bottom

        width:  parent.width
        height:  width

        drag.target: held? dragArea: undefined
        drag.axis: Drag.XAndYAxis

        onClicked:{ //Configuration panel will be displayed:
            if(!popup.active){

                blockSeq.focus = true;
                blockSeq.displayedMenu = dropIndex;

                configMenu.menuVisible = true;

                configMenu.blockID = dropIndex;
                configMenu.menuColor = blockColor;
                configMenu.menuTitle = blockText;

                displayFields(dropIndex);

                for(var i=0; i<blockList.count; i++){
                     collapse(i);
                }
                 expand(configMenu.blockID);

            }else{
                grouped = !grouped;
            }
        }

        hoverEnabled: true

        onEntered: {
            blockSeq.hoveredBlock = dropIndex;

            if(!blockView.held){
                if(!isChild(dropIndex)){ // If it is not a child (1st level node)
                    // Collapse all nodes so we can only see 1st level nodes
                    for (var i=0; i<blockList.count; i++){
                         collapse(i);
                    }
                }
                else { // If it is a child
                    var max = -1;
                    var min = blockSeq.displayedGroup;

                    if(min>=0){
                        for (i=0; i<blockList.get(min).children.count; i++){
                            if(blockList.get(min).children.get(i).number > max){
                                max = blockList.get(min).children.get(i).number;
                            }
                        }
                        if (dropIndex<min || dropIndex>max){
                            for (i=0; i<blockList.get(min).children.count; i++){
                                 collapse(blockList.get(min).children.get(i).number)
                            }
                            blockSeq.displayedGroup = getParent(dropIndex);
                        }
                    }
                }
                if(isGroup(dropIndex)){ // If it is a group (Note that a block could be a child and a group at the same time)
                    blockSeq.displayedGroup = dropIndex
                }

                expand(blockSeq.hoveredBlock);

                if(blockSeq.displayedMenu>=0){
                    expand(blockSeq.displayedMenu);
                }
            }
        }

        onExited: {
            dragged = false;
            if(!blockView.held){
                timer.setTimeout(function(){
                    if(dropIndex==blockSeq.hoveredBlock){
                        blockSeq.hoveredBlock = -1;
                        for (var i=0; i<blockList.count; i++){
                            if (blockList.get(i).grouped){
                                return;
                            }
                        }
                        for (i=0; i<blockList.count; i++){
                                collapse(i);
                        }

                        if(blockSeq.displayedMenu>=0){
                            expand(blockSeq.displayedMenu);
                        }
                    }
                }, 10);
            }
        }

        // ---------------------------------- DRAG AND DROP MECHANICS ---------------------------------------

        onPressed:{
            if (!window.mobile){
                dragged = true;
                if(!popup.active){
                    held = true
                    blockView.held = true;
                    blockView.dragIndex = dropIndex

                    if(isGroup(dropIndex)){
                        for(var i=0; i<blockList.get(dropIndex).children.count; i++){
                            collapse(blockList.get(dropIndex).children.get(i).number);
                        }
                    }
                }
            }
        }

        onPressAndHold:{
            if (window.mobile){
                dragged = true;
                if(!popup.active){
                    held = true
                    blockView.held = true;
                    blockView.dragIndex = dropIndex

                    if(isGroup(dropIndex)){
                        for(var i=0; i<blockList.get(dropIndex).children.count; i++){
                            collapse(blockList.get(dropIndex).children.get(i).number);
                        }
                    }
                }
            }
        }

        onReleased: {
            dragged = false;
            held = false;
            blockView.held = false;
        }

        Drag.active: held
        Drag.source: dragArea
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: height / 2

        // We define a DropArea on each element so we can determine when the hot spot of the dragged object interacts with another object
        DropArea {
            id:dropArea
            anchors {fill: parent; margins: 10}

            onEntered: {
                // Blocks must be siblings so we can move them
                if(getParent(dropIndex) === getParent(blockView.dragIndex)){
                    configMenu.menuVisible = false;
                    blockSeq.displayedMenu = -1;

                    moveBlock(blockView.dragIndex,dropIndex)
                }
            }
        } // DropArea

        RectangularGlow {
            id: itemGlow
            anchors.fill: item
            visible: !dragArea.held
            glowRadius: 4
            spread: 0.2
            color: item.color
            opacity: 0.5
            cornerRadius: item.radius + glowRadius
        }

        Rectangle {
            id: item;
            color: blockColor
            anchors.fill: parent
            anchors.margins: 10

            radius: 4

            // Block Text
            Text {
                id: textBlock
                color: "black"
                font.pointSize: 10 - 2*ngroups
                anchors{
                    horizontalCenter: parent.horizontalCenter
                    verticalCenter: parent.verticalCenter
                }
                text: blockText
             }

            Text {
                id: blockNumber
                color: "black"
                font.pointSize: 8 - ngroups
                anchors{
                    left: parent.left
                    bottom: parent.bottom
                    margins: 4
                }
                text: dropIndex
            }

            //Delete button
            DeleteButton {
                function clicked(){
                    removeBlock(index);
                    configMenu.menuVisible = false;
                    blockSeq.displayedMenu = -1;
                }

                anchors.top: parent.top
                anchors.right: parent.right

                anchors.margins:2

                height: 15 - 2*ngroups
                width:  15 - 2*ngroups
            }

        } //Rectangle

        Item{
            visible:!dragArea.held
            anchors.left:item.right
            anchors.leftMargin:6
            anchors.verticalCenter: item.verticalCenter
            height:12
            width:8
            Image{
                visible:index==blockList.count-1?false:true
                source: "qrc:/icons/arrow_gray.png"
                anchors.fill:parent
            }
        }

        states: [
            State {
                name: "held"; when: dragArea.Drag.active
                PropertyChanges{
                    target: item
                    color: Qt.darker(blockColor,1.5)
                    scale: 0.7
                    opacity: 1
                }
                PropertyChanges{
                    target: block
                    z: 100
                }
                PropertyChanges{
                    target: dropArea
                    visible:false
                }
            },

            State {
                name: "grouped"; when: grouped
                PropertyChanges{
                    target: itemGlow
                    scale: 0.8
                }
                PropertyChanges{
                    target: item
                    scale: 0.8
                }
            }, State{
                name:"selected"; when: dragArea.selected;
                PropertyChanges{
                    target: item
                    color: Qt.darker(blockColor,1.8)
                }
                PropertyChanges{
                    target: textBlock
                    font.bold: true
                    color: "white"
                }
            }, State{
                name:"dragged"; when: dragArea.dragged;
                PropertyChanges{
                    target: item
                    scale: 0.75
                }
            }
        ]

        // ANIMACIONES dependientes del cambio de estado
        transitions: [
            Transition{
                PropertyAnimation {property: "scale"; duration: 40}
                PropertyAnimation {property: "color"; duration: 80}
                AnchorAnimation { duration: 100 }
            }
        ]

    } // MouseArea
} //Item


