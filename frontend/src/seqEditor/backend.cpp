#include "backend.h"

using namespace std;

Backend::Backend(QObject *parent)
    : QObject{parent}
{}

bool Backend::active(int code, std::vector<int> vector){
    return std::find(vector.begin(), vector.end(), code) != vector.end();
}

// Private
QByteArray Backend::processJSONSequence(QByteArray data){
    std::string str = QString(data).toStdString();
    json j = json::parse(str);
    QByteArray processedData;

    for (auto& block : j["blocks"]) {
        int code = block["cod"];
        int cont = 0;

        // Verificar si el valor 'code' está presente en cada vector
        bool durationActive = this->active(code,{1, 2, 4});
        bool linesActive = this->active(code,{5, 6});
        bool samplesActive = this->active(code,{4, 5, 6});
        bool adcActive = this->active(code,{4});
        bool fovActive = this->active(code,{5, 6});
        bool rfActive = this->active(code,{1, 6});
        bool gradientsActive = this->active(code,{1, 3, 4});
        bool tActive = this->active(code,{6});
        bool groupActive = this->active(code,{0});

        block.erase("collapsed");
        block.erase("grouped");

        if(rfActive){
            cont = 0;
            for (auto& rf : block["rf"]) {
                int select = rf["select"];
                switch(select){
                case 0: //FLip angle and duration
                    rf.erase("b1Module");
                    break;
                case 1: // Flip angle and amplitude
                    block.erase("duration");
                    break;
                case 2: // Duration and amplitude
                    rf.erase("flipAngle");
                    break;
                }
                rf.erase("select");
            }
        } else {
            block.erase("rf");
        }

        if(!durationActive){
            block.erase("duration");
        }

        if(!linesActive){
            block.erase("lines");
        }

        if(!samplesActive){
            block.erase("samples");
        }

        if(!adcActive){
            block.erase("adcDelay");
            block.erase("adcPhase");
        }

        if(!fovActive){
            block.erase("fov");
        }

        if(!gradientsActive){
            block.erase("gradients");
        }

        if(!tActive){
            block.erase("t");
        }

        if(!groupActive){
            block.erase("repetitions");
            block.erase("iterator");
        }

        // More processing if necessary
    }

    processedData.append(j.dump(4));
    return processedData;
}

QByteArray Backend::parseJSONSequenceToQML(QByteArray data){
    std::string str = QString(data).toStdString();
    json j = json::parse(str);
    json blocksArray    = j["blocks"];
    json variablesArray = j["variables"];

    QByteArray qmlData;

    qmlData.append("import QtQuick \n");
    qmlData.append("ListModel{ \n");
    qmlData.append("    id: sequence \n");
    qmlData.append("    property string description: " + j["description"].dump() + " \n");
    qmlData.append("    property var variables: [ \n");
    for (const auto& variable : variablesArray) {
        qmlData.append("            { \n");  
        qmlData.append("                name: "       + variable["name"].dump()           + ", \n");  
        qmlData.append("                expression: " + variable["expression"].dump()     + ", \n");  
        qmlData.append("                value: "      + variable["value"].dump()          + ", \n");  
        qmlData.append("                readonly: "   + variable["readonly"].dump()       + "  \n"); 
        qmlData.append("            }, \n"); 
    }
    qmlData.append("    ] \n");

    // Iterar sobre los elementos de la matriz "blocks"

    for (const auto& block : blocksArray) {
        int code = block["cod"];
        int cont = 0;

        // Verificar si el valor 'code' está presente en cada vector
        bool durationActive = this->active(code,{1, 2, 4});
        bool linesActive = this->active(code,{5, 6});
        bool samplesActive = this->active(code,{4, 5, 6});
        bool adcActive = this->active(code,{4});
        bool fovActive = this->active(code,{5, 6});
        bool rfActive = this->active(code,{1, 6});
        bool gradientsActive = this->active(code,{1, 3, 4});
        bool tActive = this->active(code,{6});
        bool groupActive = this->active(code,{0});

        qmlData.append("    ListElement { \n");
        qmlData.append("        cod: " + block["cod"].dump() + " \n");
        qmlData.append("        name: " + block["name"].dump() + " \n");
        qmlData.append("        ngroups: " + block["ngroups"].dump() + " \n");
        qmlData.append("        grouped: false \n");
        qmlData.append("        collapsed: false \n");

        qmlData.append("        children: [");
        json childrenArray = block["children"];
        cont = 0;
        if(childrenArray.size()>0){
            for (const auto& child : childrenArray) {
                cont++;
                qmlData.append("\n            ListElement { number: " + child["number"].dump() + " }");
                if(cont<childrenArray.size()){
                    qmlData.append(",");
                } else {
                    qmlData.append("\n");
                }
            }
            qmlData.append("        ");
        }
        qmlData.append("] \n");

        if(durationActive & (code != 1)){
            qmlData.append("        duration: " + block["duration"].dump() + " \n");
        }

        if(linesActive){
            qmlData.append("        lines: " + block["lines"].dump() + " \n");
        }

        if(adcActive){
            qmlData.append("        adcDelay: " + block["adcDelay"].dump() + " \n");
            qmlData.append("        adcPhase: " + block["adcPhase"].dump() + " \n");
        }

        if(samplesActive){
            qmlData.append("        samples: " + block["samples"].dump() + " \n");
        }

        if(fovActive){
            qmlData.append("        fov: " + block["fov"].dump() + " \n");
        }


        qmlData.append("        rf: [");
        int select = 1;
        if(rfActive){
            json rfArray = block["rf"];
            cont = 0;
            for (const auto& rf : rfArray) {
                bool flipAngle, b1Module = false;

                cont ++;
                qmlData.append("\n            ListElement { \n");
                qmlData.append("                shape: " +      rf["shape"].dump() + "\n");
                if (rf.find("flipAngle") != rf.end()){
                    qmlData.append("                flipAngle: " +  rf["flipAngle"].dump() + "\n");
                    flipAngle = true;
                }
                if (rf.find("b1Module") != rf.end()){
                    qmlData.append("                b1Module: " +   rf["b1Module"].dump() + "\n");
                    b1Module = true;
                }
                qmlData.append("                deltaf: " +     rf["deltaf"].dump() + "\n");

                if (flipAngle & b1Module){
                    select = 1;
                } else if (flipAngle & !b1Module){
                    select = 0;
                } else if (!flipAngle) {
                    select = 2;
                }

                qmlData.append("                select: " +     to_string(select) + "\n");

                if(cont<rfArray.size()){
                    qmlData.append("            },");
                } else {
                    qmlData.append("            } \n");
                }
            }
            qmlData.append("        ");
        }
        qmlData.append("] \n");

        if (code==1 & select !=1){
            qmlData.append("        duration: " + block["duration"].dump() + " \n");
        }


        qmlData.append("        gradients: [");
        if (gradientsActive) {
            json gradientsArray = block["gradients"];
            cont = 0;
            for (const auto& gradient : gradientsArray) {
                cont++;
                qmlData.append("\n            ListElement { \n");
                qmlData.append("                axis: " +       gradient["axis"].dump() + "\n");
                qmlData.append("                delay: " +      gradient["delay"].dump() + "\n");
                qmlData.append("                rise: " +       gradient["rise"].dump() + "\n");
                qmlData.append("                flatTop: " +    gradient["flatTop"].dump() + "\n");
                qmlData.append("                amplitude: " +  gradient["amplitude"].dump() + "\n");
                if(cont<gradientsArray.size()){
                    qmlData.append("            },");
                } else {
                    qmlData.append("            } \n");
                }
            }
            qmlData.append("        ");
        }
        qmlData.append("] \n");

        qmlData.append("        t: [");
        if(tActive){
            json tArray = block["t"];
            cont = 0;
            for (const auto& t : tArray) {
                cont++;
                qmlData.append("\n            ListElement { \n");
                qmlData.append("                te: " + t["te"].dump() + "\n");
                qmlData.append("                tr: " + t["tr"].dump() + "\n");
                if(cont<tArray.size()){
                    qmlData.append("            },");
                } else {
                    qmlData.append("            } \n");
                }
            }
            qmlData.append("        ");
        }
        qmlData.append("] \n");

        if(groupActive){
            qmlData.append("        repetitions: " + block["repetitions"].dump() + " \n");
            qmlData.append("        iterator: " + block["iterator"].dump() + " \n");
        }

        qmlData.append("    } \n");
    }
    qmlData.append("} \n");

    return qmlData;
}

QByteArray Backend::parseJSONScannerToQML(QByteArray data){
    std::string str = QString(data).toStdString();
    json j = json::parse(str);
    json variablesArray = j["variables"];
    json parameters     = j["parameters"];
    QByteArray qmlData;

    qmlData.append("import QtQuick \n");
    qmlData.append("Item{ \n");
    qmlData.append("    id: scanner \n");
    qmlData.append("    property var parameters: ({ \n");
    int paramCount = 0;
    for (const auto& [key, value]  : parameters.items()) {
        qmlData.append("        " + key + ": " + value.dump());
        if (++paramCount < parameters.size()) {
            qmlData.append(", \n");
        } else {
            qmlData.append(" \n");
        }
    }
    qmlData.append("    }) \n");
    qmlData.append("    property var variables: [ \n");
    for (const auto& variable : variablesArray) {
        qmlData.append("            { \n");  
        qmlData.append("                name: "       + variable["name"].dump()           + ", \n");  
        qmlData.append("                expression: " + variable["expression"].dump()     + ", \n");  
        qmlData.append("                value: "      + variable["value"].dump()          + ", \n");  
        qmlData.append("                readonly: "   + variable["readonly"].dump()       + "  \n"); 
        qmlData.append("            }, \n"); 
    }
    qmlData.append("    ] \n");
    qmlData.append("} \n");

    return qmlData;
}

QByteArray Backend::parseQStringtoQByteArray(QString model){
    QByteArray data;
    std::string str = model.toStdString();
    json j = json::parse(str);
    std::string s = j.dump();
    data.append(s);
    return data;
}

// WebAssembly
#ifdef Q_OS_WASM
EM_JS(void, plot_sequence, (const char* scanModel, const char* seqModel), {
    plot_seq(UTF8ToString(scanModel), UTF8ToString(seqModel));
})
EM_JS(void, plot_3d, (float gx, float gy, float gz, float deltaf, float gamma), {
    setNormalPlane(gx, gy, gz, deltaf, gamma);
})
EM_JS(void, display_phantom, (const char* filename), {
    displayVolume(UTF8ToString(filename));
})
EM_JS(void, sim_js, (const char* seqModel, const char* scanModel), {
    komaMRIsim(UTF8ToString(seqModel), UTF8ToString(scanModel));
})
#endif

// Slots
void Backend::getUploadSequence(){
    QFileDialog::getOpenFileContent("(*.json *.qml)", [this](const QString &fileName, const QByteArray &data){
        if (fileName.isEmpty()) {
            // No file was selected
        } else {
            QByteArray qmlData;
            std::string name = fileName.toStdString();
            // Encuentra la posición del último punto en la cadena
            size_t lastDotPosition = name.find_last_of('.');

            // Verifica si se encontró un punto y extrae la extensión
            if (lastDotPosition != std::string::npos) {
                std::string extension = name.substr(lastDotPosition + 1);
                if (extension == "json"){
                    qmlData = parseJSONSequenceToQML(data);
                } else {
                    qmlData = data;
                }
            } else {
                std::cout << "No se encontró ningún punto en la ruta del archivo." << std::endl;
                return;
            }

            // std::cout << qmlData.data();

            #ifdef Q_OS_WASM
                EM_ASM({
                    var tempFileName = $2 + ".qml";
                    var stream = FS.open(tempFileName,'w');
                    var dataPtr = $0; // Obtén el puntero al inicio del bloque de datos
                    var dataSize = $1; // Obtén el tamaño de los datos
                    FS.write(stream, HEAPU8, dataPtr, dataSize, 0);
                    FS.close(stream);
                }, qmlData.data(), qmlData.size(), fileNumber);
                emit this->uploadSequenceSelected("file://" + QString::fromStdString(to_string(fileNumber)) + ".qml");
            #else
                #ifdef _WIN32
                    std::string tempFileName =  std::filesystem::temp_directory_path().string() + std::to_string(fileNumber) + ".qml";
                #elif linux
                    std::string tempFileName =  std::filesystem::temp_directory_path().string() + "/" + std::to_string(fileNumber) + ".qml";
                #endif

                ofstream MyFile(tempFileName);

                // Write to the file
                MyFile << qmlData.toStdString();

                // Close the file
                MyFile.close();

                emit this->uploadSequenceSelected("file://"+QString::fromStdString(tempFileName));
            #endif
            fileNumber++;
        }
    });
}

void Backend::getUploadScanner(){
    QFileDialog::getOpenFileContent("(*.json)", [this](const QString &fileName, const QByteArray &data){
        if (fileName.isEmpty()) {
            // No file was selected
        } else {
            QByteArray qmlData;
            qmlData = parseJSONScannerToQML(data);

            // std::cout << qmlData.data();

            #ifdef Q_OS_WASM
                EM_ASM({
                    var tempFileName = $2 + ".qml";
                    var stream = FS.open(tempFileName,'w');
                    var dataPtr = $0; // Obtén el puntero al inicio del bloque de datos
                    var dataSize = $1; // Obtén el tamaño de los datos
                    FS.write(stream, HEAPU8, dataPtr, dataSize, 0);
                    FS.close(stream);
                }, qmlData.data(), qmlData.size(), fileNumber);
                emit this->uploadScannerSelected("file:///" + QString::fromStdString(to_string(fileNumber)) + ".qml");
            #else
                #ifdef _WIN32
                    std::string tempFileName =  std::filesystem::temp_directory_path().string() + std::to_string(fileNumber) + ".qml";
                #elif linux
                    std::string tempFileName =  std::filesystem::temp_directory_path().string() + "/" + std::to_string(fileNumber) + ".qml";
                #endif
                ofstream MyFile(tempFileName);

                // Write to the file
                MyFile << qmlData.toStdString();

                // Close the file
                MyFile.close();

                emit this->uploadScannerSelected("file:///"+QString::fromStdString(tempFileName));
            #endif

            fileNumber++;
        }
    });
}

void Backend::getDownloadSequence(QString qmlModel, QString extension){
    QByteArray data;
    std::string str = qmlModel.toStdString();
    json j = json::parse(str);
    std::string s = j.dump(4);
    data.append(s);
    if(extension == "json"){
        QFileDialog::saveFileContent(processJSONSequence(data), "Sequence.json");
    } else if(extension == "qml"){
        QFileDialog::saveFileContent(parseJSONSequenceToQML(processJSONSequence(data)), "Sequence.qml");
    }
}

void Backend::getDownloadScanner(QString qmlModel){
    QByteArray data;
    std::string str = qmlModel.toStdString();
    json j = json::parse(str);
    std::string s = j.dump(4);
    data.append(s);
    QFileDialog::saveFileContent(data, "Scanner.json");
}

void Backend::plotSequence(QString qmlScan, QString qmlSeq){
    #ifdef Q_OS_WASM
        QByteArray scanData = parseQStringtoQByteArray(qmlScan);
        QByteArray seqData  = processJSONSequence(parseQStringtoQByteArray(qmlSeq));

        plot_sequence(QString(scanData).toStdString().c_str(), QString(seqData).toStdString().c_str());
    #endif
}

void Backend::plot3D(float gx, float gy, float gz, float deltaf, float gamma){
    #ifdef Q_OS_WASM
        plot_3d(gx, gy, gz, deltaf, gamma);
    #endif
}

void Backend::displayPhantom(QString filename){
    #ifdef Q_OS_WASM
        display_phantom(filename.toStdString().c_str());
    #endif
}

void Backend::simulate(QString qmlSeq, QString qmlScan){
    #ifdef Q_OS_WASM
        QByteArray seqData      = processJSONSequence(parseQStringtoQByteArray(qmlSeq));
        QByteArray scanData     = parseQStringtoQByteArray(qmlScan);
        sim_js(QString(seqData).toStdString().c_str(), QString(scanData).toStdString().c_str());
    #endif
}