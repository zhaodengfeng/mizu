#!/usr/bin/env bash
# Mizu — 全协议原生代理部署管理系统
# Version: 26.4.16
# 一键部署 9 种代理协议，每个协议使用其作者发布的原生程序

set -euo pipefail

VERSION="26.4.16"
MIZU_REPO="zhaodengfeng/mizu"

# ─── Bootstrap: if running from process substitution (curl|bash), clone and re-exec ──
if [[ "$0" == /dev/fd/* ]]; then
    if ! command -v git >/dev/null 2>&1; then
        echo "错误: 请先安装 git (apt install git / yum install git)" >&2
        exit 1
    fi
    if [[ -d /opt/mizu ]]; then
        echo "检测到已有安装，正在更新 ..."
        git -C /opt/mizu pull --ff-only 2>/dev/null || true
    else
        echo "正在下载 Mizu 到 /opt/mizu ..."
        git clone "https://github.com/${MIZU_REPO}.git" /opt/mizu --quiet
    fi
    echo "启动 Mizu ..."
    exec bash /opt/mizu/mizu.sh "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# If running from /opt/mizu, use that path
if [[ "$SCRIPT_DIR" == "/opt/mizu" ]]; then
    LIB_DIR="/opt/mizu/lib"
    PROTO_DIR_SCRIPTS="/opt/mizu/protocols"
    RUNTIME_DIR="/opt/mizu/runtimes"
    TEMPLATE_DIR="/opt/mizu/templates"
else
    LIB_DIR="${SCRIPT_DIR}/lib"
    PROTO_DIR_SCRIPTS="${SCRIPT_DIR}/protocols"
    RUNTIME_DIR="${SCRIPT_DIR}/runtimes"
    TEMPLATE_DIR="${SCRIPT_DIR}/templates"
fi

# ─── Load libraries ──────────────────────────────────────────────────────────
source "${LIB_DIR}/common.sh"
source "${LIB_DIR}/menu.sh"
source "${LIB_DIR}/detect.sh"
source "${LIB_DIR}/cert.sh"
source "${LIB_DIR}/service.sh"
source "${LIB_DIR}/share-link.sh"
source "${LIB_DIR}/fallback-site.sh"

# ─── Global State ────────────────────────────────────────────────────────────
FIRST_RUN=false

# ─── Protocol handler mapping ────────────────────────────────────────────────
declare -A PROTO_SCRIPTS=(
    ["trojan"]="${PROTO_DIR_SCRIPTS}/trojan.sh"
    ["vless-reality"]="${PROTO_DIR_SCRIPTS}/vless-reality.sh"
    ["vless-vision"]="${PROTO_DIR_SCRIPTS}/vless-vision.sh"
    ["vmess"]="${PROTO_DIR_SCRIPTS}/vmess.sh"
    ["shadowtls"]="${PROTO_DIR_SCRIPTS}/shadowtls.sh"
    ["anytls"]="${PROTO_DIR_SCRIPTS}/anytls.sh"
    ["hysteria2"]="${PROTO_DIR_SCRIPTS}/hysteria2.sh"
    ["shadowsocks"]="${PROTO_DIR_SCRIPTS}/shadowsocks.sh"
    ["snell"]="${PROTO_DIR_SCRIPTS}/snell.sh"
)

declare -A PROTO_INSTALL_FUNC=(
    ["trojan"]="trojan_install"
    ["vless-reality"]="vless_reality_install"
    ["vless-vision"]="vless_vision_install"
    ["vmess"]="vmess_install"
    ["shadowtls"]="shadowtls_install"
    ["anytls"]="anytls_install"
    ["hysteria2"]="hysteria2_install"
    ["shadowsocks"]="shadowsocks_install"
    ["snell"]="snell_install"
)

declare -A PROTO_REGEN_FUNC=(
    ["trojan"]="trojan_regen"
    ["vless-reality"]="vless_reality_regen"
    ["vless-vision"]="vless_vision_regen"
    ["vmess"]="vmess_regen"
    ["shadowtls"]="shadowtls_regen"
    ["anytls"]="anytls_regen"
    ["hysteria2"]="hysteria2_regen"
    ["shadowsocks"]="shadowsocks_regen"
    ["snell"]="snell_regen"
)

declare -A PROTO_UNINSTALL_FUNC=(
    ["trojan"]="trojan_uninstall"
    ["vless-reality"]="vless_reality_uninstall"
    ["vless-vision"]="vless_vision_uninstall"
    ["vmess"]="vmess_uninstall"
    ["shadowtls"]="shadowtls_uninstall"
    ["anytls"]="anytls_uninstall"
    ["hysteria2"]="hysteria2_uninstall"
    ["shadowsocks"]="shadowsocks_uninstall"
    ["snell"]="snell_uninstall"
)

# ─── Load protocol scripts ──────────────────────────────────────────────────
load_protocols() {
    for proto in "${!PROTO_SCRIPTS[@]}"; do
        if [[ -f "${PROTO_SCRIPTS[$proto]}" ]]; then
            source "${PROTO_SCRIPTS[$proto]}"
        fi
    done
}

# ─── Source runtime scripts ──────────────────────────────────────────────────
load_runtimes() {
    for rt_file in "${RUNTIME_DIR}"/*.sh; do
        [[ -f "$rt_file" ]] && source "$rt_file"
    done
}

# ─── Init ─────────────────────────────────────────────────────────────────────
mizu_init() {
    check_root

    # Create log directory
    mkdir -p /var/log/mizu

    # Setup logrotate (once)
    if [[ ! -f /etc/logrotate.d/mizu ]]; then
        cat > /etc/logrotate.d/mizu <<'EOF'
/var/log/mizu/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    copytruncate
}
EOF
    fi

    # Init state
    if [[ ! -f "$STATE_FILE" ]]; then
        FIRST_RUN=true
        state_init
    fi

    # Load all modules
    load_runtimes
    load_protocols
}

# ─── CLI Mode ─────────────────────────────────────────────────────────────────
cli_install() {
    local proto="$1"
    shift
    if [[ ! -f "${PROTO_SCRIPTS[$proto]}" ]]; then
        msg_error "未知协议: $proto"
        echo "支持的协议: ${!PROTO_SCRIPTS[@]}"
        exit 1
    fi
    # If domain provided, override prompt_domain
    if [[ $# -gt 0 ]]; then
        local domain="$1"
        # We'll pass it through an env var
        export MIZU_DOMAIN="$domain"
    fi
    "${PROTO_INSTALL_FUNC[$proto]}"
}

cli_info() {
    local proto="$1"
    if ! state_protocol_exists "$proto"; then
        msg_error "${PROTO_NAMES[$proto]} 未安装"
        exit 1
    fi
    show_proto_credentials "$proto"
    local share_link
    share_link=$(state_get ".protocols.${proto}.share_link")
    if [[ -n "$share_link" && "$share_link" != "null" ]]; then
        echo ""
        printf "  分享链接:\n"
        msg_link "  ${share_link}"
    fi
}

cli_start() {
    local proto="$1"
    if ! state_protocol_exists "$proto"; then
        msg_error "${PROTO_NAMES[$proto]} 未安装"
        exit 1
    fi
    # Start caddy if trojan
    if [[ "$proto" == "trojan" ]]; then
        systemctl start mizu-caddy 2>/dev/null
    fi
    service_start "$proto"
    msg_success "${PROTO_NAMES[$proto]} 已启动"
}

cli_stop() {
    local proto="$1"
    if ! state_protocol_exists "$proto"; then
        msg_error "${PROTO_NAMES[$proto]} 未安装"
        exit 1
    fi
    service_stop "$proto"
    msg_success "${PROTO_NAMES[$proto]} 已停止"
}

cli_restart() {
    local proto="$1"
    if ! state_protocol_exists "$proto"; then
        msg_error "${PROTO_NAMES[$proto]} 未安装"
        exit 1
    fi
    service_restart "$proto"
    msg_success "${PROTO_NAMES[$proto]} 已重启"
}

cli_regen() {
    local proto="$1"
    if ! state_protocol_exists "$proto"; then
        msg_error "${PROTO_NAMES[$proto]} 未安装"
        exit 1
    fi
    "${PROTO_REGEN_FUNC[$proto]}"
}

cli_uninstall_proto() {
    local proto="$1"
    if ! state_protocol_exists "$proto"; then
        msg_error "${PROTO_NAMES[$proto]} 未安装"
        exit 1
    fi
    "${PROTO_UNINSTALL_FUNC[$proto]}"
}

cli_update() {
    local target="${1:-all}"

    case "$target" in
        xray)              rt_xray_update ;;
        sing-box)          rt_singbox_update ;;
        hysteria)          rt_hysteria_update ;;
        shadowsocks-rust)  rt_ss_update ;;
        caddy)             rt_caddy_update ;;
        snell)             rt_snell_update ;;
        all)
            [[ "$(state_get '.runtimes.xray')" != "" ]] && rt_xray_update
            [[ "$(state_get '.runtimes.sing-box')" != "" ]] && rt_singbox_update
            [[ "$(state_get '.runtimes.hysteria')" != "" ]] && rt_hysteria_update
            [[ "$(state_get '.runtimes.shadowsocks-rust')" != "" ]] && rt_ss_update
            [[ "$(state_get '.runtimes.caddy')" != "" ]] && rt_caddy_update
            [[ "$(state_get '.runtimes.snell')" != "" ]] && rt_snell_update
            ;;
        *)
            msg_error "未知运行时: $target"
            msg_dim "  支持: xray sing-box hysteria shadowsocks-rust caddy snell all"
            return 1
            ;;
    esac
}

cli_status() {
    local ipv4
    ipv4=$(detect_ipv4)
    printf "${C_CYAN}Mizu v${VERSION} | $(detect_arch) | ${ipv4}${C_RESET}\n\n"

    local protocols
    protocols=$(state_list_protocols)
    if [[ -z "$protocols" ]]; then
        msg_dim "  尚未安装任何协议"
        return
    fi

    while IFS= read -r proto; do
        local name="${PROTO_NAMES[$proto]}"
        local port domain status
        port=$(state_get ".protocols.${proto}.port")
        domain=$(state_get ".protocols.${proto}.domain")
        status=$(systemctl is-active "mizu-${proto}" 2>/dev/null || echo "stopped")

        if [[ "$status" == "active" ]]; then
            printf "  %-20s %5s  ${C_GREEN}●运行${C_RESET}  %s\n" "$name" "$port" "${domain:---}"
        else
            printf "  %-20s %5s  ${C_RED}○停止${C_RESET}  %s\n" "$name" "$port" "${domain:---}"
        fi
    done <<< "$protocols"
}

cli_uninstall_all() {
    printf "${C_RED}${C_BOLD}  ⚠ 卸载 Mizu${C_RESET}\n\n"
    printf "  将删除: 所有协议服务、配置、凭证、伪装网站、核心程序、acme.sh 续期任务、Mizu 脚本\n\n"
    msg_success "证书保留在 /etc/mizu/tls/ (不删除)"
    msg_success "acme.sh 程序保留 (不删除)"
    echo ""
    printf "  输入 ${C_RED}\"uninstall\"${C_RESET} 确认: "
    read -r confirm
    if [[ "$confirm" != "uninstall" ]]; then
        msg_dim "已取消"
        return
    fi

    do_uninstall_all
}

# ─── Full Uninstall ───────────────────────────────────────────────────────────
do_uninstall_all() {
    msg_info "正在卸载 Mizu..."

    # Stop all services
    service_stop_all
    service_remove_all

    # Clean up iptables services and kernel rules
    for f in /etc/systemd/system/mizu-iptables-*.service; do
        [[ -f "$f" ]] || continue
        local svc_name
        svc_name=$(basename "$f")
        systemctl stop "$svc_name" 2>/dev/null || true
        systemctl disable "$svc_name" 2>/dev/null || true
        rm -f "$f"
    done
    if command -v iptables &>/dev/null; then
        iptables -t nat -S 2>/dev/null | grep "REDIRECT" | grep -i "mizu\|/etc/mizu" | while read -r rule; do
            iptables -t nat $(echo "$rule" | sed 's/^-A/-D/') 2>/dev/null || true
        done
    fi
    systemctl daemon-reload 2>/dev/null || true

    # Remove configs, sites, logs, share links
    rm -rf /etc/mizu/trojan /etc/mizu/vless-reality /etc/mizu/vless-vision /etc/mizu/vmess \
           /etc/mizu/shadowtls /etc/mizu/anytls /etc/mizu/hysteria2 /etc/mizu/shadowsocks \
           /etc/mizu/snell /etc/mizu/caddy
    rm -rf /etc/mizu/share-links /etc/mizu/iptables
    rm -rf /var/www/mizu
    rm -rf /var/log/mizu
    rm -f "$STATE_FILE" "${STATE_FILE}.lock"
    rm -f "$CERT_MAP" "${CERT_MAP}.lock"

    # Remove binaries
    rm -f /usr/local/bin/xray /usr/local/bin/sing-box /usr/local/bin/hysteria
    rm -f /usr/local/bin/ssserver /usr/local/bin/ssservice
    rm -f /usr/local/bin/snell-server /usr/local/bin/caddy

    # Remove acme.sh cron (keep program)
    ~/.acme.sh/acme.sh --uninstall-cron 2>/dev/null || true

    # Remove script symlink
    rm -f /usr/local/bin/mizu

    msg_success "Mizu 已完全卸载（证书保留在 /etc/mizu/tls/）"

    # Remove script source last (running script is in memory, safe to delete)
    rm -rf /opt/mizu
}

# ─── TUI — Install Protocol ──────────────────────────────────────────────────
tui_install_protocol() {
    while true; do
        show_install_menu
        read -r choice

        case "$choice" in
            0) return ;;
            [1-9])
                local idx=$((choice - 1))
                local proto="${PROTO_ORDER[$idx]}"
                if [[ -n "$proto" && -f "${PROTO_SCRIPTS[$proto]}" ]]; then
                    "${PROTO_INSTALL_FUNC[$proto]}"
                    press_enter
                fi
                ;;
            *) ;;
        esac
    done
}

# ─── TUI — Manage Protocols ──────────────────────────────────────────────────
tui_manage_protocols() {
    while true; do
        show_manage_list || return

        local protocols
        protocols=$(state_list_protocols)
        [[ -z "$protocols" ]] && return

        read -r choice

        case "$choice" in
            0) return ;;
            a)
                service_start_all
                msg_success "所有协议已启动"
                press_enter
                ;;
            A)
                service_stop_all
                msg_success "所有协议已停止"
                press_enter
                ;;
            [1-9]*)
                # Map choice number to protocol
                local protos=()
                while IFS= read -r p; do
                    protos+=("$p")
                done <<< "$protocols"

                local idx=$((choice - 1))
                if [[ $idx -ge 0 && $idx -lt ${#protos[@]} ]]; then
                    tui_protocol_detail "${protos[$idx]}"
                fi
                ;;
            *) ;;
        esac
    done
}

# ─── TUI — Protocol Detail ───────────────────────────────────────────────────
tui_protocol_detail() {
    local proto="$1"

    while true; do
        show_protocol_detail "$proto"
        read -r -n1 choice
        echo ""

        case "$choice" in
            0) return ;;
            s)
                # Start (also start caddy for trojan)
                [[ "$proto" == "trojan" ]] && systemctl start mizu-caddy 2>/dev/null
                service_start "$proto"
                msg_success "${PROTO_NAMES[$proto]} 已启动"
                press_enter
                ;;
            t)
                service_stop "$proto"
                msg_success "${PROTO_NAMES[$proto]} 已停止"
                press_enter
                ;;
            r)
                service_restart "$proto"
                msg_success "${PROTO_NAMES[$proto]} 已重启"
                press_enter
                ;;
            g)
                if prompt_yesno "重新生成凭证? (旧凭证将失效)" "N"; then
                    "${PROTO_REGEN_FUNC[$proto]}"
                fi
                press_enter
                ;;
            d)
                if prompt_yesno "确定卸载 ${PROTO_NAMES[$proto]}?" "N"; then
                    "${PROTO_UNINSTALL_FUNC[$proto]}"
                    press_enter
                    return
                fi
                ;;
            C)
                local share_link
                share_link=$(state_get ".protocols.${proto}.share_link")
                if [[ -n "$share_link" && "$share_link" != "null" ]]; then
                    copy_to_clipboard "$share_link" && msg_success "已复制到剪贴板"
                else
                    msg_warn "无分享链接"
                fi
                ;;
            *) ;;
        esac
    done
}

# ─── TUI — Uninstall Mizu ────────────────────────────────────────────────────
tui_uninstall() {
    show_uninstall_confirm
    read -r confirm

    if [[ "$confirm" == "uninstall" ]]; then
        do_uninstall_all
        exit 0
    else
        msg_dim "已取消"
    fi
}

# ─── Main Loop ────────────────────────────────────────────────────────────────
tui_main() {
    local ipv4
    ipv4=$(detect_ipv4)
    local arch
    arch=$(detect_arch)

    while true; do
        show_main_menu "$VERSION" "$arch" "$ipv4"
        read -r choice

        case "$choice" in
            1) tui_install_protocol ;;
            2) tui_manage_protocols ;;
            3) tui_check_updates ;;
            4) tui_uninstall ;;
            0|q|Q)
                clear_screen
                msg_dim "再见"
                exit 0
                ;;
            *) ;;
        esac
    done
}

# ─── Self Update ──────────────────────────────────────────────────────────────
mizu_self_update() {
    msg_info "检查 Mizu 脚本更新..."

    local latest
    latest=$(github_latest_tag "$MIZU_REPO" 2>/dev/null)
    if [[ -z "$latest" ]]; then
        msg_error "无法获取最新版本 (仓库: ${MIZU_REPO})"
        msg_dim "  提示: 请确认 MIZU_REPO 变量已设置为正确的 GitHub 仓库"
        return 1
    fi

    if [[ "$VERSION" == "$latest" ]]; then
        msg_success "Mizu v${VERSION} (已是最新)"
        return 0
    fi

    msg_warn "发现新版本: v${VERSION} → v${latest}"

    local tmpdir
    tmpdir=$(mktemp -d)

    # Download latest release archive
    local url="https://github.com/${MIZU_REPO}/archive/refs/tags/v${latest}.tar.gz"
    msg_info "下载 Mizu v${latest}..."

    if ! download_file "$url" "${tmpdir}/mizu.tar.gz"; then
        # Try main branch archive
        url="https://github.com/${MIZU_REPO}/archive/refs/heads/main.tar.gz"
        if ! download_file "$url" "${tmpdir}/mizu.tar.gz"; then
            msg_error "下载失败"
            rm -rf "$tmpdir"
            return 1
        fi
    fi

    # Backup current installation
    local install_dir
    if [[ -d /opt/mizu ]]; then
        install_dir="/opt/mizu"
    else
        install_dir="$SCRIPT_DIR"
    fi

    local backup_dir="${install_dir}.bak.$(date +%s)"
    msg_info "备份当前版本到 ${backup_dir}..."
    cp -a "$install_dir" "$backup_dir"

    # Extract and replace
    tar -xzf "${tmpdir}/mizu.tar.gz" -C "${tmpdir}" >/dev/null
    local extracted_dir
    extracted_dir=$(find "${tmpdir}" -maxdepth 1 -type d -name "mizu-*" -o -name "mizu" | head -1)

    if [[ -z "$extracted_dir" ]]; then
        msg_error "解压失败"
        rm -rf "$tmpdir"
        return 1
    fi

    # Replace script files (state/tls/certs are in /etc/mizu, not in install dir)
    rsync -a "${extracted_dir}/" "${install_dir}/" 2>/dev/null \
        || cp -a "${extracted_dir}/." "${install_dir}/"

    # Ensure executable
    chmod +x "${install_dir}/mizu.sh"

    # Update symlink if exists
    if [[ -L /usr/local/bin/mizu ]]; then
        ln -sf "${install_dir}/mizu.sh" /usr/local/bin/mizu
    fi

    # Update version in state
    state_set_string ".version" "$latest"

    rm -rf "$tmpdir"
    msg_success "Mizu 已更新到 v${latest}"
    msg_dim "  旧版本备份在: ${backup_dir}"

    return 0
}

# ─── TUI — Check Updates (enhanced with self-update) ─────────────────────────
tui_check_updates() {
    # Check Mizu self first
    local mizu_latest=""
    if [[ "$MIZU_REPO" != "USER/mizu" ]]; then
        mizu_latest=$(github_latest_tag "$MIZU_REPO" 2>/dev/null)
    fi

    local updates=()

    # Check Mizu script update
    if [[ -n "$mizu_latest" && "$mizu_latest" != "$VERSION" ]]; then
        updates+=("Mizu|${VERSION}|${mizu_latest}|mizu-self")
    fi

    # Check each runtime
    local runtimes=("xray" "sing-box" "hysteria" "shadowsocks-rust" "caddy" "snell")
    declare -A rt_repos=(
        ["xray"]="XTLS/Xray-core"
        ["sing-box"]="SagerNet/sing-box"
        ["hysteria"]="apernet/hysteria"
        ["shadowsocks-rust"]="shadowsocks/shadowsocks-rust"
        ["caddy"]="caddyserver/caddy"
        ["snell"]=""
    )
    declare -A rt_names=(
        ["xray"]="Xray"
        ["sing-box"]="sing-box"
        ["hysteria"]="Hysteria 2"
        ["shadowsocks-rust"]="shadowsocks-rust"
        ["caddy"]="Caddy"
        ["snell"]="Snell (手动版本)"
    )

    for rt in "${runtimes[@]}"; do
        local current
        current=$(state_get ".runtimes.${rt}")
        [[ -z "$current" || "$current" == "null" ]] && continue

        local repo="${rt_repos[$rt]}"
        [[ -z "$repo" ]] && continue

        local latest
        latest=$(github_latest_tag "$repo" 2>/dev/null)
        [[ -z "$latest" ]] && continue

        if [[ "$current" != "$latest" ]]; then
            updates+=("${rt_names[$rt]}|${current}|${latest}|${rt}")
        fi
    done

    while true; do
        clear_screen
        msg_info "检查更新"
        echo ""

        # Show current versions
        printf "  %-20s" "Mizu 脚本:"
        if [[ -n "$mizu_latest" && "$mizu_latest" != "$VERSION" ]]; then
            printf "${C_YELLOW}v${VERSION} → v${mizu_latest} [可更新]${C_RESET}\n"
        else
            printf "${C_GREEN}v${VERSION} (最新)${C_RESET}\n"
        fi

        for rt in "${runtimes[@]}"; do
            local current
            current=$(state_get ".runtimes.${rt}")
            [[ -z "$current" || "$current" == "null" ]] && continue
            printf "  %-20s" "${rt_names[$rt]}:"
            printf "${C_GREEN}v${current} (当前)${C_RESET}\n"
        done

        echo ""

        if [[ ${#updates[@]} -eq 0 ]]; then
            msg_success "所有程序均为最新版本"
            echo ""
            printf "  ${C_WHITE}[0] 返回${C_RESET}\n"
            read -r choice
            return
        fi

        msg_warn "发现 ${#updates[@]} 个可更新"
        echo ""
        local i=1
        for item in "${updates[@]}"; do
            local name
            IFS='|' read -r name _ _ _ <<< "$item"
            printf "  ${C_WHITE}[%d] 更新 %s${C_RESET}\n" "$i" "$name"
            ((i++))
        done
        printf "  ${C_WHITE}[A] 全部更新  [0] 返回${C_RESET}\n"
        echo ""
        printf "请选择: "

        read -r choice

        case "$choice" in
            0) return ;;
            A)
                for item in "${updates[@]}"; do
                    local rt
                    IFS='|' read -r _ _ _ rt <<< "$item"
                    if [[ "$rt" == "mizu-self" ]]; then
                        mizu_self_update
                    else
                        cli_update "$rt"
                    fi
                done
                updates=()
                press_enter
                return
                ;;
            [1-9]*)
                local idx=$((choice - 1))
                if [[ $idx -ge 0 && $idx -lt ${#updates[@]} ]]; then
                    local rt
                    IFS='|' read -r _ _ _ rt <<< "${updates[$idx]}"
                    if [[ "$rt" == "mizu-self" ]]; then
                        mizu_self_update
                    else
                        cli_update "$rt"
                    fi
                    updates=("${updates[@]:0:$idx}" "${updates[@]:$((idx+1))}")
                fi
                ;;
            *) ;;
        esac
    done
}

# ─── CLI Parser ───────────────────────────────────────────────────────────────
parse_cli() {
    local cmd="${1:-}"
    shift || true

    case "$cmd" in
        install)
            [[ $# -lt 1 ]] && { msg_error "用法: mizu install <protocol> [domain]"; exit 1; }
            cli_install "$@"
            ;;
        info)
            [[ $# -lt 1 ]] && { msg_error "用法: mizu info <protocol>"; exit 1; }
            cli_info "$1"
            ;;
        start)
            [[ $# -lt 1 ]] && { msg_error "用法: mizu start <protocol>"; exit 1; }
            cli_start "$1"
            ;;
        stop)
            [[ $# -lt 1 ]] && { msg_error "用法: mizu stop <protocol>"; exit 1; }
            cli_stop "$1"
            ;;
        restart)
            [[ $# -lt 1 ]] && { msg_error "用法: mizu restart <protocol>"; exit 1; }
            cli_restart "$1"
            ;;
        regen)
            [[ $# -lt 1 ]] && { msg_error "用法: mizu regen <protocol>"; exit 1; }
            cli_regen "$1"
            ;;
        uninstall)
            [[ $# -lt 1 ]] && { msg_error "用法: mizu uninstall <protocol>"; exit 1; }
            cli_uninstall_proto "$1"
            ;;
        update)
            cli_update "${1:-all}"
            ;;
        self-update)
            mizu_self_update
            ;;
        uninstall-all)
            cli_uninstall_all
            ;;
        status)
            cli_status
            ;;
        help|--help|-h)
            echo "Mizu v${VERSION} — 全协议原生代理部署管理系统"
            echo ""
            echo "用法: mizu [命令] [参数]"
            echo ""
            echo "命令:"
            echo "  install <protocol> [domain]   安装协议"
            echo "  info <protocol>                查看凭证"
            echo "  start <protocol>               启动服务"
            echo "  stop <protocol>                停止服务"
            echo "  restart <protocol>             重启服务"
            echo "  regen <protocol>               重新生成凭证"
            echo "  uninstall <protocol>           卸载协议"
            echo "  update [runtime]               检查/执行更新"
            echo "  self-update                    更新 Mizu 脚本自身"
            echo "  uninstall-all                  完全卸载 Mizu"
            echo "  status                         状态总览"
            echo ""
            echo "支持的协议: trojan vless-reality vless-vision vmess"
            echo "            shadowtls anytls hysteria2 shadowsocks snell"
            echo ""
            echo "无参数运行进入 TUI 交互模式。"
            ;;
        *)
            # Unknown command
            msg_error "未知命令: $cmd"
            msg_dim "  输入 'mizu help' 查看可用命令"
            return 1
            ;;
    esac
    return 0
}

# ─── Entry Point ──────────────────────────────────────────────────────────────
main() {
    # Try CLI mode first
    if [[ $# -gt 0 ]]; then
        mizu_init
        parse_cli "$@"
        exit $?
    fi

    # TUI mode
    mizu_init

    # First run → environment detection
    if [[ "$FIRST_RUN" == "true" ]]; then
        detect_environment || exit 1
    fi

    tui_main
}

main "$@"
