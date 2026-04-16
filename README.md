<div align="center">

<img src="assets/mizu-banner.png" alt="Mizu Banner" width="100%">

**Mizu**，取水之意。

*水润万物而不争，随势成形。*

故此项目亦以 **"化繁为简"** 为旨——将 Snell、Vless、Hysteria 等常见代理协议的部署、配置与启用，尽量归于 **一键完成**。使原本繁杂反复之事，变得清晰、顺手、可复用。

> 愿初学者见之不惧其难，熟练者用之亦省其功。
> 使每一次搭建都如行舟顺水，轻而能达，稳而不乱。

[![Version](https://img.shields.io/badge/version-26.4.16-blue.svg)](https://github.com/zhaodengfeng/mizu)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux-orange.svg)](#支持环境)

</div>

---

## 协议矩阵

<div align="center">

| 运行时 | 协议 | 原生程序 |
|:------:|:----:|----------|
| **Xray** | Trojan | Xray-core + Caddy（回落伪装） |
| **Xray** | VLESS+Reality | Xray-core |
| **Xray** | VLESS+Vision | Xray-core |
| **Xray** | VMess+WS | Xray-core |
| **sing-box** | ShadowTLS | sing-box |
| **sing-box** | AnyTLS | sing-box |
| **Hysteria** | Hysteria 2 | hysteria（端口跳跃 / Salamander） |
| **SS-Rust** | Shadowsocks 2022 | shadowsocks-rust |
| **Snell** | Snell v4 | snell-server |

</div>

## 特性

- **原生部署** — 直接下载各项目官方二进制，不依赖 Docker
- **双模式** — TUI 交互菜单 + CLI 命令行，适配不同使用场景
- **证书管理** — 自动申请/续期 Let's Encrypt 证书，支持 HTTP-01 和 DNS-01（Cloudflare / DNSPod / Aliyun）
- **安全加固** — systemd 沙箱隔离（NoNewPrivileges / ProtectSystem=strict）
- **状态管理** — JSON 状态文件 + flock 互斥锁，支持多协议并行安装
- **一键更新** — 运行时二进制独立更新，自动重启关联服务

## 支持环境

<div align="center">

| 发行版 | 版本 |
|:------:|:----:|
| Ubuntu | 20.04+ |
| Debian | 11+ |
| CentOS Stream | 8+ |
| Fedora | 38+ |
| AlmaLinux / Rocky Linux | 8+ |
| Alpine | 3.18+ |

架构: `x86_64 (amd64)` / `aarch64 (arm64)`

</div>

## 快速开始

```bash
# 一键安装
bash <(curl -fsSL https://raw.githubusercontent.com/zhaodengfeng/mizu/main/mizu.sh)

# 或克隆后运行
git clone https://github.com/zhaodengfeng/mizu.git /opt/mizu
bash /opt/mizu/mizu.sh
```

无参数运行进入 TUI 交互模式，按菜单操作即可。

## CLI 用法

```
mizu [命令] [参数]

命令:
  install <protocol> [domain]   安装协议
  info <protocol>               查看凭证与分享链接
  start <protocol>              启动服务
  stop <protocol>               停止服务
  restart <protocol>            重启服务
  regen <protocol>              重新生成凭证
  uninstall <protocol>          卸载协议
  update [runtime|all]          检查/执行运行时更新
  self-update                   更新 Mizu 脚本自身
  uninstall-all                 完全卸载 Mizu
  status                        状态总览
  help                          显示帮助

协议名称:
  trojan  vless-reality  vless-vision  vmess
  shadowtls  anytls  hysteria2  shadowsocks  snell
```

### 示例

```bash
# 安装 Trojan（需要域名）
mizu install trojan example.com

# 安装 VLESS+Reality（无需域名）
mizu install vless-reality

# 查看已安装协议的凭证
mizu info trojan

# 更新所有运行时
mizu update all
```

## 项目结构

```
mizu/
├── mizu.sh              # 主入口（TUI + CLI）
├── lib/
│   ├── common.sh        # 通用工具（状态管理、端口检测、密码生成）
│   ├── cert.sh          # 证书管理（acme.sh 封装、引用计数）
│   ├── service.sh       # systemd 服务管理
│   ├── detect.sh        # 环境检测与依赖安装
│   ├── menu.sh          # TUI 菜单渲染
│   ├── share-link.sh    # 分享链接生成
│   └── fallback-site.sh # Trojan 伪装站点生成
├── protocols/           # 9 个协议处理器（install/regen/uninstall）
├── runtimes/            # 6 个运行时下载器（xray/sing-box/hysteria/ss-rust/caddy/snell）
├── templates/           # HTML/CSS 模板
└── assets/              # Logo 与 Banner 资源
```

## 许可证

[MIT](LICENSE)
