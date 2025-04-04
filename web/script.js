document.addEventListener('DOMContentLoaded', () => {
    const refreshChartsButton = document.getElementById('refresh-charts');
    const statusMessage = document.getElementById('status-message');
    const commandStatusDiv = document.getElementById('command-status');
    const enableConfTextarea = document.getElementById('enable-conf-content');
    const disableConfTextarea = document.getElementById('disable-conf-content');
    const saveConfigButton = document.getElementById('save-config-btn');
    const configStatusMessage = document.getElementById('config-status-message');
    const postSaveStatusDiv = document.getElementById('post-save-status');
    const updateStatusDiv = document.getElementById('update-status');
    const reloadStatusDiv = document.getElementById('reload-status');
    const updateOutputPre = document.getElementById('update-output');

    // Map pour stocker les instances de Chart.js
    const chartInstances = {};

    // --- NOUVEAU: Fonction générique pour créer/mettre à jour un graphique --- 
    const renderChart = (canvasId, chartType, data, options, title) => {
        const ctx = document.getElementById(canvasId)?.getContext('2d');
        if (!ctx) {
            console.error(`Canvas element #${canvasId} not found!`);
            return;
        }

        // Détruire l'instance précédente si elle existe
        if (chartInstances[canvasId]) {
            chartInstances[canvasId].destroy();
        }
        
        // Afficher un message si pas de données
        if (!data || !data.labels || data.labels.length === 0) {
             console.log(`No data available for chart #${canvasId}.`);
             ctx.clearRect(0, 0, ctx.canvas.width, ctx.canvas.height);
             ctx.font = "16px Arial";
             ctx.fillStyle = "grey";
             ctx.textAlign = "center";
             // Mettre le titre comme message peut être utile
             ctx.fillText(title ? `${title} - Données indisponibles` : "Données indisponibles", ctx.canvas.width / 2, ctx.canvas.height / 2);
             chartInstances[canvasId] = null; // Assurer qu'il n'y a pas d'instance
             return;
         }

        // Créer la nouvelle instance
        try {
             chartInstances[canvasId] = new Chart(ctx, {
                 type: chartType,
                 data: data,
                 options: options
             });
        } catch (error) {
             console.error(`Error rendering chart #${canvasId}:`, error);
             ctx.clearRect(0, 0, ctx.canvas.width, ctx.canvas.height);
             ctx.font = "14px Arial";
             ctx.fillStyle = "red";
             ctx.textAlign = "center";
             ctx.fillText(`Erreur rendu: ${error.message}`, ctx.canvas.width/2, ctx.canvas.height/2, ctx.canvas.width - 20);
             chartInstances[canvasId] = null;
        }
    };
    
    // Options par défaut pour les graphiques (peuvent être surchargées)
    const defaultChartOptions = {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
            legend: {
                position: 'top',
            },
            tooltip: {
                mode: 'index',
                intersect: false,
            }
        }
    };
    
    const horizontalBarOptions = { 
         ...defaultChartOptions,
         indexAxis: 'y', 
         scales: { x: { beginAtZero: true } },
         plugins: { legend: { display: false } }
    };
    
    const pieChartOptions = { 
         ...defaultChartOptions, 
         plugins: { legend: { position: 'right' } }
    };

    // --- NOUVEAU: Fonctions pour récupérer les données et rendre chaque graphique ---

    const fetchAndRenderTopAlerts = async () => {
        try {
            const response = await fetch('/api/stats/top_signatures');
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            const apiData = await response.json();
            renderChart('topAlertsChart', 'bar', 
                 {
                    labels: apiData.labels,
                    datasets: [{
                         label: 'Occurrences',
                         data: apiData.values,
                         backgroundColor: 'rgba(255, 99, 132, 0.5)', 
                         borderColor: 'rgba(255, 99, 132, 1)',
                         borderWidth: 1
                    }]
                 },
                 horizontalBarOptions,
                 "Top 10 Signatures d'Alerte"
            );
        } catch (error) {
            console.error('Error fetching/rendering Top Alerts:', error);
            renderChart('topAlertsChart', 'bar', null, horizontalBarOptions, "Top 10 Signatures d'Alerte"); // Afficher erreur/indisponible
        }
    };

    const fetchAndRenderTopDns = async () => {
        try {
            const response = await fetch('/api/stats/top_dns');
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            const apiData = await response.json();
            renderChart('topDnsChart', 'bar', 
                 {
                    labels: apiData.labels,
                    datasets: [{
                         label: 'Requêtes',
                         data: apiData.values,
                         backgroundColor: 'rgba(54, 162, 235, 0.5)',
                         borderColor: 'rgba(54, 162, 235, 1)',
                         borderWidth: 1
                    }]
                 },
                 horizontalBarOptions,
                 "Top 10 Requêtes DNS"
            );
        } catch (error) {
            console.error('Error fetching/rendering Top DNS:', error);
            renderChart('topDnsChart', 'bar', null, horizontalBarOptions, "Top 10 Requêtes DNS");
        }
    };
    
    const fetchAndRenderTopTlsSni = async () => {
        try {
            const response = await fetch('/api/stats/top_tls_sni');
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            const apiData = await response.json();
            renderChart('topTlsSniChart', 'bar', 
                 {
                    labels: apiData.labels,
                    datasets: [{
                         label: 'Connexions',
                         data: apiData.values,
                         backgroundColor: 'rgba(75, 192, 192, 0.5)', 
                         borderColor: 'rgba(75, 192, 192, 1)',
                         borderWidth: 1
                    }]
                 },
                 horizontalBarOptions,
                 "Top 10 TLS SNI"
            );
        } catch (error) {
            console.error('Error fetching/rendering Top TLS SNI:', error);
            renderChart('topTlsSniChart', 'bar', null, horizontalBarOptions, "Top 10 TLS SNI");
        }
    };
    
    const fetchAndRenderProtoCharts = async () => {
        try {
            const response = await fetch('/api/stats/latest_counters');
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            const counters = await response.json();

            // Decoder Chart (L3/L4)
            const decoderStats = counters.decoder || {};
            const decoderLabels = ['TCP', 'UDP', 'ICMPv4', 'ICMPv6', 'IPv4', 'IPv6', 'Autre'];
            const decoderValues = [
                 decoderStats.tcp || 0,
                 decoderStats.udp || 0,
                 decoderStats.icmpv4 || 0,
                 decoderStats.icmpv6 || 0,
                 decoderStats.ipv4 || 0,
                 decoderStats.ipv6 || 0,
                 (decoderStats.pkts || 0) - (decoderStats.tcp || 0) - (decoderStats.udp || 0) - (decoderStats.icmpv4 || 0) - (decoderStats.icmpv6 || 0) - (decoderStats.ipv4 || 0) - (decoderStats.ipv6 || 0) // Calcul simple pour "Autre"
            ];
             // Filtrer les valeurs nulles pour le pie chart
             const filteredDecoderLabels = decoderLabels.filter((_, i) => decoderValues[i] > 0);
             const filteredDecoderValues = decoderValues.filter(v => v > 0);
            
            renderChart('decoderProtoChart', 'pie', 
                 {
                    labels: filteredDecoderLabels,
                    datasets: [{
                         label: 'Paquets Décodés',
                         data: filteredDecoderValues,
                         backgroundColor: [
                            'rgba(255, 159, 64, 0.7)', 'rgba(153, 102, 255, 0.7)', 'rgba(255, 206, 86, 0.7)',
                            'rgba(75, 192, 192, 0.7)', 'rgba(54, 162, 235, 0.7)', 'rgba(201, 203, 207, 0.7)',
                            'rgba(255, 99, 132, 0.7)'
                         ],
                    }]
                 },
                 pieChartOptions,
                 "Répartition Protocoles L3/L4 (Decodeur)"
            );

            // App Layer Chart
            const appLayerStats = counters.app_layer?.flow || {};
            const appLabels = Object.keys(appLayerStats).filter(k => appLayerStats[k] > 0); // Filtrer les protocoles avec 0 flux
            const appValues = appLabels.map(k => appLayerStats[k]);
            
            renderChart('appLayerProtoChart', 'doughnut', 
                 {
                    labels: appLabels,
                    datasets: [{
                         label: 'Flux Applicatifs',
                         data: appValues,
                         // Ajouter plus de couleurs si nécessaire
                         backgroundColor: [
                             '#4e73df', '#1cc88a', '#36b9cc', '#f6c23e', '#e74a3b', '#858796', '#f8f9fc', 
                             '#5a5c69', '#fd7e14', '#6f42c1', '#d63384', '#20c997'
                         ],
                    }]
                 },
                 pieChartOptions,
                 "Répartition Protocoles Applicatifs (Flow)"
            );

        } catch (error) {
            console.error('Error fetching/rendering Protocol Charts:', error);
            renderChart('decoderProtoChart', 'pie', null, pieChartOptions, "Répartition Protocoles L3/L4 (Decodeur)");
            renderChart('appLayerProtoChart', 'doughnut', null, pieChartOptions, "Répartition Protocoles Applicatifs (Flow)");
        }
    };
    
    // --- Fonction pour charger toutes les données des graphiques ---
    const loadAllChartData = () => {
        console.log('Loading all chart data...');
        fetchAndRenderTopAlerts();
        fetchAndRenderTopDns();
        fetchAndRenderTopTlsSni();
        fetchAndRenderProtoCharts();
        // Ajouter fetch pour captureStatsChart ici si implémenté
    };

    // --- Config File Fetching & Saving ---
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

    // --- Initial Load --- 
    loadAllChartData(); // Charger tous les graphiques
    fetchConfigFile('enable.conf', enableConfTextarea);
    fetchConfigFile('disable.conf', disableConfTextarea);

    if (refreshChartsButton) {
        refreshChartsButton.addEventListener('click', loadAllChartData); // Rafraîchir tous les graphiques
    }

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

    // --- Event Listeners --- 
    if (refreshChartsButton) {
        refreshChartsButton.addEventListener('click', loadAllChartData);
    }

    // --- NOUVEAU: Config File Fetching & Saving ---
    const saveConfigFile = async (filename, textareaElement) => {
        const content = textareaElement.value;
        console.log(`Saving ${filename}...`);
        configStatusMessage.textContent = 'Sauvegarde en cours...';
        configStatusMessage.className = 'ms-3 text-info';
        saveConfigButton.disabled = true; // Disable button during save
        postSaveStatusDiv.style.display = 'none'; // Hide status area initially
        updateStatusDiv.className = 'alert alert-info';
        updateStatusDiv.textContent = 'Exécution de suricata-update...';
        reloadStatusDiv.style.display = 'none';
        reloadStatusDiv.className = 'alert alert-secondary';
        reloadStatusDiv.textContent = 'Rechargement des règles dans Suricata...';
        updateOutputPre.style.display = 'none';
        updateOutputPre.textContent = '';

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
            configStatusMessage.className = 'ms-3 text-success';
            // Afficher la zone de statut pour l'étape suivante
            postSaveStatusDiv.style.display = 'block'; 

            // 2. Exécuter suricata-update via API
            try {
                const updateResponse = await fetch('/api/run-suricata-update', { method: 'POST' });
                const updateResult = await updateResponse.json();

                if (!updateResponse.ok || updateResult.status !== 'success') {
                    throw new Error(updateResult.message || `Erreur HTTP ${updateResponse.status}`);
                }
                
                updateStatusDiv.className = 'alert alert-success';
                updateStatusDiv.innerHTML = '<code>suricata-update</code> exécuté avec succès.'; // Utiliser innerHTML pour le code tag
                if(updateResult.output_summary) {
                     updateOutputPre.textContent = updateResult.output_summary;
                     updateOutputPre.style.display = 'block';
                }
                reloadStatusDiv.style.display = 'block'; // Afficher le statut de rechargement

                // 3. Recharger les règles via API
                try {
                    const reloadResponse = await fetch('/api/command', {
                         method: 'POST',
                         headers: {'Content-Type': 'application/json'},
                         body: JSON.stringify({ command: 'ruleset-reload-rules' })
                    });
                    const reloadResult = await reloadResponse.json();

                    if (!reloadResponse.ok || reloadResult.return === 'FAILED') {
                        throw new Error(reloadResult.message || `Erreur HTTP ${reloadResponse.status}`);
                    }
                    
                    reloadStatusDiv.className = 'alert alert-success';
                    reloadStatusDiv.textContent = `Rechargement des règles réussi: ${JSON.stringify(reloadResult.message || reloadResult)}`;

                } catch (reloadError) {
                     console.error('Erreur lors du rechargement des règles:', reloadError);
                     reloadStatusDiv.className = 'alert alert-danger';
                     reloadStatusDiv.textContent = `Erreur rechargement règles: ${reloadError.message}`;
                }

            } catch (updateError) {
                console.error('Erreur lors de l\'exécution de suricata-update:', updateError);
                updateStatusDiv.className = 'alert alert-danger';
                updateStatusDiv.textContent = `Erreur suricata-update: ${updateError.message}`;
                 // Afficher les détails si disponibles (par exemple stderr)
                 if (updateError.stderr || updateError.stdout) {
                     updateOutputPre.textContent = `Stderr:\n${updateError.stderr || ''}\n\nStdout:\n${updateError.stdout || ''}`;
                     updateOutputPre.style.display = 'block';
                 }
            }

            return true; // Indicate success
        } catch (error) {
            console.error(`Erreur lors de la sauvegarde de ${filename}:`, error);
            configStatusMessage.textContent = `Erreur sauvegarde ${filename}: ${error.message}`;
            configStatusMessage.className = 'ms-3 text-danger';
            textareaElement.classList.add('is-invalid');
            return false; // Indicate failure
        } finally {
            saveConfigButton.disabled = false; // Re-enable button
        }
    };

    // AJOUT: Event listener pour le bouton de sauvegarde de la config
    if (saveConfigButton) {
        saveConfigButton.addEventListener('click', async () => {
            configStatusMessage.textContent = 'Sauvegarde en cours...';
            configStatusMessage.className = 'ms-3 text-info';
            saveConfigButton.disabled = true; // Disable button during save
            postSaveStatusDiv.style.display = 'none'; // Hide status area initially
            updateStatusDiv.className = 'alert alert-info';
            updateStatusDiv.textContent = 'Exécution de suricata-update...';
            reloadStatusDiv.style.display = 'none';
            reloadStatusDiv.className = 'alert alert-secondary';
            reloadStatusDiv.textContent = 'Rechargement des règles dans Suricata...';
            updateOutputPre.style.display = 'none';
            updateOutputPre.textContent = '';

            // Sauvegarder les deux fichiers
            const enableSuccess = await saveConfigFile('enable.conf', enableConfTextarea);
            const disableSuccess = await saveConfigFile('disable.conf', disableConfTextarea);

            if (enableSuccess && disableSuccess) {
                 configStatusMessage.textContent = 'Configuration sauvegardée.';
                 configStatusMessage.className = 'ms-3 text-success';
                 // Afficher la zone de statut pour l'étape suivante
                 postSaveStatusDiv.style.display = 'block'; 
            } else {
                 // Error message is already set by saveConfigFile on failure
                 configStatusMessage.className = 'ms-3 text-danger'; // Ensure it's red
                 postSaveStatusDiv.style.display = 'none'; // Keep status hidden on save failure
            }
        });
    }
}); 