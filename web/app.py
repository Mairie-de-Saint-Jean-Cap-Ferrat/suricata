import os
import socket
import json
import logging
from collections import Counter
from flask import Flask, request, jsonify, send_from_directory

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

# --- NOUVEL ENDPOINT POUR LES STATISTIQUES ---
@app.route('/api/stats/top_signatures', methods=['GET'])
def get_top_signatures():
    """Reads eve.json and returns the top 10 alert signatures."""
    eve_path = os.path.join(app.root_path, LOGS_FOLDER_PATH, EVE_JSON_FILE)
    logger.info(f"Attempting to read statistics from: {eve_path}")

    if not os.path.exists(eve_path):
        logger.error(f"Statistics file not found: {eve_path}")
        return jsonify({"error": f"{EVE_JSON_FILE} not found in the logs directory."}), 404

    signature_counts = Counter()
    lines_processed = 0
    errors_parsing = 0

    try:
        with open(eve_path, 'r') as f:
            for line in f:
                lines_processed += 1
                try:
                    event = json.loads(line)
                    # Vérifier si c'est une alerte et si la signature existe
                    if event.get('event_type') == 'alert' and 'alert' in event and 'signature' in event['alert']:
                        signature_counts[event['alert']['signature']] += 1
                except json.JSONDecodeError:
                    errors_parsing += 1
                    # Logger l'erreur peut être trop verbeux, on logue juste à la fin si besoin
                    continue # Passer à la ligne suivante en cas d'erreur JSON

        if errors_parsing > 0:
             logger.warning(f"Encountered {errors_parsing} JSON decoding errors while processing {eve_path}.")

        # Obtenir les 10 signatures les plus fréquentes
        top_10 = signature_counts.most_common(10)

        # Préparer les données pour Chart.js
        labels = [item[0] for item in top_10]
        values = [item[1] for item in top_10]

        logger.info(f"Successfully processed {lines_processed} lines from {eve_path}. Found {len(signature_counts)} unique signatures.")
        return jsonify({"labels": labels, "values": values})

    except FileNotFoundError: # Double check, bien que déjà fait plus haut
         logger.error(f"File not found error during processing: {eve_path}")
         return jsonify({"error": f"{EVE_JSON_FILE} not found during processing."}), 404
    except Exception as e:
        logger.error(f"An unexpected error occurred while processing statistics: {e}")
        return jsonify({"error": f"An unexpected error occurred while processing {EVE_JSON_FILE}: {e}"}), 500

if __name__ == '__main__':
    # Make sure to run with a production server like gunicorn or waitress in production
    app.run(host='0.0.0.0', port=5001, debug=True) # Use a different port than common defaults 