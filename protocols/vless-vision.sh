#!/usr/bin/env bash
# Mizu — VLESS + Vision protocol (Xray, TCP+TLS)

vless_vision_install() {
    local proto="vless-vision"
    local proto_dir="/etc/mizu/${proto}"

    if state_protocol_exists "$proto" || [[ -f "/etc/systemd/system/mizu-${proto}.service" ]]; then
        msg_error "VLESS+Vision 已安装，请先卸载"
        return 1
    fi

    msg_info ">>> 安装 VLESS + Vision <<<"
    echo ""

    # Get domain
    local domain
    domain=$(prompt_domain)

    # Resolve port
    local port
    port=$(resolve_port 443 8443)

    # Step 1: Install Xray
    msg_step 1 4 "安装 Xray..."
    rt_xray_install || return 1

    # Step 2: Certificate
    msg_step 2 4 "检查证书..."
    cert_issue "$domain" || return 1

    # Step 3: Generate credentials
    msg_step 3 4 "生成凭证..."
    local uuid
    uuid=$(gen_uuid)

    msg_success "UUID: ${uuid}"

    # Step 4: Generate config & start
    msg_step 4 4 "启动 VLESS+Vision..."

    mkdir -p "$proto_dir"

    jq -n \
        --argjson port "$port" \
        --arg uuid "$uuid" \
        --arg domain "$domain" \
        --arg cert "$(cert_fullchain "$domain")" \
        --arg key "$(cert_key "$domain")" \
        '{
            "log": {"loglevel": "warning", "access": "/var/log/mizu/xray-vless-vision-access.log", "error": "/var/log/mizu/xray-vless-vision-error.log"},
            "inbounds": [{
                "port": $port,
                "listen": "0.0.0.0",
                "protocol": "vless",
                "settings": {
                    "clients": [{"id": $uuid, "flow": "xtls-rprx-vision"}],
                    "decryption": "none"
                },
                "streamSettings": {
                    "network": "tcp",
                    "security": "tls",
                    "tlsSettings": {
                        "serverName": $domain,
                        "alpn": ["h2", "http/1.1"],
                        "certificates": [{
                            "certificateFile": $cert,
                            "keyFile": $key
                        }]
                    }
                }
            }],
            "outbounds": [{"protocol": "freedom", "settings": {}}]
        }' > "${proto_dir}/config.json"

    service_create "$proto" "/usr/local/bin/xray" "run -config ${proto_dir}/config.json" || return 1
    service_start_verified "$proto" || return 1
    service_enable "$proto" || true
    msg_success "VLESS+Vision 已启动 (端口 ${port})"

    # Save state
    local ipv4
    ipv4=$(detect_ipv4)

    state_set_protocol "$proto" "$(jq -n \
        --arg port "$port" --arg domain "$domain" --arg uuid "$uuid" \
        --arg transport "TCP+TLS (Vision)" '{
            "port": $port, "domain": $domain, "transport": $transport,
            "status": "running",
            "credential": {"uuid": $uuid}
        }')" || return 1
    local share_link
    share_link=$(refresh_share_link "$proto" "$ipv4") || return 1

    # Show result
    echo ""
    msg_info "VLESS + Vision — 安装成功"
    echo ""
    printf "  端口:     %s\n" "$port"
    printf "  域名:     %s\n" "$domain"
    printf "  UUID:     %s\n" "$uuid"
    printf "  传输:     TCP + TLS (Vision)\n"
    printf "  Flow:     xtls-rprx-vision\n"
    echo ""

    show_install_result "$proto" "$share_link"
}

vless_vision_regen() {
    local proto="vless-vision"
    local proto_dir="/etc/mizu/${proto}"

    local uuid
    uuid=$(gen_uuid)

    jq --arg uuid "$uuid" '.inbounds[0].settings.clients[0].id = $uuid' \
        "${proto_dir}/config.json" > "${proto_dir}/config.json.tmp" \
        && mv "${proto_dir}/config.json.tmp" "${proto_dir}/config.json"

    state_set_string ".protocols.${proto}.credential.uuid" "$uuid"
    service_restart_verified "$proto" || return 1

    local ipv4
    ipv4=$(detect_ipv4)
    save_share_link "$proto" "$ipv4" || return 1
    msg_success "凭证已重新生成"
}

vless_vision_uninstall() {
    local proto="vless-vision"
    local proto_dir="/etc/mizu/${proto}"

    msg_warn "正在卸载 VLESS+Vision..."
    service_remove "$proto"
    rm -rf "$proto_dir"

    local domain
    domain=$(state_get ".protocols.${proto}.domain")
    cert_ref_del "$domain"

    state_del ".protocols.${proto}"
    msg_success "VLESS+Vision 已卸载"
}
