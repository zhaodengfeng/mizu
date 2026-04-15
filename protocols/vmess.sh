#!/usr/bin/env bash
# Mizu — VMess + WebSocket protocol (Xray)

vmess_install() {
    local proto="vmess"
    local proto_dir="/etc/mizu/${proto}"

    if state_protocol_exists "$proto"; then
        msg_error "VMess 已安装，请先卸载"
        return 1
    fi

    msg_info ">>> 安装 VMess + WebSocket <<<"
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
    local ws_path
    ws_path="/$(openssl rand -hex 12)"
    msg_success "UUID: ${uuid}"
    msg_success "路径: ${ws_path}"

    # Step 4: Generate config & start
    msg_step 4 4 "启动 VMess..."

    mkdir -p "$proto_dir"

    jq -n \
        --argjson port "$port" \
        --arg uuid "$uuid" \
        --arg ws_path "$ws_path" \
        --arg domain "$domain" \
        --arg cert "$(cert_fullchain "$domain")" \
        --arg key "$(cert_key "$domain")" \
        '{
            "log": {"loglevel": "warning", "access": "/var/log/mizu/xray-vmess-access.log", "error": "/var/log/mizu/xray-vmess-error.log"},
            "inbounds": [{
                "port": $port,
                "listen": "0.0.0.0",
                "protocol": "vmess",
                "settings": {"clients": [{"id": $uuid, "alterId": 0}]},
                "streamSettings": {
                    "network": "ws",
                    "security": "tls",
                    "wsSettings": {"path": $ws_path},
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
    service_enable "$proto"
    msg_success "VMess 已启动 (端口 ${port})"

    # Save state
    local ipv4
    ipv4=$(detect_ipv4)

    # VMess share link (v2 base64)
    local vmess_json
    vmess_json=$(jq -n \
        --arg v "2" \
        --arg ps "Mizu-VMess" \
        --arg add "$ipv4" \
        --arg port "$port" \
        --arg id "$uuid" \
        --arg host "$domain" \
        --arg path "$ws_path" \
        '{v:$v, ps:$ps, add:$add, port:$port, id:$id, aid:"0", scy:"auto", net:"ws", type:"none", host:$host, path:$path, tls:"tls", sni:$host}')
    local share_link="vmess://$(echo -n "$vmess_json" | base64 -w 0)"

    state_set_protocol "$proto" "$(jq -n \
        --arg port "$port" --arg domain "$domain" --arg uuid "$uuid" \
        --arg path "$ws_path" --arg link "$share_link" '{
            "port": $port, "domain": $domain, "transport": "TCP+TLS+WS",
            "status": "running", "share_link": $link,
            "credential": {"uuid": $uuid, "path": $path}
        }')"

    # Show result
    echo ""
    msg_info "VMess + WebSocket — 安装成功"
    echo ""
    printf "  端口:     %s\n" "$port"
    printf "  域名:     %s\n" "$domain"
    printf "  UUID:     %s\n" "$uuid"
    printf "  传输:     TCP + TLS + WebSocket\n"
    printf "  路径:     %s\n" "$ws_path"
    printf "  提示:     客户端追加 ?ed=2560 降低延迟\n"
    echo ""

    show_install_result "$proto" "$share_link"
}

vmess_regen() {
    local proto="vmess"
    local proto_dir="/etc/mizu/${proto}"

    local uuid
    uuid=$(gen_uuid)

    jq --arg uuid "$uuid" '.inbounds[0].settings.clients[0].id = $uuid' \
        "${proto_dir}/config.json" > "${proto_dir}/config.json.tmp" \
        && mv "${proto_dir}/config.json.tmp" "${proto_dir}/config.json"

    state_set_string ".protocols.${proto}.credential.uuid" "$uuid"
    service_restart "$proto"

    local ipv4
    ipv4=$(detect_ipv4)
    save_share_link "$proto" "$ipv4"
    msg_success "凭证已重新生成"
}

vmess_uninstall() {
    local proto="vmess"
    local proto_dir="/etc/mizu/${proto}"

    msg_warn "正在卸载 VMess..."
    service_remove "$proto"
    rm -rf "$proto_dir"

    local domain
    domain=$(state_get ".protocols.${proto}.domain")
    cert_ref_del "$domain"

    state_del ".protocols.${proto}"
    msg_success "VMess 已卸载"
}
