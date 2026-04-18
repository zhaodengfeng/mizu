#!/usr/bin/env bash
# Mizu — sing-box runtime (2 protocols: ShadowTLS, AnyTLS)

[[ -n "${_MIZU_RT_SINGBOX_LOADED:-}" ]] && return 0
_MIZU_RT_SINGBOX_LOADED=1

SINGBOX_REPO="SagerNet/sing-box"
SINGBOX_BIN="/usr/local/bin/sing-box"

rt_singbox_install() {
    local arch
    arch=$(detect_arch)
    if [[ "$arch" == "unsupported" ]]; then
        msg_error "不支持的架构"
        return 1
    fi

    local version
    version=$(github_latest_tag "$SINGBOX_REPO")
    if [[ -z "$version" ]]; then
        msg_error "获取 sing-box 版本失败"
        return 1
    fi

    local current
    current=$(state_get ".runtimes.sing-box")
    if [[ "$current" == "$version" ]]; then
        msg_success "sing-box v${version} 已是最新版本"
        return 0
    fi

    msg_info "安装 sing-box v${version}..."

    # sing-box uses different naming convention
    local download_arch="$arch"
    local filename="sing-box-${version}-linux-${download_arch}.tar.gz"
    local url="https://github.com/${SINGBOX_REPO}/releases/download/v${version}/${filename}"

    local tmpdir
    tmpdir=$(mktemp -d)
    if ! download_file "$url" "${tmpdir}/${filename}"; then
        # Try alternative naming
        filename="sing-box-${version}.linux-${download_arch}.tar.gz"
        url="https://github.com/${SINGBOX_REPO}/releases/download/v${version}/${filename}"
        if ! download_file "$url" "${tmpdir}/${filename}"; then
            msg_error "sing-box 下载失败"
            rm -rf "$tmpdir"
            return 1
        fi
    fi

    # SHA256 verification
    local shasum_url="https://github.com/${SINGBOX_REPO}/releases/download/v${version}/sing-box-${version}.checksums.txt"
    if download_file "$shasum_url" "${tmpdir}/checksums.txt" 2>/dev/null; then
        local expected actual
        expected=$(grep "$(basename "${tmpdir}/${filename}")" "${tmpdir}/checksums.txt" | awk '{print $1}')
        actual=$(sha256sum "${tmpdir}/${filename}" | awk '{print $1}')
        if [[ -n "$expected" && "$expected" != "$actual" ]]; then
            msg_error "sing-box SHA256 校验失败"
            rm -rf "$tmpdir"
            return 1
        fi
        msg_success "SHA256 校验通过"
    else
        msg_warn "未找到校验文件，跳过 SHA256 验证"
    fi

    # Backup
    local backup_bin=""
    if [[ -f "$SINGBOX_BIN" ]]; then
        backup_bin="${SINGBOX_BIN}.bak"
        cp "$SINGBOX_BIN" "$backup_bin"
    fi

    # Extract and install
    if ! tar -xzf "${tmpdir}/${filename}" -C "${tmpdir}" >/dev/null; then
        [[ -n "$backup_bin" && -f "$backup_bin" ]] && cp "$backup_bin" "$SINGBOX_BIN"
        rm -rf "$tmpdir"
        msg_error "sing-box 解压失败，已恢复旧版本"
        return 1
    fi
    local singbox_file
    singbox_file=$(find "${tmpdir}" -name "sing-box" -type f | head -1)
    if [[ -z "$singbox_file" ]]; then
        [[ -n "$backup_bin" && -f "$backup_bin" ]] && cp "$backup_bin" "$SINGBOX_BIN"
        msg_error "sing-box 二进制未找到"
        rm -rf "$tmpdir"
        return 1
    fi
    chmod +x "$singbox_file"
    if ! cp "$singbox_file" "$SINGBOX_BIN"; then
        [[ -n "$backup_bin" && -f "$backup_bin" ]] && cp "$backup_bin" "$SINGBOX_BIN"
        rm -rf "$tmpdir"
        msg_error "sing-box 安装失败，已恢复旧版本"
        return 1
    fi

    rm -rf "$tmpdir"
    state_set_string ".runtimes.sing-box" "$version"
    msg_success "sing-box v${version} 安装成功"
    return 0
}

rt_singbox_update() {
    local current
    current=$(state_get ".runtimes.sing-box")
    if [[ -z "$current" || "$current" == "null" ]]; then
        msg_error "sing-box 未安装"
        return 1
    fi

    local latest
    latest=$(github_latest_tag "$SINGBOX_REPO")

    if [[ "$current" == "$latest" ]]; then
        msg_success "sing-box v${current} (最新)"
        return 0
    fi

    msg_info "更新 sing-box ${current} → ${latest}..."
    rt_singbox_install || return 1
    local singbox_protos=("shadowtls" "anytls")
    restart_protocols_verified "${singbox_protos[@]}" || return 1
    msg_success "相关服务已重启"
}

rt_singbox_remove() {
    local singbox_protos=("shadowtls" "anytls")
    for p in "${singbox_protos[@]}"; do
        if state_protocol_exists "$p"; then
            msg_warn "sing-box 仍被 ${p} 使用，跳过删除"
            return 0
        fi
    done
    rm -f "$SINGBOX_BIN"
    state_del ".runtimes.sing-box"
    msg_success "sing-box 已删除"
}
