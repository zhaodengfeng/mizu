#!/usr/bin/env bash
# Mizu — Common utility functions
# Port detection, password generation, architecture detection, state management

# ─── Include Guard ────────────────────────────────────────────────────────────
[[ -n "${_MIZU_COMMON_SH_LOADED:-}" ]] && return 0
_MIZU_COMMON_SH_LOADED=1

# ─── ANSI Colors ───────────────────────────────────────────────────────────────
readonly C_CYAN='\033[1;36m'
readonly C_WHITE='\033[1;37m'
readonly C_GRAY='\033[2;37m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[0;33m'
readonly C_RED='\033[1;31m'
readonly C_MAGENTA='\033[0;35m'
readonly C_BLUE='\033[1;34m'
readonly C_BOLD='\033[1m'
readonly C_RESET='\033[0m'

# ─── Print Functions ──────────────────────────────────────────────────────────
msg_info()    { printf "${C_CYAN}%b${C_RESET}\n" "$*"; }
msg_success() { printf "${C_GREEN}  ✓ %b${C_RESET}\n" "$*"; }
msg_warn()    { printf "${C_YELLOW}  ○ %b${C_RESET}\n" "$*"; }
msg_error()   { printf "${C_RED}  ✗ %b${C_RESET}\n" "$*"; }
msg_step()    { printf "${C_WHITE}[%d/%d] %b${C_RESET}\n" "$1" "$2" "$3"; }
msg_dim()     { printf "${C_GRAY}%b${C_RESET}\n" "$*"; }
msg_link()    { printf "${C_CYAN}  %b${C_RESET}\n" "$*"; }
msg_running() { printf "${C_GREEN}●运行${C_RESET}"; }
msg_stopped() { printf "${C_RED}○停止${C_RESET}"; }

msg_separator() {
    printf "${C_GRAY}──────────────────────────────────────────${C_RESET}\n"
}

# ─── Check Root ───────────────────────────────────────────────────────────────
check_root() {
    if [[ $EUID -ne 0 ]]; then
        msg_error "请使用 root 用户运行"
        exit 1
    fi
}

# ─── Service Identity & Permission Helpers ───────────────────────────────────
readonly MIZU_SERVICE_USER="nobody"
readonly MIZU_SERVICE_GROUP="mizu"

_group_exists() {
    local group="$1"
    getent group "$group" >/dev/null 2>&1 || grep -q "^${group}:" /etc/group 2>/dev/null
}

mizu_service_user() {
    echo "$MIZU_SERVICE_USER"
}

mizu_service_group() {
    echo "$MIZU_SERVICE_GROUP"
}

ensure_mizu_service_group() {
    if _group_exists "$MIZU_SERVICE_GROUP"; then
        return 0
    fi

    if command -v groupadd >/dev/null 2>&1; then
        groupadd --system "$MIZU_SERVICE_GROUP" >/dev/null 2>&1 \
            || groupadd "$MIZU_SERVICE_GROUP" >/dev/null 2>&1 || true
    elif command -v addgroup >/dev/null 2>&1; then
        addgroup --system "$MIZU_SERVICE_GROUP" >/dev/null 2>&1 \
            || addgroup -S "$MIZU_SERVICE_GROUP" >/dev/null 2>&1 \
            || addgroup "$MIZU_SERVICE_GROUP" >/dev/null 2>&1 || true
    fi

    if ! _group_exists "$MIZU_SERVICE_GROUP"; then
        msg_error "无法创建服务组: ${MIZU_SERVICE_GROUP}"
        return 1
    fi
}

secure_proto_dir() {
    local proto_dir="$1"
    [[ -d "$proto_dir" ]] || return 0

    ensure_mizu_service_group || return 1

    local group
    group=$(mizu_service_group)

    chgrp "$group" "$proto_dir" 2>/dev/null || true
    chmod 750 "$proto_dir" 2>/dev/null || true

    local had_nullglob=0
    shopt -q nullglob && had_nullglob=1
    shopt -s nullglob

    local file
    for file in "$proto_dir"/*; do
        [[ -f "$file" ]] || continue
        case "$file" in
            *.json|*.yaml|*.yml|*.conf)
                chgrp "$group" "$file" 2>/dev/null || true
                chmod 640 "$file" 2>/dev/null || true
                ;;
        esac
    done

    if [[ $had_nullglob -eq 0 ]]; then
        shopt -u nullglob
    fi
}

# ─── Architecture Detection ──────────────────────────────────────────────────
detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7l)  echo "armv7" ;;
        *)       echo "unsupported" ;;
    esac
}

detect_arch_raw() {
    uname -m
}

# ─── OS Detection ─────────────────────────────────────────────────────────────
detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "${ID}"
    elif command -v lsb_release &>/dev/null; then
        lsb_release -is | tr '[:upper:]' '[:lower:]'
    else
        echo "unknown"
    fi
}

detect_os_full() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "${PRETTY_NAME:-$ID $VERSION_ID}"
    else
        uname -srm
    fi
}

detect_pkg_manager() {
    if command -v apt-get &>/dev/null; then
        echo "apt"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v yum &>/dev/null; then
        echo "yum"
    elif command -v apk &>/dev/null; then
        echo "apk"
    else
        echo "unknown"
    fi
}

# ─── IP Detection ────────────────────────────────────────────────────────────
_CACHED_IPV4=""

detect_ipv4() {
    if [[ -n "$_CACHED_IPV4" ]]; then
        echo "$_CACHED_IPV4"
        return
    fi
    local ip
    ip=$(curl -s4 --max-time 5 https://ifconfig.me 2>/dev/null) \
        || ip=$(curl -s4 --max-time 5 https://api.ipify.org 2>/dev/null) \
        || ip=$(curl -s4 --max-time 5 https://ipv4.icanhazip.com 2>/dev/null)
    if [[ -z "$ip" ]]; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    if [[ -z "$ip" ]]; then
        msg_warn "无法自动检测公网 IP"
        printf "${C_WHITE}请输入服务器公网 IP: ${C_RESET}"
        read -r ip
    fi
    _CACHED_IPV4="$ip"
    echo "${ip}"
}

detect_ipv6() {
    local ip
    ip=$(curl -s6 --max-time 5 https://ifconfig.me 2>/dev/null) \
        || ip=$(curl -s6 --max-time 5 https://api64.ipify.org 2>/dev/null)
    echo "${ip}"
}

# ─── Port Check ───────────────────────────────────────────────────────────────
port_in_use() {
    local port=$1
    ss -tlnp 2>/dev/null | grep -q ":${port} " && return 0
    ss -ulnp 2>/dev/null | grep -q ":${port} " && return 0
    return 1
}

port_in_use_udp() {
    local port=$1
    ss -ulnp 2>/dev/null | grep -q ":${port} " && return 0
    return 1
}

find_free_port() {
    local port=$1
    while port_in_use "$port" || port_in_use_udp "$port"; do
        ((port++))
        if ((port > 65535)); then
            msg_error "没有可用端口 (已搜索至 65535)"
            return 1
        fi
    done
    echo "$port"
}

# ─── Password / Credential Generation ─────────────────────────────────────────
gen_hex() {
    local len="${1:-16}"
    openssl rand -hex "$len"
}

gen_base64() {
    local len="${1:-32}"
    openssl rand -base64 "$len" | tr -d '\n'
}

gen_base64url() {
    local len="${1:-32}"
    openssl rand -base64 "$len" | tr -d '\n' | tr '/+' '_-' | tr -d '='
}

gen_uuid() {
    local result
    if command -v xray &>/dev/null; then
        result=$(xray uuid 2>/dev/null)
    else
        result=$(python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null \
            || cat /proc/sys/kernel/random/uuid 2>/dev/null \
            || uuidgen 2>/dev/null)
    fi
    if [[ -z "$result" ]]; then
        msg_error "无法生成 UUID，请安装 uuidgen 或 python3"
        return 1
    fi
    echo "$result"
}

gen_password() {
    gen_hex 16
}

# ─── Domain Validation ────────────────────────────────────────────────────────
validate_domain() {
    local domain="$1"
    if [[ -z "$domain" ]]; then
        return 1
    fi
    # Basic domain validation
    if [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        return 0
    fi
    return 1
}

# ─── URL Encoding (safe — no eval, uses argv) ────────────────────────────────
url_encode() {
    local str="$1"
    python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$str" 2>/dev/null \
        || {
            # Pure Bash fallback
            local encoded=""
            local i char code
            for ((i=0; i<${#str}; i++)); do
                char="${str:$i:1}"
                case "$char" in
                    [a-zA-Z0-9.~_-]) encoded+="$char" ;;
                    *) printf -v code '%%%02X' "'$char"; encoded+="$code" ;;
                esac
            done
            echo "$encoded"
        }
}

# ─── State Management ─────────────────────────────────────────────────────────
STATE_FILE="/etc/mizu/state.json"

# Convert jq dot-path to safe bracket notation for keys with hyphens
# .protocols.vless-reality.credential.uuid → .protocols["vless-reality"].credential.uuid
_jq_safe_path() {
    echo "$1" | sed -E 's/\.([a-zA-Z0-9_]*-[a-zA-Z0-9_-]*)/["\1"]/g'
}

state_init() {
    if [[ ! -f "$STATE_FILE" ]]; then
        mkdir -p /etc/mizu
        (
            flock -x 200
            # Double-check after acquiring lock (another process may have created it)
            if [[ -f "$STATE_FILE" ]]; then
                exit 0
            fi
            cat > "$STATE_FILE" <<EOF
{
    "version": "1.0.0",
    "installed": "$(date +%Y-%m-%d)",
    "runtimes": {},
    "protocols": {}
}
EOF
            chmod 600 "$STATE_FILE"
        ) 200>"${STATE_FILE}.lock"
    fi
}

state_get() {
    local key
    key=$(_jq_safe_path "$1")
    jq -r "${key} // empty" "$STATE_FILE" 2>/dev/null || echo ""
}

state_set() {
    local key
    key=$(_jq_safe_path "$1")
    local value="$2"
    (
        flock -x 200
        local tmp
        tmp=$(mktemp "${STATE_FILE}.XXXXXX") || exit 1
        trap 'rm -f "$tmp"' EXIT
        if jq --argjson v "$value" "${key} = \$v" "$STATE_FILE" > "$tmp"; then
            mv "$tmp" "$STATE_FILE"
            trap - EXIT
        else
            rm -f "$tmp"
            exit 1
        fi
    ) 200>"${STATE_FILE}.lock"
}

state_set_string() {
    local key
    key=$(_jq_safe_path "$1")
    local value="$2"
    (
        flock -x 200
        local tmp
        tmp=$(mktemp "${STATE_FILE}.XXXXXX") || exit 1
        trap 'rm -f "$tmp"' EXIT
        if jq --arg v "$value" "${key} = \$v" "$STATE_FILE" > "$tmp"; then
            mv "$tmp" "$STATE_FILE"
            trap - EXIT
        else
            rm -f "$tmp"
            exit 1
        fi
    ) 200>"${STATE_FILE}.lock"
}

state_del() {
    local key
    key=$(_jq_safe_path "$1")
    (
        flock -x 200
        local tmp
        tmp=$(mktemp "${STATE_FILE}.XXXXXX") || exit 1
        trap 'rm -f "$tmp"' EXIT
        if jq "del(${key})" "$STATE_FILE" > "$tmp"; then
            mv "$tmp" "$STATE_FILE"
            trap - EXIT
        else
            rm -f "$tmp"
            exit 1
        fi
    ) 200>"${STATE_FILE}.lock"
}

state_list_protocols() {
    jq -r '.protocols | keys[]' "$STATE_FILE" 2>/dev/null || true
}

state_protocol_exists() {
    local proto="$1"
    jq -e --arg p "$proto" '.protocols[$p] != null' "$STATE_FILE" &>/dev/null
}

# ─── Prompt Helpers ───────────────────────────────────────────────────────────
prompt_yesno() {
    local msg="$1"
    local default="${2:-Y}"
    local prompt_suffix
    if [[ "$default" == "Y" ]]; then
        prompt_suffix="[Y/n]"
    else
        prompt_suffix="[y/N]"
    fi
    while true; do
        printf "${C_WHITE}%s %s: ${C_RESET}" "$msg" "$prompt_suffix"
        read -r answer
        answer="${answer:-$default}"
        case "$answer" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
        esac
    done
}

prompt_input() {
    local msg="$1"
    local var="$2"
    printf "${C_WHITE}%s: ${C_RESET}" "$msg"
    read -r "$var"
}

prompt_domain() {
    # CLI mode: use MIZU_DOMAIN env var if set
    if [[ -n "${MIZU_DOMAIN:-}" ]]; then
        if validate_domain "$MIZU_DOMAIN"; then
            echo "$MIZU_DOMAIN"
            return 0
        fi
        msg_error "MIZU_DOMAIN 域名格式无效: $MIZU_DOMAIN" >&2
    fi
    local domain=""
    while true; do
        printf "${C_WHITE}请输入域名: ${C_RESET}" >&2
        read -r domain
        if validate_domain "$domain"; then
            echo "$domain"
            return 0
        fi
        msg_error "域名格式无效，请重新输入" >&2
    done
}

# ─── Spinner ──────────────────────────────────────────────────────────────────
_spinner_pid=""

spinner_start() {
    local msg="$1"
    (
        while true; do
            printf "\r${C_YELLOW}  ⠋ %s${C_RESET}" "$msg"
            sleep 0.1
            printf "\r${C_YELLOW}  ⠙ %s${C_RESET}" "$msg"
            sleep 0.1
            printf "\r${C_YELLOW}  ⠹ %s${C_RESET}" "$msg"
            sleep 0.1
            printf "\r${C_YELLOW}  ⠸ %s${C_RESET}" "$msg"
            sleep 0.1
            printf "\r${C_YELLOW}  ⠼ %s${C_RESET}" "$msg"
            sleep 0.1
            printf "\r${C_YELLOW}  ⠴ %s${C_RESET}" "$msg"
            sleep 0.1
            printf "\r${C_YELLOW}  ⠦ %s${C_RESET}" "$msg"
            sleep 0.1
            printf "\r${C_YELLOW}  ⠧ %s${C_RESET}" "$msg"
            sleep 0.1
            printf "\r${C_YELLOW}  ⠇ %s${C_RESET}" "$msg"
            sleep 0.1
            printf "\r${C_YELLOW}  ⠏ %s${C_RESET}" "$msg"
            sleep 0.1
        done
    ) &
    _spinner_pid=$!
}

spinner_stop() {
    if [[ -n "$_spinner_pid" ]]; then
        kill "$_spinner_pid" 2>/dev/null
        wait "$_spinner_pid" 2>/dev/null
        _spinner_pid=""
        printf "\r%50s\r" ""
    fi
}

# ─── Download Helper ─────────────────────────────────────────────────────────
download_file() {
    local url="$1"
    local output="$2"
    curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 300 -o "$output" "$url"
}

github_latest_tag() {
    local repo="$1"
    local response
    response=$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null)
    if [[ -n "$response" ]] && echo "$response" | jq -e '.message' 2>/dev/null | grep -qi "rate limit"; then
        msg_warn "GitHub API 限流，请稍后重试或配置 GITHUB_TOKEN"
        return 1
    fi
    echo "$response" | jq -r '.tag_name // empty' \
        | sed 's/^v//'
}

github_latest_url() {
    local repo="$1"
    local pattern="$2"
    local url
    url=$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
        | jq -r ".assets[] | select(.name | test(\"${pattern}\")) | .browser_download_url" \
        | head -1)
    echo "$url"
}

# ─── Network Interface ───────────────────────────────────────────────────────
get_default_interface() {
    ip route show default 2>/dev/null | awk '{print $5}' | head -1
}

# ─── Misc ─────────────────────────────────────────────────────────────────────
press_enter() {
    local msg="${1:-按回车键继续...}"
    printf "${C_GRAY}%s${C_RESET}" "$msg"
    read -r
}

clear_screen() {
    printf "\033[2J\033[H"
}

# ─── Install Result Display (dedup helper) ────────────────────────────────────
show_install_result() {
    local proto="$1"
    local share_link="$2"
    if [[ -n "$share_link" ]]; then
        mkdir -p /etc/mizu/share-links
        echo "$share_link" > "/etc/mizu/share-links/${proto}.txt"
        echo ""
        printf "  分享链接:\n"
        msg_link "  ${share_link}"
        echo ""
    fi
    if [[ -t 0 ]]; then
        printf "${C_GRAY}  [Q] 显示二维码  [回车] 继续${C_RESET}\n"
        read -r -n1 action
        echo ""
        if [[ "$action" == [qQ] ]]; then
            show_qrcode "$share_link"
            echo ""
            press_enter
        fi
    fi
}

# ─── QR Code Display ──────────────────────────────────────────────────────────
show_qrcode() {
    local text="$1"
    if command -v qrencode &>/dev/null; then
        echo ""
        qrencode -t ANSIUTF8 -m 2 "$text"
        echo ""
    else
        msg_warn "qrencode 未安装，无法显示二维码"
    fi
}

# ─── State Save Protocol (dedup helper) ───────────────────────────────────────
state_set_protocol() {
    local proto="$1"
    local json="$2"
    state_set ".protocols.${proto}" "$json" || return 1
    secure_proto_dir "${proto_dir:-/etc/mizu/${proto}}"
}

# ─── Service Start with Verification ─────────────────────────────────────────
_systemd_unit_print_recent_logs() {
    local unit="$1"
    msg_dim "最近日志:"
    journalctl -u "$unit" --no-pager -n 15 2>/dev/null | while IFS= read -r line; do
        printf "  %s\n" "$line"
    done
}

_systemd_unit_wait_active() {
    local unit="$1"
    local retries=3
    while (( retries > 0 )); do
        sleep 1
        if systemctl is-active --quiet "$unit" 2>/dev/null; then
            return 0
        fi
        ((retries--))
    done
    return 1
}

systemd_unit_start_verified() {
    local unit="$1"
    local display_name="${2:-$unit}"
    systemctl start "$unit"
    if _systemd_unit_wait_active "$unit"; then
        msg_success "${display_name} 已启动"
        return 0
    fi
    msg_error "${display_name} 启动失败"
    _systemd_unit_print_recent_logs "$unit"
    return 1
}

systemd_unit_restart_verified() {
    local unit="$1"
    local display_name="${2:-$unit}"
    systemctl restart "$unit"
    if _systemd_unit_wait_active "$unit"; then
        msg_success "${display_name} 已重启"
        return 0
    fi
    msg_error "${display_name} 重启失败"
    _systemd_unit_print_recent_logs "$unit"
    return 1
}

systemd_unit_stop_verified() {
    local unit="$1"
    local display_name="${2:-$unit}"
    systemctl stop "$unit"
    if systemctl is-active --quiet "$unit" 2>/dev/null; then
        msg_error "${display_name} 停止失败"
        _systemd_unit_print_recent_logs "$unit"
        return 1
    fi
    msg_success "${display_name} 已停止"
    return 0
}

service_start_verified() {
    local proto="$1"
    secure_proto_dir "/etc/mizu/${proto}" || return 1
    systemd_unit_start_verified "mizu-${proto}" "${PROTO_NAMES[$proto]:-$proto}"
}

service_restart_verified() {
    local proto="$1"
    secure_proto_dir "/etc/mizu/${proto}" || return 1
    systemd_unit_restart_verified "mizu-${proto}" "${PROTO_NAMES[$proto]:-$proto}"
}

service_stop_verified() {
    local proto="$1"
    systemd_unit_stop_verified "mizu-${proto}" "${PROTO_NAMES[$proto]:-$proto}"
}

# ─── Port Conflict Check Helper ──────────────────────────────────────────────
resolve_port() {
    local default_port="$1"
    local fallback_port="${2:-8443}"
    if port_in_use "$default_port" || port_in_use_udp "$default_port"; then
        find_free_port "$fallback_port"
    else
        echo "$default_port"
    fi
}
