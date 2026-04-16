#!/usr/bin/env bash
# Mizu — AnyTLS protocol (sing-box)

anytls_install() {
    local proto="anytls"
    local proto_dir="/etc/mizu/${proto}"

    if state_protocol_exists "$proto" || [[ -f "/etc/systemd/system/mizu-${proto}.service" ]]; then
        msg_error "AnyTLS 已安装，请先卸载"
        return 1
    fi

    msg_info ">>> 安装 AnyTLS <<<"
    echo ""

    # Get domain
    local domain
    domain=$(prompt_domain)

    # Step 1: Install sing-box
    msg_step 1 3 "安装 sing-box..."
    rt_singbox_install || return 1

    # Step 2: Certificate
    msg_step 2 3 "检查证书..."
    cert_issue "$domain" || return 1

    # Step 3: Generate credentials & start
    msg_step 3 3 "生成凭证并启动..."

    local password
    password=$(gen_password)

    local port
    port=$(resolve_port 443 8443)

    mkdir -p "$proto_dir"

    local cert_path key_path
    cert_path=$(cert_fullchain "$domain")
    key_path=$(cert_key "$domain")

    jq -n \
        --arg password "$password" \
        --arg domain "$domain" \
        --arg cert "$cert_path" \
        --arg key "$key_path" \
        --argjson port "$port" \
        '{
            "inbounds": [{
                "type": "anytls",
                "tag": "anytls-in",
                "listen": "::",
                "listen_port": $port,
                "users": [{"name": "mizu", "password": $password}],
                "tls": {
                    "enabled": true,
                    "server_name": $domain,
                    "certificate_path": $cert,
                    "key_path": $key
                }
            }],
            "outbounds": [{"type": "direct", "tag": "direct"}]
        }' > "${proto_dir}/config.json" || { msg_error "配置文件生成失败"; return 1; }

    service_create "$proto" "/usr/local/bin/sing-box" "run -c ${proto_dir}/config.json" || return 1
    service_start_verified "$proto" || return 1
    service_enable "$proto" || true

    # Save state
    local ipv4
    ipv4=$(detect_ipv4)
    local share_link="anytls://${password}@${ipv4}:${port}?sni=${domain}&type=tcp#Mizu-AnyTLS"

    state_set_protocol "$proto" "$(jq -n --arg port "$port" --arg domain "$domain" --arg password "$password" \
        --arg link "$share_link" '{
            "port": $port, "domain": $domain, "transport": "TCP+TLS (AnyTLS)",
            "status": "running", "share_link": $link,
            "credential": {"password": $password}
        }')"

    show_install_result "$proto" "$share_link"
}

anytls_regen() {
    local proto="anytls"
    local proto_dir="/etc/mizu/${proto}"

    local password
    password=$(gen_password)

    jq --arg p "$password" '.inbounds[0].users[0].password = $p' \
        "${proto_dir}/config.json" > "${proto_dir}/config.json.tmp" \
        && mv "${proto_dir}/config.json.tmp" "${proto_dir}/config.json"

    state_set_string ".protocols.${proto}.credential.password" "$password"
    service_restart "$proto"

    local ipv4
    ipv4=$(detect_ipv4)
    save_share_link "$proto" "$ipv4"
    msg_success "凭证已重新生成"
}

anytls_uninstall() {
    local proto="anytls"
    local proto_dir="/etc/mizu/${proto}"

    msg_warn "正在卸载 AnyTLS..."
    service_remove "$proto"
    rm -rf "$proto_dir"

    local domain
    domain=$(state_get ".protocols.${proto}.domain")
    cert_ref_del "$domain"

    state_del ".protocols.${proto}"
    msg_success "AnyTLS 已卸载"
}
