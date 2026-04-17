# Mizu 上线前验证清单（GPT-5.4）

项目路径：`/Users/zdf/Documents/New project/mizu`  
检查日期：`2026-04-17`

## 目标

这份清单用于上线前的真实环境验收，重点验证：

- 服务权限模型是否真的可运行
- TLS 协议首次安装、重启、自启是否稳定
- 证书申请与续期回调是否可靠
- 分享链接、运行时更新、卸载流程是否一致
- 关键安全修复是否没有回归

## 使用建议

- 建议至少准备 2 台干净测试机：
  - Debian/Ubuntu 一台
  - RHEL 系（Rocky/Alma/CentOS Stream）一台
- 所有步骤尽量在 `root` 下执行
- 建议每次只装一个协议，验证完再清理
- 建议保留完整 `journalctl` 输出和安装终端日志

## 一、必须通过

### 1. 基础环境检查

- 确认系统使用 `systemd`
- 确认存在公网 IPv4
- 确认 `80/443`、测试协议端口、UDP 端口策略符合预期
- 确认机器时间同步正常

建议命令：

```bash
ps -p 1 -o comm=
timedatectl
ss -tulpn
```

通过标准：

- `PID 1` 为 `systemd`
- 系统时间同步正常
- 没有未知服务抢占计划使用的关键端口

### 2. 依赖检测与初始化

执行：

```bash
cd /opt/mizu
bash ./mizu.sh
```

通过标准：

- 首次初始化不报错
- `mizu` 组被成功创建
- `/var/log/mizu` 被创建
- `/etc/mizu/state.json` 被创建

建议检查：

```bash
getent group mizu
ls -ld /var/log/mizu
ls -l /etc/mizu/state.json
```

### 3. Trojan 首次安装验收

执行完整安装，使用真实可解析域名。

通过标准：

- `Caddy` 启动成功
- `mizu-trojan` 启动成功
- `systemctl is-active mizu-caddy mizu-trojan` 均为 `active`
- `trojan` 分享链接生成成功
- 伪装站点可访问

建议检查：

```bash
systemctl status mizu-caddy --no-pager
systemctl status mizu-trojan --no-pager
journalctl -u mizu-caddy -n 50 --no-pager
journalctl -u mizu-trojan -n 50 --no-pager
ls -ld /var/www/mizu /etc/mizu/caddy
ls -l /etc/mizu/caddy/Caddyfile
curl -I http://127.0.0.1:8080
```

重点确认：

- `/var/www/mizu` 与 `/etc/mizu/caddy` 对服务进程可读
- 严格 `umask` 环境下也不会因为站点或 `Caddyfile` 权限失败

### 4. TLS 协议首次安装与重启

至少验证以下协议：

- `trojan`
- `vless-vision`
- `anytls`
- `hysteria2`

每个协议都要执行：

```bash
systemctl restart mizu-<proto>
systemctl is-active mizu-<proto>
journalctl -u mizu-<proto> -n 50 --no-pager
```

通过标准：

- 首次安装后可启动
- 手动重启后仍可启动
- 无证书读取失败、配置权限失败、日志目录写入失败

### 5. 权限模型验收

至少检查一个 TLS 协议目录与一个证书目录。

建议检查：

```bash
namei -l /etc/mizu/tls/<domain>/<domain>.key
namei -l /etc/mizu/tls/<domain>/fullchain.cer
namei -l /etc/mizu/<proto>/config.json
systemctl cat mizu-<proto>
```

通过标准：

- 服务使用 `User=nobody`
- 服务使用 `Group=mizu`
- 服务单元包含 `UMask=0027`
- 配置文件与证书文件对 `mizu` 组可读
- 不再出现 `root:root 600/640` 导致的读取失败

### 6. 证书申请链路验收

分别验证两类场景：

- `80` 端口空闲时 HTTP-01
- `80` 端口被占用时提示改走 DNS-01

通过标准：

- `80` 被占用时不会再盲目猜测并停错服务
- HTTP-01 失败后切换 ZeroSSL 时，`webroot` 场景仍使用 `webroot`
- 证书安装完成后权限自动修正

建议检查：

```bash
ls -ld /etc/mizu/tls /etc/mizu/tls/<domain>
ls -l /etc/mizu/tls/<domain>
```

### 7. Hysteria2 输入校验验收

在安装或设置里测试以下输入：

- `20000-30000`
- `65535-65535`
- `abc-def`
- `1;rm -rf /`
- `70000-80000`
- `30000-20000`

通过标准：

- 只有合法 `start-end` 端口范围被接受
- 非法输入全部被拒绝
- 失败时不会继续写规则或继续安装

### 8. 开机自启验收

执行：

```bash
systemctl enable mizu-<proto>
reboot
systemctl is-active mizu-<proto>
```

如果安装了 Trojan，还要检查：

```bash
systemctl is-active mizu-caddy
```

通过标准：

- 重启后服务仍可自动起来
- 不出现“首次可用，重启失效”的权限回归

## 二、建议通过

### 9. 分享链接一致性

对支持分享链接的协议，安装完成后分别比较：

- 安装完成展示的链接
- `info` 输出中的链接
- `regen` 后重新写入的链接文件
- `/etc/mizu/share-links/<proto>.txt`

通过标准：

- 同一时刻多个入口看到的链接一致
- `regen` 后链接与新凭证一致

### 10. 运行时更新回归

分别测试：

- `xray`
- `sing-box`
- `hysteria`
- `shadowsocks-rust`
- `snell`
- `caddy`

通过标准：

- 下载失败或解压失败时旧二进制仍保留
- 更新成功后相关服务可正常重启
- `caddy` 更新后 Trojan 伪装站仍正常

### 11. 卸载清理

至少验证：

- 卸载单个 TLS 协议
- 卸载 `trojan`
- 全部卸载

通过标准：

- 服务单元被清理
- 相关配置目录被清理
- 状态文件对应节点被删除
- 不会误删仍被使用的 runtime

### 12. 续期回调

建议手动模拟一次 `reload-cert.sh` 调用：

```bash
/etc/mizu/reload-cert.sh <domain>
```

通过标准：

- 对使用该域名证书的服务能正常 reload 或 restart
- Trojan 场景下 `mizu-caddy` 可被正常重启
- 无 jq 注入或域名拼接异常

## 三、可选但推荐

### 13. 非默认 umask 验证

建议在 `umask 077` 下重新跑一次 Trojan 安装。

通过标准：

- `Caddy` 仍能正常启动
- 站点目录与 `Caddyfile` 权限仍满足读取要求

### 14. 多协议并存验证

建议组合测试：

- `trojan` + `hysteria2`
- `vless-vision` + `vmess`
- `shadowsocks` + `shadowtls`

通过标准：

- 互不覆盖状态
- 互不影响服务管理
- 批量启动/停止结果真实可靠

### 15. CI 本地补跑

建议执行：

```bash
find . -name '*.sh' -not -path '*/.git/*' -print0 | xargs -0 -n1 bash -n
shellcheck $(find . -name '*.sh' -not -path '*/.git/*')
```

通过标准：

- `bash -n` 全通过
- `shellcheck` 无新的高优先级告警

## 四、阻断上线项

以下任一项失败，都不建议上线：

- 任一 TLS 协议首次安装后无法启动
- 任一 TLS 协议重启后因权限问题失败
- 开机自启失败
- 证书申请在 `80` 端口占用时仍错误停服务
- Hysteria2 非法端口跳跃输入未被拒绝
- Trojan 的 `Caddy` 或伪装站点因权限问题无法启动

## 五、验收结论模板

可直接用下面模板记录结果：

```md
# Mizu 上线验收结果

- 验收时间：
- 系统版本：
- 内核版本：
- systemd 版本：

## 必须项
- 基础环境：通过 / 失败
- Trojan 安装：通过 / 失败
- TLS 首装与重启：通过 / 失败
- 权限模型：通过 / 失败
- 证书申请：通过 / 失败
- Hysteria2 输入校验：通过 / 失败
- 自启：通过 / 失败

## 建议项
- 分享链接一致性：通过 / 失败
- 运行时更新：通过 / 失败
- 卸载清理：通过 / 失败
- 续期回调：通过 / 失败

## 结论
- 是否建议上线：
- 阻断问题：
- 可延期问题：
```
