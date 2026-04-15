#!/usr/bin/env bash
# Mizu — shadowsocks-rust runtime

[[ -n "${_MIZU_RT_SS_LOADED:-}" ]] && return 0
_MIZU_RT_SS_LOADED=1

SS_REPO="shadowsocks/shadowsocks-rust"
SS_BIN="/usr/local/bin/ssserver"
SS_SERVICE_BIN="/usr/local/bin/ssservice"

rt_ss_install() {
    local arch
    arch=$(detect_arch)
    if [[ "$arch" == "unsupported" ]]; then
        msg_error "不支持的架构"
        return 1
    fi

    local version
    version=$(github_latest_tag "$SS_REPO")
    if [[ -z "$version" ]]; then
        msg_error "获取 shadowsocks-rust 版本失败"
        return 1
    fi

    local current
    current=$(state_get ".runtimes.shadowsocks-rust")
    if [[ "$current" == "$version" ]]; then
        msg_success "shadowsocks-rust v${version} 已是最新版本"
        return 0
    fi

    msg_info "安装 shadowsocks-rust v${version}..."

    local download_arch
    case "$arch" in
        amd64) download_arch="x86_64" ;;
        arm64) download_arch="aarch64" ;;
        *) msg_error "不支持的架构: $arch"; return 1 ;;
    esac
    local filename="shadowsocks-v${version}.${download_arch}-unknown-linux-gnu.tar.xz"
    local url="https://github.com/${SS_REPO}/releases/download/v${version}/${filename}"

    local tmpdir
    tmpdir=$(mktemp -d)
    if ! download_file "$url" "${tmpdir}/${filename}"; then
        # Try .tar.gz
        filename="shadowsocks-v${version}.${download_arch}-unknown-linux-gnu.tar.gz"
        url="https://github.com/${SS_REPO}/releases/download/v${version}/${filename}"
        if ! download_file "$url" "${tmpdir}/${filename}"; then
            msg_error "shadowsocks-rust 下载失败"
            rm -rf "$tmpdir"
            return 1
        fi
    fi

    # Backup
    [[ -f "$SS_BIN" ]] && cp "$SS_BIN" "${SS_BIN}.bak"

    # Extract
    if [[ "$filename" == *.tar.xz ]]; then
        tar -xJf "${tmpdir}/${filename}" -C "${tmpdir}" >/dev/null
    else
        tar -xzf "${tmpdir}/${filename}" -C "${tmpdir}" >/dev/null
    fi

    # Find and install binaries
    local ssserver_bin ssservice_bin
    ssserver_bin=$(find "${tmpdir}" -name "ssserver" -type f | head -1)
    ssservice_bin=$(find "${tmpdir}" -name "ssservice" -type f | head -1)

    if [[ -z "$ssserver_bin" ]]; then
        msg_error "ssserver 二进制未在 release 包中找到"
        rm -rf "$tmpdir"
        return 1
    fi

    chmod +x "$ssserver_bin"
    cp "$ssserver_bin" "$SS_BIN"
    if [[ -n "$ssservice_bin" ]]; then
        chmod +x "$ssservice_bin"
        cp "$ssservice_bin" "$SS_SERVICE_BIN"
    fi

    rm -rf "$tmpdir"
    state_set_string ".runtimes.shadowsocks-rust" "$version"
    msg_success "shadowsocks-rust v${version} 安装成功"
    return 0
}

rt_ss_update() {
    local current
    current=$(state_get ".runtimes.shadowsocks-rust")
    if [[ -z "$current" || "$current" == "null" ]]; then
        msg_error "shadowsocks-rust 未安装"
        return 1
    fi

    local latest
    latest=$(github_latest_tag "$SS_REPO")

    if [[ "$current" == "$latest" ]]; then
        msg_success "shadowsocks-rust v${current} (最新)"
        return 0
    fi

    msg_info "更新 shadowsocks-rust ${current} → ${latest}..."
    rt_ss_install || return 1
    # Restart protocol that depends on shadowsocks-rust
    state_protocol_exists "shadowsocks" && service_restart "shadowsocks" 2>/dev/null
    msg_success "相关服务已重启"
}

rt_ss_remove() {
    if state_protocol_exists "shadowsocks"; then
        msg_warn "shadowsocks-rust 仍被 SS2022 使用，跳过删除"
        return 0
    fi
    rm -f "$SS_BIN" "$SS_SERVICE_BIN"
    state_del ".runtimes.shadowsocks-rust"
    msg_success "shadowsocks-rust 已删除"
}
