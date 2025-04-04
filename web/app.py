import os
import socket
import json
import logging
import subprocess # AJOUT pour exécuter des commandes externes
import time # AJOUT pour SSE
from collections import Counter, deque # AJOUT: deque pour lire les dernières lignes efficacement
from flask import Flask, request, jsonify, send_from_directory, Response # AJOUT Response pour SSE

# Assuming the Flask app is run from the /app/web directory as set in Dockerfile.webinterface
# We need to serve static files (HTML, CSS, JS) from the 'web' directory relative to the CWD
# and logs from the mounted 'logs' directory.
# Flask looks for static files relative to its root_path or a specified static_folder.
STATIC_FOLDER_PATH = '.' # Serve from the current working directory (/app/web)
LOGS_FOLDER_PATH = 'logs' # Where logs will be mounted/available
EVE_JSON_FILE = 'eve.json' # Nom du fichier log principal
# AJOUT: Chemin vers le répertoire de configuration monté
SURICATA_CONFIG_DIR = '/etc/suricata'

app = Flask(__name__, static_folder=STATIC_FOLDER_PATH, static_url_path='')

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- Configuration --- 
# Determine the socket path relative to a common base or use an absolute path
# Default location is often within Suricata's run directory
# Adjust this path based on your Suricata installation and configuration
# Common locations might be /var/run/suricata/suricata-command.socket or similar
# For dev container, it might be relative to the workspace if Suricata runs there
DEFAULT_SOCKET_PATH = '/var/run/suricata/suricata-command.socket' # ADJUST IF NEEDED
SURICATA_SOCKET_PATH = os.environ.get('SURICATA_SOCKET_PATH', DEFAULT_SOCKET_PATH)

# --- Helper Function --- 
def send_unix_command(command_data):
    """Sends a command to the Suricata Unix socket and returns the response."""
    if not os.path.exists(SURICATA_SOCKET_PATH):
        logger.error(f"Socket file not found at {SURICATA_SOCKET_PATH}")
        return {"status": "error", "message": f"Socket file not found at {SURICATA_SOCKET_PATH}. Is Suricata running and configured for Unix socket?"}

    try:
        client_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        logger.info(f"Connecting to socket: {SURICATA_SOCKET_PATH}")
        client_socket.connect(SURICATA_SOCKET_PATH)
        logger.info("Connected to socket")

        # Initial handshake (optional but good practice based on suricatasc examples)
        # Some versions might not require this
        try:
            client_socket.sendall(json.dumps({"version": "0.1"}).encode('utf-8'))
            initial_response = client_socket.recv(4096).decode('utf-8')
            logger.info(f"Handshake response: {initial_response}")
            # Handle potential handshake errors if necessary
        except Exception as handshake_err:
            logger.warning(f"Handshake failed (might be optional): {handshake_err}")

        # Send the actual command
        logger.info(f"Sending command: {command_data}")
        client_socket.sendall(json.dumps(command_data).encode('utf-8'))

        # Receive the response (potentially in chunks)
        response_data = b""
        while True:
            chunk = client_socket.recv(4096)
            if not chunk:
                break
            response_data += chunk
            # Simple check if response seems complete (ends with '}')
            if response_data.strip().endswith(b'}'):
                 break
            # Add a small delay or more robust end-of-message detection if needed
            # For simplicity, we break if we receive something ending in '}'

        logger.info(f"Raw response received: {response_data.decode('utf-8', errors='ignore')}")
        client_socket.close()

        if not response_data:
             logger.warning("Received empty response from socket")
             return {"status": "error", "message": "Received empty response from Suricata."}

        try:
            response_json = json.loads(response_data.decode('utf-8'))
            return {"status": "success", "data": response_json}
        except json.JSONDecodeError as json_err:
            logger.error(f"Failed to decode JSON response: {json_err}")
            logger.error(f"Raw response was: {response_data.decode('utf-8', errors='ignore')}")
            return {"status": "error", "message": "Failed to decode JSON response from Suricata.", "raw_response": response_data.decode('utf-8', errors='ignore')}

    except socket.error as e:
        logger.error(f"Socket error: {e}")
        return {"status": "error", "message": f"Socket communication error: {e}"}
    except Exception as e:
        logger.error(f"An unexpected error occurred: {e}")
        return {"status": "error", "message": f"An unexpected error occurred: {e}"}

# --- Static File Serving ---
@app.route('/')
def index():
    """Serve the main HTML page."""
    logger.info(f"Serving index.html from {app.static_folder}")
    # Flask automatically serves files from static_folder if static_url_path is set
    # However, explicitly defining a route for '/' to serve index.html is clearer.
    return send_from_directory(app.static_folder, 'index.html')

# Flask's default static file handling (via static_url_path='') should serve
# style.css and script.js automatically when requested like <link rel="stylesheet" href="style.css">
# No need for explicit routes for them if they are in the static_folder.

# --- Log File Serving ---
@app.route('/logs/<path:filename>')
def serve_log(filename):
    """Serve log files (eve.json, suricata.log) from the mounted logs directory."""
    logs_dir = os.path.join(app.root_path, LOGS_FOLDER_PATH)
    logger.info(f"Attempting to serve log file: {filename} from {logs_dir}")
    if not os.path.exists(logs_dir):
         logger.error(f"Logs directory not found at {logs_dir}")
         return jsonify({"error": "Logs directory not configured or not found on server."}), 404
    try:
        # Force mimetype pour eve.json pour éviter les problèmes de rendu navigateur
        mimetype = 'application/json' if filename == EVE_JSON_FILE else 'text/plain'
        return send_from_directory(logs_dir, filename, mimetype=mimetype)
    except FileNotFoundError:
        logger.warning(f"Log file not found: {filename} in {logs_dir}")
        return "", 200 # Le frontend gère le fichier vide

# --- API Endpoint --- 
@app.route('/api/command', methods=['POST'])
def handle_command():
    """Receives a command from the frontend and sends it to Suricata via Unix socket."""
    data = request.get_json()
    if not data or 'command' not in data:
        return jsonify({"status": "error", "message": "Invalid request. 'command' field missing."}), 400

    suricata_command = {"command": data['command']}
    if 'arguments' in data:
        suricata_command['arguments'] = data['arguments']

    logger.info(f"Received API request for command: {suricata_command}")
    result = send_unix_command(suricata_command)

    if result['status'] == 'success':
        return jsonify(result['data']) # Return Suricata's direct response
    else:
        # Return the error message from our helper function
        return jsonify({"return": "FAILED", "message": result['message']}), 500

# --- NOUVEAUX ENDPOINTS POUR LA CONFIGURATION DES RÈGLES ---

def read_config_file(filename):
    """Helper function to read a config file."""
    filepath = os.path.join(SURICATA_CONFIG_DIR, filename)
    logger.info(f"Attempting to read config file: {filepath}")
    if not os.path.exists(filepath):
        logger.warning(f"Config file not found: {filepath}. Returning empty content.")
        # Il est normal que ces fichiers n'existent pas initialement
        return "" 
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        logger.info(f"Successfully read config file: {filepath}")
        return content
    except Exception as e:
        logger.error(f"Error reading config file {filepath}: {e}")
        raise # Re-raise the exception to be caught by the endpoint

def write_config_file(filename, content):
    """Helper function to write to a config file."""
    filepath = os.path.join(SURICATA_CONFIG_DIR, filename)
    logger.info(f"Attempting to write config file: {filepath}")
    try:
        # Ensure the directory exists (should be mounted by Docker, but good practice)
        os.makedirs(os.path.dirname(filepath), exist_ok=True)
        with open(filepath, 'w') as f:
            f.write(content)
        logger.info(f"Successfully wrote config file: {filepath}")
    except Exception as e:
        logger.error(f"Error writing config file {filepath}: {e}")
        raise

@app.route('/api/config/<filename>', methods=['GET'])
def get_config_file(filename):
    """Get the content of enable.conf or disable.conf."""
    if filename not in ('enable.conf', 'disable.conf'):
        return jsonify({"error": "Invalid config filename specified."}), 400
    try:
        content = read_config_file(filename)
        return jsonify({"filename": filename, "content": content})
    except Exception as e:
        return jsonify({"error": f"Failed to read {filename}: {e}"}), 500

@app.route('/api/config/<filename>', methods=['POST'])
def save_config_file(filename):
    """Save content to enable.conf or disable.conf."""
    if filename not in ('enable.conf', 'disable.conf'):
        return jsonify({"error": "Invalid config filename specified."}), 400
    
    data = request.get_json()
    if data is None or 'content' not in data:
        return jsonify({"error": "Invalid request. 'content' field missing."}), 400

    content = data['content']
    # Basic sanity check (optional): ensure content is string
    if not isinstance(content, str):
         return jsonify({"error": "Invalid content format, must be a string."}), 400

    try:
        write_config_file(filename, content)
        return jsonify({"status": "success", "message": f"{filename} saved successfully."})
    except Exception as e:
        return jsonify({"error": f"Failed to save {filename}: {e}"}), 500

# --- NOUVEL ENDPOINT POUR DÉCLENCHER SURICATA-UPDATE --- 
@app.route('/api/run-suricata-update', methods=['POST'])
def run_suricata_update():
    """Exécute 'docker compose exec suricata suricata-update' via le socket Docker monté."""
    logger.info("Attempting to run suricata-update via docker compose exec...")

    # Assurez-vous que le service s'appelle bien 'suricata' dans docker-compose.yml
    command = ["docker", "compose", "exec", "suricata", "suricata-update"]
    # Le répertoire de travail du conteneur web est /app/web, mais docker compose devrait fonctionner 
    # depuis n'importe où si docker.sock est monté. Spécifier le CWD du projet hôte peut être plus sûr si nécessaire.
    # Nous supposons que le contexte docker compose est correctement géré.

    try:
        # Exécuter la commande
        result = subprocess.run(command, capture_output=True, text=True, check=True, timeout=120) # Timeout de 2 minutes
        
        logger.info(f"suricata-update executed successfully. Output:\n{result.stdout}")
        # Renvoyer une partie de la sortie (peut être long)
        output_summary = result.stdout[-1000:] # Renvoyer les 1000 derniers caractères
        return jsonify({
            "status": "success", 
            "message": "suricata-update executed successfully.",
            "output_summary": output_summary
        })

    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to execute suricata-update. Return code: {e.returncode}")
        logger.error(f"Stderr:\n{e.stderr}")
        logger.error(f"Stdout:\n{e.stdout}")
        return jsonify({
            "status": "error", 
            "message": f"Failed to execute suricata-update. Check backend logs.",
            "stderr": e.stderr,
            "stdout": e.stdout
        }), 500
    except subprocess.TimeoutExpired:
         logger.error("suricata-update command timed out.")
         return jsonify({"status": "error", "message": "suricata-update command timed out after 120 seconds."}), 500
    except FileNotFoundError:
        logger.error("'docker' command not found. Is Docker CLI installed in the web container and docker.sock mounted?")
        return jsonify({"status": "error", "message": "Docker command not found in web container."}), 500
    except Exception as e:
        logger.error(f"An unexpected error occurred while running suricata-update: {e}")
        return jsonify({"status": "error", "message": f"An unexpected error occurred: {e}"}), 500

# --- ENDPOINT POUR LE STREAMING DES LOGS (SSE) --- 
@app.route('/api/logs/stream')
def stream_logs():
    """Endpoint SSE pour streamer les nouvelles lignes d'eve.json."""
    eve_path = os.path.join(app.root_path, LOGS_FOLDER_PATH, EVE_JSON_FILE)
    logger.info(f"Starting log stream for {eve_path}")

    if not os.path.exists(eve_path):
        logger.error(f"Cannot start stream: Log file not found at {eve_path}")
        # On ne peut pas vraiment renvoyer une erreur standard ici car c'est un stream
        # Le client devra gérer l'échec de connexion
        def error_generator():
             yield f"data: {json.dumps({'error': 'Log file not found'})}\n\n"
        return Response(error_generator(), mimetype='text/event-stream')

    def generate():
        # Utiliser tail -f pour suivre le fichier. '-n 0' pour ne pas envoyer l'historique.
        # On lit depuis la fin du fichier.
        try:
            # D'abord, positionner à la fin
            with open(eve_path, 'r') as f:
                 f.seek(0, os.SEEK_END)
                 # logger.info("Positioned at the end of the log file.")
            
            # Lancer tail -f --follow=name --retry pour gérer la rotation
            # Le conteneur doit avoir `tail` (normalement présent dans les images debian/python slim)
            proc = subprocess.Popen([
                    'tail', '-n', '0', '--follow=name', '--retry', eve_path
                 ], 
                 stdout=subprocess.PIPE, 
                 stderr=subprocess.PIPE, 
                 text=True)
            
            logger.info(f"tail -f process started for {eve_path}")
            
            while True:
                 line = proc.stdout.readline()
                 if not line:
                      # Vérifier si le processus tail a terminé (peut arriver en cas d'erreur)
                      poll_status = proc.poll()
                      if poll_status is not None:
                          stderr_output = proc.stderr.read()
                          logger.error(f"tail process exited with code {poll_status}. Stderr: {stderr_output}")
                          yield f"data: {json.dumps({'error': f'Log stream failed. Tail process exited (code {poll_status}).'})}\n\n"
                          break # Sortir de la boucle while
                      # Si pas de ligne mais processus tourne toujours, juste attendre
                      # time.sleep(0.1)
                      continue 
                 
                 # Envoyer la ligne au client au format SSE
                 # Tenter de valider/parser le JSON avant de l'envoyer?
                 try:
                     json.loads(line) # Juste pour valider
                     yield f"data: {line.strip()}\n\n"
                 except json.JSONDecodeError:
                     logger.warning(f"Streaming non-JSON line: {line.strip()}")
                     # Envoyer quand même? Ou seulement les lignes JSON valides?
                     # Pour l'instant, on envoie tout ce que tail sort.
                     yield f"data: {json.dumps({'raw_line': line.strip()})}\n\n" 
                 
        except Exception as e:
             logger.error(f"Error during log streaming: {e}", exc_info=True)
             yield f"data: {json.dumps({'error': f'Log stream encountered an error: {e}'})}\n\n"
        finally:
            if 'proc' in locals() and proc.poll() is None:
                 logger.info("Terminating tail process.")
                 proc.terminate()
                 try:
                     proc.wait(timeout=2)
                 except subprocess.TimeoutExpired:
                     proc.kill()
            logger.info("Log stream stopped.")
            
    # Renvoyer la réponse avec le générateur et le bon mimetype
    return Response(generate(), mimetype='text/event-stream')

# --- ENDPOINTS POUR LES STATISTIQUES (Mis à jour et Nouveaux) --- 

def parse_eve_json_lines(filepath, max_lines=2000, event_filter=None):
    """Lit les N dernières lignes d'eve.json et parse le JSON.
       Retourne une liste d'événements décodés.
       Peut filtrer par event_type si spécifié.
    """
    try:
        with open(filepath, 'r') as f:
            # Utiliser deque pour garder seulement les N dernières lignes en mémoire
            # Ceci est plus efficace que de lire tout le fichier pour les gros logs
            last_lines = deque(f, maxlen=max_lines)
        
        events = []
        for line in last_lines:
            try:
                event = json.loads(line)
                if event_filter is None or event.get('event_type') == event_filter:
                    events.append(event)
            except json.JSONDecodeError:
                logger.warning(f"Skipping malformed JSON line in {filepath}: {line.strip()}")
                continue
        logger.info(f"Parsed {len(events)} events (type: {event_filter or 'any'}) from last {max_lines} lines of {filepath}")
        return events
    except FileNotFoundError:
        logger.error(f"Eve JSON file not found at {filepath}")
        return []
    except Exception as e:
        logger.error(f"Error reading/parsing {filepath}: {e}")
        return []

@app.route('/api/stats/top_signatures', methods=['GET'])
def get_top_signatures():
    """Lit eve.json et retourne les top 10 signatures d'alerte (MODIFIÉ pour utiliser parse_eve_json_lines)."""
    eve_path = os.path.join(app.root_path, LOGS_FOLDER_PATH, EVE_JSON_FILE)
    logger.info(f"Attempting to read alert statistics from: {eve_path}")

    # Lire ~5000 dernières lignes pour trouver des alertes
    events = parse_eve_json_lines(eve_path, max_lines=5000, event_filter='alert') 

    if not events:
        # Pas forcément une erreur, peut juste être vide
        logger.info("No 'alert' events found in recent log lines.")
        return jsonify({"labels": [], "values": []})

    signature_counts = Counter()
    for event in events:
         # Vérifier la structure
        if 'alert' in event and isinstance(event['alert'], dict) and 'signature' in event['alert']:
             signature_counts[event['alert']['signature']] += 1

    top_10 = signature_counts.most_common(10)
    labels = [item[0] for item in top_10]
    values = [item[1] for item in top_10]

    logger.info(f"Found {len(signature_counts)} unique alert signatures in recent lines.")
    return jsonify({"labels": labels, "values": values})

@app.route('/api/stats/latest_counters', methods=['GET'])
def get_latest_counters():
    """Extrait les compteurs du DERNIER événement 'stats' trouvé dans eve.json."""
    eve_path = os.path.join(app.root_path, LOGS_FOLDER_PATH, EVE_JSON_FILE)
    logger.info(f"Attempting to read latest 'stats' event from: {eve_path}")

    # Lire les ~500 dernières lignes (les stats sont fréquentes)
    events = parse_eve_json_lines(eve_path, max_lines=500, event_filter='stats')

    if not events:
        logger.warning("No 'stats' events found in recent log lines.")
        return jsonify({"error": "No recent stats events found."}), 404

    # Le dernier événement dans la liste est le plus récent trouvé dans les lignes lues
    latest_stats_event = events[-1] 
    
    # Extraire les sections intéressantes (capture, decoder, flow, app_layer)
    stats_data = latest_stats_event.get('stats', {})
    counters = {
        "timestamp": latest_stats_event.get("timestamp"),
        "capture": stats_data.get("capture", {}),
        "decoder": stats_data.get("decoder", {}),
        "flow_stats": stats_data.get("flow", {}), # Renommé pour éviter conflit avec app_layer.flow
        "app_layer": stats_data.get("app_layer", {})
    }
    
    logger.info(f"Returning latest counters from timestamp: {counters.get('timestamp')}")
    return jsonify(counters)

@app.route('/api/stats/top_dns', methods=['GET'])
def get_top_dns():
    """Analyse les événements DNS récents pour trouver les noms de domaine les plus demandés."""
    eve_path = os.path.join(app.root_path, LOGS_FOLDER_PATH, EVE_JSON_FILE)
    logger.info(f"Attempting to read DNS query statistics from: {eve_path}")

    # Lire ~2000 dernières lignes pour trouver des requêtes DNS
    events = parse_eve_json_lines(eve_path, max_lines=2000, event_filter='dns') 

    if not events:
        logger.info("No 'dns' events found in recent log lines.")
        return jsonify({"labels": [], "values": []})

    dns_counts = Counter()
    for event in events:
        # Compter seulement les requêtes (type query) et si rrname existe
        if event.get('dns', {}).get('type') == 'query' and 'rrname' in event.get('dns', {}):
            dns_counts[event['dns']['rrname']] += 1

    top_10 = dns_counts.most_common(10)
    labels = [item[0] for item in top_10]
    values = [item[1] for item in top_10]

    logger.info(f"Found {len(dns_counts)} unique DNS query names in recent lines.")
    return jsonify({"labels": labels, "values": values})

@app.route('/api/stats/top_tls_sni', methods=['GET'])
def get_top_tls_sni():
    """Analyse les événements TLS récents pour trouver les SNI les plus fréquents."""
    eve_path = os.path.join(app.root_path, LOGS_FOLDER_PATH, EVE_JSON_FILE)
    logger.info(f"Attempting to read TLS SNI statistics from: {eve_path}")

    # Lire ~2000 dernières lignes pour trouver des événements TLS
    events = parse_eve_json_lines(eve_path, max_lines=2000, event_filter='tls') 

    if not events:
        logger.info("No 'tls' events found in recent log lines.")
        return jsonify({"labels": [], "values": []})

    sni_counts = Counter()
    for event in events:
        # Vérifier si tls.sni existe
        if 'sni' in event.get('tls', {}):
            sni_counts[event['tls']['sni']] += 1

    top_10 = sni_counts.most_common(10)
    labels = [item[0] for item in top_10]
    values = [item[1] for item in top_10]

    logger.info(f"Found {len(sni_counts)} unique TLS SNIs in recent lines.")
    return jsonify({"labels": labels, "values": values})

# --- NOUVEL ENDPOINT POUR L'HISTORIQUE DES PAQUETS --- 
@app.route('/api/stats/capture_history', methods=['GET'])
def get_capture_history():
    """Récupère l'historique récent des paquets capturés/perdus à partir des événements stats."""
    eve_path = os.path.join(app.root_path, LOGS_FOLDER_PATH, EVE_JSON_FILE)
    logger.info(f"Attempting to read capture history from: {eve_path}")

    # Lire un nombre suffisant de lignes pour avoir plusieurs points de stats
    # Ajuster max_lines en fonction de la fréquence des stats (souvent toutes les 8-10s)
    # 500 lignes -> ~40-50 points de stats si log toutes les 10s ?
    events = parse_eve_json_lines(eve_path, max_lines=500, event_filter='stats')

    if not events:
        logger.warning("No 'stats' events found for capture history.")
        return jsonify({"timestamps": [], "packets": [], "drops": []})

    timestamps = []
    packets = []
    drops = []

    for event in events:
        stats_data = event.get('stats', {})
        capture_data = stats_data.get('capture', {})
        timestamp = event.get("timestamp")
        # Utiliser kernel_packets/kernel_drops ou le total pkts/drop ?
        # kernel_* semble plus spécifique à l'interface de capture
        pkt_count = capture_data.get('kernel_packets') 
        drop_count = capture_data.get('kernel_drops')

        # On a besoin du timestamp et des compteurs pour ajouter un point
        if timestamp is not None and pkt_count is not None and drop_count is not None:
            # Convertir le timestamp ISO en quelque chose que Chart.js time adapter comprend
            # Le format ISO 8601 est généralement bien géré par les adapters
            timestamps.append(timestamp)
            packets.append(pkt_count)
            drops.append(drop_count)

    logger.info(f"Returning capture history with {len(timestamps)} data points.")
    return jsonify({"timestamps": timestamps, "packets": packets, "drops": drops})

if __name__ == '__main__':
    # Make sure to run with a production server like gunicorn or waitress in production
    app.run(host='0.0.0.0', port=5001, debug=True) # Use a different port than common defaults 