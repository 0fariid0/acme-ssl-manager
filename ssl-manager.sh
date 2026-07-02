#!/usr/bin/env bash
# SSL Manager for acme.sh
# GitHub-ready standalone Bash TUI
# Author: your-name
# License: MIT

set -o pipefail

APP_NAME="ACME SSL Manager"
APP_VERSION="1.3.0"
ACME_HOME="${ACME_HOME:-$HOME/.acme.sh}"
ACME_BIN="${ACME_BIN:-$ACME_HOME/acme.sh}"
CERT_BASE="${CERT_BASE:-/etc/acme-ssl-manager/certs}"
BACKUP_BASE="${BACKUP_BASE:-/etc/acme-ssl-manager/backups}"
MANAGER_BIN="/usr/local/bin/sslmgr"
DEFAULT_CA="letsencrypt"
# Default one-click issuing settings. Advanced mode is still available from the menu.
DEFAULT_CHALLENGE_MODE="http"      # http = HTTP-01 standalone on port 80
DEFAULT_KEY_LENGTH="ec-256"        # ECC ec-256
DEFAULT_AUTO_STOP="yes"            # stop/restart active web services automatically
WEB_SERVICES=(apache2 httpd nginx caddy haproxy)
STOPPED_SERVICES=()

# ---------- Colors ----------
if [[ -t 1 ]]; then
  C_RESET='\033[0m'
  C_BOLD='\033[1m'
  C_DIM='\033[2m'
  C_RED='\033[31m'
  C_GREEN='\033[32m'
  C_YELLOW='\033[33m'
  C_BLUE='\033[34m'
  C_MAGENTA='\033[35m'
  C_CYAN='\033[36m'
  C_WHITE='\033[97m'
else
  C_RESET=''; C_BOLD=''; C_DIM=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_MAGENTA=''; C_CYAN=''; C_WHITE=''
fi

say() { echo -e "$*"; }
ok() { say "${C_GREEN}[OK]${C_RESET} $*"; }
info() { say "${C_CYAN}[INFO]${C_RESET} $*"; }
warn() { say "${C_YELLOW}[WARN]${C_RESET} $*"; }
err() { say "${C_RED}[ERR]${C_RESET} $*"; }

pause() {
  echo
  read -rp "Press Enter to continue..." _
}

line() {
  say "${C_DIM}────────────────────────────────────────────────────────────${C_RESET}"
}

header() {
  clear 2>/dev/null || true
  say "${C_CYAN}${C_BOLD}╔════════════════════════════════════════════════════════════╗${C_RESET}"
  printf "${C_CYAN}${C_BOLD}║${C_RESET}  ${C_WHITE}${C_BOLD}%-54s${C_RESET} ${C_CYAN}${C_BOLD}║${C_RESET}\n" "$APP_NAME v$APP_VERSION"
  say "${C_CYAN}${C_BOLD}╚════════════════════════════════════════════════════════════╝${C_RESET}"
  say "${C_DIM}Managed cert path: $CERT_BASE${C_RESET}"
  echo
}

need_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    err "Please run as root. Example: sudo bash $0"
    exit 1
  fi
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

pkg_install() {
  local pkgs=("$@")
  if command_exists apt-get; then
    DEBIAN_FRONTEND=noninteractive apt-get update -y >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
  elif command_exists dnf; then
    dnf install -y "${pkgs[@]}"
  elif command_exists yum; then
    yum install -y "${pkgs[@]}"
  elif command_exists apk; then
    apk add --no-cache "${pkgs[@]}"
  else
    err "No supported package manager found. Install manually: ${pkgs[*]}"
    return 1
  fi
}

ensure_tools() {
  local missing=()
  for bin in curl openssl socat tar awk sed grep date getent; do
    command_exists "$bin" || missing+=("$bin")
  done
  if (( ${#missing[@]} > 0 )); then
    info "Installing required tools. Missing commands: ${missing[*]}"
    # Use package names, not command names, because some commands come from core packages.
    pkg_install curl openssl ca-certificates socat tar coreutils grep sed gawk iproute2 net-tools || return 1
    command_exists update-ca-certificates && update-ca-certificates >/dev/null 2>&1 || true
  fi
  mkdir -p "$CERT_BASE" "$BACKUP_BASE"
}

ensure_acme() {
  ensure_tools || return 1
  if [[ ! -x "$ACME_BIN" ]]; then
    warn "acme.sh was not found. Installing it now..."
    curl -fsSL https://get.acme.sh | sh || return 1
  fi
  if [[ ! -x "$ACME_BIN" ]]; then
    err "acme.sh installation finished but binary was not found at: $ACME_BIN"
    return 1
  fi
  "$ACME_BIN" --set-default-ca --server "$DEFAULT_CA" >/dev/null 2>&1 || true
  ok "acme.sh is ready: $ACME_BIN"
}



le_api_url() {
  echo "https://acme-v02.api.letsencrypt.org/directory"
}

le_nonce_url() {
  echo "https://acme-v02.api.letsencrypt.org/acme/new-nonce"
}

curl_acme_test() {
  local ipver="$1" label="$2"
  local dir_url nonce_url
  dir_url="$(le_api_url)"
  nonce_url="$(le_nonce_url)"

  local ipopt=()
  [[ -n "$ipver" ]] && ipopt+=("$ipver")

  # Directory is a GET endpoint. Some setups fail or behave differently with HEAD, so do not use -I here.
  if ! curl "${ipopt[@]}" -fsSL --connect-timeout 10 --max-time 25 "$dir_url" >/dev/null 2>&1; then
    warn "ACME directory is NOT reachable with $label"
    return 1
  fi

  # The nonce endpoint is the exact step that often fails with: Could not get nonce.
  if ! curl "${ipopt[@]}" -fsSI --connect-timeout 10 --max-time 25 "$nonce_url" >/dev/null 2>&1; then
    warn "ACME new-nonce endpoint is NOT reachable with $label"
    return 1
  fi

  ok "ACME API and nonce endpoint reachable with $label"
  return 0
}

preflight_acme_api() {
  say "${C_BOLD}ACME API preflight${C_RESET}"
  line
  if curl_acme_test "" "default network stack"; then
    return 0
  fi

  warn "Default connection to Let's Encrypt failed. Testing IPv4/IPv6 separately..."
  local v4=1 v6=1
  curl_acme_test -4 IPv4; v4=$?
  curl_acme_test -6 IPv6; v6=$?

  if [[ "$v4" == 0 && "$v6" != 0 ]]; then
    warn "IPv4 works but IPv6 fails. The script will use acme.sh --request-v4 automatically."
    return 2
  fi
  if [[ "$v4" != 0 && "$v6" == 0 ]]; then
    warn "IPv6 works but IPv4 fails. The script can continue with the default/IPv6 path."
    return 3
  fi

  err "Could not reach Let's Encrypt ACME API or nonce endpoint with IPv4 or IPv6."
  warn "This must be fixed before issuing/renewing certificates. The domain validation step has not started yet."
  return 1
}

auto_network_repair_quiet() {
  warn "Running automatic Network/TLS repair before retrying preflight..."
  if command_exists apt-get; then
    DEBIAN_FRONTEND=noninteractive apt-get update || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl openssl ca-certificates socat tzdata
    update-ca-certificates >/dev/null 2>&1 || true
  elif command_exists dnf; then
    dnf install -y curl openssl ca-certificates socat tzdata
    update-ca-trust >/dev/null 2>&1 || true
  elif command_exists yum; then
    yum install -y curl openssl ca-certificates socat tzdata
    update-ca-trust >/dev/null 2>&1 || true
  elif command_exists apk; then
    apk add --no-cache curl openssl ca-certificates socat tzdata
    update-ca-certificates >/dev/null 2>&1 || true
  else
    warn "Unsupported package manager. Install curl openssl ca-certificates socat manually."
  fi

  if command_exists timedatectl; then
    timedatectl set-ntp true >/dev/null 2>&1 || true
  fi

  if [[ -x "$ACME_BIN" ]]; then
    "$ACME_BIN" --upgrade >/dev/null 2>&1 || true
    "$ACME_BIN" --set-default-ca --server "$DEFAULT_CA" >/dev/null 2>&1 || true
  fi
}

ACME_IP_MODE="auto"

prepare_acme_network_or_abort() {
  local allow_repair="${1:-yes}" rc
  ACME_IP_MODE="auto"
  preflight_acme_api
  rc=$?

  case "$rc" in
    0) ACME_IP_MODE="auto"; return 0 ;;
    2) ACME_IP_MODE="v4"; return 0 ;;
    3) ACME_IP_MODE="auto"; return 0 ;;
  esac

  if [[ "$allow_repair" == "yes" ]]; then
    auto_network_repair_quiet
    echo
    preflight_acme_api
    rc=$?
    case "$rc" in
      0) ACME_IP_MODE="auto"; return 0 ;;
      2) ACME_IP_MODE="v4"; return 0 ;;
      3) ACME_IP_MODE="auto"; return 0 ;;
    esac
  fi

  ACME_IP_MODE="fail"
  return 1
}

acme_net_args() {
  local mode="$1" ipmode="$2"
  case "$ipmode" in
    v4)
      printf '%s\0' --request-v4
      # For standalone validation, also bind the temporary challenge server on IPv4.
      if [[ "$mode" == "http" || "$mode" == "alpn" ]]; then
        printf '%s\0' --listen-v4
      fi
      ;;
    v6)
      printf '%s\0' --request-v6
      if [[ "$mode" == "http" || "$mode" == "alpn" ]]; then
        printf '%s\0' --listen-v6
      fi
      ;;
  esac
}

run_acme_logged() {
  local tmp rc
  tmp="/tmp/sslmgr-acme-$$.log"
  "$ACME_BIN" "$@" 2>&1 | tee "$tmp"
  rc=${PIPESTATUS[0]}
  if [[ $rc -ne 0 ]]; then
    if grep -Eqi 'Could not get nonce|error code: 35|SSL connect|Le_OrderFinalize not found' "$tmp"; then
      echo
      err "acme.sh failed before domain validation. This is usually outbound HTTPS/TLS connectivity to Let's Encrypt."
      warn "The script already tested ACME API before this step. Run option 12 and check provider firewall/DNS/TLS if this repeats."
    fi
  fi
  rm -f "$tmp"
  return $rc
}

service_exists() {
  systemctl list-unit-files "$1.service" >/dev/null 2>&1 || systemctl status "$1" >/dev/null 2>&1
}

is_service_active() {
  systemctl is-active --quiet "$1" >/dev/null 2>&1
}

stop_web_services() {
  STOPPED_SERVICES=()
  local svc
  for svc in "${WEB_SERVICES[@]}"; do
    if service_exists "$svc" && is_service_active "$svc"; then
      warn "Stopping $svc temporarily..."
      if systemctl stop "$svc"; then
        STOPPED_SERVICES+=("$svc")
      else
        err "Could not stop $svc"
      fi
    fi
  done
}

restore_web_services() {
  local svc
  for svc in "${STOPPED_SERVICES[@]}"; do
    warn "Starting $svc again..."
    systemctl start "$svc" || err "Could not start $svc. Check: systemctl status $svc"
  done
  STOPPED_SERVICES=()
}

with_web_stop() {
  local auto_stop="$1"
  shift
  if [[ "$auto_stop" == "yes" ]]; then
    trap 'restore_web_services; exit 130' INT TERM
    stop_web_services
  fi
  "$@"
  local rc=$?
  if [[ "$auto_stop" == "yes" ]]; then
    restore_web_services
    trap - INT TERM
  fi
  return $rc
}

safe_domain_name() {
  echo "$1" | sed 's#^\*\.\?##; s#[^A-Za-z0-9._-]#_#g'
}

strip_quotes() {
  sed -E "s/^[^=]+=//; s/^'//; s/'$//; s/^\"//; s/\"$//"
}

conf_value() {
  local conf="$1" key="$2"
  grep -E "^${key}=" "$conf" 2>/dev/null | tail -n1 | strip_quotes
}

cert_file_from_domain() {
  local domain="$1" safe
  safe="$(safe_domain_name "$domain")"
  for f in \
    "$CERT_BASE/$safe/fullchain.pem" \
    "$ACME_HOME/${domain}_ecc/fullchain.cer" \
    "$ACME_HOME/${domain}/fullchain.cer" \
    "$ACME_HOME/${safe}_ecc/fullchain.cer" \
    "$ACME_HOME/${safe}/fullchain.cer"; do
    [[ -f "$f" ]] && { echo "$f"; return 0; }
  done
  find "$ACME_HOME" -maxdepth 2 -type f \( -name fullchain.cer -o -name fullchain.pem \) 2>/dev/null | grep -m1 "/${safe}\(_ecc\)\?/"
}

cert_expiry_epoch() {
  local file="$1" end
  [[ -f "$file" ]] || return 1
  end="$(openssl x509 -enddate -noout -in "$file" 2>/dev/null | sed 's/^notAfter=//')" || return 1
  date -d "$end" +%s 2>/dev/null
}

cert_expiry_human() {
  local file="$1" end
  [[ -f "$file" ]] || { echo "unknown"; return 0; }
  end="$(openssl x509 -enddate -noout -in "$file" 2>/dev/null | sed 's/^notAfter=//')" || { echo "unknown"; return 0; }
  date -d "$end" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || echo "$end"
}

cert_left_human() {
  local file="$1" exp now diff days hours
  exp="$(cert_expiry_epoch "$file")" || { echo "unknown"; return 0; }
  now="$(date +%s)"
  diff=$(( exp - now ))
  if (( diff <= 0 )); then
    echo "expired"
    return 0
  fi
  days=$(( diff / 86400 ))
  hours=$(( (diff % 86400) / 3600 ))
  if (( days > 0 )); then
    echo "${days}d ${hours}h"
  else
    echo "${hours}h"
  fi
}

left_color() {
  local left="$1"
  if [[ "$left" == "expired" ]]; then
    echo -e "${C_RED}${left}${C_RESET}"
  elif [[ "$left" =~ ^([0-9]+)d ]]; then
    local d="${BASH_REMATCH[1]}"
    if (( d <= 7 )); then echo -e "${C_RED}${left}${C_RESET}"
    elif (( d <= 20 )); then echo -e "${C_YELLOW}${left}${C_RESET}"
    else echo -e "${C_GREEN}${left}${C_RESET}"
    fi
  else
    echo -e "${C_YELLOW}${left}${C_RESET}"
  fi
}

collect_acme_confs() {
  find "$ACME_HOME" -mindepth 2 -maxdepth 2 -type f -name "*.conf" 2>/dev/null | while read -r conf; do
    local domain
    domain="$(conf_value "$conf" Le_Domain)"
    [[ -n "$domain" ]] && echo "$conf"
  done | sort -u
}

print_acme_table() {
  local i=0 conf domain alt key cert_file exp left fullchain linked_fullchain
  printf "${C_BOLD}%-4s %-28s %-10s %-22s %-14s %s${C_RESET}\n" "No" "Domain" "Key" "Expires" "Left" "Fullchain"
  line
  while IFS= read -r conf; do
    ((i++)) || true
    domain="$(conf_value "$conf" Le_Domain)"
    alt="$(conf_value "$conf" Le_Alt)"
    key="$(conf_value "$conf" Le_Keylength)"
    linked_fullchain="$(conf_value "$conf" Le_LinkFullChain)"
    cert_file="${linked_fullchain:-$(cert_file_from_domain "$domain")}" 
    exp="$(cert_expiry_human "$cert_file")"
    left="$(cert_left_human "$cert_file")"
    fullchain="${linked_fullchain:-$cert_file}"
    [[ -z "$key" ]] && key="unknown"
    printf "%-4s %-28s %-10s %-22s %-22b %s\n" "$i" "$domain" "$key" "$exp" "$(left_color "$left")" "$fullchain"
    if [[ -n "$alt" && "$alt" != "no" ]]; then
      printf "     ${C_DIM}SAN: %s${C_RESET}\n" "$alt"
    fi
  done < <(collect_acme_confs)
}

list_certs() {
  header
  ensure_acme || { pause; return; }
  say "${C_BOLD}acme.sh managed certificates${C_RESET}"
  line
  if ! collect_acme_confs | grep -q .; then
    warn "No acme.sh certificates found."
  else
    print_acme_table
  fi
  echo
  say "${C_BOLD}External Certbot/Let's Encrypt certificates (read-only)${C_RESET}"
  line
  if [[ -d /etc/letsencrypt/live ]]; then
    local found=0 d f exp left name
    for d in /etc/letsencrypt/live/*; do
      [[ -d "$d" ]] || continue
      f="$d/fullchain.pem"
      [[ -f "$f" ]] || continue
      found=1
      name="$(basename "$d")"
      exp="$(cert_expiry_human "$f")"
      left="$(cert_left_human "$f")"
      printf "%-28s %-22s %-20b %s\n" "$name" "$exp" "$(left_color "$left")" "$f"
    done
    [[ "$found" == 0 ]] && warn "No external certificates found."
  else
    warn "No /etc/letsencrypt/live directory found."
  fi
  pause
}

ask_auto_stop() {
  local ans
  read -rp "Auto-stop Apache/Nginx/Caddy/HAProxy during operation? [Y/n]: " ans
  ans="${ans:-Y}"
  [[ "$ans" =~ ^[Yy] ]] && echo "yes" || echo "no"
}

build_domain_args() {
  local raw="$1" domains=() d args=()
  raw="$(echo "$raw" | tr ',' ' ')"
  for d in $raw; do
    [[ -n "$d" ]] && domains+=("$d")
  done
  if (( ${#domains[@]} == 0 )); then
    return 1
  fi
  for d in "${domains[@]}"; do
    args+=("-d" "$d")
  done
  printf '%s\0' "${args[@]}"
}

install_cert_to_path() {
  local main="$1" keylength="$2" safe dest ecc_flag=()
  safe="$(safe_domain_name "$main")"
  dest="$CERT_BASE/$safe"
  mkdir -p "$dest"
  if [[ "$keylength" == ec-* || "$keylength" == "ecc" ]]; then
    ecc_flag=(--ecc)
  fi
  run_acme_logged --install-cert -d "$main" "${ecc_flag[@]}" \
    --key-file "$dest/private.key" \
    --cert-file "$dest/cert.pem" \
    --ca-file "$dest/ca.pem" \
    --fullchain-file "$dest/fullchain.pem" \
    --reloadcmd "systemctl reload nginx 2>/dev/null || systemctl reload apache2 2>/dev/null || systemctl reload httpd 2>/dev/null || systemctl reload haproxy 2>/dev/null || true"
}

issue_cert_inner() {
  local mode="$1" keylength="$2" ipmode="$3" main="$4"
  shift 4
  local domain_args=("$@") net_args=() item
  while IFS= read -r -d '' item; do net_args+=("$item"); done < <(acme_net_args "$mode" "$ipmode")
  if [[ "$mode" == "http" ]]; then
    run_acme_logged --issue --server "$DEFAULT_CA" "${net_args[@]}" --standalone --keylength "$keylength" "${domain_args[@]}"
  else
    run_acme_logged --issue --server "$DEFAULT_CA" "${net_args[@]}" --alpn --keylength "$keylength" "${domain_args[@]}"
  fi
}

issue_cert_core() {
  local raw_domains="$1" mode="$2" keylength="$3" auto_stop="$4" pause_after="${5:-yes}"
  raw_domains="$(echo "$raw_domains" | xargs)"
  if [[ -z "$raw_domains" ]]; then
    err "No domain entered."
    [[ "$pause_after" == "yes" ]] && pause
    return 1
  fi

  local first_domain item ipmode
  first_domain="$(echo "$raw_domains" | tr ',' ' ' | awk '{print $1}')"

  if ! prepare_acme_network_or_abort yes; then
    echo
    err "ACME API is still unreachable after automatic repair. Issuing was stopped before touching web services."
    warn "Fix outbound HTTPS from this server to: $(le_api_url)"
    warn "Useful checks: timedatectl ; curl -4Iv $(le_nonce_url) ; curl -6Iv $(le_nonce_url)"
    [[ "$pause_after" == "yes" ]] && pause
    return 1
  fi
  ipmode="$ACME_IP_MODE"
  if [[ "$ipmode" == "v4" ]]; then
    ok "IPv4-only ACME mode enabled automatically: acme.sh --request-v4 --listen-v4"
  fi

  local args=()
  while IFS= read -r -d '' item; do args+=("$item"); done < <(build_domain_args "$raw_domains")
  if (( ${#args[@]} == 0 )); then
    err "Could not parse domains."
    [[ "$pause_after" == "yes" ]] && pause
    return 1
  fi

  line
  info "Issuing certificate for: $raw_domains"
  info "Defaults: HTTP-01 port 80, ECC ec-256, auto-stop web services enabled"
  if with_web_stop "$auto_stop" issue_cert_inner "$mode" "$keylength" "$ipmode" "$first_domain" "${args[@]}"; then
    ok "Certificate issued. Installing copy to $CERT_BASE..."
    install_cert_to_path "$first_domain" "$keylength" && ok "Installed: $CERT_BASE/$(safe_domain_name "$first_domain")"
    [[ "$pause_after" == "yes" ]] && pause
    return 0
  else
    err "Certificate issue failed. Check DNS A/AAAA records and open port 80/443."
    [[ "$pause_after" == "yes" ]] && pause
    return 1
  fi
}

issue_cert() {
  header
  ensure_acme || { pause; return; }
  say "${C_BOLD}Quick issue certificate${C_RESET}"
  line
  say "This mode asks only for domain(s)."
  say "Defaults: HTTP-01 on port 80, ECC ec-256, auto-stop Apache/Nginx/Caddy/HAProxy."
  echo
  read -rp "Enter domain(s), separated by space or comma: " raw_domains
  issue_cert_core "$raw_domains" "$DEFAULT_CHALLENGE_MODE" "$DEFAULT_KEY_LENGTH" "$DEFAULT_AUTO_STOP" yes
}

issue_cert_advanced() {
  header
  ensure_acme || { pause; return; }
  say "${C_BOLD}Advanced issue certificate${C_RESET}"
  line
  warn "HTTP-01 standalone normally needs public port 80. TLS-ALPN needs public port 443."
  read -rp "Enter domain(s), separated by space or comma: " raw_domains
  raw_domains="$(echo "$raw_domains" | xargs)"
  [[ -z "$raw_domains" ]] && { err "No domain entered."; pause; return; }

  say "Choose challenge mode:"
  say "  1) HTTP-01 standalone on port 80 (recommended)"
  say "  2) TLS-ALPN-01 standalone on port 443"
  read -rp "Select [1-2]: " mode_choice
  local mode="http"
  [[ "$mode_choice" == "2" ]] && mode="alpn"

  say "Choose key type:"
  say "  1) ECC ec-256 (recommended, small and fast)"
  say "  2) RSA 2048"
  read -rp "Select [1-2]: " key_choice
  local keylength="ec-256"
  [[ "$key_choice" == "2" ]] && keylength="2048"

  local auto_stop
  auto_stop="$(ask_auto_stop)"
  issue_cert_core "$raw_domains" "$mode" "$keylength" "$auto_stop" yes
}

select_acme_cert() {
  local -n out_conf_ref=$1
  local confs=() i=0 choice
  while IFS= read -r conf; do confs+=("$conf"); done < <(collect_acme_confs)
  if (( ${#confs[@]} == 0 )); then
    warn "No acme.sh certificates found."
    return 1
  fi
  printf "${C_BOLD}%-4s %-35s %-10s %-18s${C_RESET}\n" "No" "Domain" "Key" "Left"
  line
  for conf in "${confs[@]}"; do
    ((i++)) || true
    local domain key file left
    domain="$(conf_value "$conf" Le_Domain)"
    key="$(conf_value "$conf" Le_Keylength)"
    file="$(cert_file_from_domain "$domain")"
    left="$(cert_left_human "$file")"
    printf "%-4s %-35s %-10s %-18b\n" "$i" "$domain" "${key:-unknown}" "$(left_color "$left")"
  done
  read -rp "Select certificate number: " choice
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#confs[@]} )); then
    err "Invalid selection."
    return 1
  fi
  out_conf_ref="${confs[$((choice-1))]}"
}

is_ecc_conf() {
  local conf="$1" key
  key="$(conf_value "$conf" Le_Keylength)"
  [[ "$key" == ec-* || "$(dirname "$conf")" == *_ecc ]]
}

renew_cert_inner() {
  local domain="$1" ecc="$2" force="$3" ipmode="$4" args=(--renew -d "$domain") net_args=() item
  while IFS= read -r -d '' item; do net_args+=("$item"); done < <(acme_net_args "renew" "$ipmode")
  [[ "$ecc" == "yes" ]] && args+=(--ecc)
  [[ "$force" == "yes" ]] && args+=(--force)
  run_acme_logged "${net_args[@]}" "${args[@]}"
}

renew_one() {
  header
  ensure_acme || { pause; return; }
  local conf domain key auto_stop force_ans force="no" ecc="no"
  select_acme_cert conf || { pause; return; }
  domain="$(conf_value "$conf" Le_Domain)"
  key="$(conf_value "$conf" Le_Keylength)"
  is_ecc_conf "$conf" && ecc="yes"
  read -rp "Force renewal even if not due? [y/N]: " force_ans
  [[ "$force_ans" =~ ^[Yy] ]] && force="yes"
  auto_stop="$(ask_auto_stop)"
  local ipmode
  if ! prepare_acme_network_or_abort yes; then
    echo
    err "ACME API is still unreachable after automatic repair. Renewal was stopped before touching web services."
    warn "Fix outbound HTTPS from this server to: $(le_api_url)"
    pause
    return
  fi
  ipmode="$ACME_IP_MODE"
  [[ "$ipmode" == "v4" ]] && ok "IPv4-only ACME mode enabled automatically: acme.sh --request-v4"
  line
  info "Renewing: $domain"
  if with_web_stop "$auto_stop" renew_cert_inner "$domain" "$ecc" "$force" "$ipmode"; then
    ok "Renew done. Re-installing copy to $CERT_BASE..."
    install_cert_to_path "$domain" "${key:-ec-256}" && ok "Installed copy updated."
  else
    err "Renew failed."
  fi
  pause
}

renew_all_inner() {
  local force="$1" ipmode="$2" args=(--renew-all) net_args=() item
  while IFS= read -r -d '' item; do net_args+=("$item"); done < <(acme_net_args "renew" "$ipmode")
  [[ "$force" == "yes" ]] && args+=(--force)
  run_acme_logged "${net_args[@]}" "${args[@]}"
}

renew_all() {
  header
  ensure_acme || { pause; return; }
  local force_ans force="no" auto_stop
  read -rp "Force renew all certificates? [y/N]: " force_ans
  [[ "$force_ans" =~ ^[Yy] ]] && force="yes"
  auto_stop="$(ask_auto_stop)"
  local ipmode
  if ! prepare_acme_network_or_abort yes; then
    echo
    err "ACME API is still unreachable after automatic repair. Renew-all was stopped before touching web services."
    warn "Fix outbound HTTPS from this server to: $(le_api_url)"
    pause
    return
  fi
  ipmode="$ACME_IP_MODE"
  [[ "$ipmode" == "v4" ]] && ok "IPv4-only ACME mode enabled automatically: acme.sh --request-v4"
  line
  info "Running renew-all..."
  if with_web_stop "$auto_stop" renew_all_inner "$force" "$ipmode"; then
    ok "Renew-all finished."
  else
    err "Renew-all returned an error. Check output above."
  fi
  pause
}

remove_cert() {
  header
  ensure_acme || { pause; return; }
  local conf domain safe ecc="no" revoke_ans yes_ans args=()
  select_acme_cert conf || { pause; return; }
  domain="$(conf_value "$conf" Le_Domain)"
  safe="$(safe_domain_name "$domain")"
  is_ecc_conf "$conf" && ecc="yes"
  warn "Selected: $domain"
  read -rp "Revoke certificate before removing from acme.sh? [y/N]: " revoke_ans
  read -rp "Type DELETE to confirm removing local records and installed copy: " yes_ans
  [[ "$yes_ans" != "DELETE" ]] && { warn "Cancelled."; pause; return; }

  if [[ "$revoke_ans" =~ ^[Yy] ]]; then
    args=(--revoke -d "$domain")
    [[ "$ecc" == "yes" ]] && args+=(--ecc)
    run_acme_logged "${args[@]}" || warn "Revoke failed or was already invalid. Continuing with remove..."
  fi

  args=(--remove -d "$domain")
  [[ "$ecc" == "yes" ]] && args+=(--ecc)
  run_acme_logged "${args[@]}" || warn "acme.sh remove returned an error."

  if [[ -d "$CERT_BASE/$safe" ]]; then
    rm -rf "$CERT_BASE/$safe"
    ok "Removed installed copy: $CERT_BASE/$safe"
  fi
  ok "Remove operation finished."
  pause
}

backup_certs() {
  header
  ensure_tools || { pause; return; }
  local out
  out="$BACKUP_BASE/ssl-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
  tar -czf "$out" "$ACME_HOME" "$CERT_BASE" 2>/dev/null
  if [[ -f "$out" ]]; then
    ok "Backup created: $out"
  else
    err "Backup failed."
  fi
  pause
}

show_paths() {
  header
  ensure_acme || { pause; return; }
  local conf domain safe
  say "${C_BOLD}Certificate paths for panels/apps${C_RESET}"
  line
  while IFS= read -r conf; do
    domain="$(conf_value "$conf" Le_Domain)"
    safe="$(safe_domain_name "$domain")"
    if [[ -d "$CERT_BASE/$safe" ]]; then
      say "${C_GREEN}$domain${C_RESET}"
      say "  Private key : $CERT_BASE/$safe/private.key"
      say "  Full chain  : $CERT_BASE/$safe/fullchain.pem"
      say "  Cert        : $CERT_BASE/$safe/cert.pem"
      say "  CA          : $CERT_BASE/$safe/ca.pem"
      echo
    fi
  done < <(collect_acme_confs)
  pause
}

port_owner() {
  local port="$1"
  if command_exists ss; then
    ss -ltnp 2>/dev/null | awk -v p=":$port" '$4 ~ p {print}'
  elif command_exists netstat; then
    netstat -ltnp 2>/dev/null | awk -v p=":$port" '$4 ~ p {print}'
  else
    echo "ss/netstat not found"
  fi
}

diagnostics() {
  header
  ensure_tools || { pause; return; }
  say "${C_BOLD}Diagnostics${C_RESET}"
  line
  say "acme.sh: $([[ -x "$ACME_BIN" ]] && "$ACME_BIN" --version 2>/dev/null | head -n1 || echo 'not installed')"
  echo
  say "${C_BOLD}Active web services${C_RESET}"
  for svc in "${WEB_SERVICES[@]}"; do
    if service_exists "$svc"; then
      if is_service_active "$svc"; then
        say "  ${C_GREEN}active${C_RESET}   $svc"
      else
        say "  ${C_DIM}inactive${C_RESET} $svc"
      fi
    fi
  done
  echo
  say "${C_BOLD}Port 80 owner${C_RESET}"
  port_owner 80 || true
  echo
  say "${C_BOLD}Port 443 owner${C_RESET}"
  port_owner 443 || true
  echo
  preflight_acme_api || true
  echo
  read -rp "Enter a domain to check DNS/public IP, or leave blank: " d
  if [[ -n "$d" ]]; then
    echo
    say "${C_BOLD}DNS records for $d${C_RESET}"
    getent ahosts "$d" | awk '{print $1}' | sort -u || true
    if command_exists curl; then
      echo
      say "${C_BOLD}Server public IPv4${C_RESET}"
      curl -4fsS --max-time 5 https://api.ipify.org || true
      echo
      say "${C_BOLD}Server public IPv6${C_RESET}"
      curl -6fsS --max-time 5 https://api64.ipify.org || true
      echo
    fi
  fi
  pause
}

network_repair() {
  header
  need_root
  say "${C_BOLD}Network/TLS repair for ACME${C_RESET}"
  line
  info "Installing/updating curl, OpenSSL, CA certificates, and socat..."
  if command_exists apt-get; then
    DEBIAN_FRONTEND=noninteractive apt-get update -y || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl openssl ca-certificates socat
    update-ca-certificates >/dev/null 2>&1 || true
  elif command_exists dnf; then
    dnf install -y curl openssl ca-certificates socat
    update-ca-trust >/dev/null 2>&1 || true
  elif command_exists yum; then
    yum install -y curl openssl ca-certificates socat
    update-ca-trust >/dev/null 2>&1 || true
  elif command_exists apk; then
    apk add --no-cache curl openssl ca-certificates socat
    update-ca-certificates >/dev/null 2>&1 || true
  else
    warn "Unsupported package manager. Install curl openssl ca-certificates socat manually."
  fi

  if command_exists timedatectl; then
    info "Enabling NTP time sync..."
    timedatectl set-ntp true >/dev/null 2>&1 || true
    timedatectl status | sed -n '1,8p' || true
  fi

  if [[ -x "$ACME_BIN" ]]; then
    info "Upgrading acme.sh..."
    "$ACME_BIN" --upgrade || true
    "$ACME_BIN" --set-default-ca --server "$DEFAULT_CA" >/dev/null 2>&1 || true
  fi

  echo
  preflight_acme_api || true
  pause
}

upgrade_acme() {
  header
  ensure_acme || { pause; return; }
  "$ACME_BIN" --upgrade
  pause
}

install_manager_command() {
  header
  need_root
  local src
  src="$(readlink -f "$0" 2>/dev/null || echo "$0")"
  if [[ ! -f "$src" ]]; then
    err "Could not find current script path."
    pause
    return
  fi
  install -m 755 "$src" "$MANAGER_BIN"
  ok "Installed command: $MANAGER_BIN"
  ok "Run it anytime with: sslmgr"
  pause
}

register_account() {
  header
  ensure_acme || { pause; return; }
  local email
  read -rp "Enter email for Let's Encrypt account: " email
  [[ -z "$email" ]] && { err "Email is required."; pause; return; }
  "$ACME_BIN" --register-account -m "$email" --server "$DEFAULT_CA"
  pause
}

main_menu() {
  need_root
  while true; do
    header
    say "${C_BOLD}1)${C_RESET} View certificates and remaining time"
    say "${C_BOLD}2)${C_RESET} Quick issue certificate (default)"
    say "${C_BOLD}3)${C_RESET} Advanced issue certificate"
    say "${C_BOLD}4)${C_RESET} Renew one certificate"
    say "${C_BOLD}5)${C_RESET} Renew all certificates"
    say "${C_BOLD}6)${C_RESET} Remove certificate"
    say "${C_BOLD}7)${C_RESET} Show cert/key paths"
    say "${C_BOLD}8)${C_RESET} Backup certificates"
    say "${C_BOLD}9)${C_RESET} Diagnostics"
    say "${C_BOLD}10)${C_RESET} Install/Update local command: sslmgr"
    say "${C_BOLD}11)${C_RESET} Upgrade acme.sh"
    say "${C_BOLD}12)${C_RESET} Register/Update Let's Encrypt account email"
    say "${C_BOLD}13)${C_RESET} Network/TLS repair & ACME preflight"
    say "${C_BOLD}0)${C_RESET} Exit"
    echo
    read -rp "Select an option: " choice
    case "$choice" in
      1) list_certs ;;
      2) issue_cert ;;
      3) issue_cert_advanced ;;
      4) renew_one ;;
      5) renew_all ;;
      6) remove_cert ;;
      7) show_paths ;;
      8) backup_certs ;;
      9) diagnostics ;;
      10) install_manager_command ;;
      11) upgrade_acme ;;
      12) register_account ;;
      13) network_repair ;;
      0) exit 0 ;;
      *) warn "Invalid option"; sleep 1 ;;
    esac
  done
}

quick_issue_from_cli() {
  need_root
  ensure_acme || return 1
  local raw_domains="$*"
  if [[ -z "$(echo "$raw_domains" | xargs)" ]]; then
    err "Usage: sslmgr issue example.com [www.example.com]"
    return 1
  fi
  issue_cert_core "$raw_domains" "$DEFAULT_CHALLENGE_MODE" "$DEFAULT_KEY_LENGTH" "$DEFAULT_AUTO_STOP" no
}

case "${1:-}" in
  issue|quick|--issue)
    shift
    quick_issue_from_cli "$@"
    ;;
  help|--help|-h)
    echo "$APP_NAME v$APP_VERSION"
    echo "Usage:"
    echo "  sslmgr                    Open menu"
    echo "  sslmgr issue example.com  Issue SSL with default quick mode"
    ;;
  *)
    main_menu "$@"
    ;;
esac
