#!/usr/bin/env bash
# Mizu — Fallback website generation for Trojan

[[ -n "${_MIZU_FALLBACK_SITE_SH_LOADED:-}" ]] && return 0
_MIZU_FALLBACK_SITE_SH_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SITE_DIR="/var/www/mizu"

# ─── Generate fake website ───────────────────────────────────────────────────
generate_site() {
    local domain="$1"

    mkdir -p "${SITE_DIR}/journal" "${SITE_DIR}/about" "${SITE_DIR}/css"

    # Site name from domain
    local site_name
    site_name=$(echo "$domain" | awk -F. '{if(NF>2) print substr($0, index($0,$2)); else print $0}')
    site_name=$(echo "$site_name" | sed 's/\b\(.\)/\u\1/g')

    # Copy CSS
    if [[ -f "${TEMPLATE_DIR}/site-styles.css" ]]; then
        cp "${TEMPLATE_DIR}/site-styles.css" "${SITE_DIR}/css/styles.css"
    else
        generate_css > "${SITE_DIR}/css/styles.css"
    fi

    # Generate index.html
    if [[ -f "${TEMPLATE_DIR}/site-index.html" ]]; then
        sed "s/{{SITE_NAME}}/${site_name}/g" "${TEMPLATE_DIR}/site-index.html" > "${SITE_DIR}/index.html"
    else
        generate_index "$site_name" "$domain" > "${SITE_DIR}/index.html"
    fi

    # Generate journal page
    if [[ -f "${TEMPLATE_DIR}/site-journal.html" ]]; then
        sed "s/{{SITE_NAME}}/${site_name}/g" "${TEMPLATE_DIR}/site-journal.html" > "${SITE_DIR}/journal/index.html"
    else
        generate_journal "$site_name" > "${SITE_DIR}/journal/index.html"
    fi

    # Generate about page
    if [[ -f "${TEMPLATE_DIR}/site-about.html" ]]; then
        sed "s/{{SITE_NAME}}/${site_name}/g" "${TEMPLATE_DIR}/site-about.html" > "${SITE_DIR}/about/index.html"
    else
        generate_about "$site_name" "$domain" > "${SITE_DIR}/about/index.html"
    fi

    # robots.txt
    cat > "${SITE_DIR}/robots.txt" <<EOF
User-agent: *
Allow: /
Sitemap: https://${domain}/sitemap.xml
EOF

    msg_success "伪装网站已生成"
}

# ─── Generate Caddy config ───────────────────────────────────────────────────
generate_caddy_config() {
    local domain="$1"
    local listen_port="${2:-8080}"
    local caddy_dir="/etc/mizu/caddy"

    mkdir -p "$caddy_dir"

    cat > "${caddy_dir}/Caddyfile" <<EOF
:${listen_port} {
    root * ${SITE_DIR}
    file_server
    encode gzip

    header {
        Server ""
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        X-XSS-Protection "1; mode=block"
        Referrer-Policy no-referrer-when-downgrade
    }

    log {
        output file /var/log/mizu/caddy.log
        format console
    }
}
EOF

    msg_success "Caddy 配置已生成"
}

# ─── Generate CSS ─────────────────────────────────────────────────────────────
generate_css() {
    cat <<'CSSEOF'
/* Mizu Fallback Site Styles */
:root {
    --color-bg: #faf9f7;
    --color-text: #2c2c2c;
    --color-accent: #8b4513;
    --color-link: #5b7a5e;
    --color-muted: #6b6b6b;
    --color-border: #e0ddd5;
    --font-serif: 'Georgia', 'Times New Roman', serif;
    --font-sans: 'Segoe UI', system-ui, sans-serif;
}

* { margin: 0; padding: 0; box-sizing: border-box; }

body {
    font-family: var(--font-serif);
    background: var(--color-bg);
    color: var(--color-text);
    line-height: 1.8;
    font-size: 16px;
}

.container {
    max-width: 1100px;
    margin: 0 auto;
    padding: 0 2rem;
}

header {
    border-bottom: 1px solid var(--color-border);
    padding: 1.5rem 0;
    margin-bottom: 2rem;
}

header h1 {
    font-size: 1.3rem;
    font-weight: 400;
    color: var(--color-accent);
    letter-spacing: 0.5px;
}

nav {
    margin-top: 0.5rem;
}

nav a {
    color: var(--color-muted);
    text-decoration: none;
    font-family: var(--font-sans);
    font-size: 0.85rem;
    margin-right: 1.5rem;
}

nav a:hover { color: var(--color-accent); }

main {
    display: grid;
    grid-template-columns: 2fr 1fr;
    gap: 3rem;
    padding-bottom: 3rem;
}

article {
    border-bottom: 1px solid var(--color-border);
    padding-bottom: 1.5rem;
    margin-bottom: 1.5rem;
}

article h2 {
    font-size: 1.2rem;
    font-weight: 400;
    margin-bottom: 0.5rem;
}

article h2 a {
    color: var(--color-text);
    text-decoration: none;
}

article h2 a:hover { color: var(--color-accent); }

.date {
    font-family: var(--font-sans);
    font-size: 0.8rem;
    color: var(--color-muted);
    margin-bottom: 0.8rem;
}

.excerpt {
    font-size: 0.95rem;
    color: var(--color-muted);
}

.sidebar h3 {
    font-size: 1rem;
    font-weight: 400;
    color: var(--color-accent);
    margin-bottom: 1rem;
    padding-bottom: 0.5rem;
    border-bottom: 1px solid var(--color-border);
}

.sidebar ul {
    list-style: none;
}

.sidebar li {
    padding: 0.4rem 0;
    font-size: 0.9rem;
}

.sidebar li a {
    color: var(--color-link);
    text-decoration: none;
}

.sidebar li a:hover { text-decoration: underline; }

footer {
    border-top: 1px solid var(--color-border);
    padding: 1.5rem 0;
    text-align: center;
    font-family: var(--font-sans);
    font-size: 0.8rem;
    color: var(--color-muted);
}

@media (max-width: 768px) {
    main { grid-template-columns: 1fr; gap: 2rem; }
    .container { padding: 0 1rem; }
}
CSSEOF
}

# ─── Generate Index Page ─────────────────────────────────────────────────────
generate_index() {
    local site_name="$1"
    local domain="$2"
    local dates=()
    local titles=()

    # Generate 6 recent "articles" with past dates
    for i in $(seq 0 5); do
        local d
        d=$(date -d "-$((i * 12 + RANDOM % 30)) days" "+%Y-%m-%d" 2>/dev/null || printf "2026-%02d-%02d" "$((RANDOM % 12 + 1))" "$((RANDOM % 28 + 1))")
        dates+=("$d")
    done

    cat <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${site_name}</title>
    <link rel="stylesheet" href="/css/styles.css">
</head>
<body>
<div class="container">
    <header>
        <h1>${site_name}</h1>
        <nav>
            <a href="/">Home</a>
            <a href="/journal/">Journal</a>
            <a href="/about/">About</a>
        </nav>
    </header>
    <main>
        <div class="posts">
            <article>
                <h2><a href="/journal/">Reflections on the Changing Season</a></h2>
                <div class="date">${dates[0]}</div>
                <p class="excerpt">The transition between seasons always brings a sense of renewal and contemplation. As the landscape transforms, we find ourselves drawn to quieter moments of reflection.</p>
            </article>
            <article>
                <h2><a href="/journal/">Notes on Craft and Practice</a></h2>
                <div class="date">${dates[1]}</div>
                <p class="excerpt">There is a certain satisfaction in honing one's craft over time. The small, consistent improvements accumulate into something meaningful and lasting.</p>
            </article>
            <article>
                <h2><a href="/journal/">Reading List for the Month</a></h2>
                <div class="date">${dates[2]}</div>
                <p class="excerpt">A curated selection of essays and long-form pieces that have caught our attention this month, spanning topics from design philosophy to natural history.</p>
            </article>
            <article>
                <h2><a href="/journal/">On Simplicity and Clarity</a></h2>
                <div class="date">${dates[3]}</div>
                <p class="excerpt">In a world of increasing complexity, the pursuit of simplicity becomes not just an aesthetic choice but a guiding principle for meaningful work.</p>
            </article>
        </div>
        <aside class="sidebar">
            <h3>Recent</h3>
            <ul>
                <li><a href="/journal/">Reflections on the Changing Season</a></li>
                <li><a href="/journal/">Notes on Craft and Practice</a></li>
                <li><a href="/journal/">Reading List for the Month</a></li>
                <li><a href="/journal/">On Simplicity and Clarity</a></li>
                <li><a href="/journal/">Thoughts on Digital Gardens</a></li>
                <li><a href="/journal/">A Walk Through the Neighborhood</a></li>
            </ul>
        </aside>
    </main>
    <footer>
        <p>&copy; $(date +%Y) ${site_name}. All rights reserved.</p>
    </footer>
</div>
</body>
</html>
EOF
}

# ─── Generate Journal Page ───────────────────────────────────────────────────
generate_journal() {
    local site_name="$1"
    cat <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Journal</title>
    <link rel="stylesheet" href="/css/styles.css">
</head>
<body>
<div class="container">
    <header>
        <h1>Journal</h1>
        <nav>
            <a href="/">Home</a>
            <a href="/journal/">Journal</a>
            <a href="/about/">About</a>
        </nav>
    </header>
    <main style="grid-template-columns: 1fr;">
        <div class="posts">
            <article><h2>Reflections on the Changing Season</h2><div class="date">March 2026</div><p class="excerpt">The transition between seasons always brings a sense of renewal and contemplation.</p></article>
            <article><h2>Notes on Craft and Practice</h2><div class="date">February 2026</div><p class="excerpt">There is a certain satisfaction in honing one's craft over time.</p></article>
            <article><h2>Reading List for the Month</h2><div class="date">February 2026</div><p class="excerpt">A curated selection of essays and long-form pieces.</p></article>
            <article><h2>On Simplicity and Clarity</h2><div class="date">January 2026</div><p class="excerpt">The pursuit of simplicity becomes a guiding principle for meaningful work.</p></article>
            <article><h2>Thoughts on Digital Gardens</h2><div class="date">January 2026</div><p class="excerpt">Exploring the metaphor of cultivation in how we organize our thoughts online.</p></article>
            <article><h2>A Walk Through the Neighborhood</h2><div class="date">December 2025</div><p class="excerpt">Sometimes the most ordinary walks yield the most extraordinary observations.</p></article>
        </div>
    </main>
    <footer><p>&copy; 2026 Journal. All rights reserved.</p></footer>
</div>
</body>
</html>
EOF
}

# ─── Generate About Page ─────────────────────────────────────────────────────
generate_about() {
    local site_name="$1"
    local domain="$2"
    cat <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>About</title>
    <link rel="stylesheet" href="/css/styles.css">
</head>
<body>
<div class="container">
    <header>
        <h1>${site_name}</h1>
        <nav>
            <a href="/">Home</a>
            <a href="/journal/">Journal</a>
            <a href="/about/">About</a>
        </nav>
    </header>
    <main style="grid-template-columns: 1fr;">
        <div>
            <h2>About</h2>
            <br>
            <p style="color: var(--color-muted); line-height: 1.9;">
                Welcome to ${site_name}. This is a small corner of the internet dedicated to thoughtful writing on topics that catch our interest. We believe in the value of slow, deliberate prose and the power of well-chosen words.
            </p>
            <br>
            <p style="color: var(--color-muted); line-height: 1.9;">
                If you'd like to get in touch, feel free to reach out through the usual channels. We're always happy to hear from fellow readers and writers.
            </p>
        </div>
    </main>
    <footer><p>&copy; $(date +%Y) ${site_name}. All rights reserved.</p></footer>
</div>
</body>
</html>
EOF
}

# ─── Remove site ─────────────────────────────────────────────────────────────
remove_site() {
    rm -rf "$SITE_DIR"
}
