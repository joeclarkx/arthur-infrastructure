# Maintenance & Operations

## Regular Tasks

### Daily
- Monitor service health: `ssh hetzner "systemctl status umami"`
- Check logs for errors: `ssh hetzner "journalctl -u umami --since 'today' | grep -i error"`

### Weekly
- Database maintenance (VACUUM, REINDEX):
  ```bash
  ssh hetzner "sudo -u postgres vacuumdb umami && sudo -u postgres reindexdb umami"
  ```
- Review analytics growth: `ssh hetzner "echo 'SELECT COUNT(*) FROM events;' | psql 'postgresql://umami@localhost/umami'"`
- Check disk space: `ssh hetzner "df -h /"`

### Monthly
- Review system updates: `ssh hetzner "apt list --upgradable"`
- Archive old event data (if storage is tight)
- Backup database (see Backups section)

### Quarterly
- Update Umami to latest stable release (see docs/umami-deployment.md)
- Audit Apache logs for errors: `ssh hetzner "tail -100 /var/log/apache2/error.log"`
- Review Let's Encrypt certificate status: `ssh hetzner "certbot certificates"`

## Backups

**Current Status:** Manual only (TODO: automate via cron)

### Manual Database Backup

```bash
ssh hetzner "sudo -u postgres pg_dump umami > /tmp/umami-backup-$(date +%Y%m%d).sql"
scp hetzner:/tmp/umami-backup-*.sql ~/backups/
ssh hetzner "rm /tmp/umami-backup-*.sql"
```

### Restore from Backup

```bash
scp ~/backups/umami-backup-YYYYMMDD.sql hetzner:/tmp/
ssh hetzner "sudo -u postgres psql umami < /tmp/umami-backup-YYYYMMDD.sql"
ssh hetzner "systemctl restart umami"
```

### Automated Backups (TODO)

- [ ] Script: `scripts/umami/backup.sh` (daily, to local storage)
- [ ] S3 sync: Push weekly dumps to Backblaze B2 cold storage
- [ ] Retention: Keep 30 days locally, 1 year in cold storage
- [ ] Restore test: Monthly restore drill to verify backups work

## Capacity Planning

### Database Growth

Umami stores events in PostgreSQL. Growth rate depends on:
- Website traffic volume
- Number of websites tracked
- Event retention period

**Monitoring:**
```bash
ssh hetzner "echo 'SELECT pg_size_pretty(pg_database_size(''umami''));' | psql -U postgres"
```

**Alert thresholds:**
- Database > 500MB: Consider archiving old data
- Database > 1GB: Plan upgrade or data cleanup

### Server Resources

Current: **2GB RAM, 40GB SSD**

Monitor:
```bash
ssh hetzner "free -h && df -h / && ps aux --sort=-%mem | head -10"
```

If consistently >80% RAM or disk:
- Archive event data older than 1 year
- Migrate to CX31 instance (4GB RAM, 80GB SSD)
- Implement caching layer (Redis)

## Troubleshooting

### High CPU Usage

```bash
# Check which process
ssh hetzner "top -b -n 1 | head -20"

# Check PostgreSQL queries
ssh hetzner "echo 'SELECT pid, usename, query FROM pg_stat_activity;' | psql -U postgres umami"
```

**Common causes:**
- Slow analytics queries (high traffic spike)
- Index fragmentation (run REINDEX)
- Long-running background job

### Database Bloat

```bash
ssh hetzner "echo 'SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'\''.'\''||tablename)) FROM pg_tables ORDER BY pg_total_relation_size(schemaname||'\''.'\''||tablename) DESC;' | psql -U postgres umami"
```

If specific tables are large (events, sessions), archive old data:

```bash
ssh hetzner "psql umami"
# Then in psql:
DELETE FROM events WHERE timestamp < NOW() - INTERVAL '2 years';
VACUUM events;
REINDEX TABLE events;
```

### SSL Certificate Renewal

Let's Encrypt certificates auto-renew via certbot cron. Check status:

```bash
ssh hetzner "sudo certbot renew --dry-run"
ssh hetzner "sudo certbot certificates"
```

If renewal fails, manually trigger:
```bash
ssh hetzner "sudo certbot renew --force-renewal"
ssh hetzner "systemctl reload apache2"
```

## Monitoring Setup (TODO)

Plan:
- [ ] Health check script: `scripts/monitoring/health-check.sh` (runs every 5 min)
- [ ] Alerting: Send email/Slack on service failure
- [ ] Metrics: Export Prometheus-compatible metrics
- [ ] Dashboard: Simple status page at `status.joeclark.photo`

## Security Hardening (TODO)

- [ ] Fail2ban: Rate-limit login attempts
- [ ] WAF rules: Protect against common attacks
- [ ] Audit logging: Track admin actions in Umami
- [ ] Secrets rotation: Expire API keys annually
