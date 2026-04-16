#!/usr/bin/env bash
# Mizu — Snell v5 protocol (Surge)

snell_install() {
    local proto="snell"
    local proto_dir="/etc/mizu/${proto}"

    if state_protocol_exists "$proto" || [[ -f "/etc/systemd/system/mizu-${proto}.service" ]]; then
        msg_error "Snell v5 已安装，请先卸载"
        return 1
    fi

    msg_info ">>> 安装 Snell v5 <<<"
    echo ""

    # Step 1: Install Snell
    msg_step 1 3 "安装 Snell..."
    rt_snell_install || return 1

    # Step 2: Generate credentials
    msg_step 2 3 "生成凭证..."

    local psk
    psk=$(gen_password)
    msg_success "PSK: ${psk}"

    local port
    port=$(resolve_port 36213 36214)

    # Step 3: Generate config & start
    msg_step 3 3 "启动 Snell v5..."

    mkdir -p "$proto_dir"

    cat > "${proto_dir}/snell-server.conf" <<EOF
[snell-server]
listen = 0.0.0.0:${port}
psk = ${psk}
version = 5
ipv6 = false
EOF

    service_create "$proto" "/usr/local/bin/snell-server" "-c ${proto_dir}/snell-server.conf" || return 1
    service_start_verified "$proto" || return 1
    service_enable "$proto" || true

    # Save state
    state_set_protocol "$proto" "$(jq -n --arg port "$port" --arg psk "$psk" --arg version "5" '{
        "port": $port, "transport": "TCP+UDP",
        "status": "running",
        "credential": {"psk": $psk, "version": $version}
    }')"

    # Show result (Snell has no share link)
    echo ""
    msg_info "Snell v5 — 安装成功"
    echo ""
    printf "  端口:     %s\n" "$port"
    printf "  PSK:      %s\n" "$psk"
    printf "  版本:     5\n"
    printf "  传输:     TCP+UDP (QUIC Proxy)\n"
    echo ""
    msg_dim "  Snell 无标准分享链接格式，请手动配置 Surge 客户端"
    echo ""

    press_enter "按回车键返回..."
}

snell_regen() {
    local proto="snell"
    local proto_dir="/etc/mizu/${proto}"

    local psk
    psk=$(gen_password)

    sed -i "s|psk = .*|psk = ${psk}|" "${proto_dir}/snell-server.conf"

    state_set_string ".protocols.${proto}.credential.psk" "$psk"
    service_restart "$proto"
    msg_success "凭证已重新生成"
}

snell_settings() {
    local proto="snell"
    local proto_dir="/etc/mizu/${proto}"

    while true; do
        local current_dns current_ipv6
        current_dns=$(state_get ".protocols.${proto}.credential.dns")
        current_ipv6=$(state_get ".protocols.${proto}.credential.ipv6")
        [[ -z "$current_dns" || "$current_dns" == "null" ]] && current_dns="8.8.8.8"
        [[ -z "$current_ipv6" || "$current_ipv6" == "null" ]] && current_ipv6="false"

        clear_screen
        msg_info "Snell v5 — 配置"
        echo ""
        printf "  [1] DNS 服务器: %s\n" "$current_dns"
        printf "  [2] IPv6: %s\n" "$current_ipv6"
        printf "  [0] 返回\n"
        echo ""
        printf "请选择: "
        read -r choice

        case "$choice" in
            0) return ;;
            1)
                echo ""
                printf "  可选 DNS:\n"
                printf "    [1] 8.8.8.8\n"
                printf "    [2] 1.1.1.1\n"
                printf "    [3] 自定义\n"
                printf "  请选择: "
                read -r dns_choice
                local new_dns=""
                case "$dns_choice" in
                    1) new_dns="8.8.8.8" ;;
                    2) new_dns="1.1.1.1" ;;
                    3)
                        printf "  输入 DNS 地址: "
                        read -r new_dns
                        ;;
                    *) continue ;;
                esac
                if [[ -z "$new_dns" ]]; then
                    msg_error "DNS 不能为空"
                    press_enter
                    continue
                fi
                # Update config: add or replace dns line
                if grep -q "^dns " "${proto_dir}/snell-server.conf" 2>/dev/null; then
                    sed -i "s|^dns = .*|dns = ${new_dns}|" "${proto_dir}/snell-server.conf"
                else
                    echo "dns = ${new_dns}" >> "${proto_dir}/snell-server.conf"
                fi
                state_set_string ".protocols.${proto}.credential.dns" "$new_dns"
                service_restart "$proto"
                msg_success "DNS 已设置为 ${new_dns}"
                press_enter
                ;;
            2)
                if [[ "$current_ipv6" == "false" ]]; then
                    new_ipv6="true"
                else
                    new_ipv6="false"
                fi
                sed -i "s/ipv6 = .*/ipv6 = ${new_ipv6}/" "${proto_dir}/snell-server.conf"
                state_set_string ".protocols.${proto}.credential.ipv6" "$new_ipv6"
                service_restart "$proto"
                msg_success "IPv6 已设置为 ${new_ipv6}"
                press_enter
                ;;
        esac
    done
}

snell_uninstall() {
    local proto="snell"
    local proto_dir="/etc/mizu/${proto}"

    msg_warn "正在卸载 Snell v5..."
    service_remove "$proto"
    rm -rf "$proto_dir"
    state_del ".protocols.${proto}"
    msg_success "Snell v5 已卸载"
}
