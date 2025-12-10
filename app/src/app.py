"""
DDGo API - Sample Flask Application
Demonstrates containerization, health checks, and monitoring integration.
"""

import os
import time
import logging
from datetime import datetime
from functools import wraps

from flask import Flask, jsonify, request, g
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
import redis
import psycopg2
from psycopg2 import pool

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Configuration from environment
config = {
    'DB_HOST': os.getenv('DB_HOST', 'localhost'),
    'DB_PORT': os.getenv('DB_PORT', '5432'),
    'DB_NAME': os.getenv('DB_NAME', 'ddgo'),
    'DB_USER': os.getenv('DB_USER', 'ddgo'),
    'DB_PASSWORD': os.getenv('DB_PASSWORD', 'ddgo'),
    'REDIS_HOST': os.getenv('REDIS_HOST', 'localhost'),
    'REDIS_PORT': os.getenv('REDIS_PORT', '6379'),
    'ENVIRONMENT': os.getenv('ENVIRONMENT', 'development'),
}

# Prometheus metrics
REQUEST_COUNT = Counter(
    'ddgo_requests_total',
    'Total request count',
    ['method', 'endpoint', 'status']
)
REQUEST_LATENCY = Histogram(
    'ddgo_request_latency_seconds',
    'Request latency in seconds',
    ['method', 'endpoint']
)

# Database connection pool (lazy initialization)
db_pool = None
redis_client = None


def get_db_pool():
    """Get or create database connection pool."""
    global db_pool
    if db_pool is None:
        try:
            db_pool = psycopg2.pool.ThreadedConnectionPool(
                minconn=1,
                maxconn=10,
                host=config['DB_HOST'],
                port=config['DB_PORT'],
                database=config['DB_NAME'],
                user=config['DB_USER'],
                password=config['DB_PASSWORD'],
            )
            logger.info("Database connection pool created")
        except Exception as e:
            logger.error(f"Failed to create database pool: {e}")
            raise
    return db_pool


def get_redis():
    """Get or create Redis client."""
    global redis_client
    if redis_client is None:
        try:
            redis_client = redis.Redis(
                host=config['REDIS_HOST'],
                port=int(config['REDIS_PORT']),
                decode_responses=True
            )
            redis_client.ping()
            logger.info("Redis connection established")
        except Exception as e:
            logger.warning(f"Redis not available: {e}")
            redis_client = None
    return redis_client


def track_metrics(f):
    """Decorator to track request metrics."""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        start_time = time.time()
        try:
            response = f(*args, **kwargs)
            status = response[1] if isinstance(response, tuple) else 200
            return response
        except Exception as e:
            status = 500
            raise
        finally:
            latency = time.time() - start_time
            REQUEST_COUNT.labels(
                method=request.method,
                endpoint=request.endpoint or 'unknown',
                status=status
            ).inc()
            REQUEST_LATENCY.labels(
                method=request.method,
                endpoint=request.endpoint or 'unknown'
            ).observe(latency)
    return decorated_function


@app.before_request
def before_request():
    """Record request start time."""
    g.start_time = time.time()


@app.after_request
def after_request(response):
    """Log request details."""
    if hasattr(g, 'start_time'):
        latency = time.time() - g.start_time
        logger.info(
            f"{request.method} {request.path} - {response.status_code} - {latency:.3f}s"
        )
    return response


@app.route('/health')
def health():
    """
    Basic health check endpoint.
    Used by load balancers and container orchestrators.
    """
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.utcnow().isoformat(),
        'environment': config['ENVIRONMENT'],
    })


@app.route('/health/ready')
@track_metrics
def readiness():
    """
    Readiness probe - checks if app can serve traffic.
    Verifies database and cache connectivity.
    """
    checks = {
        'database': False,
        'cache': False,
    }

    # Check database
    try:
        pool = get_db_pool()
        conn = pool.getconn()
        try:
            with conn.cursor() as cur:
                cur.execute('SELECT 1')
            checks['database'] = True
        finally:
            pool.putconn(conn)
    except Exception as e:
        logger.error(f"Database health check failed: {e}")

    # Check Redis (optional - don't fail if unavailable)
    try:
        r = get_redis()
        if r and r.ping():
            checks['cache'] = True
    except Exception as e:
        logger.warning(f"Redis health check failed: {e}")

    # Determine overall status
    is_ready = checks['database']  # DB is required, cache is optional
    status_code = 200 if is_ready else 503

    return jsonify({
        'status': 'ready' if is_ready else 'not_ready',
        'checks': checks,
        'timestamp': datetime.utcnow().isoformat(),
    }), status_code


@app.route('/health/live')
def liveness():
    """
    Liveness probe - checks if app process is alive.
    Simple check that the app can respond.
    """
    return jsonify({
        'status': 'alive',
        'timestamp': datetime.utcnow().isoformat(),
    })


@app.route('/metrics')
def metrics():
    """Prometheus metrics endpoint."""
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}


@app.route('/api/v1/search', methods=['POST'])
@track_metrics
def search():
    """
    Sample search endpoint.
    Demonstrates request handling, caching, and database access.
    """
    data = request.get_json() or {}
    query = data.get('query', '')

    if not query:
        return jsonify({'error': 'Query parameter required'}), 400

    # Check cache first
    cache_key = f"search:{query}"
    r = get_redis()
    if r:
        try:
            cached = r.get(cache_key)
            if cached:
                logger.info(f"Cache hit for query: {query}")
                return jsonify({
                    'query': query,
                    'results': eval(cached),  # In production, use json.loads
                    'cached': True,
                })
        except Exception as e:
            logger.warning(f"Cache read failed: {e}")

    # Simulate search results
    results = [
        {'id': 1, 'title': f'Result for {query}', 'score': 0.95},
        {'id': 2, 'title': f'Another result for {query}', 'score': 0.87},
    ]

    # Cache results
    if r:
        try:
            r.setex(cache_key, 300, str(results))  # Cache for 5 minutes
        except Exception as e:
            logger.warning(f"Cache write failed: {e}")

    return jsonify({
        'query': query,
        'results': results,
        'cached': False,
    })


@app.route('/api/v1/info')
@track_metrics
def info():
    """Return application information."""
    return jsonify({
        'name': 'DDGo API',
        'version': os.getenv('APP_VERSION', '1.0.0'),
        'environment': config['ENVIRONMENT'],
        'python_version': os.popen('python --version').read().strip(),
    })


@app.errorhandler(404)
def not_found(e):
    """Handle 404 errors."""
    return jsonify({'error': 'Not found'}), 404


@app.errorhandler(500)
def server_error(e):
    """Handle 500 errors."""
    logger.error(f"Internal server error: {e}")
    return jsonify({'error': 'Internal server error'}), 500


if __name__ == '__main__':
    port = int(os.getenv('PORT', 5000))
    debug = config['ENVIRONMENT'] == 'development'

    logger.info(f"Starting DDGo API on port {port} (environment: {config['ENVIRONMENT']})")
    app.run(host='0.0.0.0', port=port, debug=debug)
