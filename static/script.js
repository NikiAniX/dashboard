let cachedLogs = "No execution logs recorded.";

function openDecryptModal() {
    document.getElementById('decryptModal').style.display = 'flex';
}

function closeDecryptModal() {
    document.getElementById('decryptModal').style.display = 'none';
}

function viewLogs(task) {
    document.getElementById('logsModal').style.display = 'flex';
    document.getElementById('modalLogsContent').textContent = cachedLogs;
}

function closeLogsModal() {
    document.getElementById('logsModal').style.display = 'none';
}

document.addEventListener('DOMContentLoaded', () => {
    const decryptForm = document.getElementById('modalDecryptForm');
    if (decryptForm) {
        decryptForm.addEventListener('submit', async function(e) {
            e.preventDefault();
            closeDecryptModal();

            const formData = new FormData();
            formData.append('pdf', document.getElementById('modalPdf').files[0]);
            formData.append('password', document.getElementById('modalPassword').value);
            formData.append('encrypted_folder', document.getElementById('modalEncryptedFolder').value);
            formData.append('decrypted_folder', document.getElementById('modalDecryptedFolder').value);

            cachedLogs = "Executing task /decrypt...\nUploading file...";

            try {
                const response = await fetch('/decrypt', {
                    method: 'POST',
                    body: formData
                });
                const result = await response.json();
                cachedLogs = `Status: ${result.status.toUpperCase()}\n\nLogs:\n` + result.logs.join('\n');
            } catch (err) {
                cachedLogs = "Error executing request: " + err.message;
            }

            document.getElementById('lastRun-decrypt').textContent = new Date().toLocaleTimeString();
            viewLogs('decrypt');
        });
    }
});