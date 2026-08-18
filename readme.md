# loginfopush

> 通过读取 `/var/log/auth.log` / `/var/log/secure` / `/var/log/fail2ban.log` 文件，监听登录与封禁事件，并推送到 **Telegram** 通知渠道。
>
> 本项目为 [wanterfont/loginfopush](https://github.com/wanterfont/loginfopush) 的复刻精简版，仅保留 Telegram 渠道并支持一键非交互安装。

---

## 使用

一键安装（非交互，直接提供 Telegram 参数即可）：

```bash
curl -fsSL https://jiam9069.github.io/loginfopush/install.sh -o install.sh && bash install.sh \
  --tg-webhook 'https://api.telegram.org/bot<token>/sendMessage' \
  --tg-chatid '<chat_id>' \
  --server-name '服务器名称' \
  --server-tag '服务器标签'
```

安装脚本会自动完成以下前置准备：
1. `apt install rsyslog fail2ban -y`
2. `touch /var/log/auth.log /var/log/secure /var/log/fail2ban.log`
3. 下载并部署二进制、生成 Telegram-only 配置、注册并启动 systemd 服务。

> 说明：`--server-name` 与 `--server-tag` 可省略，缺省时自动取主机名 / 公网 IP 定位，全程不会交互提问。

### Telegram 机器人

1. 通过 [@BotFather](https://t.me/BotFather) 创建机器人，获得 `token`。
2. 获取你的 `chat_id`。
3. webhook 格式如下（token 替换成你的）：

```
https://api.telegram.org/bot<token>/sendMessage
```

消息内容参考：
> ✅ 服务器: my-server (CN)
> IP: 47.108.2.1 登录成功
> 时间: 2025-01-26 22:52:03
> 位置: China-NanJing
> 详情: IP 47.108.2.1[China-NanJing] 密钥登录成功

---

## 简介

一个服务器安全事件通知系统，监控登录尝试、封禁等安全事件，并通过 Telegram 推送。

## 功能特点

- Telegram 单渠道通知
- 可配置的事件类型
  - 登录成功通知
  - 登录失败警告
  - IP 封禁提醒
- 自定义消息模板

## 事件类型

1. **封禁通知 (ban)** — 当 IP 被封禁时触发，图标 🚫
2. **登录失败通知 (login_failure)** — 当登录失败时触发，图标 ⚠️
3. **登录成功通知 (login_success)** — 当登录成功时触发，图标 ✅

## 配置

配置文件位于 `/opt/loginfopush/config/config.json`:

```json
{
  "server": { "name": "MyServer", "tag": "tags" },
  "notifiers": {
    "telegram": {
      "type": "telegram",
      "enabled": true,
      "config": {
        "webhook_url": "https://api.telegram.org/botxxx/sendMessage",
        "chat_id": "xxx"
      }
    }
  },
  "events": { ... }
}
```

## 消息模板变量

所有事件消息模板支持以下变量：
- `{{.Server.Name}}`: 服务器名称
- `{{.Server.Tag}}`: 服务器标签
- `{{.IP}}`: 触发事件的 IP 地址
- `{{.Time}}`: 事件发生时间
- `{{.Location}}`: IP 地理位置
- `{{.Details}}`: 详细信息

## 服务管理

```bash
systemctl status loginfopush   # 查看状态
journalctl -u loginfopush -f   # 查看日志
systemctl restart loginfopush  # 重启
```

## 注意事项
- 请妥善保管 Telegram token
- 需要 root 权限安装（写入 /opt 与 systemd）
- 依赖 Debian/Ubuntu 系 `apt` 包管理器