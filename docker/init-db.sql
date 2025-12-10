-- DDGo Database Initialization Script
-- This script runs on first container startup

-- Create extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- Create schemas
CREATE SCHEMA IF NOT EXISTS app;

-- Sample tables for demonstration
CREATE TABLE IF NOT EXISTS app.searches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    query TEXT NOT NULL,
    results_count INTEGER DEFAULT 0,
    user_ip INET,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS app.metrics (
    id SERIAL PRIMARY KEY,
    metric_name VARCHAR(255) NOT NULL,
    metric_value DECIMAL(10, 4),
    labels JSONB,
    recorded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_searches_created_at ON app.searches(created_at);
CREATE INDEX IF NOT EXISTS idx_searches_query ON app.searches(query);
CREATE INDEX IF NOT EXISTS idx_metrics_recorded_at ON app.metrics(recorded_at);
CREATE INDEX IF NOT EXISTS idx_metrics_name ON app.metrics(metric_name);

-- Grant permissions
GRANT ALL PRIVILEGES ON SCHEMA app TO ddgo;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA app TO ddgo;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA app TO ddgo;

-- Insert sample data
INSERT INTO app.searches (query, results_count) VALUES
    ('example search', 10),
    ('test query', 5),
    ('sample', 15);

COMMIT;
