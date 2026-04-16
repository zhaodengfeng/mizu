#!/usr/bin/env bash
# Mizu — Shadowsocks 2022 protocol (shadowsocks-rust)

SS_METHOD="2022-blake3-aes-256-gcm"

shadowsocks_install() {
    local proto="shadowsocks"
    local proto_dir="/etc/mizu/${proto}"

    if state_protocol_exists "$proto" || [[ -f "/etc/systemd/system/mizu-${proto}.service" ]]; then
        msg_error "Shadowsocks 2022 已安装，请先卸载"
        return 1
    fi

    msg_info ">>> 安装 Shadowsocks 2022 <<<"
    echo ""

    # Step 1: Install ss-rust
    msg_step 1 3 "安装 shadowsocks-rust..."
    rt_ss_install || return 1

    # Step 2: Generate credentials
    msg_step 2 3 "生成凭证..."

    local key
    if [[ -x "/usr/local/bin/ssservice" ]]; then
        key=$(/usr/local/bin/ssservice genkey -m "$SS_METHOD" 2>/dev/null)
    fi
    if [[ -z "$key" ]]; then
        # Fallback: generate base64 key manually
        key=$(openssl rand -base64 32)
    fi
    msg_success "密钥: ${key}"

    local port
    port=$(resolve_port 8388 8389)

    # Step 3: Generate config & start
    msg_step 3 3 "启动 Shadowsocks 2022..."

    mkdir -p "$proto_dir"

    jq -n \
        --arg method "$SS_METHOD" \
        --arg key "$key" \
        --argjson port "$port" \
        '{
            "server": "0.0.0.0",
            "server_port": $port,
            "method": $method,
            "password": $key,
            "timeout": 300,
            "mode": "tcp_and_udp"
        }' > "${proto_dir}/config.json"

    service_create "$proto" "/usr/local/bin/ssserver" "-c ${proto_dir}/config.json" || return 1
    service_start_verified "$proto" || return 1
    service_enable "$proto" || true

    # Save state
    local ipv4
    ipv4=$(detect_ipv4)
    local share_link="ss://$(echo -n "${SS_METHOD}:${key}@${ipv4}:${port}" | base64 -w 0)#Mizu-SS2022"

    state_set_protocol "$proto" "$(jq -n --arg port "$port" --arg method "$SS_METHOD" --arg key "$key" \
        --arg link "$share_link" '{
            "port": $port, "transport": "TCP",
            "status": "running", "share_link": $link,
            "credential": {"method": $method, "key": $key}
        }')"

    show_install_result "$proto" "$share_link"
}

shadowsocks_regen() {
    local proto="shadowsocks"
    local proto_dir="/etc/mizu/${proto}"

    local key
    if [[ -x "/usr/local/bin/ssservice" ]]; then
        key=$(/usr/local/bin/ssservice genkey -m "$SS_METHOD" 2>/dev/null)
    fi
    if [[ -z "$key" ]]; then
        key=$(openssl rand -base64 32)
    fi

    jq --arg k "$key" '.password = $k' "${proto_dir}/config.json" > "${proto_dir}/config.json.tmp" \
        && mv "${proto_dir}/config.json.tmp" "${proto_dir}/config.json"

    state_set_string ".protocols.${proto}.credential.key" "$key"
    service_restart "$proto"

    local ipv4
    ipv4=$(detect_ipv4)
    save_share_link "$proto" "$ipv4"
    msg_success "凭证已重新生成"
}

shadowsocks_uninstall() {
    local proto="shadowsocks"
    local proto_dir="/etc/mizu/${proto}"

    msg_warn "正在卸载 Shadowsocks 2022..."
    service_remove "$proto"
    rm -rf "$proto_dir"
    state_del ".protocols.${proto}"
    msg_success "Shadowsocks 2022 已卸载"
}
