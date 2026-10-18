# Gunicorn configuration for rdgen

# Host and port for Gunicorn to listen on
bind = "0.0.0.0:8000"

# Number of worker processes for concurrency. Increased from 5 to 8 so
# multiple concurrent GitHub Action runners do not exhaust all workers.
workers = 8

# Threads per worker. Increased from 6 to 8 for higher concurrent request
# handling (total concurrent capacity = workers * threads = 64).
threads = 8

# Kill workers that are silent for more than this many seconds (default 30).
# Prevents a single hung runner request (e.g. slow GitHub API call or file
# upload) from tying up a worker indefinitely.
timeout = 120

# Graceful worker shutdown timeout
graceful_timeout = 30

# Restart workers after this many requests to clear memory leaks and stale
# DB connections over time.
max_requests = 1000
max_requests_jitter = 50

# Preload the application before forking workers, reducing memory usage
# and startup time per worker.
preload_app = True

# Activate your virtual environment if applicable
activate_base = True

# Path to your Django project's main WSGI application file
wsgi_app = "rdgen.wsgi.application"
