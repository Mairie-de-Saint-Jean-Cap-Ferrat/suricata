document.addEventListener('DOMContentLoaded', () => {
    const logContent = document.getElementById('log-content');
    const refreshLogButton = document.getElementById('refresh-log');
    const refreshChartsButton = document.getElementById('refresh-charts');
    const statusMessage = document.getElementById('status-message');
    const commandStatusDiv = document.getElementById('command-status');
    const enableConfTextarea = document.getElementById('enable-conf-content');
    const disableConfTextarea = document.getElementById('disable-conf-content');
    const saveConfigButton = document.getElementById('save-config-btn');
    const configStatusMessage = document.getElementById('config-status-message');

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

    if (refreshLogButton) {
        refreshLogButton.addEventListener('click', fetchLogs);
    }

    // Initial load
    fetchLogs();

    // --- Backend API Interaction --- 
    const sendCommandToBackend = async (command, args = null) => {
        statusMessage.textContent = `Envoi de la commande ${command}...`;
        commandStatusDiv.className = 'alert alert-info mt-3';
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
                commandStatusDiv.className = 'alert alert-danger mt-3';
                throw new Error(result.message || `Erreur HTTP! status: ${response.status}`);
            }
            
            commandStatusDiv.className = 'alert alert-success mt-3';
            // Display success and the message from Suricata's response
            statusMessage.textContent = `Commande ${command} réussie: ${JSON.stringify(result.message || result)}`;
            console.log("Backend response:", result);

        } catch (error) {
            commandStatusDiv.className = 'alert alert-danger mt-3';
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

    // --- Chart Rendering --- 
    let topAlertsChartInstance = null; // To hold the chart instance

    const renderTopAlertsChart = (labels, values) => {
        const ctx = document.getElementById('topAlertsChart')?.getContext('2d');
        if (!ctx) {
            console.error("Canvas element for top alerts chart not found!");
            return;
        }

        // Destroy previous chart instance if it exists
        if (topAlertsChartInstance) {
            topAlertsChartInstance.destroy();
        }

        topAlertsChartInstance = new Chart(ctx, {
            type: 'bar', // or 'pie', 'doughnut'
            data: {
                labels: labels,
                datasets: [{
                    label: 'Nombre d\'occurrences',
                    data: values,
                    backgroundColor: [
                        'rgba(255, 99, 132, 0.5)',
                        'rgba(54, 162, 235, 0.5)',
                        'rgba(255, 206, 86, 0.5)',
                        'rgba(75, 192, 192, 0.5)',
                        'rgba(153, 102, 255, 0.5)',
                        'rgba(255, 159, 64, 0.5)',
                        'rgba(199, 199, 199, 0.5)',
                        'rgba(83, 102, 255, 0.5)',
                        'rgba(40, 159, 64, 0.5)',
                        'rgba(210, 99, 132, 0.5)'
                    ],
                    borderColor: [
                        'rgba(255, 99, 132, 1)',
                        'rgba(54, 162, 235, 1)',
                        'rgba(255, 206, 86, 1)',
                        'rgba(75, 192, 192, 1)',
                        'rgba(153, 102, 255, 1)',
                        'rgba(255, 159, 64, 1)',
                        'rgba(199, 199, 199, 1)',
                        'rgba(83, 102, 255, 1)',
                        'rgba(40, 159, 64, 1)',
                        'rgba(210, 99, 132, 1)'
                    ],
                    borderWidth: 1
                }]
            },
            options: {
                indexAxis: 'y', // Make it horizontal for better label readability
                scales: {
                    x: {
                        beginAtZero: true
                    }
                },
                responsive: true,
                maintainAspectRatio: false, // Allow chart to resize within container
                plugins: {
                    legend: {
                        display: false // Hide legend for single dataset
                    }
                }
            }
        });
    };

    const fetchTopAlertsChartData = async () => {
        console.log('Fetching chart data...'); // Debug log
        try {
            const response = await fetch('/api/stats/top_signatures');
            if (!response.ok) {
                 const errorData = await response.json();
                throw new Error(errorData.error || `Erreur HTTP! status: ${response.status}`);
            }
            const data = await response.json();
            if (data.labels && data.values) {
                 renderTopAlertsChart(data.labels, data.values);
            } else {
                 console.error("Données reçues pour le graphique invalides:", data);
                 // Afficher un message sur le canvas ?
                 const ctx = document.getElementById('topAlertsChart')?.getContext('2d');
                 if (ctx) {
                     // Optionnel: Nettoyer et afficher un message
                     if (topAlertsChartInstance) topAlertsChartInstance.destroy();
                     ctx.clearRect(0, 0, ctx.canvas.width, ctx.canvas.height);
                     ctx.font = "16px Arial";
                     ctx.fillStyle = "grey";
                     ctx.textAlign = "center";
                     ctx.fillText("Données indisponibles ou invalides.", ctx.canvas.width/2, ctx.canvas.height/2);
                 }
            }
        } catch (error) {
            console.error('Erreur lors de la récupération des données du graphique:', error);
            // Afficher une erreur sur le canvas
            const ctx = document.getElementById('topAlertsChart')?.getContext('2d');
            if (ctx) {
                 if (topAlertsChartInstance) topAlertsChartInstance.destroy();
                 ctx.clearRect(0, 0, ctx.canvas.width, ctx.canvas.height);
                 ctx.font = "14px Arial";
                 ctx.fillStyle = "red";
                 ctx.textAlign = "center";
                 ctx.fillText(`Erreur chargement: ${error.message}`, ctx.canvas.width/2, ctx.canvas.height/2, ctx.canvas.width - 20);
            }
        }
    };

    // --- Event Listeners --- 
    if (refreshLogButton) {
        refreshLogButton.addEventListener('click', fetchLogs);
    }

    if (refreshChartsButton) {
        refreshChartsButton.addEventListener('click', fetchTopAlertsChartData);
    }

    // --- Initial Load --- 
    fetchLogs(); // Load text logs
    fetchTopAlertsChartData(); // Load chart data
    fetchConfigFile('enable.conf', enableConfTextarea);
    fetchConfigFile('disable.conf', disableConfTextarea);

    // Link chart refresh to log refresh?
    if (refreshLogButton) {
        refreshLogButton.addEventListener('click', () => {
            fetchLogs(); // Refresh text logs
            fetchTopAlertsChartData(); // Refresh chart data as well
        });
    } else {
         // If no refresh button, ensure initial load still happens
         fetchLogs();
         fetchTopAlertsChartData();
    }

    // --- NOUVEAU: Config File Fetching & Saving ---
    const fetchConfigFile = async (filename, textareaElement) => {
        console.log(`Fetching ${filename}...`);
        try {
            const response = await fetch(`/api/config/${filename}`);
            if (!response.ok) {
                const errorData = await response.json();
                throw new Error(errorData.error || `Erreur HTTP! status: ${response.status}`);
            }
            const data = await response.json();
            textareaElement.value = data.content;
            console.log(`${filename} loaded successfully.`);
        } catch (error) {
            console.error(`Erreur lors du chargement de ${filename}:`, error);
            textareaElement.value = `Erreur chargement: ${error.message}`;
            textareaElement.classList.add('is-invalid'); // Indicate error visually
            configStatusMessage.textContent = `Erreur chargement ${filename}.`;
            configStatusMessage.className = 'ms-3 text-danger';
        }
    };

    const saveConfigFile = async (filename, textareaElement) => {
        const content = textareaElement.value;
        console.log(`Saving ${filename}...`);
        configStatusMessage.textContent = `Sauvegarde de ${filename}...`;
        configStatusMessage.className = 'ms-3 text-info';

        try {
            const response = await fetch(`/api/config/${filename}`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({ content: content })
            });
            const result = await response.json();
            if (!response.ok) {
                 throw new Error(result.error || `Erreur HTTP! status: ${response.status}`);
            }
            console.log(`${filename} saved successfully.`);
            textareaElement.classList.remove('is-invalid');
            // Retour implicite au message global de succès après les deux sauvegardes
            return true; // Indicate success
        } catch (error) {
            console.error(`Erreur lors de la sauvegarde de ${filename}:`, error);
            configStatusMessage.textContent = `Erreur sauvegarde ${filename}: ${error.message}`;
            configStatusMessage.className = 'ms-3 text-danger';
            textareaElement.classList.add('is-invalid');
            return false; // Indicate failure
        }
    };

    // AJOUT: Event listener pour le bouton de sauvegarde de la config
    if (saveConfigButton) {
        saveConfigButton.addEventListener('click', async () => {
            configStatusMessage.textContent = 'Sauvegarde en cours...';
            configStatusMessage.className = 'ms-3 text-info';
            saveConfigButton.disabled = true; // Disable button during save

            // Sauvegarder les deux fichiers
            const enableSuccess = await saveConfigFile('enable.conf', enableConfTextarea);
            const disableSuccess = await saveConfigFile('disable.conf', disableConfTextarea);

            if (enableSuccess && disableSuccess) {
                 configStatusMessage.textContent = 'Configuration sauvegardée avec succès. N\'oubliez pas d\'exécuter suricata-update et de recharger les règles.';
                 configStatusMessage.className = 'ms-3 text-success';
            } else {
                 // Error message is already set by saveConfigFile on failure
                 configStatusMessage.className = 'ms-3 text-danger'; // Ensure it's red
            }
            saveConfigButton.disabled = false; // Re-enable button
        });
    }
}); 