// Global state for simulation tracking (using localStorage for persistence)
function isSimulationInProgress() {
    return localStorage.getItem('simulationInProgress') === 'true';
}

function setSimulationInProgress(value) {
    localStorage.setItem('simulationInProgress', value.toString());
}

// Global state for reconstruction tracking (using localStorage for persistence)
function isReconstructionInProgress() {
    return localStorage.getItem('reconstructionInProgress') === 'true';
}

function setReconstructionInProgress(value) {
    localStorage.setItem('reconstructionInProgress', value.toString());
}


function komaMRIsim(seq_json, scanner_json){
    // Check if simulation is already in progress
    if (isSimulationInProgress()) {
        console.log("Simulation already in progress, ignoring new request");
        return;
    }
    
    // Set simulation state
    setSimulationInProgress(true);
    
    clearSimulationPanel();
    document.getElementById('loading-sim').style.display   = "block";

    const scannerObj = JSON.parse(scanner_json);
    const seqObj     = JSON.parse(seq_json);

    var params = {
        sequence: seqObj,
        scanner: scannerObj
    }

    // HTTP Status Codes:
    // 200: OK
    // 202: Accepted
    // 303: See other

    fetch("/simulate",{
        method: "POST",
        headers:{
            "Content-type": "application/json",
            "Authorization": "Bearer " + localStorage.token,
        },
        body: JSON.stringify(params)})
    .then(res => {
            if ((res.status == 202) && (loc = res.headers.get('location'))){
                localStorage.currentSimID = loc.split('/').pop();
                requestSimResult(loc)
            }else{
                // Error
            }
        }
    )
}

function requestSimResult(loc){
    fetch(loc + "?" + new URLSearchParams({
            width:  document.getElementById("simResult").offsetWidth,
            height: document.getElementById("simResult").offsetHeight
        }).toString(), {
            method: "GET",
            headers:{
                "Authorization": "Bearer " + localStorage.token,
            },
        })
    .then(res => {
        if (res.redirected) {
            // Caso en que se recibe un 303 (redirect)
            document.getElementById("simProgress").style.visibility = "visible";
            document.getElementById('response').style.visibility    = "visible";
            
            return res.json().then(json => {
                if (json === -1) {
                    document.getElementById('response').innerHTML = "Starting simulation...";
                } else if (json === -2){
                    //Error
                    console.log("Simulation Error");
                    // Reset simulation state on simulation failure
                    setSimulationInProgress(false);
                } else {
                    // Status Bar 
                    document.getElementById('response').innerHTML = json + "%";
                    document.getElementById('myProgress').style.visibility = "visible";
                    var elem = document.getElementById("myBar");
                    elem.style.width = json + "%";
                }
                if (json > -2 && json < 100) {
                    setTimeout(function() { requestSimResult(loc); }, 500);
                } else if (json === 100) {
                    document.getElementById('response').style.visibility   = "collapse";
                    document.getElementById('myProgress').style.visibility = "collapse";
                    setTimeout(function() { requestSimResult(loc); }, 500);
                } 
            }).then(() => { return; });  // 🔹 IMPORTANTE: Evita que el flujo siga al siguiente .then()
        } if (res.ok) {
            clearSimulationPanel();
            return res.text();
        } if (res.status == 500) {
            clearSimulationPanel();
            // Reset simulation state on error
            setSimulationInProgress(false);
            return res.json().then(json => {
                document.getElementById("errorMsg").textContent =
                    "Simulation failed in KomaMRI: the provided sequence could not be simulated or reconstructed.\nDetails:\n" + json.msg;
            }).then(() => { return; });
        } throw new Error('Request error');
    })
    .then(html => {
        if (!html) return;
        var iframe = document.getElementById("simResult")
        iframe.srcdoc = html;
        iframe.onload = function() {
            document.getElementById('loading-sim').style.display = "none";
            // Set result mode to signal and show it
            setResultMode('signal');
            // Show reconstruct button when simulation is complete
            document.getElementById('reconstructButton').style.display = 'block';
            // Reset simulation state on success
            setSimulationInProgress(false);
        };
    })
    .catch(error => {
        console.error("Error in the request:", error);
        // Reset simulation state on network error
        setSimulationInProgress(false);
    });   
}

function komaMRIrecon(){
    // Check if reconstruction is already in progress
    if (isReconstructionInProgress()) {
        console.log("Reconstruction already in progress, ignoring new request");
        return;
    }
    
    // Set reconstruction state
    setReconstructionInProgress(true);
    
    clearSimulationPanel();
    document.getElementById('loading-sim').style.display = "block";

    const simID = localStorage.currentSimID;
    const reconstructUrl = `/recon/${simID}`;
    
    // First, start the reconstruction
    fetch(reconstructUrl, {
        method: "POST",
        headers: {
            "Authorization": "Bearer " + localStorage.token,
        },
    })
    .then(res => {
        if (res.status == 202) {
            const location = res.headers.get('location');
            if (location) {
                requestReconResult(location);
            }
        } else {
            throw new Error('Failed to start reconstruction');
        }
    })
    .catch(error => {
        console.error("Error starting reconstruction:", error);
        document.getElementById("errorMsg").textContent = 
            "Failed to start reconstruction: " + error.message;
    });
}

function requestReconResult(loc){
    fetch(loc + "?" + new URLSearchParams({
        width:  document.getElementById("imageResult").offsetWidth,
        height: document.getElementById("imageResult").offsetHeight
    }).toString(), {
        method: "GET",
        headers:{
            "Authorization": "Bearer " + localStorage.token,
        },
    })
    .then(res => {
        if (res.redirected) {
            document.getElementById('response').style.visibility    = "visible";

            return res.json().then(json => {
                if (json < 100) {     // Error
                    console.log("Reconstruction Error");
                    // Reset reconstruction state on error
                    setReconstructionInProgress(false);
                } if (json === 100) { // Reconstruction not finished
                    document.getElementById('response').innerHTML = "Reconstructing...";
                    setTimeout(function() { requestReconResult(loc); }, 500);
                }
                if (json === 101) {   // Reconstruction finished
                    setTimeout(function() { requestReconResult(loc); }, 500);
                } 
            }).then(() => { return; }); 
        } if (res.ok) {
            clearSimulationPanel();
            document.getElementById("resultToggle").style.display = "block";
            return res.json();
        } if (res.status == 500) {
            clearSimulationPanel();
            // Reset reconstruction state on error
            setReconstructionInProgress(false);
            return res.json().then(json => {
                document.getElementById("errorMsg").textContent = 
                    "Reconstruction failed in KomaMRI: the provided sequence could not be reconstructed.\nDetails:\n" + json.msg;
            }).then(() => { return; });
        } throw new Error('Request error');
    })
    .then(data => {
        if (!data) return;

        var img_frame    = document.getElementById("imageResult")
        var kspace_frame = document.getElementById("kspaceResult")

        img_frame.srcdoc = data.image_html;
        kspace_frame.srcdoc = data.kspace_html;

         img_frame.onload = function() { 
             document.getElementById('loading-sim').style.display = "none";
             // Set result mode to image and show it
             setResultMode('image');
             // Reset reconstruction state on success
             setReconstructionInProgress(false);
         };

         kspace_frame.onload = function() {
             document.getElementById('loading-sim').style.display = "none";
         };
    })
    .catch(error => {
        console.error("Error in the request:", error);
        // Reset reconstruction state on network error
        setReconstructionInProgress(false);
    });   
}

function clearSimulationPanel() {
    document.getElementById("simProgress").style.visibility  = "collapse";
    document.getElementById('response').style.visibility     = "collapse";
    document.getElementById('myProgress').style.visibility   = "collapse";
    document.getElementById("myBar").style.width             = "0%";
    document.getElementById("errorMsg").innerHTML            = "";
    document.getElementById('loading-sim').style.display     = "none";
    document.getElementById("simResult").style.visibility    = "hidden";
    document.getElementById("imageResult").style.visibility  = "hidden";
    document.getElementById("kspaceResult").style.visibility = "hidden";
}

function plot_seq(scanner_json, seq_json){
    const scannerObj = JSON.parse(scanner_json);
    const seqObj     = JSON.parse(seq_json);

    // Combina los dos objetos en uno solo
    const combinedObj = {
        scanner: scannerObj,
        sequence: seqObj,
        height: document.getElementById("seqDiagram").offsetHeight,
        width: document.getElementById("seqDiagram").offsetWidth,
    };

    const sequenceFrame = document.getElementById("seqDiagram");
    const kspaceFrame = document.getElementById("kspaceDiagram");
    const errorBox = document.getElementById("seqErrorMsg");

    // Hide both frames initially
    sequenceFrame.style.visibility = "hidden";
    kspaceFrame.style.visibility = "hidden";
    document.getElementById("loading-seq").style.display = "block";   

    // Create temporary listeners that don't force visibility
    const onSequenceLoad = () => {
        sequenceFrame.removeEventListener("load", onSequenceLoad);
    };

    const onKspaceLoad = () => {
        kspaceFrame.removeEventListener("load", onKspaceLoad);
    };

    sequenceFrame.addEventListener("load", onSequenceLoad);
    kspaceFrame.addEventListener("load", onKspaceLoad);

    fetch("/plot_sequence", {
        method: "POST",
        headers: {
            "Content-type": "application/json",
            "Authorization": "Bearer " + localStorage.token,
        },
        body: JSON.stringify(combinedObj)
    })
    .then(res => {
        document.getElementById("loading-seq").style.display = "none";

        if (res.ok) {
            return res.json();
        } else {
            return res.json().then(json => {
                throw new Error(json.msg);
            });
        }
    })
    .then(data => {
        // Load both HTMLs into their respective iframes
        sequenceFrame.srcdoc = data.seq_html;
        kspaceFrame.srcdoc = data.kspace_html;
        
        // Show the toggle after successful plot
        document.getElementById('seqToggle').style.display = 'block';
        
        // Show the currently selected mode (don't force change to sequence)
        const currentMode = getSeqMode();
        showSeqFrame(currentMode);
        
        errorBox.textContent = "";
    })
    .catch(error => {
        sequenceFrame.style.visibility = "hidden";
        kspaceFrame.style.visibility = "hidden";
        errorBox.textContent = 
            "Failed to plot sequence: the provided sequence could not be plotted.\nDetails:\n" + error.message;
    });
}

function logout() {
    fetch('/logout')
        .then(res => {
            if (res.status == 200) {
                console.log("Esto va bien?");
                localStorage.clear();
                setTimeout(() => {location.href = "/login";}, 0);
            }
        });
}

function loadUser() {
    const userText = document.getElementById("user-menu-text");
    userText.innerHTML = "Hi, " + localStorage.username;
}

function getResultMode(){
    return localStorage.getItem('resultMode') || 'image'
}

function setResultMode(mode){
    localStorage.setItem('resultMode', mode)
    showResultFrame(mode)
    
    // Update the toggle visual selection
    const resultToggle = document.getElementById('resultToggle')
    if(resultToggle){
        resultToggle.value = mode
    }
}

function showResultFrame(mode) {
    // Hide all result frames first
    const signalFrame = document.getElementById("simResult")
    const imageFrame = document.getElementById("imageResult") 
    const kspaceFrame = document.getElementById("kspaceResult")
    
    if (signalFrame) signalFrame.style.visibility = "hidden"
    if (imageFrame) imageFrame.style.visibility = "hidden"
    if (kspaceFrame) kspaceFrame.style.visibility = "hidden"
    
    // Show the selected frame
    switch(mode) {
        case 'signal':
            if (signalFrame) signalFrame.style.visibility = "visible"
            break
        case 'image':
            if (imageFrame) imageFrame.style.visibility = "visible"
            break
        case 'kspace':
            if (kspaceFrame) kspaceFrame.style.visibility = "visible"
            break
    }
}

// Initialize result toggle when DOM is loaded
function initializeResultToggle() {
    const resultToggle = document.getElementById('resultToggle')
    if(resultToggle){
        resultToggle.value = getResultMode()
        setResultMode(resultToggle.value)
        resultToggle.addEventListener('change', (e) => setResultMode(e.target.value))
    }
}

// Call initialization when DOM is ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initializeResultToggle)
} else {
    initializeResultToggle()
}

// ==================== SEQUENCE TOGGLE FUNCTIONS ====================

function getSeqMode(){
    return localStorage.getItem('seqMode') || 'sequence'
}

function setSeqMode(mode){
    localStorage.setItem('seqMode', mode)
    showSeqFrame(mode)
    
    // Update the toggle visual selection
    const seqToggle = document.getElementById('seqToggle')
    if(seqToggle){
        seqToggle.value = mode
        // If this is the first time showing the toggle, initialize it properly
        if(seqToggle.style.display === 'block' && !seqToggle.hasAttribute('data-initialized')){
            seqToggle.setAttribute('data-initialized', 'true')
        }
    }
}

function showSeqFrame(mode) {
    // Hide all sequence frames first
    const sequenceFrame = document.getElementById("seqDiagram")
    const kspaceFrame = document.getElementById("kspaceDiagram")
    
    if (sequenceFrame) sequenceFrame.style.visibility = "hidden"
    if (kspaceFrame) kspaceFrame.style.visibility = "hidden"
    
    // Show the selected frame
    switch(mode) {
        case 'sequence':
            if (sequenceFrame) sequenceFrame.style.visibility = "visible"
            break
        case 'kspace':
            if (kspaceFrame) kspaceFrame.style.visibility = "visible"
            break
    }
}

// Initialize sequence toggle when DOM is loaded
function initializeSeqToggle() {
    const seqToggle = document.getElementById('seqToggle')
    if(seqToggle){
        // Only initialize if the toggle is visible (has been shown after plot)
        if(seqToggle.style.display !== 'none' && seqToggle.style.display !== ''){
            seqToggle.value = getSeqMode()
            setSeqMode(seqToggle.value)
        }
        // Always add the event listener
        seqToggle.addEventListener('change', (e) => setSeqMode(e.target.value))
    }
}

// Call initialization when DOM is ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initializeSeqToggle)
} else {
    initializeSeqToggle()
}

// ==================== SIMULATION RECOVERY ====================

function checkAndResumeSimulation() {
    // Check if there's a simulation in progress
    if (isSimulationInProgress() && localStorage.currentSimID) {
        console.log("Resuming simulation with ID:", localStorage.currentSimID);
        
        // Show loading indicator
        document.getElementById('loading-sim').style.display = "block";
        
        // Resume the simulation polling
        const simID = localStorage.currentSimID;
        const loc = `/simulate/${simID}`;
        requestSimResult(loc);
    }
}

function checkAndResumeReconstruction() {
    // Check if there's a reconstruction in progress
    if (isReconstructionInProgress() && localStorage.currentSimID) {
        console.log("Resuming reconstruction with ID:", localStorage.currentSimID);
        
        // Show loading indicator
        document.getElementById('loading-sim').style.display = "block";
        
        // Resume the reconstruction polling
        const simID = localStorage.currentSimID;
        const loc = `/recon/${simID}`;
        requestReconResult(loc);
    }
}

// Call recovery functions when DOM is ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
        checkAndResumeSimulation();
        checkAndResumeReconstruction();
    })
} else {
    checkAndResumeSimulation();
    checkAndResumeReconstruction();
}