#!/usr/bin/env bash
# Mizu — Hysteria 2 runtime (apernet)

[[ -n "${_MIZU_RT_HYSTERIA_LOADED:-}" ]] && return 0
_MIZU_RT_HYSTERIA_LOADED=1

HYSTERIA_REPO="apernet/hysteria"
HYSTERIA_BIN="/usr/local/bin/hysteria"

rt_hysteria_install() {
    local arch
    arch=$(detect_arch)
    if [[ "$arch" == "unsupported" ]]; then
        msg_error "不支持的架构"
        return 1
    fi

    # Hysteria uses a custom install script or direct binary
    local version
    version=$(github_latest_tag "$HYSTERIA_REPO" | sed 's|^app/||; s|^v||')
    if [[ -z "$version" ]]; then
        msg_error "获取 Hysteria 版本失败"
        return 1
    fi

    local current
    current=$(state_get ".runtimes.hysteria")
    if [[ "$current" == "$version" ]]; then
        msg_success "Hysteria v${version} 已是最新版本"
        return 0
    fi

    msg_info "安装 Hysteria v${version}..."

    local download_arch="$arch"
    local filename="hysteria-linux-${download_arch}"
    local url="https://github.com/${HYSTERIA_REPO}/releases/download/app/v${version}/${filename}"

    # Try with .exe extension first, then without
    local tmpfile
    tmpfile=$(mktemp)

    if ! download_file "${url}" "$tmpfile"; then
        url="https://github.com/${HYSTERIA_REPO}/releases/download/app/v${version}/${filename}.exe"
        if ! download_file "${url}" "$tmpfile"; then
            msg_error "Hysteria 下载失败"
            rm -f "$tmpfile"
            return 1
        fi
    fi

    # Backup
    local backup_bin=""
    if [[ -f "$HYSTERIA_BIN" ]]; then
        backup_bin="${HYSTERIA_BIN}.bak"
        cp "$HYSTERIA_BIN" "$backup_bin"
    fi

    chmod +x "$tmpfile"
    if ! cp "$tmpfile" "$HYSTERIA_BIN"; then
        [[ -n "$backup_bin" && -f "$backup_bin" ]] && cp "$backup_bin" "$HYSTERIA_BIN"
        rm -f "$tmpfile"
        msg_error "Hysteria 安装失败，已恢复旧版本"
        return 1
    fi
    rm -f "$tmpfile"

    state_set_string ".runtimes.hysteria" "$version"
    msg_success "Hysteria v${version} 安装成功"
    return 0
}

rt_hysteria_update() {
    local current
    current=$(state_get ".runtimes.hysteria")
    if [[ -z "$current" || "$current" == "null" ]]; then
        msg_error "Hysteria 未安装"
        return 1
    fi

    local latest
    latest=$(github_latest_tag "$HYSTERIA_REPO" | sed 's|^app/||; s|^v||')

    if [[ "$current" == "$latest" ]]; then
        msg_success "Hysteria v${current} (最新)"
        return 0
    fi

    msg_info "更新 Hysteria ${current} → ${latest}..."
    rt_hysteria_install || return 1
    restart_protocols_verified "hysteria2" || return 1
    msg_success "相关服务已重启"
}

rt_hysteria_remove() {
    if state_protocol_exists "hysteria2"; then
        msg_warn "Hysteria 仍被 hysteria2 使用，跳过删除"
        return 0
    fi
    rm -f "$HYSTERIA_BIN"
    state_del ".runtimes.hysteria"
    msg_success "Hysteria 已删除"
}
