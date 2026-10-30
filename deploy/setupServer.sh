#!/usr/bin/env bash
# Sets up a Linux server (Ubuntu 22.04/24.04, Debian 12) for LogisticsLab Studio: the web app and the
# LogisticsLab server (REST, computing core with CMPL/HiGHS and OR-Tools) - both behind nginx.
#
#   browser --https--> nginx --+-- /      the web app (static files of flutter build web)
#                              +-- /v1/   proxy to uvicorn 127.0.0.1:8000 (one worker) - with the API key of the user
#                                         or (internal network) of the web app
#
# Usage (as root, again for an update - existing configuration and keys are kept):
#
#   sudo GITHUB_TOKEN=... ./setupServer.sh --domain logisticslab.example.org --email admin@example.org
#
#   --domain NAME      the name of the server (DNS) - also for the certificate; without it: only http, reached by
#                      the IP address (a name without an own domain: e.g. 194-95-44-20.nip.io)
#   --email ADDRESS    for Let's Encrypt (certbot); without it or with --no-tls only http
#   --web DIR          the built web app (flutter build web --release in LogisticsLabApp, copied to the server) -
#                      without it the web app is built here, Flutter installed to /opt/flutter if necessary
#   --flutter-version V  the Flutter of this build (default as in .github/workflows/desktop.yml)
#   --src DIR          the repositories side by side: LogisticsLabApp, pyLogisticsLab, Cmpl2
#                      (default /opt/logisticslab/src - cloned or updated with GITHUB_TOKEN)
#   --max-problems N   solver processes at the same time (default: number of CPUs - 1, at least 2)
#   --no-tls           no certificate (e.g. behind another proxy, or for a test in the local network)
#   --internal-net CIDR  a network whose users need no API key (e.g. 194.95.44.0/22 or the VPN) - several times
#   --open             nobody needs an API key (e.g. a server only reachable in the internal network)
#
# Access: by default everybody enters an API key in the app (Settings -> Computing, or the app asks for it) and
# nginx passes it on. For --internal-net and --open nginx adds the key of the web app itself - it never reaches
# the browser.
#
# GITHUB_TOKEN: a token with read access to the private repositories pyLogisticsLab, pyCmpl and LogisticsLabApp -
# only used for git and pip during the setup, it is not stored.
#
# Afterwards:
#   systemctl status logisticslab           journalctl -u logisticslab -f
#   /etc/logisticsLab/                      configuration (logisticsLab.yml, logisticsLabServer.yml, apiKeys.yml)
#   /var/log/logisticsLab/                  logs          /var/lib/logisticsLab/   matrix cache
#   further API keys (e.g. for the desktop apps):
#     sudo -u loglab LOGLAB_CONF_DIR=/etc/logisticsLab /opt/logisticslab/venv/bin/python \
#          /opt/logisticslab/src/pyLogisticsLab/logisticsLabServer/manageKeys.py add NAME

set -euo pipefail

BASE=/opt/logisticslab
CONF=/etc/logisticsLab
LOGS=/var/log/logisticsLab
DATA=/var/lib/logisticsLab
WWW=/var/www/logisticslab
USER_NAME=loglab
PORT=8000
FLUTTER_DIR=/opt/flutter
FLUTTER_VERSION=3.44.4
REPOS=(LogisticsLabApp pyLogisticsLab Cmpl2)

DOMAIN="" EMAIL="" WEB="" SRC="$BASE/src" MAX_PROBLEMS="" TLS=1 OPEN=0
INTERNAL_NETS=()

log()  { printf '\n==> %s\n' "$*"; }
fail() { printf '\nFEHLER: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --domain)       DOMAIN="$2"; shift 2 ;;
    --email)        EMAIL="$2"; shift 2 ;;
    --web)          WEB="$2"; shift 2 ;;
    --flutter-version) FLUTTER_VERSION="$2"; shift 2 ;;
    --src)          SRC="$2"; shift 2 ;;
    --max-problems) MAX_PROBLEMS="$2"; shift 2 ;;
    --no-tls)       TLS=0; shift ;;
    --internal-net) INTERNAL_NETS+=("$2"); shift 2 ;;
    --open)         OPEN=1; shift ;;
    -h|--help)      sed -n '2,40p' "$0"; exit 0 ;;
    *)              fail "unbekannte Option $1 (--help)" ;;
  esac
done

[ "$(id -u)" = 0 ] || fail "bitte als root starten (sudo)"
# without a name: every address (server_name _), only http
SERVER_NAME="${DOMAIN:-_}"
[ -n "$DOMAIN" ] || TLS=0
command -v apt-get >/dev/null || fail "nur fuer Debian/Ubuntu (apt)"
[ -n "$EMAIL" ] || TLS=0
[ -z "$WEB" ] || [ -f "$WEB/index.html" ] || fail "$WEB/index.html fehlt - das Verzeichnis von flutter build web angeben"
if [ -z "$MAX_PROBLEMS" ]; then
  MAX_PROBLEMS=$(( $(nproc) - 1 )); [ "$MAX_PROBLEMS" -ge 2 ] || MAX_PROBLEMS=2
fi

# tar as root takes the owners of the archive - in a container (e.g. unprivileged LXC) they do not exist and tar
# fails (Flutter: "Cannot change ownership to uid ...")
export TAR_OPTIONS=--no-same-owner

# the token for git and pip of this run only (also git inside pip) - nothing is written to a file
if [ -n "${GITHUB_TOKEN:-}" ]; then
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0="url.https://x-access-token:${GITHUB_TOKEN}@github.com/.insteadOf"
  export GIT_CONFIG_VALUE_0="https://github.com/"
fi

# ------------------------------------------------------------------ packages, user, directories
log "Pakete"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q nginx git curl ca-certificates rsync build-essential make g++ \
  python3 python3-venv python3-pip python3-dev unzip xz-utils
[ "$TLS" = 0 ] || apt-get install -y -q certbot python3-certbot-nginx

log "Benutzer $USER_NAME und Verzeichnisse"
id "$USER_NAME" >/dev/null 2>&1 || useradd --system --home-dir "$BASE" --shell /usr/sbin/nologin "$USER_NAME"
mkdir -p "$BASE" "$CONF" "$LOGS" "$DATA" "$WWW"
chown "$USER_NAME:$USER_NAME" "$LOGS" "$DATA"
chown "root:$USER_NAME" "$CONF"; chmod 770 "$CONF"

# ------------------------------------------------------------------ sources
log "Quellen in $SRC"
mkdir -p "$SRC"
for r in "${REPOS[@]}"; do
  if [ -d "$SRC/$r/.git" ]; then
    git -C "$SRC/$r" pull --ff-only
  else
    [ -n "${GITHUB_TOKEN:-}" ] || [ "$r" = Cmpl2 ] || fail "$SRC/$r fehlt - GITHUB_TOKEN setzen oder --src angeben"
    git clone "https://github.com/MikeSteglich/$r.git" "$SRC/$r"
  fi
done

# ------------------------------------------------------------------ CMPL with HiGHS
log "CMPL (Kern mit HiGHS) nach $BASE/cmpl"
python3 "$SRC/Cmpl2/dist/buildDist.py" --core --no-archive --stage "$BASE/cmpl.new"
rm -rf "$BASE/cmpl"; mv "$BASE/cmpl.new" "$BASE/cmpl"

# ------------------------------------------------------------------ Python environment
log "Python-Umgebung $BASE/venv"
[ -x "$BASE/venv/bin/python" ] || python3 -m venv "$BASE/venv"
"$BASE/venv/bin/pip" install -q --upgrade pip
# pyCmpl from its private repository (requirements.txt), pyLogisticsLab with the server
"$BASE/venv/bin/pip" install -q "$(grep -E '^pyCmpl' "$SRC/pyLogisticsLab/requirements.txt")"
"$BASE/venv/bin/pip" install -q -e "$SRC/pyLogisticsLab[server]"
chown -R "root:$USER_NAME" "$BASE"; chmod -R g+rX,o-rwx "$BASE"

# ------------------------------------------------------------------ configuration
log "Konfiguration in $CONF"
for f in logisticsLab.yml logisticsLabServer.yml; do
  [ -f "$CONF/$f" ] || cp "$SRC/pyLogisticsLab/confs/$f" "$CONF/$f"
done
S="$CONF/logisticsLabServer.yml"
# logs, matrix cache and parallelism - set again with every run, the other settings stay as edited
sed -i -E "s|^#?logPath:.*|logPath: $LOGS|" "$S"
sed -i -E "s|^#?matrixCacheFile:.*|matrixCacheFile: $DATA/matrixCache.sqlite|" "$S"
sed -i -E "s|^maxProblems:.*|maxProblems:  $MAX_PROBLEMS                 # solver processes|" "$S"
sed -i -E "s|^debugging:.*|debugging: False|" "$S"
# the web app shares one key: its users together may have as many open problems as the queue takes
QUEUE=$(sed -nE 's/^maxQueueSize:[[:space:]]*([0-9]+).*/\1/p' "$S"); QUEUE=${QUEUE:-50}

KEYFILE="$CONF/webapp.key"
ACCESS=/etc/nginx/conf.d/logisticslab-access.conf
if [ "$OPEN" = 1 ] || [ ${#INTERNAL_NETS[@]} -gt 0 ]; then
  if [ ! -s "$KEYFILE" ]; then
    log "API-Key der Web-App (internes Netz)"
    out=$(cd "$SRC/pyLogisticsLab/logisticsLabServer" && LOGLAB_CONF_DIR="$CONF" \
          "$BASE/venv/bin/python" manageKeys.py add webapp --maxOpenProblems "$QUEUE")
    key=$(printf '%s\n' "$out" | tail -n 1 | tr -d '[:space:]')
    [ -n "$key" ] || fail "kein API-Key erzeugt: $out"
    printf '%s\n' "$key" > "$KEYFILE"
  fi
fi
chown "root:$USER_NAME" "$CONF"/*; chmod 640 "$CONF"/*; [ ! -f "$KEYFILE" ] || chmod 600 "$KEYFILE"

# who needs a key: nginx sends the key of the user (header X-API-Key) - for the internal networks (and this
# machine) that of the web app; written with every run, only readable by root (the key)
{
  echo "# LogisticsLab - access to /v1/ (written by setupServer.sh)"
  echo "geo \$loglab_internal {"
  if [ "$OPEN" = 1 ]; then echo "    default 1;"; else echo "    default 0;"; fi
  if [ ${#INTERNAL_NETS[@]} -gt 0 ]; then
    echo "    127.0.0.1 1;"
    for n in "${INTERNAL_NETS[@]}"; do echo "    $n 1;"; done
  fi
  echo "}"
  echo "map \$loglab_internal \$loglab_api_key {"
  echo "    default \$http_x_api_key;"
  if [ -s "$KEYFILE" ] && { [ "$OPEN" = 1 ] || [ ${#INTERNAL_NETS[@]} -gt 0 ]; }; then
    echo "    1 \"$(cat "$KEYFILE")\";"
  fi
  echo "}"
} > "$ACCESS"
chmod 600 "$ACCESS"
rm -f /etc/nginx/logisticslab-apikey.conf

# ------------------------------------------------------------------ web app
log "Web-App nach $WWW"
if [ -z "$WEB" ]; then
  # Flutter in /opt/flutter (a checkout of the release tag - also on arm64) - only the web part
  if [ "$("$FLUTTER_DIR/bin/flutter" --version --machine 2>/dev/null | sed -nE 's/.*"frameworkVersion": *"([^"]+)".*/\1/p')" != "$FLUTTER_VERSION" ]; then
    log "Flutter $FLUTTER_VERSION nach $FLUTTER_DIR"
    rm -rf "$FLUTTER_DIR"
    git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_DIR"
  fi
  export PATH="$FLUTTER_DIR/bin:$PATH" FLUTTER_SUPPRESS_ANALYTICS=true CI=true   # CI: no question as root
  flutter config --no-analytics >/dev/null
  flutter precache --web
  log "Web-App bauen"
  (cd "$SRC/LogisticsLabApp" && flutter pub get && flutter build web --release)
  WEB="$SRC/LogisticsLabApp/build/web"
fi
rsync -a --delete "$WEB/" "$WWW/"
chown -R root:root "$WWW"; chmod -R a+rX "$WWW"

# ------------------------------------------------------------------ systemd
log "Dienst logisticslab"
cat > /etc/systemd/system/logisticslab.service <<EOF
[Unit]
Description=LogisticsLab server
After=network-online.target
Wants=network-online.target

[Service]
User=$USER_NAME
Group=$USER_NAME
# a writable working directory (files of the solvers, e.g. HiGHS.log) - the code from the sources (--app-dir)
WorkingDirectory=$DATA
Environment=CMPLHOME=$BASE/cmpl
Environment=LOGLAB_CONF_DIR=$CONF
Environment=LOGLAB_LOG_DIR=$LOGS
# exactly one worker: the queue and the results are kept in its memory (maxProblems: the solver processes)
ExecStart=$BASE/venv/bin/uvicorn main:app --app-dir $SRC/pyLogisticsLab/logisticsLabServer --host 127.0.0.1 --port $PORT --workers 1 --proxy-headers --forwarded-allow-ips 127.0.0.1
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
ProtectSystem=full
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable logisticslab >/dev/null
systemctl restart logisticslab

# ------------------------------------------------------------------ nginx
log "nginx"
SITE=/etc/nginx/sites-available/logisticslab
# without TLS the site on port 80 - certbot adds 443 and the redirect afterwards
cat > "$SITE" <<EOF
# LogisticsLab Studio - written by setupServer.sh (certbot adds the certificate)
limit_req_zone \$binary_remote_addr zone=loglab:10m rate=10r/s;   # polling every 0.4 s and some more

server {
    listen 80;
    listen [::]:80;
    server_name $SERVER_NAME;

    root $WWW;
    index index.html;

    client_max_body_size 5m;        # scenarios and matrices

    gzip on;
    gzip_types text/css application/javascript application/json application/wasm image/svg+xml;

    # the server: the key of the web app added by nginx
    location /v1/ {
        limit_req zone=loglab burst=40 nodelay;
        limit_req_status 429;
        proxy_set_header X-API-Key \$loglab_api_key;   # conf.d/logisticslab-access.conf
        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 180s;    # matrix and routing requests run synchronously
    }

    # the web app: a new version at once (index.html, service worker), the rest cached by the browser
    location = /index.html            { add_header Cache-Control "no-cache"; }
    location = /flutter_service_worker.js { add_header Cache-Control "no-cache"; }
    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
ln -sf "$SITE" /etc/nginx/sites-enabled/logisticslab
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

if [ "$TLS" = 1 ]; then
  log "Zertifikat (Let's Encrypt) fuer $DOMAIN"
  certbot --nginx -d "$DOMAIN" -m "$EMAIL" --agree-tos --non-interactive --redirect --keep-until-expiring
fi

# ------------------------------------------------------------------ test
log "Test: Server ueber nginx (Matrix als Luftlinie)"
# to nginx on this machine under the name of the server - https after certbot (its redirect), else http
if [ "$TLS" = 1 ]; then url="https://$DOMAIN/v1/matrix"
elif [ -n "$DOMAIN" ]; then url="http://$DOMAIN/v1/matrix"
else url="http://127.0.0.1/v1/matrix"; fi
resolve=(); [ -z "$DOMAIN" ] || resolve=(--resolve "$DOMAIN:443:127.0.0.1" --resolve "$DOMAIN:80:127.0.0.1")
# this machine counts as internal with --internal-net or --open: 200 - else the server wants a key: 401
expect=401; { [ "$OPEN" = 1 ] || [ ${#INTERNAL_NETS[@]} -gt 0 ]; } && expect=200
sleep 3
for i in 1 2 3 4 5 6 7 8 9 10; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "${resolve[@]}" -H 'Content-Type: application/json' \
         -d '{"coordinates": [[52.32, 13.63], [52.52, 13.40]], "matrixSource": "beeline", "matrixMode": "distances"}' \
         "$url" || true)
  if [ "$code" = "$expect" ]; then
    echo "    ok ($code)"; break
  fi
  [ "$i" = 10 ] && fail "erwartet $expect, Antwort $code - journalctl -u logisticslab -n 50"
  sleep 3
done

scheme=http; [ "$TLS" = 0 ] || scheme=https
log "Fertig: $scheme://${DOMAIN:-$(hostname -I | awk '{print $1}')}"
