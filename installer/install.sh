#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '\r\n' < "$SOURCE_ROOT/VERSION")"
MARIADB_CONTAINER="${GJAERINGSASSISTENT_MARIADB_CONTAINER:-gjaeringsassistent-mariadb}"
NODERED_CONTAINER="${GJAERINGSASSISTENT_NODERED_CONTAINER:-gjaeringsassistent-nodered}"
NETWORK="${GJAERINGSASSISTENT_NETWORK:-gjaeringsassistent-net}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
CURRENT_STEP="preflight"
OVERALL="FAIL"
NR_DATA=""
NR_UID_GID="unknown"
MYSQL_CONFIG_ID="unknown"
HA_SERVER_ID="unknown"
SCHEMA_VERIFICATION=""
MARIADB_SERVER_VERSION="not checked"

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
  python3 - "$JSON_FILE" "$VERSION" "$STARTED_AT" "$completed_at" "$OVERALL" "$rc" "$CURRENT_STEP" "$NODERED_CONTAINER" "$MARIADB_CONTAINER" "$NR_DATA" "$NR_UID_GID" "$MYSQL_CONFIG_ID" "$HA_SERVER_ID" "$LOG_FILE" "$MARIADB_SERVER_VERSION" <<'PY'
import json,sys
(path,version,started,completed,overall,rc,step,nr,maria,nr_data,uidgid,mysql_id,ha_id,log,maria_version)=sys.argv[1:]
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
  "prototype_database_reset":True,
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
  fi
}
trap on_exit EXIT

db_apply(){
  local file="$1"
  echo "  -> $(basename "$file")"
  docker exec -i "$MARIADB_CONTAINER" sh -lc 'mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"' < "$file"
}
reset_database(){
  local db
  db="$(docker exec "$MARIADB_CONTAINER" sh -lc 'printf "%s" "$MARIADB_DATABASE"')"
  [[ "$db" == "gjaeringsassistent" ]] || { echo "Uventet MariaDB database-navn: $db" >&2; return 1; }
  docker exec "$MARIADB_CONTAINER" sh -lc 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS gjaeringsassistent; CREATE DATABASE gjaeringsassistent CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; GRANT ALL PRIVILEGES ON gjaeringsassistent.* TO '\''gjaeringsassistent'\''@'\''%'\''; FLUSH PRIVILEGES;"'
}
install_database(){
  reset_database
  for f in \
    "$SOURCE_ROOT/sql/00-template-schema.sql" \
    "$SOURCE_ROOT/sql/01-template-registry-seed.sql" \
    "$SOURCE_ROOT/sql/10-runtime-schema.sql" \
    "$SOURCE_ROOT/sql/11-runtime-routines.sql" \
    "$SOURCE_ROOT/sql/02-runtime-registry-seed.sql" \
    "$SOURCE_ROOT/sql/03-w3470-template-seed.sql" \
    "$SOURCE_ROOT/sql/04-ale-templates-seed.sql" \
    "$SOURCE_ROOT/sql/20-views.sql" \
    "$SOURCE_ROOT/sql/21-system-metadata-seed.sql" \
    "$SOURCE_ROOT/sql/22-demo-reference-seed.sql" \
    "$SOURCE_ROOT/sql/23-measurement-source-seed.sql" \
    "$SOURCE_ROOT/sql/24-verification-metadata-seed.sql" \
    "$SOURCE_ROOT/sql/25-release-verification-results-seed.sql"; do
      CURRENT_STEP="install MariaDB $(basename "$f")"
      db_apply "$f"
  done
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
echo "Prototype mode: databasen resettes; ingen backup/migrering av prototype-data utføres."

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
[[ "$nodered_state" == "running" ]] || { echo "Node-RED-containeren $NODERED_CONTAINER kjører ikke: $nodered_state. Start den med: docker start $NODERED_CONTAINER. Ingen database-reset eller flowendring er utført." >&2; exit 1; }
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
GENERATED_FLOW="$SOURCE_ROOT/nodered/flows.generated.json"
FLOW_PATCH_JSON="$(python3 "$SOURCE_ROOT/installer/build-installed-flow.py" --template "$SOURCE_ROOT/nodered/flows.template.json" --current "$NR_DATA/flows.json" --output "$GENERATED_FLOW")"
echo "Flow config: $FLOW_PATCH_JSON"
MYSQL_CONFIG_ID="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["mysql_config_id"])' "$FLOW_PATCH_JSON")"
HA_SERVER_ID="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["ha_server_id"])' "$FLOW_PATCH_JSON")"

CURRENT_STEP="stop Node-RED for atomic prototype replacement"
docker stop "$NODERED_CONTAINER" >/dev/null

CURRENT_STEP="install clean MariaDB baseline"
echo "[DB] Reset + install $VERSION schema/template"
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
echo "Installert Node-RED-flow, staged frontendkilder/publisher og ren MariaDB-baseline."
echo "Node-RED publiserer dashboard, custom card, loader og generert frontend-manifest gjennom HA-public-mount ved oppstart."
echo "Ingen syntetisk session, HA-knappetest, restart/restore-test eller Systemkontroll ble kjørt av installeren."
