from flask import Flask, send_from_directory, request, Response
import requests
import os

app = Flask(__name__, static_folder='.', static_url_path='')

OLLAMA_API_URL = os.environ.get('OLLAMA_API_URL', 'http://localhost:11434')

@app.route('/')
def serve_index():
    return "<h1>Hello from Flask!</h1>"

@app.route('/api/<path:subpath>', methods=['GET', 'POST', 'PUT', 'DELETE'])
def proxy_ollama_api(subpath):
    # Construct the target URL for Ollama API
    target_url = f"{OLLAMA_API_URL}/v1/{subpath}"

    try:
        # Forward the request to Ollama
        if request.method == 'POST':
            resp = requests.post(target_url, json=request.get_json(), stream=True)
        elif request.method == 'GET':
            resp = requests.get(target_url, params=request.args, stream=True)
        else:
            # Handle other methods if necessary, or return error
            return Response("Method not supported", status=405)

        # Stream the response back to the client
        return Response(resp.iter_content(chunk_size=10*1024),
                        status=resp.status_code,
                        content_type=resp.headers['Content-Type'])

    except requests.exceptions.ConnectionError as e:
        return Response(f"Failed to connect to Ollama: {e}", status=503)
    except Exception as e:
        return Response(f"Proxy error: {e}", status=500)

if __name__ == '__main__':
    app.run(port=8080)