#!/usr/bin/env bash
# Mizu — TUI Menu rendering

[[ -n "${_MIZU_MENU_SH_LOADED:-}" ]] && return 0
_MIZU_MENU_SH_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ─── Protocol Display Info ───────────────────────────────────────────────────
PROTO_ORDER=(trojan vless-reality vless-vision vmess shadowtls anytls hysteria2 shadowsocks snell)

PROTO_NAMES=(
    ["trojan"]="Trojan"
    ["vless-reality"]="VLESS + Reality"
    ["vless-vision"]="VLESS + Vision"
    ["vmess"]="VMess + WebSocket"
    ["shadowtls"]="ShadowTLS"
    ["anytls"]="AnyTLS"
    ["hysteria2"]="Hysteria 2"
    ["shadowsocks"]="Shadowsocks 2022"
    ["snell"]="Snell v4"
)

PROTO_DESCS=(
    ["trojan"]="TCP+TLS 伪装网站"
    ["vless-reality"]="无需域名"
    ["vless-vision"]="TCP+TLS"
    ["vmess"]="TCP+TLS+WS"
    ["shadowtls"]="sing-box TLS 包装"
    ["anytls"]="sing-box TLS 代理"
    ["hysteria2"]="QUIC/UDP 高速"
    ["shadowsocks"]="SS 最新标准"
    ["snell"]="Surge 专属"
)

# ─── Main Menu ───────────────────────────────────────────────────────────────
show_main_menu() {
    local version="$1"
    local arch="$2"
    local ipv4="$3"

    clear_screen
    msg_info "Mizu v${version} | ${arch} | ${ipv4}"
    echo ""
    printf "${C_WHITE}  [1] 安装协议${C_RESET}\n"
    printf "${C_WHITE}  [2] 管理已安装协议${C_RESET}\n"
    printf "${C_WHITE}  [3] 检查更新${C_RESET}\n"
    printf "${C_WHITE}  [4] 卸载 Mizu${C_RESET}\n"
    printf "${C_WHITE}  [0] 退出${C_RESET}\n"
    echo ""
    printf "请选择: "
}

# ─── Protocol Install Menu ───────────────────────────────────────────────────
show_install_menu() {
    clear_screen
    msg_info "选择要安装的协议"
    echo ""

    local i=1
    for proto in "${PROTO_ORDER[@]}"; do
        local name="${PROTO_NAMES[$proto]}"
        local desc="${PROTO_DESCS[$proto]}"

        # Show status if installed
        if state_protocol_exists "$proto"; then
            local port domain status
            port=$(state_get ".protocols.${proto}.port")
            domain=$(state_get ".protocols.${proto}.domain")
            status=$(systemctl is-active "mizu-${proto}" 2>/dev/null || echo "stopped")

            if [[ "$status" == "active" ]]; then
                printf "${C_WHITE}  [%d] %-22s${C_GRAY} %-24s${C_GREEN} ✓ %s:%s ●运行${C_RESET}\n" "$i" "$name" "$desc" "${domain:-—}" "$port"
            else
                printf "${C_WHITE}  [%d] %-22s${C_GRAY} %-24s${C_RED} ✗ %s:%s ○停止${C_RESET}\n" "$i" "$name" "$desc" "${domain:-—}" "$port"
            fi
        else
            printf "${C_WHITE}  [%d] %-22s${C_GRAY} %s${C_RESET}\n" "$i" "$name" "$desc"
        fi
        ((i++))
    done

    echo ""
    printf "${C_WHITE}  [0] 返回${C_RESET}\n"
    echo ""
    printf "请选择: "
}

# ─── Protocol Management List ────────────────────────────────────────────────
show_manage_list() {
    clear_screen
    msg_info "已安装协议"
    echo ""

    local protocols
    protocols=$(state_list_protocols)
    if [[ -z "$protocols" ]]; then
        msg_dim "  尚未安装任何协议"
        echo ""
        press_enter "按回车键返回..."
        return 1
    fi

    local i=1
    while IFS= read -r proto; do
        local name="${PROTO_NAMES[$proto]}"
        local port domain status
        port=$(state_get ".protocols.${proto}.port")
        domain=$(state_get ".protocols.${proto}.domain")
        status=$(systemctl is-active "mizu-${proto}" 2>/dev/null || echo "stopped")

        if [[ "$status" == "active" ]]; then
            printf "  %d  %-18s %5s  ${C_GREEN}●运行${C_RESET}  %s\n" "$i" "$name" "$port" "${domain:---}"
        else
            printf "  %d  %-18s %5s  ${C_RED}○停止${C_RESET}  %s\n" "$i" "$name" "$port" "${domain:---}"
        fi
        ((i++))
    done <<< "$protocols"

    echo ""
    printf "  ${C_WHITE}[a] 全部启动  [A] 全部停止  [0] 返回${C_RESET}\n"
    echo ""
    printf "请选择: "
    return 0
}

# ─── Protocol Detail Page ────────────────────────────────────────────────────
show_protocol_detail() {
    local proto="$1"
    local name="${PROTO_NAMES[$proto]}"

    local port domain status
    port=$(state_get ".protocols.${proto}.port")
    domain=$(state_get ".protocols.${proto}.domain")
    status=$(systemctl is-active "mizu-${proto}" 2>/dev/null || echo "stopped")

    local status_text
    if [[ "$status" == "active" ]]; then
        status_text="${C_GREEN}●运行${C_RESET}"
    else
        status_text="${C_RED}○停止${C_RESET}"
    fi

    clear_screen
    printf "${C_CYAN}%s${C_RESET}  %s\n\n" "$name" "$status_text"

    # Protocol-specific info display
    show_proto_credentials "$proto"

    # Share link
    local share_link
    share_link=$(state_get ".protocols.${proto}.share_link")
    if [[ -n "$share_link" && "$share_link" != "null" ]]; then
        echo ""
        printf "  分享链接:\n"
        msg_link "  ${share_link}"
    fi

    echo ""
    msg_separator
    printf "${C_WHITE}  [s] 启动  [t] 停止  [r] 重启${C_RESET}\n"
    printf "${C_WHITE}  [g] 重新生成凭证${C_RESET}\n"
    printf "${C_WHITE}  [d] 卸载此协议${C_RESET}\n"
    printf "${C_WHITE}  [C] 复制分享链接${C_RESET}\n"
    printf "${C_WHITE}  [0] 返回列表${C_RESET}\n"
    echo ""
    printf "请选择: "
}

# ─── Show Protocol Credentials ───────────────────────────────────────────────
show_proto_credentials() {
    local proto="$1"
    local port domain transport
    port=$(state_get ".protocols.${proto}.port")
    domain=$(state_get ".protocols.${proto}.domain")
    transport=$(state_get ".protocols.${proto}.transport")

    printf "  端口:     %s\n" "$port"
    [[ -n "$domain" && "$domain" != "null" ]] && printf "  域名:     %s\n" "$domain"

    case "$proto" in
        trojan)
            local password
            password=$(state_get ".protocols.${proto}.credential.password")
            printf "  密码:     %s\n" "$password"
            printf "  传输:     TCP + TLS\n"
            printf "  ALPN:     h2, http/1.1\n"
            printf "  伪装:     Caddy 多页网站 (:8080)\n"
            ;;
        vless-reality)
            local uuid dest serverName shortId
            uuid=$(state_get ".protocols.${proto}.credential.uuid")
            dest=$(state_get ".protocols.${proto}.credential.dest")
            serverName=$(state_get ".protocols.${proto}.credential.serverName")
            shortId=$(state_get ".protocols.${proto}.credential.shortId")
            printf "  UUID:     %s\n" "$uuid"
            printf "  传输:     TCP + Reality\n"
            printf "  伪装目标: %s\n" "$dest"
            printf "  SNI:      %s\n" "$serverName"
            printf "  ShortID:  %s\n" "$shortId"
            ;;
        vless-vision)
            local uuid
            uuid=$(state_get ".protocols.${proto}.credential.uuid")
            printf "  UUID:     %s\n" "$uuid"
            printf "  传输:     TCP + TLS (Vision)\n"
            ;;
        vmess)
            local uuid path
            uuid=$(state_get ".protocols.${proto}.credential.uuid")
            path=$(state_get ".protocols.${proto}.credential.path")
            printf "  UUID:     %s\n" "$uuid"
            printf "  传输:     TCP + TLS + WebSocket\n"
            printf "  路径:     %s\n" "$path"
            ;;
        shadowtls)
            local stPassword ssPassword
            stPassword=$(state_get ".protocols.${proto}.credential.shadowtls_password")
            ssPassword=$(state_get ".protocols.${proto}.credential.ss_password")
            printf "  ST 密码:  %s\n" "$stPassword"
            printf "  SS 密码:  %s\n" "$ssPassword"
            printf "  传输:     TCP + TLS (ShadowTLS)\n"
            ;;
        anytls)
            local password
            password=$(state_get ".protocols.${proto}.credential.password")
            printf "  密码:     %s\n" "$password"
            printf "  传输:     TCP + TLS (AnyTLS)\n"
            ;;
        hysteria2)
            local password obfsType
            password=$(state_get ".protocols.${proto}.credential.password")
            obfsType=$(state_get ".protocols.${proto}.credential.obfs_type")
            printf "  密码:     %s\n" "$password"
            printf "  传输:     QUIC/UDP\n"
            [[ -n "$obfsType" && "$obfsType" != "null" ]] && printf "  混淆:     %s\n" "$obfsType"
            ;;
        shadowsocks)
            local method key
            method=$(state_get ".protocols.${proto}.credential.method")
            key=$(state_get ".protocols.${proto}.credential.key")
            printf "  方法:     %s\n" "$method"
            printf "  密钥:     %s\n" "$key"
            printf "  传输:     TCP\n"
            ;;
        snell)
            local psk
            psk=$(state_get ".protocols.${proto}.credential.psk")
            printf "  PSK:      %s\n" "$psk"
            printf "  传输:     TCP\n"
            ;;
    esac
}

# ─── Uninstall Confirm ───────────────────────────────────────────────────────
show_uninstall_confirm() {
    clear_screen
    printf "${C_RED}${C_BOLD}  ⚠ 卸载 Mizu${C_RESET}\n\n"
    printf "  将删除: 所有协议服务、配置、凭证、伪装网站、核心程序、acme.sh 续期任务、Mizu 脚本\n\n"
    msg_success "证书保留在 /etc/mizu/tls/ (不删除)"
    msg_success "acme.sh 程序保留 (不删除)"
    echo ""
    printf "  输入 ${C_RED}\"uninstall\"${C_RESET} 确认: "
}

# ─── Copy to Clipboard ───────────────────────────────────────────────────────
copy_to_clipboard() {
    local text="$1"
    if command -v xclip &>/dev/null; then
        echo -n "$text" | xclip -selection clipboard
    elif command -v xsel &>/dev/null; then
        echo -n "$text" | xsel --clipboard --input
    elif command -v pbcopy &>/dev/null; then
        echo -n "$text" | pbcopy
    else
        msg_warn "未找到剪贴板工具，请手动复制上方链接"
        return 1
    fi
}
