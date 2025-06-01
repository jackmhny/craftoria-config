#!/usr/bin/env bash
set -euo pipefail
source /root/.borg-env

LOCAL_DIR="/opt/minecraft"
SERVICE="minecraft@craftoria.service"
LOG="/var/log/minecraft-borg.log"

RCON_HOST="127.0.0.1"
RCON_PORT="25575"
RCON_PASSWORD="fastest,slipping,frosty,jacks"

BACKUP_NOW=false

# Parse command line arguments
for arg in "$@"; do
  if [ "$arg" == "--now" ]; then
    BACKUP_NOW=true
  fi
done

log(){ printf '[%(%F %T)T] %s\n' -1 "$*" | tee -a "$LOG"; }

trap 'log "ERROR: backup failed"; systemctl start "$SERVICE" 2>/dev/null || true' ERR

# 1) Notify & stop server
if systemctl is-active --quiet "$SERVICE"; then
  if [ "$BACKUP_NOW" = true ]; then
    log "Immediate backup requested (--now flag). Skipping countdown."
  else
    log "Notifying players: restart in 1 minute…"
  fi

  # allow RCON failures without exiting
  set +e

  mcrcon -H "$RCON_HOST" -P "$RCON_PORT" -p "$RCON_PASSWORD" save-all
  if [ $? -ne 0 ]; then
    log "Warning: save-all via RCON failed"
  fi

  if [ "$BACKUP_NOW" = false ]; then
    # Only do warning countdown if not immediate backup
    mcrcon -H "$RCON_HOST" -P "$RCON_PORT" -p "$RCON_PASSWORD" \
      'tellraw @a {"text":"","extra":[{"text":"Server will restart in ","color":"red"},{"text":"1 minute","color":"yellow"},{"text":"."}]}'
    if [ $? -ne 0 ]; then
      log "Warning: 1-minute warning via RCON failed"
    fi
  
    sleep 30
  
    mcrcon -H "$RCON_HOST" -P "$RCON_PORT" -p "$RCON_PASSWORD" \
      'tellraw @a {"text":"","extra":[{"text":"Server will restart in ","color":"red"},{"text":"30 seconds","color":"yellow"},{"text":"!"}]}'
    if [ $? -ne 0 ]; then
      log "Warning: 30-second warning via RCON failed"
    fi
  
    sleep 30
  else
    # For immediate backup, just notify that server is restarting now
    mcrcon -H "$RCON_HOST" -P "$RCON_PORT" -p "$RCON_PASSWORD" \
      'tellraw @a {"text":"","extra":[{"text":"Server restarting for immediate backup...","color":"red"}]}'
    if [ $? -ne 0 ]; then
      log "Warning: immediate restart message via RCON failed"
    fi
  fi

  mcrcon -H "$RCON_HOST" -P "$RCON_PORT" -p "$RCON_PASSWORD" save-all
  if [ $? -ne 0 ]; then
    log "Warning: final save-all via RCON failed"
  fi

  mcrcon -H "$RCON_HOST" -P "$RCON_PORT" -p "$RCON_PASSWORD" \
    'tellraw @a {"text":"","extra":[{"text":"Restarting now…","color":"red"}]}'
  if [ $? -ne 0 ]; then
    log "Warning: restart-now message via RCON failed"
  fi

  # restore errexit
  set -e

  sleep 5
  log "Stopping Minecraft server…"
  systemctl stop "$SERVICE"
fi

# 2) Create Borg archive
DT=$(date +%F_%H-%M)
log "Creating Borg archive: minecraft-$DT"
borg create --remote-path=borg14 --verbose --compression zstd,6 \
    "::minecraft-$DT" "$LOCAL_DIR"

# 3) Prune
log "Pruning archives (keep 7 daily, 4 weekly, 6 monthly)…"
borg prune --remote-path=borg14 --verbose \
    --keep-daily=7 --keep-weekly=4 --keep-monthly=6

# 4) Compact
log "Compacting repository to reclaim space…"
borg compact --remote-path=borg14 --verbose

# 5) Restart server
log "Starting Minecraft server…"
systemctl start "$SERVICE"


# 6) Generate backup web page

log "Generating /backups page"

/usr/local/bin/generate-backup-page.sh

log "Backup complete"
