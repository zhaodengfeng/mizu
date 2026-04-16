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

snell_uninstall() {
    local proto="snell"
    local proto_dir="/etc/mizu/${proto}"

    msg_warn "正在卸载 Snell v5..."
    service_remove "$proto"
    rm -rf "$proto_dir"
    state_del ".protocols.${proto}"
    msg_success "Snell v5 已卸载"
}
