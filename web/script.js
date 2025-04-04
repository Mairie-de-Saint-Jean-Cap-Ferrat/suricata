document.addEventListener('DOMContentLoaded', () => {
    const logContent = document.getElementById('log-content');
    const refreshButton = document.getElementById('refresh-log');
    const statusMessage = document.getElementById('status-message'); // Get status element

    const fetchLogs = async () => {
        logContent.textContent = 'Chargement des logs...';
        try {
            // Attempt to fetch eve.json as it's often the most useful
            const response = await fetch('/logs/eve.json');
            if (!response.ok) {
                // If eve.json fails, try suricata.log
                 const responseLog = await fetch('/logs/suricata.log');
                 if (!responseLog.ok) {
                    throw new Error(`Erreur HTTP! status: ${response.status} et ${responseLog.status}`);
                 }
                 const text = await responseLog.text();
                 logContent.textContent = text || 'suricata.log est vide ou non trouvé.';
            } else {
                const text = await response.text();
                // Displaying raw JSON isn't ideal, but simple for now
                // Attempt to pretty-print if it's JSON
                try {
                    const jsonData = JSON.parse(text);
                    logContent.textContent = JSON.stringify(jsonData, null, 2);
                } catch (jsonError) {
                    // If it's not JSON or parsing fails, display as plain text
                    logContent.textContent = text || 'eve.json est vide ou non trouvé.';
                }
            }
        } catch (error) {
            console.error('Erreur lors de la récupération des logs:', error);
            logContent.textContent = `Erreur lors du chargement des logs. Vérifiez la console et si les fichiers logs existent dans /logs/. Erreur: ${error.message}`;
        }
    };

    if (refreshButton) {
        refreshButton.addEventListener('click', fetchLogs);
    }

    // Initial load
    fetchLogs();

    // --- Backend API Interaction --- 
    const sendCommandToBackend = async (command, args = null) => {
        statusMessage.textContent = `Envoi de la commande ${command}...`;
        const payload = { command: command };
        if (args) {
            payload.arguments = args;
        }

        try {
            // Assuming backend runs on the same host, different port (5001)
            // Adjust if your backend runs elsewhere
            const response = await fetch('/api/command', { 
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(payload)
            });
            
            const result = await response.json(); // Always expect JSON back from our Flask API

            if (!response.ok || result.return === 'FAILED') {
                 // Use message from backend if available
                throw new Error(result.message || `Erreur HTTP! status: ${response.status}`);
            }
            
            // Display success and the message from Suricata's response
            statusMessage.textContent = `Commande ${command} réussie: ${JSON.stringify(result.message || result)}`; // Show the actual response message
            console.log("Backend response:", result);

        } catch (error) {
            console.error(`Erreur lors de l'envoi de la commande ${command}:`, error);
            statusMessage.textContent = `Erreur commande ${command}: ${error.message}`;
        }
    };

    // --- Control Button Event Listeners --- 
    const reloadBtn = document.getElementById('reload-btn');
    const shutdownBtn = document.getElementById('shutdown-btn');
    const uptimeBtn = document.getElementById('uptime-btn');
    const ifaceListBtn = document.getElementById('iface-list-btn');
    // const startBtn = document.getElementById('start-btn'); // Start not implemented

    /* if (startBtn) {
        startBtn.addEventListener('click', () => { 
             statusMessage.textContent = 'Le démarrage de Suricata n'est pas supporté via cette interface.';
             // sendCommandToBackend('start'); // Example if backend could handle it
        });
    } */
    
    if (reloadBtn) {
        // Example: ruleset-reload-rules takes no arguments
        reloadBtn.addEventListener('click', () => sendCommandToBackend('ruleset-reload-rules'));
    }
    if (shutdownBtn) {
        // Example: shutdown takes no arguments
        shutdownBtn.addEventListener('click', () => sendCommandToBackend('shutdown'));
    }
    if (uptimeBtn) {
        // Example: uptime takes no arguments
        uptimeBtn.addEventListener('click', () => sendCommandToBackend('uptime'));
    }
    if (ifaceListBtn) {
        // Example: iface-list takes no arguments
        ifaceListBtn.addEventListener('click', () => sendCommandToBackend('iface-list'));
    }

    // Example for a command with arguments (if you add a button for it)
    /*
    const ifaceStatBtn = document.getElementById('iface-stat-btn');
    const ifaceNameInput = document.getElementById('iface-name-input'); 
    if (ifaceStatBtn && ifaceNameInput) {
        // Example: iface-stat requires an 'iface' argument
        ifaceStatBtn.addEventListener('click', () => {
             const ifaceName = ifaceNameInput.value;
             if (ifaceName) {
                 sendCommandToBackend('iface-stat', { iface: ifaceName });
             } else {
                 statusMessage.textContent = 'Veuillez entrer un nom d'interface.';
             }
        });
    }
    */

}); 