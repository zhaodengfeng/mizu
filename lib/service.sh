#!/usr/bin/env bash
# Mizu — systemd service management

[[ -n "${_MIZU_SERVICE_SH_LOADED:-}" ]] && return 0
_MIZU_SERVICE_SH_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ─── Create systemd service ──────────────────────────────────────────────────
# Usage: service_create PROTOCOL BINARY ARGS [EXTRA_DEPS]
# EXTRA_DEPS format: "After=xxx.service Wants=xxx.service"
service_create() {
    local proto="$1"
    local binary="$2"
    local args="$3"
    shift 3
    local extra_after=""
    local extra_wants=""
    local extra_readwrite=""

    # Parse extra dependencies
    while [[ $# -gt 0 ]]; do
        case "$1" in
            after=*) extra_after="$1" ;;
            wants=*) extra_wants="$1" ;;
            readwrite=*) extra_readwrite="$1" ;;
        esac
        shift
    done

    local service_name="mizu-${proto}"
    local service_file="/etc/systemd/system/${service_name}.service"
    local name="${PROTO_NAMES[$proto]:-$proto}"
    ensure_mizu_service_group || return 1

    local svc_group svc_user
    svc_group=$(mizu_service_group)
    svc_user=$(mizu_service_user)

    local after_line="After=network.target"
    local wants_line=""
    local rw_paths="ReadWritePaths=/etc/mizu/${proto} /var/log/mizu"

    [[ -n "$extra_after" ]] && after_line="${after_line} ${extra_after#after=}"
    [[ -n "$extra_wants" ]] && wants_line=$'\n'"Wants=${extra_wants#wants=}"
    [[ -n "$extra_readwrite" ]] && rw_paths="${rw_paths} ${extra_readwrite#readwrite=}"

    cat > "$service_file" <<EOF
[Unit]
Description=Mizu - ${name}
${after_line}${wants_line}

[Service]
Type=simple
User=${svc_user}
Group=${svc_group}
UMask=0027
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX AF_NETLINK
RestrictRealtime=true
DevicePolicy=closed
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
ExecStart=${binary} ${args}
Restart=on-failure
RestartSec=5
${rw_paths}

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload --no-block 2>/dev/null || systemctl daemon-reload
}

# ─── Service control ─────────────────────────────────────────────────────────
service_start() {
    local proto="$1"
    systemctl start "mizu-${proto}" 2>/dev/null
}

service_stop() {
    local proto="$1"
    systemctl stop "mizu-${proto}" 2>/dev/null
}

service_restart() {
    local proto="$1"
    systemctl restart "mizu-${proto}" 2>/dev/null
}

service_enable() {
    local proto="$1"
    systemctl enable "mizu-${proto}" 2>/dev/null
}

service_disable() {
    local proto="$1"
    systemctl disable "mizu-${proto}" 2>/dev/null
}

service_is_active() {
    local proto="$1"
    systemctl is-active "mizu-${proto}" &>/dev/null
}

service_status() {
    local proto="$1"
    systemctl is-active "mizu-${proto}" 2>/dev/null || echo "stopped"
}

# ─── Remove service ──────────────────────────────────────────────────────────
service_remove() {
    local proto="$1"
    local service_name="mizu-${proto}"
    systemctl stop "$service_name" 2>/dev/null
    systemctl disable "$service_name" 2>/dev/null
    rm -f "/etc/systemd/system/${service_name}.service"
    systemctl daemon-reload --no-block 2>/dev/null || systemctl daemon-reload
}

# ─── Create Caddy service (special) ──────────────────────────────────────────
service_create_caddy() {
    local service_file="/etc/systemd/system/mizu-caddy.service"
    local caddyfile="/etc/mizu/caddy/Caddyfile"
    ensure_mizu_service_group || return 1

    local svc_group svc_user
    svc_group=$(mizu_service_group)
    svc_user=$(mizu_service_user)

    cat > "$service_file" <<EOF
[Unit]
Description=Mizu - Caddy (Trojan 伪装)
After=network.target

[Service]
Type=simple
User=${svc_user}
Group=${svc_group}
UMask=0027
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX AF_NETLINK
RestrictRealtime=true
DevicePolicy=closed
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
ExecStart=/usr/local/bin/caddy run --config ${caddyfile}
Restart=on-failure
RestartSec=5
ReadWritePaths=/var/www/mizu /var/log/mizu /etc/mizu/caddy

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload --no-block 2>/dev/null || systemctl daemon-reload
}

# ─── Start all services ──────────────────────────────────────────────────────
service_start_all() {
    local protocols
    protocols=$(state_list_protocols)
    [[ -z "$protocols" ]] && return 0
    while IFS= read -r proto; do
        [[ -z "$proto" ]] && continue
        service_start "$proto"
        service_enable "$proto"
    done <<< "$protocols"
}

service_start_all_verified() {
    local protocols
    protocols=$(state_list_protocols)
    [[ -z "$protocols" ]] && return 0

    local failures=()
    while IFS= read -r proto; do
        [[ -z "$proto" ]] && continue
        service_enable "$proto" || true
        if ! service_start_verified "$proto"; then
            failures+=("${PROTO_NAMES[$proto]:-$proto}")
        fi
    done <<< "$protocols"

    if [[ ${#failures[@]} -gt 0 ]]; then
        msg_error "以下协议启动失败: ${failures[*]}"
        return 1
    fi
    return 0
}

# ─── Stop all services ───────────────────────────────────────────────────────
service_stop_all() {
    local protocols
    protocols=$(state_list_protocols)
    if [[ -n "$protocols" ]]; then
        while IFS= read -r proto; do
            [[ -n "$proto" ]] && service_stop "$proto"
        done <<< "$protocols"
    fi
    # Stop Caddy if running
    systemctl stop mizu-caddy 2>/dev/null || true
}

service_stop_all_verified() {
    local protocols
    protocols=$(state_list_protocols)
    [[ -z "$protocols" ]] && return 0

    local failures=()
    while IFS= read -r proto; do
        [[ -z "$proto" ]] && continue
        if ! service_stop_verified "$proto"; then
            failures+=("${PROTO_NAMES[$proto]:-$proto}")
        fi
    done <<< "$protocols"

    systemctl stop mizu-caddy 2>/dev/null || true

    if [[ ${#failures[@]} -gt 0 ]]; then
        msg_error "以下协议停止失败: ${failures[*]}"
        return 1
    fi
    return 0
}

# ─── Remove all services ─────────────────────────────────────────────────────
service_remove_all() {
    local protocols
    protocols=$(state_list_protocols)
    [[ -z "$protocols" ]] && return 0
    while IFS= read -r proto; do
        [[ -z "$proto" ]] && continue
        service_remove "$proto"
    done <<< "$protocols"
    # Remove caddy service if exists
    systemctl stop mizu-caddy 2>/dev/null
    systemctl disable mizu-caddy 2>/dev/null
    rm -f /etc/systemd/system/mizu-caddy.service
    systemctl daemon-reload
}
