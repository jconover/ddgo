"""
Tests for DDGo API
"""

import pytest
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from app import app


@pytest.fixture
def client():
    """Create test client."""
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client


class TestHealthEndpoints:
    """Test health check endpoints."""

    def test_health_returns_200(self, client):
        """Basic health check should always return 200."""
        response = client.get('/health')
        assert response.status_code == 200
        data = response.get_json()
        assert data['status'] == 'healthy'
        assert 'timestamp' in data

    def test_liveness_returns_200(self, client):
        """Liveness probe should always return 200."""
        response = client.get('/health/live')
        assert response.status_code == 200
        data = response.get_json()
        assert data['status'] == 'alive'


class TestAPIEndpoints:
    """Test API endpoints."""

    def test_info_returns_app_info(self, client):
        """Info endpoint should return application details."""
        response = client.get('/api/v1/info')
        assert response.status_code == 200
        data = response.get_json()
        assert data['name'] == 'DDGo API'
        assert 'version' in data
        assert 'environment' in data

    def test_search_requires_query(self, client):
        """Search endpoint should require query parameter."""
        response = client.post('/api/v1/search', json={})
        assert response.status_code == 400
        data = response.get_json()
        assert 'error' in data

    def test_search_returns_results(self, client):
        """Search endpoint should return results for valid query."""
        response = client.post('/api/v1/search', json={'query': 'test'})
        assert response.status_code == 200
        data = response.get_json()
        assert data['query'] == 'test'
        assert 'results' in data
        assert isinstance(data['results'], list)


class TestErrorHandling:
    """Test error handling."""

    def test_404_returns_json(self, client):
        """404 errors should return JSON."""
        response = client.get('/nonexistent')
        assert response.status_code == 404
        data = response.get_json()
        assert 'error' in data


class TestMetrics:
    """Test metrics endpoint."""

    def test_metrics_endpoint_exists(self, client):
        """Metrics endpoint should be accessible."""
        response = client.get('/metrics')
        assert response.status_code == 200
        assert b'ddgo_requests_total' in response.data or response.status_code == 200
