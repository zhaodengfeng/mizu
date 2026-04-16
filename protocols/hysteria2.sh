#!/usr/bin/env bash
# Mizu — Hysteria 2 protocol (apernet/hysteria)

hysteria2_install() {
    local proto="hysteria2"
    local proto_dir="/etc/mizu/${proto}"

    if state_protocol_exists "$proto" || [[ -f "/etc/systemd/system/mizu-${proto}.service" ]]; then
        msg_error "Hysteria 2 已安装，请先卸载"
        return 1
    fi

    msg_info ">>> 安装 Hysteria 2 <<<"
    echo ""

    # Get domain
    local domain
    domain=$(prompt_domain)

    # Step 1: Install Hysteria
    msg_step 1 5 "安装 Hysteria 2..."
    rt_hysteria_install || return 1

    # Step 2: Certificate
    msg_step 2 5 "检查证书..."
    cert_issue "$domain" || return 1

    # Step 3: Generate credentials
    msg_step 3 5 "生成凭证..."
    local password
    password=$(gen_base64 32)
    msg_success "密码: ${password}"

    # Step 4: Port config
    local port
    port=$(resolve_port 443 8443)

    local port_hopping="n"
    local hopping_range=""

    if prompt_yesno "启用 UDP 端口跳跃? (推荐)" "Y"; then
        port_hopping="y"
        printf "${C_WHITE}  端口范围 (默认 20000-50000): ${C_RESET}"
        read -r hopping_input
        if [[ -n "$hopping_input" ]]; then
            hopping_range="$hopping_input"
        else
            hopping_range="20000-50000"
        fi
        msg_success "端口跳跃: ${hopping_range} → ${port}"
    fi

    # Step 5: Generate config & start
    msg_step 5 5 "启动 Hysteria 2..."

    mkdir -p "$proto_dir"

    cat > "${proto_dir}/config.yaml" <<EOF
listen: :${port}

tls:
  cert: $(cert_fullchain "$domain")
  key: $(cert_key "$domain")

masquerade:
  type: proxy
  proxy:
    url: https://news.yandex.com
    rewriteHost: true
EOF

    # Auth + QUIC
    cat >> "${proto_dir}/config.yaml" <<EOF

auth:
  type: password
  password: ${password}

quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 8388608
  initConnReceiveWindow: 20971520
  maxConnReceiveWindow: 20971520
  maxIdleTimeout: 60s
EOF

    # Setup iptables for port hopping
    if [[ "$port_hopping" == "y" ]]; then
        local iface
        iface=$(get_default_interface)
        local start_port=${hopping_range%%-*}
        local end_port=${hopping_range##*-}
        iptables -t nat -A PREROUTING -i "${iface}" -p udp --dport "${start_port}:${end_port}" -j REDIRECT --to-port "${port}" 2>/dev/null
        # Save iptables rule
        mkdir -p /etc/mizu/iptables
        cat > "/etc/mizu/iptables/${proto}.rules" <<EOF
#!/bin/bash
iptables -t nat -A PREROUTING -i ${iface} -p udp --dport ${start_port}:${end_port} -j REDIRECT --to-port ${port}
EOF
        chmod +x "/etc/mizu/iptables/${proto}.rules"

        # Create iptables restore service
        cat > /etc/systemd/system/mizu-iptables-${proto}.service <<EOF
[Unit]
Description=Mizu iptables rules
Before=mizu-${proto}.service

[Service]
Type=oneshot
ExecStart=/bin/bash /etc/mizu/iptables/${proto}.rules
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable "mizu-iptables-${proto}" 2>/dev/null
    fi

    service_create "$proto" "/usr/local/bin/hysteria" "server -c ${proto_dir}/config.yaml" || return 1
    service_start_verified "$proto" || return 1
    service_enable "$proto" || true

    # Save state
    local ipv4
    ipv4=$(detect_ipv4)
    local share_params="sni=${domain}&insecure=0"
    if [[ "$port_hopping" == "y" ]]; then
        share_params="${share_params}&mport=${hopping_range}"
    fi
    local share_link="hysteria2://${password}@${ipv4}:${port}?${share_params}#Mizu-HY2"

    state_set_protocol "$proto" "$(jq -n --arg port "$port" --arg domain "$domain" --arg password "$password" \
        --arg port_hopping "$port_hopping" --arg hopping_range "$hopping_range" \
        --arg link "$share_link" '{
            "port": $port, "domain": $domain, "transport": "QUIC/UDP",
            "status": "running", "share_link": $link,
            "credential": {
                "password": $password,
                "port_hopping": $port_hopping,
                "hopping_range": $hopping_range
            }
        }')"

    show_install_result "$proto" "$share_link"
}

hysteria2_regen() {
    local proto="hysteria2"
    local proto_dir="/etc/mizu/${proto}"

    local password
    password=$(gen_base64 32)

    # Use awk to only replace the password in the auth section
    awk -v pw="$password" '
/^auth:/ { in_auth=1; print; next }
in_auth && /password:/ { print "  password: " pw; next }
/^[^ ]/ { in_auth=0 }
{ print }
' "${proto_dir}/config.yaml" > "${proto_dir}/config.yaml.tmp" && mv "${proto_dir}/config.yaml.tmp" "${proto_dir}/config.yaml"

    state_set_string ".protocols.${proto}.credential.password" "$password"
    service_restart "$proto"

    local ipv4
    ipv4=$(detect_ipv4)
    save_share_link "$proto" "$ipv4"
    msg_success "凭证已重新生成"
}

hysteria2_uninstall() {
    local proto="hysteria2"
    local proto_dir="/etc/mizu/${proto}"

    msg_warn "正在卸载 Hysteria 2..."
    service_remove "$proto"

    # Stop and disable iptables service
    systemctl stop "mizu-iptables-${proto}" 2>/dev/null || true
    systemctl disable "mizu-iptables-${proto}" 2>/dev/null || true
    rm -f "/etc/systemd/system/mizu-iptables-${proto}.service"
    systemctl daemon-reload 2>/dev/null || true

    # Remove iptables rules
    if [[ -f "/etc/mizu/iptables/${proto}.rules" ]]; then
        local iface hopping_range port
        iface=$(get_default_interface)
        hopping_range=$(state_get ".protocols.${proto}.credential.hopping_range")
        port=$(state_get ".protocols.${proto}.port")
        if [[ -n "$hopping_range" && "$hopping_range" != "null" ]]; then
            local start_port=${hopping_range%%-*}
            local end_port=${hopping_range##*-}
            iptables -t nat -D PREROUTING -i "${iface}" -p udp --dport "${start_port}:${end_port}" -j REDIRECT --to-port "${port}" 2>/dev/null || true
        fi
        rm -f "/etc/mizu/iptables/${proto}.rules"
    fi

    rm -rf "$proto_dir"

    local domain
    domain=$(state_get ".protocols.${proto}.domain")
    cert_ref_del "$domain"

    state_del ".protocols.${proto}"
    msg_success "Hysteria 2 已卸载"
}
