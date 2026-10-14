# Hobby server — rebuild notes

Everything needed to rebuild the server from scratch. **No secrets in this file** — those live in the password manager and in `~/supabase-project/.env` on the server.

## What runs where

| Piece | Where | Notes |
|---|---|---|
| Server | OVHcloud VPS-2 (8 GB), Hillsboro, Ubuntu 26.04 LTS | IP `40.160.150.92`, user `ubuntu`, SSH key only |
| Supabase | `~/supabase-project` on the server | self-hosted v0.8.2, Caddy for HTTPS |
| Public URL | `https://supabase.erichenry.com` | Cloudflare DNS A record, **DNS only** (grey cloud) |
| Dashboard | same URL in a browser | login in password manager: “Hobby server – Supabase dashboard” |
| Backups | server `~/backups` → NAS `/Volume1/vps-backups` | server keeps 2 days, NAS keeps 60 |
| Monitoring | healthchecks.io | checks “VPS Backup” and “NAS pull”, email alerts |

## Password manager entries

- Hobby server – emergency login (OVH console) — `ubuntu` password, for sudo / OVH web console only
- Hobby server – Supabase dashboard — `DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD`
- VPS Supabase (secure note) — full copy of `~/supabase-project/.env` (all keys and passwords). Re-copy it after every `.env` change, from the Mac: `ssh ubuntu@40.160.150.92 'cat ~/supabase-project/.env' | pbcopy`
- OVHcloud account, Healthchecks.io account, NAS admin

## Rebuild, step by step

### 1. Order and log in
- OVH VPS: no commitment, Hillsboro, Ubuntu LTS.
- From the Mac: `ssh ubuntu@<IP>` (change forced password), then `ssh-copy-id ubuntu@<IP>`.

### 2. Lock down
```sh
sudo apt update && sudo apt full-upgrade -y
printf "PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin no\n" | sudo tee /etc/ssh/sshd_config.d/00-hardening.conf
sudo systemctl reload ssh
sudo ufw allow OpenSSH && sudo ufw allow 80 && sudo ufw allow 443 && sudo ufw --force enable
printf 'Unattended-Upgrade::Automatic-Reboot "true";\nUnattended-Upgrade::Automatic-Reboot-Time "04:00";\n' | sudo tee /etc/apt/apt.conf.d/52-auto-reboot
sudo reboot
```

### 3. DNS
Cloudflare → erichenry.com → A record `supabase` → server IP, **DNS only**.

### 4. Install Supabase
```sh
curl -fsSL https://raw.githubusercontent.com/supabase/supabase/master/docker/setup.sh -o setup.sh
sh setup.sh
#   SUPABASE_PUBLIC_URL: https://supabase.erichenry.com
#   API_EXTERNAL_URL:    (Enter)
#   SITE_URL:            https://spoonfloor.github.io
#   PROXY_DOMAIN:        (Enter)
exit   # log back in so the docker group applies
```
```sh
cd ~/supabase-project
sh run.sh config add caddy
cat > docker-compose.local.yml <<'YML'
services:
  supavisor:
    ports: !override
      - "127.0.0.1:5432:5432"
      - "127.0.0.1:6543:6543"
YML
sh run.sh config add local
# Rebuilding? Replace the generated .env with the “VPS Supabase” note now (nano .env),
# so the old keys carry over and existing apps keep working. Then skip the next two seds.
sed -i 's/^DISABLE_SIGNUP=.*/DISABLE_SIGNUP=true/' .env
sed -i 's/^PGRST_DB_SCHEMAS=.*/PGRST_DB_SCHEMAS=public,graphql_public,relationships/' .env
printf '{\n  "log-driver": "local",\n  "log-opts": { "max-size": "10m", "max-file": "3" }\n}\n' | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker
sh run.sh start
```
Why: Caddy = HTTPS; `local` override keeps the database port off the internet (Docker bypasses ufw); sign-ups off; app schemas exposed to the API (see “Apps on this server”; `.env` isn’t in the database backup, which is why the note exists); logs capped.

### 5. Restore data (if rebuilding)
Copy the newest `supabase-YYYYMMDD.sql.gz` from the NAS to the server, then:
```sh
PW=$(grep '^POSTGRES_PASSWORD=' ~/supabase-project/.env | cut -d= -f2-)
gunzip -c supabase-YYYYMMDD.sql.gz | docker exec -i -e PGPASSWORD="$PW" supabase-db psql -U supabase_admin -h localhost -d postgres
```
(Untested so far — do a practice restore before relying on it.)

### 6. Nightly backup on the server
`~/backup-db.sh` (bash): `pg_dumpall` → `~/backups/supabase-YYYYMMDD.sql.gz`, keeps 2, pings Healthchecks “VPS Backup”, reports failure if disk ≥ 80%.
Cron: `15 3 * * * /home/ubuntu/backup-db.sh` (03:15 UTC).

### 7. NAS pull
- NAS key: `/Volume1/vps-backups/.ssh/id_ed25519` (chmod 600).
- On the server, `~/.ssh/authorized_keys` line, read-only and limited to the backups folder:
  `command="rrsync -ro /home/ubuntu/backups",restrict ssh-ed25519 AAAA… nas-backup`
- NAS script `/Volume1/vps-backups/pull.sh`: rsync from server, delete copies > 60 days, ping Healthchecks “NAS pull”.
- NAS container (Docker Manager app doesn’t work; use SSH, port 9222):
```sh
docker run -d --name vps-backup --restart unless-stopped -v /Volume1/vps-backups:/backups alpine:3.22 sh -c 'apk add -q --no-cache openssh-client rsync && echo "0 5 * * * sh /backups/pull.sh >> /backups/pull.log 2>&1" > /etc/crontabs/root && exec crond -f'
```
Runs 05:00 UTC.

## Apps on this server

| App | Schema | Repo | Setup SQL |
|---|---|---|---|
| Relationships | `relationships` | `spoonfloor/relationships` | `supabase/schema.sql` |

## Adding an app
1. In the dashboard SQL editor, create its tables in its own schema, and grant access: `grant usage on schema <name> to anon, authenticated, service_role;` plus table grants to `anon, authenticated` (RLS still applies). Without the grants, the API returns “permission denied.”
2. Enable row level security on every table.
3. Add the schema to `PGRST_DB_SCHEMAS` in `.env`, then `sh run.sh recreate rest`. Also add it to the `PGRST_DB_SCHEMAS` line in step 4 and to the table above.
4. In the app: URL `https://supabase.erichenry.com`, key = `ANON_KEY` from `.env` (public by design), and `createClient(url, key, { db: { schema: "<name>" } })`.

## Useful commands (on the server, in `~/supabase-project`)
- `sh run.sh status` — are services healthy?
- `sh run.sh logs <service>` — e.g. `rest`, `auth`, `caddy`
- `sh run.sh restart`
- `df -h /` — disk space
