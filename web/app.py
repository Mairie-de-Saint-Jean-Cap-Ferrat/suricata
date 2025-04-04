import os
import socket
import json
import logging
from flask import Flask, request, jsonify, send_from_directory

# Assuming the Flask app is run from the /app/web directory as set in Dockerfile.webinterface
# We need to serve static files (HTML, CSS, JS) from the 'web' directory relative to the CWD
# and logs from the mounted 'logs' directory.
# Flask looks for static files relative to its root_path or a specified static_folder.
STATIC_FOLDER_PATH = '.' # Serve from the current working directory (/app/web)
LOGS_FOLDER_PATH = 'logs' # Where logs will be mounted/available

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
        return send_from_directory(logs_dir, filename, mimetype='text/plain')
    except FileNotFoundError:
        logger.warning(f"Log file not found: {filename} in {logs_dir}")
        # Return empty content with 200 OK, as the frontend handles this message.
        # Returning 404 might be treated as a general fetch error by the frontend.
        return "", 200 # Or return jsonify({"error": f"Log file '{filename}' not found"}), 404

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

if __name__ == '__main__':
    # Make sure to run with a production server like gunicorn or waitress in production
    app.run(host='0.0.0.0', port=5001, debug=True) # Use a different port than common defaults 