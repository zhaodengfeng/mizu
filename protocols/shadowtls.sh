#!/usr/bin/env bash
# Mizu — ShadowTLS protocol (sing-box)

shadowtls_install() {
    local proto="shadowtls"
    local proto_dir="/etc/mizu/${proto}"

    if state_protocol_exists "$proto" || [[ -f "/etc/systemd/system/mizu-${proto}.service" ]]; then
        msg_error "ShadowTLS 已安装，请先卸载"
        return 1
    fi

    msg_info ">>> 安装 ShadowTLS <<<"
    echo ""

    # Get handshake domain (a real TLS server for handshake)
    local domain
    domain=$(prompt_domain)

    # Resolve port
    local port
    port=$(resolve_port 443 8443)

    # Step 1: Install sing-box
    msg_step 1 2 "安装 sing-box..."
    rt_singbox_install || return 1

    # Step 2: Generate credentials & start
    msg_step 2 2 "生成凭证并启动..."

    local st_password
    st_password=$(gen_password)
    local ss_password
    ss_password=$(gen_base64 32)

    # Handshake server: use the domain itself (must resolve to a real TLS server)
    local handshake_server="$domain"
    local handshake_port=443

    # ShadowTLS v3 + SS2022 inner
    mkdir -p "$proto_dir"

    jq -n \
        --argjson port "$port" \
        --arg st_password "$st_password" \
        --arg ss_password "$ss_password" \
        --arg handshake_server "$handshake_server" \
        --argjson handshake_port "$handshake_port" \
        '{
            "inbounds": [{
                "type": "shadowtls",
                "tag": "shadowtls-in",
                "listen": "::",
                "listen_port": $port,
                "version": 3,
                "users": [{"name": "mizu", "password": $st_password}],
                "handshake": {
                    "server": $handshake_server,
                    "server_port": $handshake_port
                },
                "detour": "ss-in"
            }, {
                "type": "shadowsocks",
                "tag": "ss-in",
                "listen": "127.0.0.1",
                "listen_port": 10808,
                "method": "2022-blake3-aes-256-gcm",
                "password": $ss_password
            }],
            "outbounds": [{"type": "direct", "tag": "direct"}]
        }' > "${proto_dir}/config.json" || { msg_error "配置文件生成失败"; return 1; }

    service_create "$proto" "/usr/local/bin/sing-box" "run -c ${proto_dir}/config.json" || return 1
    service_start_verified "$proto" || return 1
    service_enable "$proto" || true
    msg_success "ShadowTLS 已启动 (端口 ${port})"

    # Save state
    local ipv4
    ipv4=$(detect_ipv4)

    state_set_protocol "$proto" "$(jq -n \
        --arg port "$port" --arg domain "$domain" --arg st_password "$st_password" \
        --arg ss_password "$ss_password" '{
            "port": $port, "domain": $domain, "transport": "TCP+TLS (ShadowTLS v3)",
            "status": "running",
            "credential": {"shadowtls_password": $st_password, "ss_password": $ss_password}
        }')" || return 1

    # Show result (ShadowTLS outputs Clash config fragment, no standard share link)
    echo ""
    msg_info "ShadowTLS — 安装成功"
    echo ""
    printf "  端口:     %s\n" "$port"
    printf "  域名:     %s\n" "$domain"
    printf "  ST 密码:  %s\n" "$st_password"
    printf "  SS 密码:  %s\n" "$ss_password"
    printf "  传输:     TCP + TLS (ShadowTLS v3)\n"
    echo ""

    # Output Clash config fragment and persist it
    echo "  Clash 配置片段:"
    echo ""
    local clash_config
    clash_config=$(gen_shadowtls_link "$ipv4")
    echo "$clash_config"

    # Persist to share-links file
    mkdir -p /etc/mizu/share-links
    echo "$clash_config" > "/etc/mizu/share-links/${proto}.txt"
    state_set_string ".protocols.${proto}.share_link" "$clash_config"
}

shadowtls_regen() {
    local proto="shadowtls"
    local proto_dir="/etc/mizu/${proto}"

    local st_password ss_password
    st_password=$(gen_password)
    ss_password=$(gen_base64 32)

    jq --arg st "$st_password" --arg ss "$ss_password" \
        '.inbounds[0].users[0].password = $st | .inbounds[1].password = $ss' \
        "${proto_dir}/config.json" > "${proto_dir}/config.json.tmp" \
        && mv "${proto_dir}/config.json.tmp" "${proto_dir}/config.json"

    state_set_string ".protocols.${proto}.credential.shadowtls_password" "$st_password"
    state_set_string ".protocols.${proto}.credential.ss_password" "$ss_password"
    service_restart_verified "$proto" || return 1

    # Update persisted Clash config
    local ipv4
    ipv4=$(detect_ipv4)
    local clash_config
    clash_config=$(gen_shadowtls_link "$ipv4")
    mkdir -p /etc/mizu/share-links
    echo "$clash_config" > "/etc/mizu/share-links/${proto}.txt"
    state_set_string ".protocols.${proto}.share_link" "$clash_config"

    msg_success "凭证已重新生成"
}

shadowtls_uninstall() {
    local proto="shadowtls"
    local proto_dir="/etc/mizu/${proto}"

    msg_warn "正在卸载 ShadowTLS..."
    service_remove "$proto"
    rm -rf "$proto_dir"

    state_del ".protocols.${proto}"
    msg_success "ShadowTLS 已卸载"
}
