#!/usr/bin/env bash
# Mizu — systemd service management

[[ -n "${_MIZU_SERVICE_SH_LOADED:-}" ]] && return 0
_MIZU_SERVICE_SH_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ─── Detect unprivileged group (nogroup on Debian, nobody on RHEL) ────────────
_service_group() {
    if getent group nogroup &>/dev/null; then
        echo "nogroup"
    elif getent group nobody &>/dev/null; then
        echo "nobody"
    else
        echo "nogroup"
    fi
}

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
    local svc_group
    svc_group=$(_service_group)

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
User=nobody
Group=${svc_group}
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

    systemctl daemon-reload
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
    systemctl daemon-reload
}

# ─── Create Caddy service (special) ──────────────────────────────────────────
service_create_caddy() {
    local service_file="/etc/systemd/system/mizu-caddy.service"
    local caddyfile="/etc/mizu/caddy/Caddyfile"
    local svc_group
    svc_group=$(_service_group)

    cat > "$service_file" <<EOF
[Unit]
Description=Mizu - Caddy (Trojan 伪装)
After=network.target

[Service]
Type=simple
User=nobody
Group=${svc_group}
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

    systemctl daemon-reload
}

# ─── Start all services ──────────────────────────────────────────────────────
service_start_all() {
    local protocols
    protocols=$(state_list_protocols)
    while IFS= read -r proto; do
        service_start "$proto"
        service_enable "$proto"
    done <<< "$protocols"
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

# ─── Remove all services ─────────────────────────────────────────────────────
service_remove_all() {
    local protocols
    protocols=$(state_list_protocols)
    while IFS= read -r proto; do
        service_remove "$proto"
    done <<< "$protocols"
    # Remove caddy service if exists
    systemctl stop mizu-caddy 2>/dev/null
    systemctl disable mizu-caddy 2>/dev/null
    rm -f /etc/systemd/system/mizu-caddy.service
    systemctl daemon-reload
}
