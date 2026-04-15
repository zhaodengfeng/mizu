#!/usr/bin/env bash
# Mizu — Share link generation

[[ -n "${_MIZU_SHARE_LINK_SH_LOADED:-}" ]] && return 0
_MIZU_SHARE_LINK_SH_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ─── Generate share link for protocol ────────────────────────────────────────
generate_share_link() {
    local proto="$1"
    local ipv4="$2"
    local link=""

    case "$proto" in
        trojan)
            link=$(gen_trojan_link "$ipv4")
            ;;
        vless-reality)
            link=$(gen_vless_reality_link "$ipv4")
            ;;
        vless-vision)
            link=$(gen_vless_vision_link "$ipv4")
            ;;
        vmess)
            link=$(gen_vmess_link "$ipv4")
            ;;
        shadowtls)
            link=$(gen_shadowtls_link "$ipv4")
            ;;
        anytls)
            link=$(gen_anytls_link "$ipv4")
            ;;
        hysteria2)
            link=$(gen_hysteria2_link "$ipv4")
            ;;
        shadowsocks)
            link=$(gen_ss_link "$ipv4")
            ;;
        snell)
            # Snell doesn't have a standard URI format
            link=""
            ;;
        *)
            link=""
            ;;
    esac

    echo "$link"
}

# ─── Trojan ──────────────────────────────────────────────────────────────────
gen_trojan_link() {
    local ipv4="$1"
    local password domain port
    password=$(state_get ".protocols.trojan.credential.password")
    domain=$(state_get ".protocols.trojan.domain")
    port=$(state_get ".protocols.trojan.port")
    echo "trojan://${password}@${ipv4}:${port}?security=tls&type=tcp&sni=${domain}#Mizu-Trojan"
}

# ─── VLESS + Reality ─────────────────────────────────────────────────────────
gen_vless_reality_link() {
    local ipv4="$1"
    local uuid port pbk sid sni fp
    uuid=$(state_get ".protocols.vless-reality.credential.uuid")
    port=$(state_get ".protocols.vless-reality.port")
    pbk=$(state_get ".protocols.vless-reality.credential.publicKey")
    sid=$(state_get ".protocols.vless-reality.credential.shortId")
    sni=$(state_get ".protocols.vless-reality.credential.serverName")
    fp=$(state_get ".protocols.vless-reality.credential.fingerprint")
    echo "vless://${uuid}@${ipv4}:${port}?encryption=none&security=reality&sni=${sni}&fp=${fp}&pbk=$(url_encode "$pbk")&sid=${sid}&type=tcp&flow=xtls-rprx-vision#Mizu-VLESS-Reality"
}

# ─── VLESS + Vision ──────────────────────────────────────────────────────────
gen_vless_vision_link() {
    local ipv4="$1"
    local uuid domain port
    uuid=$(state_get ".protocols.vless-vision.credential.uuid")
    domain=$(state_get ".protocols.vless-vision.domain")
    port=$(state_get ".protocols.vless-vision.port")
    echo "vless://${uuid}@${ipv4}:${port}?encryption=none&security=tls&type=tcp&sni=${domain}&flow=xtls-rprx-vision&fp=chrome#Mizu-VLESS-Vision"
}

# ─── VMess + WebSocket ───────────────────────────────────────────────────────
gen_vmess_link() {
    local ipv4="$1"
    local uuid domain port path
    uuid=$(state_get ".protocols.vmess.credential.uuid")
    domain=$(state_get ".protocols.vmess.domain")
    port=$(state_get ".protocols.vmess.port")
    path=$(state_get ".protocols.vmess.credential.path")
    local encoded_path
    encoded_path=$(url_encode "$path")

    # VMess uses base64-encoded v2 JSON
    local vmess_json
    vmess_json=$(jq -n \
        --arg v "2" \
        --arg ps "Mizu-VMess" \
        --arg add "$ipv4" \
        --arg port "$port" \
        --arg id "$uuid" \
        --arg host "$domain" \
        --arg path "$path" \
        '{v:$v, ps:$ps, add:$add, port:$port, id:$id, aid:"0", scy:"auto", net:"ws", type:"none", host:$host, path:$path, tls:"tls", sni:$host}')
    echo "vmess://$(echo -n "$vmess_json" | base64 -w 0)"
}

# ─── ShadowTLS ───────────────────────────────────────────────────────────────
gen_shadowtls_link() {
    # ShadowTLS has no standard share link; output a Clash config fragment
    local ipv4="$1"
    local port ss_password st_password domain
    port=$(state_get ".protocols.shadowtls.port")
    ss_password=$(state_get ".protocols.shadowtls.credential.ss_password")
    st_password=$(state_get ".protocols.shadowtls.credential.shadowtls_password")
    domain=$(state_get ".protocols.shadowtls.domain")

    echo "proxies:"
    echo "  - name: Mizu-ShadowTLS"
    echo "    type: ss"
    echo "    server: ${ipv4}"
    echo "    port: ${port}"
    echo "    cipher: 2022-blake3-aes-256-gcm"
    echo "    password: \"${ss_password}\""
    echo "    plugin: shadow-tls"
    echo "    plugin-opts:"
    echo "      host: ${domain}"
    echo "      password: \"${st_password}\""
    echo "      version: 3"
}

# ─── AnyTLS ──────────────────────────────────────────────────────────────────
gen_anytls_link() {
    local ipv4="$1"
    local password domain port
    password=$(state_get ".protocols.anytls.credential.password")
    domain=$(state_get ".protocols.anytls.domain")
    port=$(state_get ".protocols.anytls.port")
    # AnyTLS share link format
    echo "anytls://${password}@${ipv4}:${port}?sni=${domain}&type=tcp#Mizu-AnyTLS"
}

# ─── Hysteria 2 ──────────────────────────────────────────────────────────────
gen_hysteria2_link() {
    local ipv4="$1"
    local password domain port obfs_type obfs_password
    password=$(state_get ".protocols.hysteria2.credential.password")
    domain=$(state_get ".protocols.hysteria2.domain")
    port=$(state_get ".protocols.hysteria2.port")
    obfs_type=$(state_get ".protocols.hysteria2.credential.obfs_type")
    obfs_password=$(state_get ".protocols.hysteria2.credential.obfs_password")

    local params="sni=${domain}&insecure=0"
    if [[ -n "$obfs_type" && "$obfs_type" != "null" ]]; then
        params="${params}&obfs=${obfs_type}&obfs-password=$(url_encode "$obfs_password")"
    fi
    local port_hopping hopping_range
    port_hopping=$(state_get ".protocols.hysteria2.credential.port_hopping")
    hopping_range=$(state_get ".protocols.hysteria2.credential.hopping_range")
    if [[ "$port_hopping" == "y" && -n "$hopping_range" && "$hopping_range" != "null" ]]; then
        params="${params}&mport=${hopping_range}"
    fi
    echo "hysteria2://${password}@${ipv4}:${port}?${params}#Mizu-HY2"
}

# ─── Shadowsocks 2022 ────────────────────────────────────────────────────────
gen_ss_link() {
    local ipv4="$1"
    local method key port
    method=$(state_get ".protocols.shadowsocks.credential.method")
    key=$(state_get ".protocols.shadowsocks.credential.key")
    port=$(state_get ".protocols.shadowsocks.port")
    echo "ss://$(echo -n "${method}:${key}@${ipv4}:${port}" | base64 -w 0)#Mizu-SS2022"
}

# ─── Save share link to state ────────────────────────────────────────────────
save_share_link() {
    local proto="$1"
    local ipv4="$2"
    local link
    link=$(generate_share_link "$proto" "$ipv4")
    if [[ -n "$link" ]]; then
        state_set_string ".protocols.${proto}.share_link" "$link"
    fi
    # Also save to file
    local link_file="/etc/mizu/share-links/${proto}.txt"
    mkdir -p /etc/mizu/share-links
    echo "$link" > "$link_file"
}
