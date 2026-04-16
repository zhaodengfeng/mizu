#!/usr/bin/env bash
# Mizu — Snell runtime (Surge)

[[ -n "${_MIZU_RT_SNELL_LOADED:-}" ]] && return 0
_MIZU_RT_SNELL_LOADED=1

# Snell doesn't have public GitHub releases - download URL is fixed
SNELL_BIN="/usr/local/bin/snell-server"
SNELL_VERSION="5.0.1"

rt_snell_install() {
    local arch
    arch=$(detect_arch)
    if [[ "$arch" == "unsupported" ]]; then
        msg_error "不支持的架构"
        return 1
    fi

    local current
    current=$(state_get ".runtimes.snell")
    if [[ "$current" == "$SNELL_VERSION" ]]; then
        msg_success "Snell v${SNELL_VERSION} 已是最新版本"
        return 0
    fi

    msg_info "安装 Snell v${SNELL_VERSION}..."

    local download_arch
    case "$arch" in
        amd64) download_arch="amd64" ;;
        arm64) download_arch="aarch64" ;;
        *) msg_error "不支持的架构: $arch"; return 1 ;;
    esac
    local url="https://dl.nssurge.com/snell/snell-server-v${SNELL_VERSION}-linux-${download_arch}.zip"

    local tmpdir
    tmpdir=$(mktemp -d)
    if ! download_file "$url" "${tmpdir}/snell.zip"; then
        msg_error "Snell 下载失败（可能需要手动下载）"
        rm -rf "$tmpdir"
        return 1
    fi

    # Backup
    [[ -f "$SNELL_BIN" ]] && cp "$SNELL_BIN" "${SNELL_BIN}.bak"

    unzip -o "${tmpdir}/snell.zip" -d "${tmpdir}" >/dev/null
    local snell_file
    snell_file=$(find "${tmpdir}" -name "snell-server" -type f -o -name "snell-server-*" -type f | head -1)

    if [[ -z "$snell_file" ]]; then
        msg_error "Snell 二进制未找到"
        rm -rf "$tmpdir"
        return 1
    fi

    chmod +x "$snell_file"
    cp "$snell_file" "$SNELL_BIN"

    rm -rf "$tmpdir"
    state_set_string ".runtimes.snell" "$SNELL_VERSION"
    msg_success "Snell v${SNELL_VERSION} 安装成功"
    return 0
}

rt_snell_update() {
    local current
    current=$(state_get ".runtimes.snell")
    if [[ -z "$current" || "$current" == "null" ]]; then
        msg_error "Snell 未安装"
        return 1
    fi

    if [[ "$current" == "$SNELL_VERSION" ]]; then
        msg_success "Snell v${current} (最新)"
        msg_dim "提示: Snell 版本随 Mizu 更新而更新 (当前内置 v${SNELL_VERSION})"
        return 0
    fi

    msg_info "更新 Snell ${current} → ${SNELL_VERSION}..."
    rt_snell_install || return 1
    # Restart protocol that depends on Snell
    state_protocol_exists "snell" && service_restart "snell" 2>/dev/null
    msg_success "相关服务已重启"
}

rt_snell_remove() {
    if state_protocol_exists "snell"; then
        msg_warn "Snell 仍被 snell 协议使用，跳过删除"
        return 0
    fi
    rm -f "$SNELL_BIN"
    state_del ".runtimes.snell"
    msg_success "Snell 已删除"
}
