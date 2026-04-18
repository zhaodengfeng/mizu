#!/usr/bin/env bash
# Mizu — Certificate management with acme.sh
# Supports: HTTP-01, DNS-01 (Cloudflare, AliDNS, DP, Cloudns, LuaDNS, etc.)

[[ -n "${_MIZU_CERT_SH_LOADED:-}" ]] && return 0
_MIZU_CERT_SH_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

CERT_DIR="/etc/mizu/tls"
CERT_MAP="/etc/mizu/tls/cert-map.json"
RELOAD_CERT_SCRIPT="/etc/mizu/reload-cert.sh"

# ─── DNS provider config ─────────────────────────────────────────────────────
DNS_PROVIDERS=(
    "cloudflare"
    "dns_ali"
    "dns_dp"
    "dns_cloudns"
    "dns_lua"
    "dns_gd"
    "dns_namecheap"
    "dns_route53"
)

declare -A DNS_PROVIDER_NAMES=(
    ["cloudflare"]="Cloudflare"
    ["dns_ali"]="阿里云 DNS"
    ["dns_dp"]="DNSPod (腾讯云)"
    ["dns_cloudns"]="ClouDNS"
    ["dns_lua"]="LuaDNS"
    ["dns_gd"]="GoDaddy"
    ["dns_namecheap"]="Namecheap"
    ["dns_route53"]="AWS Route53"
)

# Required env vars per provider
declare -A DNS_ENV_VARS=(
    ["cloudflare"]="CF_Token:CF_Zone_ID"
    ["dns_ali"]="Ali_Key:Ali_Secret"
    ["dns_dp"]="DP_Id:DP_Key"
    ["dns_cloudns"]="CLOUDNS_SUB_AUTH_ID:CLOUDNS_AUTH_PASSWORD"
    ["dns_lua"]="LUA_Email:LUA_Key"
    ["dns_gd"]="GD_Key:GD_Secret"
    ["dns_namecheap"]="NAMECHEAP_USERNAME:NAMECHEAP_API_KEY"
    ["dns_route53"]="AWS_ACCESS_KEY_ID:AWS_SECRET_ACCESS_KEY"
)

declare -A DNS_ENV_PROMPTS=(
    ["cloudflare"]="CF_Token:API Token:;CF_Zone_ID:Zone ID:"
    ["dns_ali"]="Ali_Key:Access Key ID:;Ali_Secret:Access Key Secret:"
    ["dns_dp"]="DP_Id:Account ID:;DP_Key:API Token:"
    ["dns_cloudns"]="CLOUDNS_SUB_AUTH_ID:Sub Auth ID:;CLOUDNS_AUTH_PASSWORD:Auth Password:"
    ["dns_lua"]="LUA_Email:Email:;LUA_Key:API Key:"
    ["dns_gd"]="GD_Key:API Key:;GD_Secret:API Secret:"
    ["dns_namecheap"]="NAMECHEAP_USERNAME:Username:;NAMECHEAP_API_KEY:API Key:"
    ["dns_route53"]="AWS_ACCESS_KEY_ID:Access Key ID:;AWS_SECRET_ACCESS_KEY:Secret Access Key:"
)

# ─── Init cert directory ─────────────────────────────────────────────────────
cert_init() {
    ensure_mizu_service_group || return 1
    mkdir -p "$CERT_DIR"
    if [[ ! -f "$CERT_MAP" ]]; then
        echo '{}' > "$CERT_MAP"
    fi
    _install_reload_cert_script
}

# ─── Install certificate reload helper script ─────────────────────────────────
_install_reload_cert_script() {
    mkdir -p /etc/mizu
    cat > "$RELOAD_CERT_SCRIPT" <<'SCRIPTEOF'
#!/usr/bin/env bash
# Reload services that use a given domain's certificate
domain="$1"
if [[ -z "$domain" || "$domain" =~ [^a-zA-Z0-9._-] ]]; then
    echo "Invalid domain" >&2; exit 1
fi
STATE_FILE="/etc/mizu/state.json"
if [[ ! -f "$STATE_FILE" ]]; then exit 0; fi
while IFS= read -r svc; do
    case "$svc" in
        trojan|vless-vision|vmess)
            systemctl reload "mizu-${svc}" 2>/dev/null || systemctl restart "mizu-${svc}" 2>/dev/null
            ;;
        *)
            systemctl restart "mizu-${svc}" 2>/dev/null
            ;;
    esac
done < <(jq -r --arg d "$domain" '.protocols | to_entries[] | select(.value.domain == $d) | .key' "$STATE_FILE" 2>/dev/null)
# Reload Caddy if trojan uses this domain
while IFS= read -r svc; do
    systemctl restart mizu-caddy 2>/dev/null
done < <(jq -r --arg d "$domain" '.protocols | to_entries[] | select(.value.domain == $d and .key == "trojan") | .key' "$STATE_FILE" 2>/dev/null)
SCRIPTEOF
    chmod 700 "$RELOAD_CERT_SCRIPT"
}

# ─── Check existing certificate ──────────────────────────────────────────────
cert_exists() {
    local domain="$1"
    [[ -f "${CERT_DIR}/${domain}/fullchain.cer" && -f "${CERT_DIR}/${domain}/${domain}.key" ]]
}

# ─── Get certificate expiry date ─────────────────────────────────────────────
cert_expiry() {
    local domain="$1"
    local cer="${CERT_DIR}/${domain}/fullchain.cer"
    if [[ -f "$cer" ]]; then
        openssl x509 -enddate -noout -in "$cer" 2>/dev/null | cut -d= -f2
    fi
}

# ─── Days until expiry ───────────────────────────────────────────────────────
cert_days_remaining() {
    local domain="$1"
    local expiry
    expiry=$(cert_expiry "$domain")
    if [[ -n "$expiry" ]]; then
        local expiry_epoch now_epoch
        expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$expiry" +%s 2>/dev/null)
        now_epoch=$(date +%s)
        echo $(( (expiry_epoch - now_epoch) / 86400 ))
    fi
}

# ─── Register acme account ───────────────────────────────────────────────────
acme_register() {
    if [[ ! -f "${ACME_HOME}/acme.sh" ]]; then
        msg_error "acme.sh 未安装"
        return 1
    fi
}

# ─── Interactive DNS provider selection ──────────────────────────────────────
prompt_dns_provider() {
    msg_info "选择 DNS 验证方式" >&2
    echo "" >&2
    printf "${C_WHITE}  [1] Cloudflare${C_RESET}\n" >&2
    printf "${C_WHITE}  [2] 阿里云 DNS${C_RESET}\n" >&2
    printf "${C_WHITE}  [3] DNSPod (腾讯云)${C_RESET}\n" >&2
    printf "${C_WHITE}  [4] ClouDNS${C_RESET}\n" >&2
    printf "${C_WHITE}  [5] LuaDNS${C_RESET}\n" >&2
    printf "${C_WHITE}  [6] GoDaddy${C_RESET}\n" >&2
    printf "${C_WHITE}  [7] Namecheap${C_RESET}\n" >&2
    printf "${C_WHITE}  [8] AWS Route53${C_RESET}\n" >&2
    printf "${C_WHITE}  [0] 返回${C_RESET}\n" >&2
    echo "" >&2
    printf "请选择: " >&2

    local dns_providers=("cloudflare" "dns_ali" "dns_dp" "dns_cloudns" "dns_lua" "dns_gd" "dns_namecheap" "dns_route53")

    read -r dns_choice
    local idx=$((dns_choice - 1))
    if [[ $idx -ge 0 && $idx -lt ${#dns_providers[@]} ]]; then
        echo "${dns_providers[$idx]}"
    else
        echo ""
    fi
}

# ─── Prompt for DNS env vars ─────────────────────────────────────────────────
prompt_dns_env() {
    local provider="$1"
    local prompt_spec="${DNS_ENV_PROMPTS[$provider]}"

    # prompt_spec format: "VAR1:Prompt1:;VAR2:Prompt2:"
    IFS=';' read -ra pairs <<< "$prompt_spec"
    for pair in "${pairs[@]}"; do
        local var_name prompt_text
        IFS=':' read -r var_name prompt_text _ <<< "$pair"
        if [[ -z "$prompt_text" ]]; then
            prompt_text="$var_name"
        fi
        printf "${C_WHITE}  %s: ${C_RESET}" "$prompt_text"
        read -rs val
        echo
        export "$var_name=$val"
    done
}

# ─── Save DNS provider config for renewal ────────────────────────────────────
save_dns_config() {
    local domain="$1"
    local provider="$2"
    local conf_file="${CERT_DIR}/${domain}/dns-provider.conf"
    cat > "$conf_file" <<EOF
# Mizu DNS provider config for ${domain}
DNS_PROVIDER=${provider}
EOF
    # Save env var names (not values — those are in acme.sh config)
    local env_vars="${DNS_ENV_VARS[$provider]}"
    echo "DNS_ENV_VARS=${env_vars}" >> "$conf_file"
}

# ─── Issue via DNS-01 ────────────────────────────────────────────────────────
cert_issue_dns() {
    local domain="$1"
    local provider="$2"

    msg_warn "使用 DNS-01 验证 (${DNS_PROVIDER_NAMES[$provider]})..."

    # Prompt for credentials
    prompt_dns_env "$provider"

    # Prompt for email (only once per session)
    if [[ -z "${_MIZU_ACME_EMAIL:-}" ]]; then
        printf "${C_WHITE}请输入邮箱 (用于证书到期提醒): ${C_RESET}" >&2
        read -r _MIZU_ACME_EMAIL
        export _MIZU_ACME_EMAIL
    fi

    # Register account in isolated ACME_HOME
    "${ACME_HOME}/acme.sh" --home "${ACME_HOME}" --register-account -m "$_MIZU_ACME_EMAIL" --server letsencrypt 2>/dev/null

    # Issue with DNS
    if "${ACME_HOME}/acme.sh" --home "${ACME_HOME}" --issue -d "$domain" --keylength ec-256 --dns "$provider" --server letsencrypt 2>/dev/null; then
        msg_success "证书申请成功 (DNS-01)"
    else
        # Try ZeroSSL
        msg_warn "Let's Encrypt 失败，尝试 ZeroSSL..."
        if "${ACME_HOME}/acme.sh" --home "${ACME_HOME}" --issue -d "$domain" --keylength ec-256 --dns "$provider" --server zerossl 2>/dev/null; then
            msg_success "证书申请成功 (ZeroSSL + DNS-01)"
        else
            msg_error "DNS-01 证书申请失败"
            return 1
        fi
    fi

    # Install certificate
    mkdir -p "${CERT_DIR}/${domain}"
    if ! "${ACME_HOME}/acme.sh" --home "${ACME_HOME}" --install-cert -d "$domain" --ecc \
        --fullchain-file "${CERT_DIR}/${domain}/fullchain.cer" \
        --key-file "${CERT_DIR}/${domain}/${domain}.key" \
        --reloadcmd "${RELOAD_CERT_SCRIPT} ${domain}" \
        2>/dev/null; then
        msg_error "证书安装失败"
        return 1
    fi
    if [[ ! -s "${CERT_DIR}/${domain}/fullchain.cer" || ! -s "${CERT_DIR}/${domain}/${domain}.key" ]]; then
        msg_error "证书文件缺失或为空"
        return 1
    fi

    save_dns_config "$domain" "$provider"
    msg_success "证书已安装到 ${CERT_DIR}/${domain}/"
    cert_ref_add "$domain"
    _fix_cert_permissions "$domain"
    return 0
}

# ─── Issue new certificate (main entry) ──────────────────────────────────────
cert_issue() {
    local domain="$1"
    local webroot="${2:-}"
    local force_dns="${3:-}"  # "dns" to force DNS-01

    cert_init

    _fix_cert_permissions_all

    # Check if certificate already exists
    if cert_exists "$domain"; then
        local days
        days=$(cert_days_remaining "$domain")
        msg_success "发现已有证书: ${domain} (到期 $(cert_expiry "$domain"), 还有 ${days} 天)"

        if prompt_yesno "继续使用该证书?" "Y"; then
            msg_success "使用已有证书"
            cert_ref_add "$domain"
            return 0
        fi
    fi

    # If force_dns is set, go directly to DNS-01
    if [[ "$force_dns" == "dns" ]]; then
        local provider
        provider=$(prompt_dns_provider)
        [[ -z "$provider" ]] && return 1
        cert_issue_dns "$domain" "$provider"
        return $?
    fi

    # Issue new certificate — try HTTP-01 first
    msg_warn "正在申请证书: ${domain}..."

    # Prompt for email (only once per session)
    if [[ -z "${_MIZU_ACME_EMAIL:-}" ]]; then
        printf "${C_WHITE}请输入邮箱 (用于证书到期提醒): ${C_RESET}" >&2
        read -r _MIZU_ACME_EMAIL
        export _MIZU_ACME_EMAIL
    fi

    # Register account in isolated ACME_HOME
    "${ACME_HOME}/acme.sh" --home "${ACME_HOME}" --register-account -m "$_MIZU_ACME_EMAIL" --server letsencrypt 2>/dev/null

    local issue_args=(
        --home "${ACME_HOME}"
        --issue
        -d "$domain"
        --keylength ec-256
        --server letsencrypt
    )

    if [[ -n "$webroot" ]]; then
        issue_args+=(--webroot "$webroot")
    else
        if port_in_use 80; then
            msg_warn "检测到 80 端口已被占用，无法安全使用 HTTP-01 standalone"
            printf "${C_WHITE}  证书申请方式:${C_RESET}\n"
            printf "${C_WHITE}  [1] 改用 DNS-01 验证 (推荐)${C_RESET}\n"
            printf "${C_WHITE}  [0] 取消${C_RESET}\n"
            printf "请选择: "
            read -r port80_choice

            case "$port80_choice" in
                1)
                    local provider
                    provider=$(prompt_dns_provider)
                    if [[ -n "$provider" ]]; then
                        cert_issue_dns "$domain" "$provider"
                        return $?
                    fi
                    msg_error "已取消"
                    return 1
                    ;;
                *)
                    msg_dim "已取消"
                    return 1
                    ;;
            esac
        fi
        issue_args+=(--standalone)
    fi

    local cert_output
    cert_output=$("${ACME_HOME}/acme.sh" "${issue_args[@]}" 2>&1)
    if [[ $? -eq 0 ]]; then
        msg_success "证书申请成功 (HTTP-01)"
    else
        # HTTP-01 failed — show error and offer DNS-01
        msg_warn "HTTP-01 验证失败"
        # Show last few lines of acme output for diagnosis
        echo "$cert_output" | grep -i -E "error|fail|timeout|refused|connect|dns" | tail -3 | while read -r line; do
            msg_dim "  $line"
        done
        echo ""
        printf "${C_WHITE}  证书申请方式:${C_RESET}\n"
        printf "${C_WHITE}  [1] 改用 DNS-01 验证 (推荐)${C_RESET}\n"
        printf "${C_WHITE}  [2] 重试 ZeroSSL (HTTP-01)${C_RESET}\n"
        printf "${C_WHITE}  [0] 取消${C_RESET}\n"
        printf "请选择: "
        read -r cert_choice

        case "$cert_choice" in
            1)
                local provider
                provider=$(prompt_dns_provider)
                if [[ -n "$provider" ]]; then
                    cert_issue_dns "$domain" "$provider"
                    return $?
                fi
                msg_error "已取消"
                return 1
                ;;
            2)
                msg_warn "尝试 ZeroSSL..."
                local zerossl_output
                local retry_args=(
                    --home "${ACME_HOME}"
                    --issue
                    -d "$domain"
                    --keylength ec-256
                    --server zerossl
                )
                if [[ -n "$webroot" ]]; then
                    retry_args+=(--webroot "$webroot")
                else
                    retry_args+=(--standalone)
                fi
                "${ACME_HOME}/acme.sh" --home "${ACME_HOME}" --register-account -m "${_MIZU_ACME_EMAIL:-}" --server zerossl 2>/dev/null
                zerossl_output=$("${ACME_HOME}/acme.sh" "${retry_args[@]}" 2>&1)
                if [[ $? -eq 0 ]]; then
                    msg_success "证书申请成功 (ZeroSSL)"
                else
                    msg_error "ZeroSSL 申请失败"
                    echo "$zerossl_output" | grep -i -E "error|fail|timeout|refused|connect" | tail -3 | while read -r line; do
                        msg_dim "  $line"
                    done
                    return 1
                fi
                ;;
            *)
                msg_dim "已取消"
                return 1
                ;;
        esac
    fi

    # Install certificate
    mkdir -p "${CERT_DIR}/${domain}"
    if ! "${ACME_HOME}/acme.sh" --home "${ACME_HOME}" --install-cert -d "$domain" --ecc \
        --fullchain-file "${CERT_DIR}/${domain}/fullchain.cer" \
        --key-file "${CERT_DIR}/${domain}/${domain}.key" \
        --reloadcmd "${RELOAD_CERT_SCRIPT} ${domain}" \
        2>/dev/null; then
        msg_error "证书安装失败"
        return 1
    fi
    if [[ ! -s "${CERT_DIR}/${domain}/fullchain.cer" || ! -s "${CERT_DIR}/${domain}/${domain}.key" ]]; then
        msg_error "证书文件缺失或为空"
        return 1
    fi

    msg_success "证书已安装到 ${CERT_DIR}/${domain}/"
    cert_ref_add "$domain"
    _fix_cert_permissions "$domain"

    return 0
}

# ─── Certificate permission helpers ───────────────────────────────────────────
_fix_cert_permissions() {
    local domain="$1"
    local dir="${CERT_DIR}/${domain}"
    [[ ! -d "$dir" ]] && return
    ensure_mizu_service_group || return 1
    local group
    group=$(mizu_service_group)
    chgrp "$group" "${CERT_DIR}" 2>/dev/null || true
    chmod 750 "${CERT_DIR}" 2>/dev/null || true
    chgrp -R "$group" "$dir" 2>/dev/null || true
    find "$dir" -type d -exec chmod 750 {} \; 2>/dev/null
    find "$dir" -name 'fullchain.cer' -exec chmod 640 {} \; 2>/dev/null
    find "$dir" -name '*.key' -exec chmod 640 {} \; 2>/dev/null
    find "$dir" -name '*.cer' ! -name 'fullchain.cer' -exec chmod 640 {} \; 2>/dev/null
}

_fix_cert_permissions_all() {
    [[ ! -d "${CERT_DIR}" ]] && return
    ensure_mizu_service_group || return 1
    local group
    group=$(mizu_service_group)
    chgrp -R "$group" "${CERT_DIR}" 2>/dev/null || true
    find "${CERT_DIR}" -type d -exec chmod 750 {} \; 2>/dev/null
    find "${CERT_DIR}" -name 'fullchain.cer' -exec chmod 640 {} \; 2>/dev/null
    find "${CERT_DIR}" -name '*.cer' ! -name 'fullchain.cer' -exec chmod 640 {} \; 2>/dev/null
    find "${CERT_DIR}" -name '*.key' -exec chmod 640 {} \; 2>/dev/null
}

# ─── Certificate reference counting ──────────────────────────────────────────
cert_ref_add() {
    local domain="$1"
    (
        flock -x 200
        local count
        count=$(jq -r --arg d "$domain" '.[$d] // 0' "$CERT_MAP")
        jq --arg d "$domain" --argjson c $((count + 1)) '.[$d] = $c' "$CERT_MAP" > "${CERT_MAP}.tmp" \
            && mv "${CERT_MAP}.tmp" "$CERT_MAP"
    ) 200>"${CERT_MAP}.lock"
}

cert_ref_del() {
    local domain="$1"
    [[ -z "$domain" || "$domain" == "null" ]] && return 0
    (
        flock -x 200
        local count
        count=$(jq -r --arg d "$domain" '.[$d] // 0' "$CERT_MAP")
        if [[ $count -le 1 ]]; then
            jq --arg d "$domain" 'del(.[$d])' "$CERT_MAP" > "${CERT_MAP}.tmp" \
                && mv "${CERT_MAP}.tmp" "$CERT_MAP"
        else
            jq --arg d "$domain" --argjson c $((count - 1)) '.[$d] = $c' "$CERT_MAP" > "${CERT_MAP}.tmp" \
                && mv "${CERT_MAP}.tmp" "$CERT_MAP"
        fi
    ) 200>"${CERT_MAP}.lock"
}

# ─── Get cert paths ──────────────────────────────────────────────────────────
cert_path() {
    local domain="$1"
    echo "${CERT_DIR}/${domain}"
}

cert_fullchain() {
    local domain="$1"
    echo "${CERT_DIR}/${domain}/fullchain.cer"
}

cert_key() {
    local domain="$1"
    echo "${CERT_DIR}/${domain}/${domain}.key"
}
