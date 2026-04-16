#!/usr/bin/env bash
# Mizu — Xray runtime (4 protocols: Trojan, VLESS+Reality, VLESS+Vision, VMess)

[[ -n "${_MIZU_RT_XRAY_LOADED:-}" ]] && return 0
_MIZU_RT_XRAY_LOADED=1

XRAY_REPO="XTLS/Xray-core"
XRAY_BIN="/usr/local/bin/xray"

rt_xray_install() {
    local arch
    arch=$(detect_arch)
    if [[ "$arch" == "unsupported" ]]; then
        msg_error "不支持的架构"
        return 1
    fi

    local version
    version=$(github_latest_tag "$XRAY_REPO")
    if [[ -z "$version" ]]; then
        msg_error "获取 Xray 版本失败"
        return 1
    fi

    # Check if already installed with same version
    local current
    current=$(state_get ".runtimes.xray")
    if [[ "$current" == "$version" ]]; then
        msg_success "Xray v${version} 已是最新版本"
        return 0
    fi

    msg_info "安装 Xray v${version}..."

    local download_arch
    case "$arch" in
        amd64) download_arch="64" ;;
        arm64) download_arch="arm64-v8a" ;;
        *) msg_error "不支持的架构: $arch"; return 1 ;;
    esac
    local ext="zip"
    local filename="Xray-linux-${download_arch}.${ext}"
    local url="https://github.com/${XRAY_REPO}/releases/download/v${version}/${filename}"

    local tmpdir
    tmpdir=$(mktemp -d)
    if ! download_file "$url" "${tmpdir}/${filename}"; then
        msg_error "Xray 下载失败"
        rm -rf "$tmpdir"
        return 1
    fi

    # Verify SHA256
    local sha_url="https://github.com/${XRAY_REPO}/releases/download/v${version}/Xray-linux-${download_arch}.${ext}.sha256"
    local expected_sha
    expected_sha=$(curl -fsSL "$sha_url" 2>/dev/null | awk '{print $1}')
    # Fallback: try unified checksum file
    if [[ -z "$expected_sha" ]]; then
        local checksum_url="https://github.com/${XRAY_REPO}/releases/download/v${version}/sha256sum.txt"
        expected_sha=$(curl -fsSL "$checksum_url" 2>/dev/null | grep "${filename}" | awk '{print $1}')
    fi
    if [[ -n "$expected_sha" ]]; then
        local actual_sha
        actual_sha=$(sha256sum "${tmpdir}/${filename}" | awk '{print $1}')
        if [[ "$actual_sha" != "$expected_sha" ]]; then
            msg_error "SHA256 校验失败"
            rm -rf "$tmpdir"
            return 1
        fi
    else
        msg_dim "SHA256 校验文件不可用，跳过"
    fi

    # Backup old binary
    [[ -f "$XRAY_BIN" ]] && cp "$XRAY_BIN" "${XRAY_BIN}.bak"

    # Extract and install
    unzip -o "${tmpdir}/${filename}" -d "${tmpdir}/xray" >/dev/null
    chmod +x "${tmpdir}/xray/xray"
    cp "${tmpdir}/xray/xray" "$XRAY_BIN"

    # Install geo files
    mkdir -p /usr/local/share/xray
    [[ -f "${tmpdir}/xray/geoip.dat" ]] && cp "${tmpdir}/xray/geoip.dat" /usr/local/share/xray/
    [[ -f "${tmpdir}/xray/geosite.dat" ]] && cp "${tmpdir}/xray/geosite.dat" /usr/local/share/xray/

    rm -rf "$tmpdir"
    state_set_string ".runtimes.xray" "$version"
    msg_success "Xray v${version} 安装成功"
    return 0
}

rt_xray_update() {
    local current
    current=$(state_get ".runtimes.xray")
    if [[ -z "$current" || "$current" == "null" ]]; then
        msg_error "Xray 未安装"
        return 1
    fi

    local latest
    latest=$(github_latest_tag "$XRAY_REPO")

    if [[ "$current" == "$latest" ]]; then
        msg_success "Xray v${current} (最新)"
        return 0
    fi

    msg_info "更新 Xray ${current} → ${latest}..."
    rt_xray_install || return 1
    # Restart protocols that depend on Xray
    local xray_protos=("trojan" "vless-reality" "vless-vision" "vmess")
    for p in "${xray_protos[@]}"; do
        state_protocol_exists "$p" && service_restart "$p" 2>/dev/null
    done
    msg_success "相关服务已重启"
}

rt_xray_remove() {
    # Check if any Xray protocol is still installed
    local xray_protos=("trojan" "vless-reality" "vless-vision" "vmess")
    for p in "${xray_protos[@]}"; do
        if state_protocol_exists "$p"; then
            msg_warn "Xray 仍被 ${p} 使用，跳过删除"
            return 0
        fi
    done
    rm -f "$XRAY_BIN"
    rm -rf /usr/local/share/xray
    state_del ".runtimes.xray"
    msg_success "Xray 已删除"
}
