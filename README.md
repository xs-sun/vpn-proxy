# vpn-proxy (Mac 内网穿透工具)

这是一个轻量级的 macOS VPN 隧道工具，利用 `tun2socks` 将 Mac 的特定网络流量通过 SOCKS5 代理转发到另一台设备（如 Windows 办公机）。

## 💡 适用场景

-   **办公网络受限**：公司内网 VPN 客户端仅支持 Windows，而你需要在 Mac 上办公。
-   **内网资源访问**：需要从 Mac 访问内网服务器、数据库、中间件等资源。

## 🚀 工作原理

1.  在 Windows (或其他设备) 上连接 VPN，并使用代理软件（如 v2rayN）开启 **允许局域网连接** 的 SOCKS5 代理。
2.  在 Mac 上运行此脚本，它会创建一个虚拟网卡 (如 `utun9`)。
3.  脚本会自动配置路由表，将目标网段（如 `10.0.0.0/8`）的流量路由到该虚拟网卡。
4.  `tun2socks` 进程捕获虚拟网卡流量，并通过 SOCKS5 协议转发到 Windows 机器的代理端口。

## 🛠️ 安装与配置

### 1. 准备工作

确认目录中包含以下文件：
- `proxy.sh`: 主控制脚本
- `tun2socks`: 隧道核心程序 (需适配 macOS)

### 2. 赋予执行权限

```bash
chmod +x ./proxy.sh
chmod +x ./tun2socks
```

### 3. 关键配置 (必读)

使用文本编辑器打开 `proxy.sh`，根据你的网络环境修改文件顶部的配置变量：

```bash
# =================配置区域=================

# 【重要】你的 Windows 机器在局域网的 IP 地址
WINDOWS_IP="192.168.3.3"

# 【重要】Windows 代理软件开放的 SOCKS5 端口
PROXY_PORT="10808"

# 虚拟网卡名称 (通常无需修改，如果冲突可改为 utun8, utun10 等)
TUN_DEV="utun9"

# 【重要】需要走代理的内网网段 (CIDR 格式)
# 只有访问这些网段的流量才会经过 VPN 隧道
TARGET_NETS=(
    "10.14.0.0/16"
)

# 需检测的具体业务端口 (用于 status 命令检查连通性)
CHECK_LIST=(
    "10.14.2.109:9876"
)
```

## 📖 使用说明

### 基本命令

脚本必须以 `sudo` 权限运行，因为需要修改系统网络配置。

```bash
sudo ./proxy.sh start     # 启动代理
sudo ./proxy.sh stop      # 停止代理
sudo ./proxy.sh restart   # 重启代理
sudo ./proxy.sh status    # 查看状态 & 连通性测试
sudo ./proxy.sh clean     # 清理日志
```

### 全局安装 (推荐)

安装后将注册为全局命令 `vproxy`，可以在任意目录下使用。

```bash
# 安装
sudo ./proxy.sh install

# 使用全局命令管理
sudo vproxy start
sudo vproxy status
sudo vproxy stop

# 卸载
sudo ./proxy.sh uninstall
```

## ❓ 常见问题

1.  **无法运行/权限被拒绝**：
    -   确保已使用 `chmod +x` 赋予脚本和二进制文件执行权限。
    -   必须使用 `sudo` 运行脚本。

2.  **"无法打开 tun2socks，因为无法验证开发者"**：
    -   这是 macOS 的安全机制。首次运行需要解除隔离：
        ```bash
        sudo xattr -d com.apple.quarantine tun2socks
        ```
    -   或者在 "系统偏好设置 -> 安全性与隐私" 中点击 "仍要打开"。

3.  **如何查看日志？**
    -   日志文件位于脚本同级目录的 `logs/tun2socks.log`。
    -   使用 `tail -f logs/tun2socks.log` 实时查看。

## 📜 License

MIT