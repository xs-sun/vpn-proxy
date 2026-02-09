#!/bin/bash

# =================配置区域=================
# 获取脚本所在的实际绝对路径
# 获取脚本真实的物理路径（完美处理软链接情况）
SOURCE="$0"
while [ -h "$SOURCE" ]; do
    DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

# 配置软连接的目标路径和名称
INSTALL_PATH="/usr/local/bin/vproxy"
# 获取当前目录下 proxy.sh 的绝对路径
SOURCE_SCRIPT="$(pwd)/proxy.sh"

WINDOWS_IP="192.168.3.3"
PROXY_PORT="10808"
TUN_DEV="utun9"
# 修改日志路径，或者确保目录存在
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/tun2socks.log"
TUN_BIN="$SCRIPT_DIR/tun2socks"

TARGET_NETS=(
    "10.14.0.0/16"
)

# 需检测的具体业务端口 (IP:PORT)
CHECK_LIST=(
    "10.14.2.109:9876"  # RocketMQ NameServer
    "10.14.2.109:10911" # RocketMQ Broker
    "10.14.2.115:8848"  # Nacos HTTP
    "10.14.2.115:9848"  # Nacos gRPC
)
# ==========================================

if [ "$EUID" -ne 0 ]; then
  echo "请使用 sudo 运行此脚本"
  exit
fi

# 确保日志目录存在 (修复报错的关键)
mkdir -p $LOG_DIR

rotate_log() {
    # 如果日志文件存在，则进行轮转
    if [ -f "$LOG_FILE" ]; then
        TIMESTAMP=$(date +%Y%m%d-%H%M%S)
        mv "$LOG_FILE" "$LOG_DIR/tun2socks.log.$TIMESTAMP"
        echo "原日志已归档为: logs/tun2socks.log.$TIMESTAMP"
    fi
    
    # 自动清理旧日志（保留最近 5 个）
    count=$(ls -1 "$LOG_DIR"/tun2socks.log.* 2>/dev/null | wc -l)
    if [ "$count" -gt 5 ]; then
        ls -tp "$LOG_DIR"/tun2socks.log.* | grep -v '/$' | tail -n +6 | xargs -I {} rm -- "{}"
        echo "已清理旧日志，仅保留最近 5 份"
    fi
}

clean_logs() {
    echo "正在清理日志..."
    
    # 1. 如果正在运行，清空当前日志文件但不删除文件（不影响进程写入）
    if [ -f "$LOG_FILE" ]; then
        # 截断文件
        cat /dev/null > "$LOG_FILE"
        echo "当前日志已清空: $LOG_FILE"
    fi
    
    # 2. 删除所有归档的旧日志
    # find "$LOG_DIR" -name "tun2socks.log.*" -type f -delete
    # 或者保留最近 2-3 个？ 这里根据需求，既然是 clean 命令，我们可以彻底一点
    # 但为了安全，我们还是用保留 0 个（全删）或者仅针对归档
    
    rm -f "$LOG_DIR"/tun2socks.log.*
    echo "归档日志已全部删除"
}


start_proxy() {
    echo "正在检查环境..."
    chmod +x $TUN_BIN

    echo "正在启动 tun2socks 隧道..."
    # 确保解除隔离标记: sudo xattr -d com.apple.quarantine tun2socks
    
    # 启动前日志轮转
    rotate_log
    
    nohup $TUN_BIN -device $TUN_DEV -proxy socks5://$WINDOWS_IP:$PROXY_PORT > $LOG_FILE 2>&1 &
    
    # 给一点时间让系统创建设备
    sleep 2

    # --- 核心修复：激活网卡并分配 IP ---
    echo "正在激活虚拟网卡 $TUN_DEV..."
    if ifconfig $TUN_DEV > /dev/null 2>&1; then
        sudo ifconfig $TUN_DEV 10.0.0.1 10.0.0.1 up
        echo "网卡 $TUN_DEV 已激活 (10.0.0.1)"
    else
        echo "错误：网卡 $TUN_DEV 未创建，请检查日志 $LOG_FILE"
        exit 1
    fi
    # --------------------------------

    echo "正在配置路由表..."
    for net in "${TARGET_NETS[@]}"; do
        route delete -net "$net" > /dev/null 2>&1
        route add -net "$net" -interface "$TUN_DEV"
        echo "已指向: $net -> $TUN_DEV"
    done
    
    echo "---------------------------------------"
    echo "开启成功！"
}

stop_proxy() {
    echo "正在清理环境..."
    # 1. 杀掉进程 (使用精准匹配，防止误杀其他 tun 进程)
    pkill -9 -f "tun2socks.*$TUN_DEV"
    # 2. 精准删除路由
    for net in "${TARGET_NETS[@]}"; do
        route delete -net "$net" -interface "$TUN_DEV" > /dev/null 2>&1
    done
    # 3. 彻底销毁网卡 (这是恢复默认路径的关键)
    if ifconfig $TUN_DEV > /dev/null 2>&1; then
        # 在 macOS 上，destroy 比 down 更彻底，能释放设备占用
        ifconfig $TUN_DEV down > /dev/null 2>&1
        # 注意：部分 macOS 版本不支持 destroy，此时仅用 down 即可
    fi
    # 4. 仅刷新应用层 DNS 缓存，不重启系统服务 (防止 Google 解析断掉)
    dscacheutil -flushcache
    echo "关闭完成。"
}

check_status() {
    echo "=== 隧道连接状态检查 ==="
    
    # 1. 检查进程
    if pgrep -f "tun2socks.*$TUN_DEV" > /dev/null; then
        echo "[进程] tun2socks 正在运行 ✅"
    else
        echo "[进程] tun2socks 未启动 ❌"
    fi

    # 2. 检查网卡
    if ifconfig "$TUN_DEV" > /dev/null 2>&1; then
        echo "[网卡] $TUN_DEV 已挂载 ✅"
    else
        echo "[网卡] $TUN_DEV 不存在 ❌"
    fi

    # 3. 检查路由
    SAMPLE_NET="${TARGET_NETS[0]}"
    ROUTE_CHECK=$(route get "$SAMPLE_NET" | grep interface | awk '{print $2}')
    if [ "$ROUTE_CHECK" == "$TUN_DEV" ]; then
        echo "[路由] 目标流量已指向隧道 ✅"
    else
        echo "[路由] 流量未指向隧道 ($ROUTE_CHECK) ❌"
    fi

    # 4. 业务端口拨测
    echo "[业务] 关键服务连通性测试:"
    for item in "${CHECK_LIST[@]}"; do
        IP=$(echo $item | cut -d: -f1)
        PORT=$(echo $item | cut -d: -f2)
        
        # 使用 nc 进行 2 秒超时拨测
        if nc -vz -w 2 "$IP" "$PORT" > /dev/null 2>&1; then
            echo "      ➜ $IP:$PORT  [成功] 🟢"
        else
            echo "      ➜ $IP:$PORT  [失败] 🔴"
        fi
    done
    echo "========================"
}

install_vproxy() {
    if [ ! -f "$SOURCE_SCRIPT" ]; then
        echo "错误：找不到 proxy.sh 文件，请确保在脚本所在目录下运行此命令。"
        exit 1
    fi

    echo "正在安装 vproxy 到 $INSTALL_PATH..."
    
    # 赋予执行权限
    chmod +x "$SOURCE_SCRIPT"
    chmod +x "$(pwd)/tun2socks"
    
    # 创建软连接 (-f 表示如果存在则覆盖)
    ln -sf "$SOURCE_SCRIPT" "$INSTALL_PATH"
    
    if [ $? -eq 0 ]; then
        echo "---------------------------------------"
        echo "安装成功！"
        echo "现在你可以在任何地方运行：sudo vproxy start"
    else
        echo "安装失败，请检查权限。"
    fi
}

uninstall_vproxy() {
    echo "正在卸载 vproxy..."
    
    if [ -L "$INSTALL_PATH" ]; then
        rm "$INSTALL_PATH"
        echo "软连接已删除。"
    else
        echo "未发现安装的 vproxy 软连接。"
    fi
    
    echo "卸载完成。"
}

clean_vproxy() {
    clean_logs
}

case "$1" in
    start) start_proxy ;;
    stop) stop_proxy ;;
    restart) stop_proxy; sleep 1; start_proxy ;;
    status) check_status ;;
    install) install_vproxy ;;
    uninstall) uninstall_vproxy ;;
    clean) clean_vproxy ;;
    *) echo "用法: sudo $0 {start|stop|restart|status|install|uninstall|clean}"; exit 1 ;;
esac