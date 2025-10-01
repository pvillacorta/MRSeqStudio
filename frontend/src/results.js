function showMsg(text, error = true) {
    const msg = document.getElementById("msg");
    msg.textContent = text;
    msg.className = `msg ${error ? 'error' : 'success'}`;
    msg.style.display = "block";
    setTimeout(() => { msg.style.display = "none"; }, 5000);
}

function loadUserResults() {
    fetch("/api/results", { 
        headers: {
            "Authorization": "Bearer " + localStorage.token
        }
    })
    .then(res => {
        if (!res.ok) throw new Error("Could not load results");
        return res.json();
    })
    .then(results => {
        const panel = document.getElementById("resultsPanel");
        const statsPanel = document.getElementById("resultsStats");
        
        panel.innerHTML = "";
        
        if (results.length === 0) {
            panel.innerHTML = `
                <div class="empty-state">
                    <h3>No Results Found</h3>
                    <p>You don't have any saved results yet.</p>
                </div>
            `;
            statsPanel.style.display = "none";
            return;
        }

        // Show stats
        updateStats(results);
        statsPanel.style.display = "flex";

        // Render results
        results.forEach(result => {
            const row = document.createElement("div");
            row.className = "result-row";
            
            const createdDate = new Date(result.created_at);
            const formattedDate = createdDate.toLocaleDateString('en-US', {
                year: 'numeric',
                month: 'short',
                day: 'numeric',
                hour: '2-digit',
                minute: '2-digit'
            });
            
            row.innerHTML = `
                <div class="result-info">
                    <div class="result-name">Result ID: ${result.id}</div>
                    <div class="result-seq">Sequence: ${result.sequence_id}</div>
                    <div class="result-date">Created: ${formattedDate}</div>
                </div>
                <div class="result-actions">
                    <button class="btn btn-success" onclick="downloadResult(${result.id})">📥 Download</button>
                    <button class="btn btn-danger" onclick="deleteResult(${result.id})">🗑️ Delete</button>
                </div>
            `;
            panel.appendChild(row);
        });
    })
    .catch(err => {
        showMsg(err.message);
        document.getElementById("resultsPanel").innerHTML = `
            <div class="empty-state">
                <h3>Error Loading Results</h3>
                <p>There was an error loading your results. Please try again later.</p>
            </div>
        `;
    });
}

function updateStats(results) {
    const totalResults = results.length;
    
    // Calculate total size - handle different possible field names and units
    const totalSize = results.reduce((sum, result) => {
        let size = 0;
        
        // Try different possible field names for file size
        if (result.file_size_mb) {
            size = result.file_size_mb; // Already in MB
        } else if (result.file_size_kb) {
            size = result.file_size_kb / 1024; // Convert KB to MB
        } else if (result.file_size_bytes) {
            size = result.file_size_bytes / (1024 * 1024); // Convert bytes to MB
        } else if (result.file_size) {
            // Assume it's in bytes if no unit specified
            size = result.file_size / (1024 * 1024);
        } else if (result.size) {
            // Generic size field
            size = result.size / (1024 * 1024);
        }
        
        return sum + size;
    }, 0);
    
    const lastResult = results.length > 0 ? 
        new Date(Math.max(...results.map(r => new Date(r.created_at)))).toLocaleDateString('en-US', {
            month: 'short',
            day: 'numeric'
        }) : '-';

    document.getElementById("totalResults").textContent = totalResults;
    document.getElementById("totalSize").textContent = totalSize.toFixed(1) + " MB";
    document.getElementById("lastResult").textContent = lastResult;
}

function downloadResult(id) {
    window.location.href = `/api/results/${id}/download`;
}

function deleteResult(id) {
    if (!confirm("Are you sure you want to delete this result? This action cannot be undone.")) return;
    
    // Show loading state
    const button = event.target;
    const originalText = button.innerHTML;
    button.innerHTML = "⏳ Deleting...";
    button.disabled = true;
    
    fetch(`/api/results/${id}`, {
        method: "DELETE",
        headers: {
            "Authorization": "Bearer " + localStorage.token
        }
    })
    .then(res => {
        if (res.ok) {
            showMsg("Result deleted successfully", false);
            loadUserResults();
        } else {
            res.json().then(data => showMsg(data.error || "Could not delete the result"));
        }
    })
    .catch(() => showMsg("Error deleting the result"))
    .finally(() => {
        button.innerHTML = originalText;
        button.disabled = false;
    });
}

document.addEventListener("DOMContentLoaded", loadUserResults);


