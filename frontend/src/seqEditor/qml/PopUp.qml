import QtQuick
import QtQuick.Controls


Item {
    id: popup

    property alias text: label.text
    property bool active: false
    property int textSize: 8

    property alias nameInput: nameInput

    function closePopUp(){
        popup.visible = false
        popup.active = false
        nameInput.text = "";
        log.text = ""
    }

    visible: false
    width: 200
    height: 150
    z: 20
    Image {
        anchors.fill: parent
        source: "qrc:/icons/balloon.png"
    }

    Column {
        id: column
        anchors.fill: parent
        anchors.margins: 25
        Text {
            id: label

            anchors.left: parent.left
            anchors.right: parent.right

            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter

            wrapMode: Text.WordWrap
            font.pointSize: popup.textSize
        }

        Item{
            width: 1
            height: 15
        }

        TextInputItem{
            id: nameInput
            anchors.left: parent.left
            anchors.right: parent.right
        }

        Text{
            id: log
            anchors.left: parent.left
            anchors.right: parent.right
            color: "red"
            wrapMode: Text.WordWrap
            font.pointSize: popup.textSize
        }
    }


    //Delete button
    DeleteButton {
        function clicked(){
            closePopUp();
            for(var i = 0; i<blockList.count; i++){
                if(blockList.get(i).grouped){
                    blockList.get(i).grouped = false;
                }
            }
        }

        y: 12
        anchors.right: parent.right

        anchors.margins:3

        height: 15
        width: 15

        color: Qt.darker(light,1.3)
    }

    //Done button
    StyledButton {
        id: doneButton
        buttonText: "Done"
        buttonWidth: 75
        buttonHeight: 25
        fontSize: popup.textSize
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: 5

        onClicked: {
            var groupedBlocks = [];
            var counter = 0;
            var lastGrouped = -1;
            var blockID = -1;
            for(var i = 0; i<blockList.count; i++){
                if(blockList.get(i).grouped){
                    if (counter != 0){
                        if ((i - lastGrouped) > 1 & !isGroup(lastGrouped)){
                            log.text = "All selected blocks must be adjacent"
                            return;
                        }
                    }else{
                        blockID = i;
                    }
                    groupedBlocks.push(i);
                    lastGrouped = i;
                    counter++;
                }
            }

            if(nameInput.text === ""){
                log.text = "No name specified"
                return;
            }

            for(var i=0; i<groupButtonList.count; i++){
                if(groupButtonList.get(i).buttonText === nameInput.text){
                    log.text = "This name already exists"
                    return;
                }
            }

            if(groupedBlocks.length <= 1){
                log.text="You must group at least 2 blocks";
                return;

            }else if(groupedBlocks.length > 1){
                for(var i = 0; i<blockList.count; i++){
                    blockList.get(i).grouped = false;
                }

                var numgroups = 0;

                for(i=0; i<groupedBlocks.length; i++){
                    for(var j=0;j<blockList.count;j++){
                        for(var k=0;k<blockList.get(j).children.count;k++){
                            // Check if the selected block already belongs to a group
                            if (blockList.get(j).children.get(k).number===groupedBlocks[i] && i>0){
                                numgroups = blockList.get(groupedBlocks[i]).ngroups;
                                blockList.get(j).children.remove(k);
                            }
                        }
                    }
                }

                for(j=0;j<blockList.count;j++){
                    for(k=0;k<blockList.get(j).children.count;k++){
                        // Check if there are more blocks that belong to an outter group but are not selected
                        if(j<getMinOfArray(groupedBlocks) && blockList.get(j).children.get(k).number>getMaxOfArray(groupedBlocks)){
                            blockList.get(j).children.get(k).number++;
                        }
                    }
                }

                blockList.append(  {"cod": 0,
                                    "name": nameInput.text,
                                    "collapsed": false,
                                    "ngroups": numgroups,
                                    "children": [],
                                    "grouped": false,
                                    "rf": [],
                                    "gradients": [],
                                    "repetitions": "1",
                                    "iterator": assignIterator()});

                for(j=blockList.count-1;j>=0;j--){
                    // Check if there are groups more to the right (we must displace their children one step to the right)
                    if(j > (getMaxOfArray(groupedBlocks) + countChildren(getMaxOfArray(groupedBlocks))) && isGroup(j)){
                        moveGroup(j,1);
                    }
                }

                blockList.move(blockList.count-1,groupedBlocks[0],1);

                for(i=0; i<groupedBlocks.length; i++){
                    blockList.get(groupedBlocks[0]).children.append({"number":groupedBlocks[i]+1});
                    addToGroup(groupedBlocks[i]+1);
                    configMenu.menuVisible = false;
                    blockSeq.displayedMenu = -1;
                }

                addGroup(nameInput.text, blockID);
                closePopUp();
            }
        }
    } //Button
}
