#!/usr/bin/env bash
# Mizu — Environment detection and dependency auto-install

[[ -n "${_MIZU_DETECT_SH_LOADED:-}" ]] && return 0
_MIZU_DETECT_SH_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ─── Required Dependencies ───────────────────────────────────────────────────
DEPS=("curl" "jq" "openssl" "unzip" "iptables" "tar" "gzip" "cron" "qrencode")

# ─── Package Install ──────────────────────────────────────────────────────────
pkg_install() {
    local pkgs=("$@")
    local pm
    pm=$(detect_pkg_manager)
    case "$pm" in
        apt)
            DEBIAN_FRONTEND=noninteractive \
            NEEDRESTART_MODE=a \
            apt-get install -y --no-install-recommends "${pkgs[@]}" 2>&1 | grep -v -E "^(Scanning|Pending|Running kernel|Diagnostics|The currently|Restarting|Service restarts|No containers|No user|No VM|debconf)"
            ;;
        dnf)
            dnf install -y "${pkgs[@]}"
            ;;
        yum)
            yum install -y "${pkgs[@]}"
            ;;
        apk)
            apk add "${pkgs[@]}"
            ;;
        *)
            msg_error "不支持的包管理器: $pm"
            return 1
            ;;
    esac
}

# ─── Check Single Dependency ─────────────────────────────────────────────────
check_dep() {
    local dep="$1"
    case "$dep" in
        curl) command -v curl &>/dev/null ;;
        jq) command -v jq &>/dev/null ;;
        openssl) command -v openssl &>/dev/null ;;
        unzip) command -v unzip &>/dev/null ;;
        iptables) command -v iptables &>/dev/null ;;
        tar) command -v tar &>/dev/null ;;
        gzip) command -v gzip &>/dev/null ;;
        acme.sh) [[ -f ~/.acme.sh/acme.sh ]] ;;
        cron) command -v crontab &>/dev/null ;;
        qrencode) command -v qrencode &>/dev/null ;;
        chrony) systemctl is-active chronyd &>/dev/null || systemctl is-active chrony &>/dev/null ;;
        systemd) pidof systemd &>/dev/null ;;
        *) command -v "$dep" &>/dev/null ;;
    esac
}

# ─── Install acme.sh ─────────────────────────────────────────────────────────
install_acme() {
    if [[ -f ~/.acme.sh/acme.sh ]]; then
        return 0
    fi
    msg_warn "acme.sh: 未安装 → 安装中..."
    curl -fsSL https://get.acme.sh | sh 2>/dev/null
    if [[ -f ~/.acme.sh/acme.sh ]]; then
        msg_success "acme.sh: 已自动安装"
        return 0
    fi
    msg_error "acme.sh: 安装失败"
    return 1
}

# ─── Install Chrony ──────────────────────────────────────────────────────────
install_chrony() {
    local pm
    pm=$(detect_pkg_manager)
    case "$pm" in
        apt) DEBIAN_FRONTEND=noninteractive apt-get install -y chrony ;;
        dnf) dnf install -y chrony ;;
        yum) yum install -y chrony ;;
        apk) apk add chrony ;;
    esac
    systemctl enable chronyd &>/dev/null
    systemctl start chronyd &>/dev/null
}

# ─── Full Environment Detection ──────────────────────────────────────────────
detect_environment() {
    clear_screen
    msg_info "Mizu — 环境检测"
    echo ""

    local failed=0
    local arch
    arch=$(detect_arch)

    # OS detection
    local os_name
    os_name=$(detect_os_full)
    local os_id
    os_id=$(detect_os)
    local supported_os=(ubuntu debian centos fedora almalinux rocky alpine)
    if [[ " ${supported_os[*]} " =~ " ${os_id} " ]]; then
        msg_success "操作系统: ${os_name} (支持)"
    else
        msg_warn "操作系统: ${os_name} (未经测试)"
    fi

    # Architecture
    if [[ "$arch" == "unsupported" ]]; then
        msg_error "架构: $(detect_arch_raw) (不支持)"
        ((failed++))
    else
        msg_success "架构:     $(detect_arch_raw) ($arch)"
    fi

    # systemd check
    if check_dep systemd; then
        msg_success "systemd:  已安装"
    else
        msg_error "systemd:  未检测到（不支持非 systemd 系统）"
        return 1
    fi

    # Package manager
    local pm
    pm=$(detect_pkg_manager)
    if [[ "$pm" != "unknown" ]]; then
        msg_success "包管理器: $pm"
    else
        msg_error "包管理器: 未识别"
        ((failed++))
    fi

    # Core dependencies
    local missing_pkgs=()
    for dep in "${DEPS[@]}"; do
        if check_dep "$dep"; then
            msg_success "${dep}:  已安装"
        else
            msg_warn "${dep}:  未安装 → 安装中..."
            local pkg_name="$dep"
            # Map to actual package names
            case "$dep" in
                jq) pkg_name="jq" ;;
                iptables) pkg_name="iptables" ;;
            esac
            missing_pkgs+=("$pkg_name")
        fi
    done

    if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
        msg_info "正在安装: ${missing_pkgs[*]}"
        echo ""
        pkg_install "${missing_pkgs[@]}" || true
        echo ""
        for dep in "${missing_pkgs[@]}"; do
            if check_dep "$dep"; then
                msg_success "${dep}:  已自动安装"
            else
                msg_error "${dep}:  安装失败"
                ((failed++))
            fi
        done
    fi

    # acme.sh
    if check_dep acme.sh; then
        msg_success "acme.sh:  已安装"
    else
        msg_info "安装 acme.sh (证书管理工具)..."
        if install_acme; then
            msg_success "acme.sh:  已安装"
        else
            msg_error "acme.sh:  安装失败"
            ((failed++))
        fi
    fi

    # NTP
    if check_dep chrony; then
        msg_success "NTP:      已同步 (chronyd)"
    else
        msg_info "NTP:      安装 chrony..."
        install_chrony
        if check_dep chrony; then
            msg_success "NTP:      已自动安装并启动"
        else
            msg_error "NTP:      安装失败"
            ((failed++))
        fi
    fi

    # Network
    local ipv4
    ipv4=$(detect_ipv4)
    if [[ -n "$ipv4" ]]; then
        msg_success "IPv4:     ${ipv4}"
    else
        msg_warn "IPv4:     未检测到"
    fi

    local ipv6
    ipv6=$(detect_ipv6)
    if [[ -n "$ipv6" ]]; then
        msg_success "IPv6:     ${ipv6}"
    else
        msg_dim "  ○ IPv6:     未检测到"
    fi

    echo ""
    if [[ $failed -eq 0 ]]; then
        msg_success "环境就绪"
    else
        msg_error "环境检测未通过，请解决上述问题后重试"
        return 1
    fi
    return 0
}
