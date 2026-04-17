#!/usr/bin/env bash
# Mizu — Trojan protocol (Xray + Caddy fallback)

trojan_install() {
    local proto="trojan"
    local proto_dir="/etc/mizu/${proto}"

    # Check if already installed
    if state_protocol_exists "$proto" || [[ -f "/etc/systemd/system/mizu-${proto}.service" ]]; then
        msg_error "Trojan 已安装，请先卸载"
        return 1
    fi

    msg_info ">>> 安装 Trojan <<<"
    echo ""

    # Get domain
    local domain
    domain=$(prompt_domain)

    # Resolve port
    local port
    port=$(resolve_port 443 8443)

    # Step 1: Install Xray
    msg_step 1 6 "安装 Xray..."
    rt_xray_install || return 1

    # Step 2: Install Caddy
    msg_step 2 6 "安装 Caddy..."
    rt_caddy_install || return 1

    # Step 3: Certificate
    msg_step 3 6 "检查证书..."
    cert_issue "$domain" || return 1

    # Step 4: Generate credentials
    msg_step 4 6 "生成凭证..."
    local password
    password=$(gen_password)
    msg_success "密码: ${password}"

    # Step 5: Generate config & site
    msg_step 5 6 "部署伪装网站 (Caddy)..."
    generate_site "$domain"
    generate_caddy_config "$domain" 8080

    # Generate Xray config
    mkdir -p "$proto_dir"

    jq -n \
        --argjson port "$port" \
        --arg password "$password" \
        --arg domain "$domain" \
        --arg cert "$(cert_fullchain "$domain")" \
        --arg key "$(cert_key "$domain")" \
        '{
            "log": {"loglevel": "warning", "access": "/var/log/mizu/xray-trojan-access.log", "error": "/var/log/mizu/xray-trojan-error.log"},
            "inbounds": [{
                "port": $port,
                "protocol": "trojan",
                "settings": {
                    "clients": [{"password": $password}],
                    "fallbacks": [{"dest": 8080}]
                },
                "streamSettings": {
                    "network": "tcp",
                    "security": "tls",
                    "tlsSettings": {
                        "serverName": $domain,
                        "alpn": ["h2", "http/1.1"],
                        "minVersion": "1.2",
                        "certificates": [{
                            "certificateFile": $cert,
                            "keyFile": $key
                        }]
                    }
                }
            }],
            "outbounds": [{"protocol": "freedom", "settings": {}}]
        }' > "${proto_dir}/config.json"

    # Step 6: Start services
    msg_step 6 6 "启动 Trojan..."

    # Start Caddy first
    service_create_caddy
    systemctl start mizu-caddy 2>/dev/null
    systemctl enable mizu-caddy 2>/dev/null
    msg_success "Caddy 已启动"

    # Create and start Trojan service
    service_create "$proto" "/usr/local/bin/xray" "run -config ${proto_dir}/config.json" \
        "after=mizu-caddy.service" "wants=mizu-caddy.service" || return 1
    service_start_verified "$proto" || return 1
    service_enable "$proto" || true

    msg_success "Xray 已启动 (端口 ${port})"
    msg_success "Fallback → Caddy:8080"

    # Save state
    local ipv4
    ipv4=$(detect_ipv4)
    local share_link="trojan://${password}@${ipv4}:${port}?security=tls&type=tcp&sni=${domain}#Mizu-Trojan"

    state_set_protocol "$proto" "$(jq -n \
        --arg port "$port" --arg domain "$domain" --arg password "$password" \
        --arg transport "TCP + TLS" --arg link "$share_link" --arg status "running" '{
            "port": $port, "domain": $domain, "transport": $transport,
            "status": $status, "share_link": $link,
            "credential": {"password": $password}
        }')"

    # Show result
    echo ""
    msg_info "Trojan — 安装成功"
    echo ""
    printf "  端口:     %s\n" "$port"
    printf "  域名:     %s\n" "$domain"
    printf "  密码:     %s\n" "$password"
    printf "  传输:     TCP + TLS\n"
    printf "  ALPN:     h2, http/1.1\n"
    printf "  伪装:     Caddy 多页网站 (:8080)\n"
    echo ""

    show_install_result "$proto" "$share_link"
}

trojan_regen() {
    local proto="trojan"
    local proto_dir="/etc/mizu/${proto}"

    local password
    password=$(gen_password)

    # Update config
    jq --arg p "$password" '.inbounds[0].settings.clients[0].password = $p' \
        "${proto_dir}/config.json" > "${proto_dir}/config.json.tmp" \
        && mv "${proto_dir}/config.json.tmp" "${proto_dir}/config.json"

    state_set_string ".protocols.${proto}.credential.password" "$password"

    service_restart "$proto"

    # Regenerate share link
    local ipv4
    ipv4=$(detect_ipv4)
    save_share_link "$proto" "$ipv4"

    msg_success "凭证已重新生成"
    msg_info "新密码: ${password}"
}

trojan_uninstall() {
    local proto="trojan"
    local proto_dir="/etc/mizu/${proto}"

    msg_warn "正在卸载 Trojan..."

    # Check if other protocols still need Caddy BEFORE deleting state
    local caddy_still_needed
    caddy_still_needed=$(jq -r '.protocols | to_entries[] |
        select(.key != "trojan") |
        select(.value.runtime == "caddy" or .key == "trojan") | .key' \
        "$STATE_FILE" 2>/dev/null | grep -v "trojan" || true)

    service_remove "$proto"

    # Stop and remove Caddy service
    systemctl stop mizu-caddy 2>/dev/null
    systemctl disable mizu-caddy 2>/dev/null
    rm -f /etc/systemd/system/mizu-caddy.service
    systemctl daemon-reload 2>/dev/null

    rm -rf "$proto_dir"
    rm -rf /etc/mizu/caddy
    remove_site

    local domain
    domain=$(state_get ".protocols.${proto}.domain")
    cert_ref_del "$domain"

    state_del ".protocols.${proto}"

    # Remove Caddy binary only if no other protocol needs it
    if [[ -z "$caddy_still_needed" ]]; then
        rt_caddy_remove 2>/dev/null || true
    fi

    msg_success "Trojan 已卸载"
}
