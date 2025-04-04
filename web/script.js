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

    // --- Initial Load --- 
    fetchLogs(); // Load text logs
    fetchTopAlertsChartData(); // Load chart data

    // Link chart refresh to log refresh?
    if (refreshButton) {
        refreshButton.addEventListener('click', () => {
            fetchLogs(); // Refresh text logs
            fetchTopAlertsChartData(); // Refresh chart data as well
        });
    } else {
         // If no refresh button, ensure initial load still happens
         fetchLogs();
         fetchTopAlertsChartData();
    }
}); 