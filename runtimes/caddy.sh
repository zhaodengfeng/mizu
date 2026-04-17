#!/usr/bin/env bash
# Mizu — Caddy runtime (Trojan fallback)

[[ -n "${_MIZU_RT_CADDY_LOADED:-}" ]] && return 0
_MIZU_RT_CADDY_LOADED=1

CADDY_REPO="caddyserver/caddy"
CADDY_BIN="/usr/local/bin/caddy"

rt_caddy_install() {
    local arch
    arch=$(detect_arch)
    if [[ "$arch" == "unsupported" ]]; then
        msg_error "不支持的架构"
        return 1
    fi

    local version
    version=$(github_latest_tag "$CADDY_REPO")
    if [[ -z "$version" ]]; then
        msg_error "获取 Caddy 版本失败"
        return 1
    fi

    local current
    current=$(state_get ".runtimes.caddy")
    if [[ "$current" == "$version" ]]; then
        msg_success "Caddy v${version} 已是最新版本"
        return 0
    fi

    msg_info "安装 Caddy v${version}..."

    local download_arch="$arch"
    local filename="caddy_${version}_linux_${download_arch}.tar.gz"
    local url="https://github.com/${CADDY_REPO}/releases/download/v${version}/${filename}"

    local tmpdir
    tmpdir=$(mktemp -d)
    if ! download_file "$url" "${tmpdir}/${filename}"; then
        msg_error "Caddy 下载失败"
        rm -rf "$tmpdir"
        return 1
    fi

    # Backup
    local backup_bin=""
    if [[ -f "$CADDY_BIN" ]]; then
        backup_bin="${CADDY_BIN}.bak"
        cp "$CADDY_BIN" "$backup_bin"
    fi

    if ! tar -xzf "${tmpdir}/${filename}" -C "${tmpdir}" caddy >/dev/null; then
        [[ -n "$backup_bin" && -f "$backup_bin" ]] && cp "$backup_bin" "$CADDY_BIN"
        rm -rf "$tmpdir"
        msg_error "Caddy 解压失败，已恢复旧版本"
        return 1
    fi
    chmod +x "${tmpdir}/caddy"
    if ! cp "${tmpdir}/caddy" "$CADDY_BIN"; then
        [[ -n "$backup_bin" && -f "$backup_bin" ]] && cp "$backup_bin" "$CADDY_BIN"
        rm -rf "$tmpdir"
        msg_error "Caddy 安装失败，已恢复旧版本"
        return 1
    fi

    rm -rf "$tmpdir"
    state_set_string ".runtimes.caddy" "$version"
    msg_success "Caddy v${version} 安装成功"
    return 0
}

rt_caddy_update() {
    local current
    current=$(state_get ".runtimes.caddy")
    if [[ -z "$current" || "$current" == "null" ]]; then
        msg_error "Caddy 未安装"
        return 1
    fi

    local latest
    latest=$(github_latest_tag "$CADDY_REPO")

    if [[ "$current" == "$latest" ]]; then
        msg_success "Caddy v${current} (最新)"
        return 0
    fi

    msg_info "更新 Caddy ${current} → ${latest}..."
    rt_caddy_install || return 1
    # Restart Caddy service if trojan is installed (Caddy is trojan's fallback)
    if state_protocol_exists "trojan"; then
        systemd_unit_restart_verified "mizu-caddy" "Caddy" || return 1
        msg_success "相关服务已重启"
    fi
}

rt_caddy_remove() {
    local caddy_protos=("trojan")
    for p in "${caddy_protos[@]}"; do
        if state_protocol_exists "$p"; then
            msg_warn "Caddy 仍被 ${p} 使用，跳过删除"
            return 0
        fi
    done
    rm -f "$CADDY_BIN"
    state_del ".runtimes.caddy"
    msg_success "Caddy 已删除"
}
