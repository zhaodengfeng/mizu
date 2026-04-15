#!/usr/bin/env bash
# Mizu — VLESS + Reality protocol (Xray)

# Reality dest candidates (same ASN, no CDN)
REALITY_DESTS=(
    "www.microsoft.com:443"
    "www.apple.com:443"
    "gateway.icloud.com:443"
    "www.amazon.com:443"
    "www.samsung.com:443"
)

vless_reality_install() {
    local proto="vless-reality"
    local proto_dir="/etc/mizu/${proto}"

    if state_protocol_exists "$proto"; then
        msg_error "VLESS+Reality 已安装，请先卸载"
        return 1
    fi

    msg_info ">>> 安装 VLESS + Reality <<<"
    echo ""

    # Resolve port
    local port
    port=$(resolve_port 443 8443)

    # Step 1: Install Xray
    msg_step 1 3 "安装 Xray..."
    rt_xray_install || return 1

    # Step 2: Generate credentials
    msg_step 2 3 "生成凭证..."
    local uuid
    uuid=$(gen_uuid)
    local key_output
    key_output=$(/usr/local/bin/xray x25519 2>/dev/null)
    local private_key public_key
    private_key=$(echo "$key_output" | grep "Private" | awk '{print $3}')
    public_key=$(echo "$key_output" | grep "Public" | awk '{print $3}')
    if [[ -z "$private_key" || -z "$public_key" ]]; then
        msg_error "Reality 密钥生成失败"
        return 1
    fi
    local short_id
    short_id=$(openssl rand -hex 8)

    # Pick dest
    local dest="${REALITY_DESTS[$((RANDOM % ${#REALITY_DESTS[@]}))]}"
    local dest_domain="${dest%%:*}"
    local dest_port="${dest##*:}"

    msg_success "UUID: ${uuid}"
    msg_success "ShortID: ${short_id}"
    msg_success "伪装目标: ${dest}"

    # Step 3: Generate config & start
    msg_step 3 3 "启动 VLESS+Reality..."

    mkdir -p "$proto_dir"

    jq -n \
        --argjson port "$port" \
        --arg uuid "$uuid" \
        --arg private_key "$private_key" \
        --arg dest_domain "$dest_domain" \
        --argjson dest_port "$dest_port" \
        --arg short_id "$short_id" \
        '{
            "log": {"loglevel": "warning", "access": "/var/log/mizu/xray-vless-reality-access.log", "error": "/var/log/mizu/xray-vless-reality-error.log"},
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
                    "security": "reality",
                    "realitySettings": {
                        "dest": ($dest_domain + ":" + ($dest_port | tostring)),
                        "serverName": $dest_domain,
                        "privateKey": $private_key,
                        "shortIds": [$short_id]
                    }
                }
            }],
            "outbounds": [{"protocol": "freedom", "settings": {}}]
        }' > "${proto_dir}/config.json"

    service_create "$proto" "/usr/local/bin/xray" "run -config ${proto_dir}/config.json" || return 1
    service_start_verified "$proto" || return 1
    service_enable "$proto"
    msg_success "VLESS+Reality 已启动 (端口 ${port})"

    # Save state
    local ipv4
    ipv4=$(detect_ipv4)
    local fingerprint="chrome"
    local share_link="vless://${uuid}@${ipv4}:${port}?encryption=none&security=reality&sni=${dest_domain}&fp=${fingerprint}&pbk=$(url_encode "$public_key")&sid=${short_id}&type=tcp&flow=xtls-rprx-vision#Mizu-VLESS-Reality"

    state_set_protocol "$proto" "$(jq -n \
        --arg port "$port" --arg uuid "$uuid" --arg private_key "$private_key" \
        --arg public_key "$public_key" --arg short_id "$short_id" --arg dest "$dest" \
        --arg serverName "$dest_domain" --arg fingerprint "$fingerprint" --arg link "$share_link" '{
            "port": $port, "status": "running", "share_link": $link,
            "credential": {
                "uuid": $uuid, "privateKey": $private_key, "publicKey": $public_key,
                "shortId": $short_id, "dest": $dest, "serverName": $serverName, "fingerprint": $fingerprint
            }
        }')"

    # Show result
    echo ""
    msg_info "VLESS + Reality — 安装成功"
    echo ""
    printf "  端口:     %s\n" "$port"
    printf "  UUID:     %s\n" "$uuid"
    printf "  传输:     TCP + Reality\n"
    printf "  伪装目标: %s\n" "$dest"
    printf "  SNI:      %s\n" "$dest_domain"
    printf "  ShortID:  %s\n" "$short_id"
    echo ""

    show_install_result "$proto" "$share_link"
}

vless_reality_regen() {
    local proto="vless-reality"
    local proto_dir="/etc/mizu/${proto}"

    local uuid
    uuid=$(gen_uuid)
    local key_output
    key_output=$(/usr/local/bin/xray x25519 2>/dev/null)
    local private_key public_key
    private_key=$(echo "$key_output" | grep "Private" | awk '{print $3}')
    public_key=$(echo "$key_output" | grep "Public" | awk '{print $3}')
    if [[ -z "$private_key" || -z "$public_key" ]]; then
        msg_error "Reality 密钥生成失败"
        return 1
    fi
    local short_id
    short_id=$(openssl rand -hex 8)

    # Update config
    jq --arg uuid "$uuid" --arg pk "$private_key" --arg sid "$short_id" \
        '.inbounds[0].settings.clients[0].id = $uuid | .inbounds[0].streamSettings.realitySettings.privateKey = $pk | .inbounds[0].streamSettings.realitySettings.shortIds = [$sid]' \
        "${proto_dir}/config.json" > "${proto_dir}/config.json.tmp" \
        && mv "${proto_dir}/config.json.tmp" "${proto_dir}/config.json"

    state_set_string ".protocols.${proto}.credential.uuid" "$uuid"
    state_set_string ".protocols.${proto}.credential.privateKey" "$private_key"
    state_set_string ".protocols.${proto}.credential.publicKey" "$public_key"
    state_set_string ".protocols.${proto}.credential.shortId" "$short_id"

    service_restart "$proto"

    local ipv4
    ipv4=$(detect_ipv4)
    save_share_link "$proto" "$ipv4"

    msg_success "凭证已重新生成"
}

vless_reality_uninstall() {
    local proto="vless-reality"
    local proto_dir="/etc/mizu/${proto}"

    msg_warn "正在卸载 VLESS+Reality..."
    service_remove "$proto"
    rm -rf "$proto_dir"
    state_del ".protocols.${proto}"
    msg_success "VLESS+Reality 已卸载"
}
