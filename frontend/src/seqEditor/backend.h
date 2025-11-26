#ifndef BACKEND_H
#define BACKEND_H

#include <QObject>
#include <QFileDialog>
#include <QStringList>

#include <iostream>
#include <fstream>
#include <filesystem>
#include <string>

#include <nlohmann/json.hpp>
// for convenience
using json = nlohmann::json;


#ifdef Q_OS_WASM
    #include <emscripten.h>
    #include <emscripten/html5.h>
#endif


class Backend : public QObject
{
    Q_OBJECT
public:
    explicit Backend(QObject *parent = nullptr);

private:
    bool active(int code, std::vector<int> vector);
    QByteArray parseJSONSequenceToQML(QByteArray data);
    QByteArray parseJSONScannerToQML(QByteArray data);
    QByteArray processJSONSequence(QByteArray data);

    QByteArray parseQStringtoQByteArray(QString model);

    int fileNumber = 0;

    // Helper functions for WASM callbacks - need to be accessible from extern "C" functions
    #ifdef Q_OS_WASM
    // Forward declaration for friend function
    friend void processPresetSequenceResultImpl(const char* jsonStr);
    #endif

signals:
    void uploadSequenceSelected(QString path);
    void uploadScannerSelected(QString path);
    void presetsSequencesReceived(QStringList sequences);

public slots:
    void getUploadSequence();
    void getUploadSequenceFromPresets();
    void loadPresetSequence(QString sequenceName);
    void getDownloadSequence(QString qmlModel, QString extension);

    void getUploadScanner();
    void getDownloadScanner(QString qmlModel);

    void plotSequence(QString qmlScan, QString qmlSeq);
    void plot3D(float gx, float gy, float gz, float deltaf, float gamma);
    void displayPhantom(QString filename);

    void simulate(QString qmlSeq, QString qmlScan);
};

#endif // BACKEND_H
