#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '\r\n' < "$SOURCE_ROOT/VERSION")"
MARIADB_CONTAINER="${GJAERINGSASSISTENT_MARIADB_CONTAINER:-gjaeringsassistent-mariadb}"
NODERED_CONTAINER="${GJAERINGSASSISTENT_NODERED_CONTAINER:-gjaeringsassistent-nodered}"
NETWORK="${GJAERINGSASSISTENT_NETWORK:-gjaeringsassistent-net}"
STAMP="$(date -u +%Y%m%dT%H%M%S%NZ)"
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
CURRENT_STEP="preflight"
OVERALL="FAIL"
NR_DATA=""
NR_UID_GID="unknown"
MYSQL_CONFIG_ID="unknown"
HA_SERVER_ID="unknown"
SCHEMA_VERIFICATION=""
MARIADB_SERVER_VERSION="not checked"
DATABASE_MODE="not planned"
DATABASE_SOURCE_VERSION="unknown"
BACKUP_DIR=""
BACKUP_VERIFIED=0
MIGRATION_SHA256=""

[[ "$EUID" -eq 0 ]] || { echo "Kjør installeren som root." >&2; exit 1; }
command -v docker >/dev/null
command -v python3 >/dev/null
command -v sha256sum >/dev/null

REPORT_DIR="$SOURCE_ROOT/install-reports"
mkdir -p "$REPORT_DIR"
LOG_FILE="$REPORT_DIR/install-${STAMP}.log"
JSON_FILE="$REPORT_DIR/install-${STAMP}.json"
exec > >(tee -a "$LOG_FILE") 2>&1

write_report(){
  local rc="$1" completed_at
  completed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  python3 - "$JSON_FILE" "$VERSION" "$STARTED_AT" "$completed_at" "$OVERALL" "$rc" "$CURRENT_STEP" "$NODERED_CONTAINER" "$MARIADB_CONTAINER" "$NR_DATA" "$NR_UID_GID" "$MYSQL_CONFIG_ID" "$HA_SERVER_ID" "$LOG_FILE" "$MARIADB_SERVER_VERSION" "$DATABASE_MODE" "$DATABASE_SOURCE_VERSION" "$BACKUP_DIR" "$MIGRATION_SHA256" "$BACKUP_VERIFIED" <<'PY'
import json,sys
(path,version,started,completed,overall,rc,step,nr,maria,nr_data,uidgid,mysql_id,ha_id,log,maria_version,mode,source,backup,migration_sha,backup_verified)=sys.argv[1:]
obj={
  "version":version,
  "started_at":started,
  "completed_at":completed,
  "overall":overall,
  "exit_code":int(rc),
  "last_step":step,
  "containers":{"nodered":nr,"mariadb":maria},
  "database_server_version":maria_version,
  "nodered_data":nr_data,
  "nodered_uid_gid":uidgid,
  "preserved_config":{"mysql_config_id":mysql_id,"ha_server_id":ha_id},
  "prototype_database_reset":False,
  "database_operation":mode,
  "database_source_version":source,
  "backup_directory":backup or None,
  "backup_verified":backup_verified=="1",
  "migration_sha256":migration_sha or None,
  "installer_scope":"install-only; no runtime target test, no synthetic Start, no Systemkontroll invocation",
  "log_file":log
}
open(path,'w',encoding='utf-8').write(json.dumps(obj,ensure_ascii=False,indent=2)+'\n')
PY
  chmod 0644 "$JSON_FILE" "$LOG_FILE" 2>/dev/null || true
}
on_exit(){
  local rc=$?
  [[ $rc -eq 0 ]] && OVERALL="PASS" || OVERALL="FAIL"
  write_report "$rc"
  echo
  echo "Install report: $JSON_FILE"
  echo "Install log:    $LOG_FILE"
  if [[ $rc -eq 0 ]]; then
    echo "RESULTAT: PASS – $VERSION er installert. Runtimefunksjon verifiseres fra Teknisk/Systemkontroll, ikke av installeren."
  else
    echo "RESULTAT: FAIL ved steg: $CURRENT_STEP" >&2
    if [[ -n "$BACKUP_DIR" && "$BACKUP_VERIFIED" == "1" ]]; then
      echo "Gjenopprettingsgrunnlag: $BACKUP_DIR. Ikke start Node-RED med ufullstendig oppgradering; se docs/08-DRIFTSVEILEDNING.md." >&2
    fi
  fi
}
trap on_exit EXIT

db_apply(){
  local file="$1"
  echo "  -> $(basename "$file")"
  docker exec -i "$MARIADB_CONTAINER" sh -lc 'mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"' < "$file"
}
install_database(){
  local f mode_key
  if [[ "$DATABASE_MODE" != "reinstall" ]]; then
    mode_key="upgrade_files"
    [[ "$DATABASE_MODE" == "fresh" ]] && mode_key="fresh_files"
    while IFS= read -r f; do
      CURRENT_STEP="MariaDB $DATABASE_MODE $f"
      db_apply "$SOURCE_ROOT/$f"
    done < <(python3 - "$SOURCE_ROOT/installer/migrations.json" "$mode_key" <<'PY2'
import json,sys
print('\n'.join(json.load(open(sys.argv[1]))[sys.argv[2]]))
PY2
    )
    CURRENT_STEP="record MariaDB migration"
    python3 - "$SOURCE_ROOT/installer/migrations.json" "$MIGRATION_SHA256" "$DATABASE_SOURCE_VERSION" "$VERSION" <<'PY2' | docker exec -i "$MARIADB_CONTAINER" sh -lc 'mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"'
import json,sys
quote=lambda v:"'"+v.replace("'","''")+"'"
mid=json.load(open(sys.argv[1]))['migration_id']
print('INSERT INTO database_migrations(migration_id,checksum_sha256,source_version,target_version,applied_at) VALUES('+','.join(map(quote,[mid,*sys.argv[2:]]))+',UTC_TIMESTAMP(3));')
PY2
  fi
  CURRENT_STEP="stamp MariaDB application version"
  printf "UPDATE database_metadata SET application_version='%s' WHERE metadata_id=1; UPDATE template_database_metadata SET application_version=(SELECT application_version FROM database_metadata WHERE metadata_id=1) WHERE metadata_id=1;\n" "$VERSION" | \
    docker exec -i "$MARIADB_CONTAINER" sh -lc 'mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"'
  local installed_version schema_metadata_rows
  CURRENT_STEP="verify MariaDB install metadata"
  installed_version="$(docker exec -i "$MARIADB_CONTAINER" sh -lc 'mariadb -N -B -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE" -e "SELECT application_version FROM database_metadata WHERE metadata_id=1"')"
  [[ "$installed_version" == "$VERSION" ]] || { echo "Database-metadata avviker: $installed_version != $VERSION" >&2; return 1; }
  schema_metadata_rows="$(docker exec -i "$MARIADB_CONTAINER" sh -lc 'mariadb -N -B -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE" -e "SELECT COUNT(*) FROM system_check_expectations WHERE check_id=\"schema\""')"
  [[ "$schema_metadata_rows" =~ ^[1-9][0-9]*$ ]] || { echo "Mangler schema-metadata for Systemkontroll." >&2; return 1; }
}
wait_nodered(){
  local max="${1:-90}" waited=0
  while (( waited < max )); do
    if [[ "$(docker inspect --format='{{.State.Status}}' "$NODERED_CONTAINER" 2>/dev/null || true)" == "running" ]]; then
      if docker exec "$NODERED_CONTAINER" node -e "fetch('http://127.0.0.1:1880/').then(r=>process.exit(r.status<500?0:2)).catch(()=>process.exit(3))" >/dev/null 2>&1; then
        return 0
      fi
    fi
    sleep 2; waited=$((waited+2))
  done
  echo "Node-RED ble ikke klar innen ${max}s." >&2
  docker logs --tail 120 "$NODERED_CONTAINER" 2>&1 || true
  return 1
}

# ---------------------------------------------------------------------------
echo "Gjæringsassistent $VERSION"
echo "Installer-scope: installer filer/DB/flow og gjør kun nødvendige installasjonskontroller."
echo "Databevarende installasjon: eksisterende database oppgraderes uten reset."

CURRENT_STEP="preflight target environment"
docker inspect "$MARIADB_CONTAINER" >/dev/null 2>&1 || { echo "Fant ikke $MARIADB_CONTAINER" >&2; exit 1; }
docker inspect "$NODERED_CONTAINER" >/dev/null 2>&1 || { echo "Fant ikke $NODERED_CONTAINER" >&2; exit 1; }
health="$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$MARIADB_CONTAINER")"
[[ "$health" == "healthy" || "$health" == "running" ]] || { echo "MariaDB er ikke klar: $health" >&2; exit 1; }
CURRENT_STEP="preflight MariaDB version"
MARIADB_SERVER_VERSION="$(docker exec "$MARIADB_CONTAINER" sh -lc 'mariadb -N -B -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" -e "SELECT VERSION()"')"
python3 "$SOURCE_ROOT/installer/check-database-version.py" --build-info "$SOURCE_ROOT/BUILD-INFO.json" --server-version "$MARIADB_SERVER_VERSION"
CURRENT_STEP="preflight Node-RED running"
nodered_state="$(docker inspect --format='{{.State.Status}}' "$NODERED_CONTAINER")"
[[ "$nodered_state" == "running" ]] || { echo "Node-RED-containeren $NODERED_CONTAINER kjører ikke: $nodered_state. Start den med: docker start $NODERED_CONTAINER. Ingen database- eller flowendring er utført." >&2; exit 1; }
CURRENT_STEP="preflight Node-RED data mount"
NR_DATA="$(docker inspect --format='{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' "$NODERED_CONTAINER")"
[[ -n "$NR_DATA" && -d "$NR_DATA" ]] || { echo "Fant ikke host-mount for Node-RED /data." >&2; exit 1; }
NR_UID_GID="$(docker exec "$NODERED_CONTAINER" sh -lc 'printf "%s:%s" "$(id -u)" "$(id -g)"')"
NR_UID="${NR_UID_GID%:*}"; NR_GID="${NR_UID_GID#*:}"
[[ -f "$NR_DATA/flows.json" ]] || { echo "Mangler eksisterende $NR_DATA/flows.json; HA/MariaDB-config kan ikke bevares." >&2; exit 1; }
docker exec "$NODERED_CONTAINER" sh -lc 'cd /data && npm list node-red-node-mysql --depth=0 >/dev/null' || { echo "node-red-node-mysql er ikke installert i Node-RED /data." >&2; exit 1; }

CURRENT_STEP="preflight SQLite file support"
docker exec "$NODERED_CONTAINER" node -e 'if(Number(process.versions.node.split(".")[0])<24)throw Error("Arkivoverføring krever Node.js 24 eller nyere");require("node:sqlite").DatabaseSync;'

CURRENT_STEP="verify release integrity"
(cd "$SOURCE_ROOT" && sha256sum -c SHA256SUMS >/dev/null)
python3 -m json.tool "$SOURCE_ROOT/nodered/flows.template.json" >/dev/null
python3 -m json.tool "$SOURCE_ROOT/contracts/ha-node-red-contract.json" >/dev/null

CURRENT_STEP="build installed flow with preserved credentials"
GENERATED_FLOW="$REPORT_DIR/flows-${STAMP}.json"
FLOW_PATCH_JSON="$(umask 077; python3 "$SOURCE_ROOT/installer/build-installed-flow.py" --template "$SOURCE_ROOT/nodered/flows.template.json" --current "$NR_DATA/flows.json" --output "$GENERATED_FLOW")"
chmod 0600 "$GENERATED_FLOW"
echo "Flow config: $FLOW_PATCH_JSON"
MYSQL_CONFIG_ID="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["mysql_config_id"])' "$FLOW_PATCH_JSON")"
HA_SERVER_ID="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["ha_server_id"])' "$FLOW_PATCH_JSON")"

CURRENT_STEP="plan databevarende databaseinstallasjon"
DATABASE_PLAN="$(python3 "$SOURCE_ROOT/installer/database-plan.py" --container "$MARIADB_CONTAINER")"
DATABASE_MODE="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["mode"])' "$DATABASE_PLAN")"
DATABASE_SOURCE_VERSION="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["source_version"] or "empty")' "$DATABASE_PLAN")"
MIGRATION_SHA256="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["migration_sha256"])' "$DATABASE_PLAN")"
echo "Databaseplan: $DATABASE_MODE · $DATABASE_SOURCE_VERSION → $VERSION"
command -v gzip >/dev/null
CURRENT_STEP="stop Node-RED for consistent upgrade backup"
docker stop "$NODERED_CONTAINER" >/dev/null

if [[ "$DATABASE_MODE" != "fresh" ]]; then
  CURRENT_STEP="backup MariaDB and installed flow"
  BACKUP_DIR="$NR_DATA/gjaeringsassistent/backups/${STAMP}-${DATABASE_SOURCE_VERSION}"
  install -d -m 0700 "$BACKUP_DIR"
  # The backup helper preserves tables/routines/triggers plus original view metadata.
  (umask 077; python3 "$SOURCE_ROOT/installer/backup-database.py" --container "$MARIADB_CONTAINER" --output "$BACKUP_DIR/database.sql.gz")
  gzip -t "$BACKUP_DIR/database.sql.gz"
  [[ -s "$BACKUP_DIR/database.sql.gz" ]]
  install -m 0600 "$NR_DATA/flows.json" "$BACKUP_DIR/flows.json"
  if [[ -f "$NR_DATA/flows_cred.json" ]]; then install -m 0600 "$NR_DATA/flows_cred.json" "$BACKUP_DIR/flows_cred.json"; fi
  (cd "$BACKUP_DIR" && sha256sum database.sql.gz flows.json > SHA256SUMS)
  chmod 0600 "$BACKUP_DIR/SHA256SUMS"
  BACKUP_VERIFIED=1
  echo "Verifisert sikkerhetskopi: $BACKUP_DIR"
fi

CURRENT_STEP="apply MariaDB install plan"
install_database

CURRENT_STEP="install Node-RED flow and stage frontend publication sources"
mkdir -p "$NR_DATA/gjaeringsassistent/frontend-source" "$NR_DATA/gjaeringsassistent/runtime"
install -m 0640 "$GENERATED_FLOW" "$NR_DATA/flows.json"
install -m 0640 "$SOURCE_ROOT/dashboard/gjaeringsassistent-dashboard.yaml" "$NR_DATA/gjaeringsassistent/frontend-source/gjaeringsassistent-dashboard.yaml"
install -m 0640 "$SOURCE_ROOT/dashboard/gjaeringsassistent-card.js" "$NR_DATA/gjaeringsassistent/frontend-source/gjaeringsassistent-card.js"
install -m 0640 "$SOURCE_ROOT/dashboard/gjaeringsassistent-card-loader.js" "$NR_DATA/gjaeringsassistent/frontend-source/gjaeringsassistent-card-loader.js"
install -m 0750 "$SOURCE_ROOT/tools/publish_frontend.js" "$NR_DATA/gjaeringsassistent/runtime/publish_frontend.js"
install -m 0750 "$SOURCE_ROOT/tools/archive_export.js" "$NR_DATA/gjaeringsassistent/runtime/archive_export.js"
install -m 0750 "$SOURCE_ROOT/tools/publish_payload.js" "$NR_DATA/gjaeringsassistent/runtime/publish_payload.js"
mkdir -p "$NR_DATA/nodes/gjaeringsassistent-archive"
install -m 0640 "$SOURCE_ROOT/nodered/archive-node.js" "$NR_DATA/nodes/gjaeringsassistent-archive/archive-node.js"
install -m 0640 "$SOURCE_ROOT/nodered/archive-node.html" "$NR_DATA/nodes/gjaeringsassistent-archive/archive-node.html"
for source in archive_worker.js sqlite_archive.js archive_contract.json archive_export.js archive_admin.js archive_catalog.js report_module.js graph_renderer.js presentation_payload.js report_renderer.js report_queries.sql; do
  install -m 0640 "$SOURCE_ROOT/tools/$source" "$NR_DATA/nodes/gjaeringsassistent-archive/$source"
done
chown -R "$NR_UID:$NR_GID" "$NR_DATA/nodes/gjaeringsassistent-archive"
chown "$NR_UID:$NR_GID" "$NR_DATA/flows.json"
chown -R "$NR_UID:$NR_GID" "$NR_DATA/gjaeringsassistent/frontend-source" "$NR_DATA/gjaeringsassistent/runtime"
# flows_cred.json is deliberately untouched; preserved config-node IDs keep HA/MariaDB credentials.
docker network connect "$NETWORK" "$NODERED_CONTAINER" >/dev/null 2>&1 || true

CURRENT_STEP="start Node-RED"
docker start "$NODERED_CONTAINER" >/dev/null
wait_nodered 90

CURRENT_STEP="completed"
echo "Installert Node-RED-flow og frontendkilder; eksisterende databasedata er bevart."
echo "Node-RED publiserer dashboard, custom card, loader og generert frontend-manifest gjennom HA-public-mount ved oppstart."
echo "Ingen syntetisk session, HA-knappetest, restart/restore-test eller Systemkontroll ble kjørt av installeren."
