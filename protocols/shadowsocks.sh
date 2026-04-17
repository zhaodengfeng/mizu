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

    state_set_protocol "$proto" "$(jq -n --arg port "$port" --arg method "$SS_METHOD" --arg key "$key" \
        '{
            "port": $port, "transport": "TCP",
            "status": "running",
            "credential": {"method": $method, "key": $key}
        }')" || return 1
    local share_link
    share_link=$(refresh_share_link "$proto" "$ipv4") || return 1

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
    service_restart_verified "$proto" || return 1

    local ipv4
    ipv4=$(detect_ipv4)
    save_share_link "$proto" "$ipv4" || return 1
    msg_success "凭证已重新生成"
}

shadowsocks_settings() {
    local proto="shadowsocks"
    local proto_dir="/etc/mizu/${proto}"

    while true; do
        local current_mode
        current_mode=$(jq -r '.mode // "tcp_and_udp"' "${proto_dir}/config.json" 2>/dev/null)

        local mode_desc
        case "$current_mode" in
            tcp_and_udp) mode_desc="TCP + UDP" ;;
            tcp_only)    mode_desc="仅 TCP" ;;
            udp_only)    mode_desc="仅 UDP" ;;
            *)           mode_desc="$current_mode" ;;
        esac

        clear_screen
        msg_info "Shadowsocks 2022 — 配置"
        echo ""
        printf "  [1] 运行模式: %s\n" "$mode_desc"
        printf "  [0] 返回\n"
        echo ""
        printf "请选择: "
        read -r choice

        case "$choice" in
            0) return ;;
            1)
                echo ""
                printf "  可选模式:\n"
                printf "    [1] TCP + UDP (推荐)\n"
                printf "    [2] 仅 TCP\n"
                printf "    [3] 仅 UDP\n"
                printf "  请选择: "
                read -r mode_choice
                local new_mode=""
                case "$mode_choice" in
                    1) new_mode="tcp_and_udp" ;;
                    2) new_mode="tcp_only" ;;
                    3) new_mode="udp_only" ;;
                    *) continue ;;
                esac
                if [[ "$new_mode" == "$current_mode" ]]; then
                    msg_dim "模式未变更"
                    press_enter
                    continue
                fi
                jq --arg m "$new_mode" '.mode = $m' "${proto_dir}/config.json" > "${proto_dir}/config.json.tmp" \
                    && mv "${proto_dir}/config.json.tmp" "${proto_dir}/config.json"
                state_set_string ".protocols.${proto}.credential.mode" "$new_mode"
                service_restart_verified "$proto" || { press_enter; continue; }
                local new_desc
                case "$new_mode" in
                    tcp_and_udp) new_desc="TCP + UDP" ;;
                    tcp_only)    new_desc="仅 TCP" ;;
                    udp_only)    new_desc="仅 UDP" ;;
                esac
                msg_success "模式已切换为 ${new_desc}"
                press_enter
                ;;
        esac
    done
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
