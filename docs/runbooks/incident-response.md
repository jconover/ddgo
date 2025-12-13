# Incident Response Runbook

## Overview

This runbook provides procedures for responding to incidents affecting the DDGo platform.

## Severity Levels

| Level | Description | Response Time | Examples |
|-------|-------------|---------------|----------|
| SEV1 | Critical - Complete outage | 15 minutes | All services down, data breach |
| SEV2 | Major - Significant degradation | 30 minutes | Partial outage, high error rate |
| SEV3 | Minor - Limited impact | 2 hours | Single component degraded |
| SEV4 | Low - Minimal impact | Next business day | Non-critical bug |

## Initial Response

### 1. Acknowledge the Incident

```bash
# Check current alerts
curl -s http://alertmanager:9093/api/v2/alerts | jq '.[] | {alertname, severity, status}'

# Acknowledge in PagerDuty/Slack
# Document the incident start time
```

### 2. Assess Impact

```bash
# Check application health
curl -s http://<ALB_DNS>/health | jq .
curl -s http://<ALB_DNS>/health/ready | jq .

# Check error rates (Prometheus)
curl -s 'http://prometheus:9090/api/v1/query?query=sum(rate(ddgo_requests_total{status=~"5.."}[5m]))/sum(rate(ddgo_requests_total[5m]))'

# Check service status
aws ecs describe-services --cluster ddgo-prod --services ddgo-prod-app
```

### 3. Initial Communication

- Post in #ddgo-incidents Slack channel
- Page on-call engineer if SEV1/SEV2
- Update status page if customer-facing

## Common Issues and Resolutions

### Application Unreachable

**Symptoms**: Health checks failing, ALB returning 5xx errors

**Investigation**:
```bash
# Check ECS service status
aws ecs describe-services --cluster ddgo-prod --services ddgo-prod-app \
  --query 'services[0].{desired:desiredCount,running:runningCount,pending:pendingCount}'

# Check task logs
aws logs tail /aws/ecs/ddgo-prod/app --since 30m

# Check target group health
aws elbv2 describe-target-health --target-group-arn <TARGET_GROUP_ARN>
```

**Resolution**:
```bash
# Force new deployment
aws ecs update-service --cluster ddgo-prod --service ddgo-prod-app --force-new-deployment

# Or rollback to previous task definition
aws ecs update-service --cluster ddgo-prod --service ddgo-prod-app \
  --task-definition <PREVIOUS_TASK_DEF_ARN>
```

### High Error Rate

**Symptoms**: Error rate above threshold, users reporting failures

**Investigation**:
```bash
# Check recent errors in logs
aws logs filter-log-events \
  --log-group-name /aws/ecs/ddgo-prod/app \
  --filter-pattern "ERROR" \
  --start-time $(date -d '30 minutes ago' +%s000)

# Check database connectivity
aws rds describe-db-instances --db-instance-identifier ddgo-prod \
  --query 'DBInstances[0].DBInstanceStatus'

# Check Redis connectivity
aws elasticache describe-cache-clusters --cache-cluster-id ddgo-prod-redis
```

**Resolution**:
```bash
# If database issue, check connections
psql -h <RDS_ENDPOINT> -U ddgo_admin -d ddgo -c "SELECT count(*) FROM pg_stat_activity;"

# If Redis issue, flush cache
redis-cli -h <REDIS_ENDPOINT> FLUSHDB

# Restart affected containers
aws ecs update-service --cluster ddgo-prod --service ddgo-prod-app --force-new-deployment
```

### High Latency

**Symptoms**: P95 latency above threshold, slow responses

**Investigation**:
```bash
# Check Prometheus for latency breakdown
curl -s 'http://prometheus:9090/api/v1/query?query=histogram_quantile(0.95,rate(ddgo_request_latency_seconds_bucket[5m]))'

# Check database slow queries
aws logs filter-log-events \
  --log-group-name /aws/rds/instance/ddgo-prod/postgresql \
  --filter-pattern "duration" \
  --start-time $(date -d '30 minutes ago' +%s000)

# Check CPU/memory utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ClusterName,Value=ddgo-prod Name=ServiceName,Value=ddgo-prod-app \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Average
```

**Resolution**:
```bash
# Scale up ECS service
aws ecs update-service --cluster ddgo-prod --service ddgo-prod-app --desired-count 10

# Or scale database if connection-limited
# (requires infrastructure change via Terraform)
```

### Database Connection Issues

**Symptoms**: Connection refused, timeout errors, connection pool exhausted

**Investigation**:
```bash
# Check RDS status
aws rds describe-db-instances --db-instance-identifier ddgo-prod

# Check connection count
psql -h <RDS_ENDPOINT> -U ddgo_admin -d ddgo -c \
  "SELECT count(*), state FROM pg_stat_activity GROUP BY state;"

# Check for blocking queries
psql -h <RDS_ENDPOINT> -U ddgo_admin -d ddgo -c \
  "SELECT pid, now() - pg_stat_activity.query_start AS duration, query
   FROM pg_stat_activity
   WHERE state != 'idle'
   ORDER BY duration DESC
   LIMIT 10;"
```

**Resolution**:
```bash
# Terminate long-running queries
psql -h <RDS_ENDPOINT> -U ddgo_admin -d ddgo -c \
  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE duration > interval '5 minutes';"

# Restart application to reset connection pool
aws ecs update-service --cluster ddgo-prod --service ddgo-prod-app --force-new-deployment
```

## Post-Incident

### 1. Verify Recovery

```bash
# Verify all health checks passing
curl -sf http://<ALB_DNS>/health && echo "Healthy"
curl -sf http://<ALB_DNS>/health/ready && echo "Ready"

# Verify error rate normalized
# Check Grafana dashboard
```

### 2. Document Timeline

Create a timeline in the incident ticket:
- When alerts fired
- When acknowledged
- Actions taken
- When resolved

### 3. Schedule Post-Mortem

For SEV1/SEV2 incidents:
- Schedule post-mortem within 48 hours
- Identify root cause
- Document action items
- Update runbooks if needed

## Escalation Contacts

| Role | Primary | Secondary |
|------|---------|-----------|
| On-Call Engineer | See PagerDuty | See PagerDuty |
| Infrastructure Lead | [Name] | [Name] |
| Database Admin | [Name] | [Name] |
| Security | [Name] | [Name] |

## Related Runbooks

- [Database Operations](database-operations.md)
- [Scaling Procedures](scaling.md)
- [Disaster Recovery](disaster-recovery.md)
