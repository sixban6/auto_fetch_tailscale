#!/bin/sh

# ==========================================
# 0. 基础环境与辅助函数
# ==========================================
LOG_FILE="/var/log/watchdog.log"
TODAY=$(date +'%Y-%m-%d')
TIMEOUT=10
PROXY_PARAM="-x socks5h://127.0.0.1:2080" # 如果本机直连不走代理，请解开并配置正确端口

# 写入日志的辅助函数，统一带上时间戳
log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') | $1" >> "$LOG_FILE"
}

# ==========================================
# 1. 专属回调函数定义
# ==========================================
xiaomi_callback() {
    log "⏩ 执行 小米路由器 专属回调逻辑 (xiaomi_callback)..."
    
# cat << 'EOF' > /etc/singctl/singctl.yaml
# subs:
#   - name: "main"
#     url: ""
#     skip_tls_verify: false
#     remove-emoji: true


# hy2:
#   up: 21
#   down: 198

# github:
#   mirror_url: "https://gh-proxy.com"          

# # (singctl update) 自动填补：Tailscale 自动化配置
# tailscale:
#   auth_key: "tskey-auth-k34pMXAe3h11CNTRL-SApqLjrAQCBuRX7PbzhhCBm2yvuxn4PF"

# server:
#   sb_domain: "sub.yourdomain.com"
#   cf_dns_key: "your_cloudflare_api_token"
# EOF
    singctl update self
}

n1_callback() {
    log "⏩ 执行 N1 盒子 专属回调逻辑 (n1_callback)..."

# cat << 'EOF' > /etc/singctl/singctl.yaml
# subs:
#   - name: "main"
#     url: ""
#     skip_tls_verify: false
#     remove-emoji: true
    
# hy2:
#   up: 21
#   down: 198

# github:
#   mirror_url: "https://gh-proxy.com"          

# # (singctl update) 自动填补：Tailscale 自动化配置
# tailscale:
#   auth_key: "tskey-auth-k34pMXAe3h11CNTRL-SApqLjrAQCBuRX7PbzhhCBm2yvuxn4PF"

# server:
#   sb_domain: "sub.yourdomain.com"
#   cf_dns_key: "your_cloudflare_api_token"
# EOF
     singctl ts stop
#     singctl sb stop
#     singctl update self && singctl ts start
}

# ==========================================
# 2. 设备架构检测与路由拦截
# ==========================================
check_device_and_route() {
    local arch=$(uname -m)
    
    # 1. 如果是 x86 架构，直接 return 0，放行执行后续的 watchdog 逻辑
    if [ "$arch" = "x86_64" ]; then
        return 0 
    fi

    # 2. 获取具体型号信息
    local model_info=""
    if [ -f /tmp/sysinfo/model ]; then
        model_info=$(cat /tmp/sysinfo/model)
    elif [ -f /sys/firmware/devicetree/base/model ]; then
        model_info=$(cat /sys/firmware/devicetree/base/model | tr -d '\0') 
    else
        model_info="unknown_arch_${arch}"
    fi

    # 3. 根据型号关键词区分执行回调
    case "$model_info" in
        *Xiaomi*|*Redmi*|*xiaomi*|*redmi*|*AX3000T*)
            xiaomi_callback
            ;;
        *N1*|*Phicomm*|*phicomm*)
            n1_callback
            ;;
        *)
            log "⏩ 设备检测: 当前设备 [$model_info] 不是目标设备，跳过执行。"
            ;;
    esac

    # 只要不是 x86，执行完对应的回调后统统退出脚本，不执行后续常规巡检
    exit 0
}

# 核心：执行检查拦截
check_device_and_route

# ==========================================
# 3. 防止脚本多开锁 (仅 x86 会走到这里)
# ==========================================
LOCK_FILE="/var/run/singbox_watchdog.pid"

if [ -f "$LOCK_FILE" ]; then
    # 读取旧的进程号
    OLD_PID=$(cat "$LOCK_FILE")
    # 检查该进程号是否还在运行
    if kill -0 "$OLD_PID" 2>/dev/null; then
        log "⚠️ 上一个 watchdog 任务(PID: $OLD_PID)仍在运行，本次跳过。"
        exit 1
    else
        # 进程已经不在了，说明是上次意外中断留下的死锁，清理掉
        rm -f "$LOCK_FILE"
    fi
fi

# 将当前脚本的进程号写入锁文件
echo $$ > "$LOCK_FILE"

# 关键：无论脚本是正常结束还是报错崩溃，退出时自动删除锁文件
trap 'rm -f "$LOCK_FILE"' EXIT INT TERM

# ==========================================
# 4. 日志轮转 (保留3天)
# ==========================================
if [ -f "$LOG_FILE" ]; then
    # 读取日志第一行的时间戳来判断属于哪一天
    FIRST_LINE_DATE=$(head -n 1 "$LOG_FILE" | awk '{print $1}')
    
    # 使用 grep -E 替代 bash 的 [[ =~ ]] 进行正则判断
    if echo "$FIRST_LINE_DATE" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
        if [ "$FIRST_LINE_DATE" != "$TODAY" ]; then
            mv "$LOG_FILE" "/var/log/watchdog_${FIRST_LINE_DATE}.log"
        fi
    fi
fi

# 清理 3 天前的历史归档 (兼容 BusyBox find，放弃 -delete 改用 -exec)
find /var/log/ -name "watchdog_[0-9][0-9][0-9][0-9]-*.log" -type f -mtime +2 -exec rm -f {} \; 2>/dev/null

# ==========================================
# 5. 网络探测函数
# ==========================================
check_proxy() {
    local max_attempts=$1
    # 兼容 sh 的 seq 替代方案，因为部分精简版 OpenWrt 没有 seq 命令
    local i=1
    while [ "$i" -le "$max_attempts" ]; do
        if curl $PROXY_PARAM -s -I -m "$TIMEOUT" https://www.google.com > /dev/null; then
            return 0 # 代理连通成功
        fi
        [ "$i" -lt "$max_attempts" ] && sleep 3
        i=$((i + 1))
    done
    return 1 # 代理连通失败
}

check_isp() {
    # 不走代理，直连测试国内网站与公共DNS，判断物理宽带是否正常
    if curl -s -I -m 5 https://www.baidu.com > /dev/null || ping -c 2 -W 3 223.5.5.5 > /dev/null; then
        return 0 # 宽带正常
    else
        return 1 # 宽带断网
    fi
}

# ==========================================
# 6. 核心救援逻辑 (软重启 -> 复测 -> 紧急回滚)
# ==========================================
execute_rescue() {
    log "🔧 启动 [第一级救援]: 保留当前配置，仅重启服务..."
    singctl sb stop 2>/dev/null
    sleep 3
    singctl sb start || singctl sb stop
    
    # 按照要求修改为 90 秒
    log "⏳ 等待 90 秒让节点建立连接..."
    sleep 90
    
    log "🔄 开始二次复测..."
    if check_proxy 3; then
        log "✅ 二次复测通过！服务软重启成功。"
    else
        log "💀 二次复测失败，当前配置或节点可能已失效。"
        log "💣 启动 [第二级救援]: 准备执行紧急配置回滚..."
        
        singctl sb stop 2>/dev/null
        
        if [ -f "/etc/sing-box/config.json.bak" ]; then
            cp /etc/sing-box/config.json.bak /etc/sing-box/config.json
            log "🔄 已用 config.json.bak 覆盖当前配置。"
        else
            log "❌ 致命错误：未找到备份配置文件，无法回滚！"
        fi
        
        sleep 3
        singctl sb start || singctl sb stop
        log "✅ 紧急回滚执行完毕，等待下一轮巡检。"
    fi
}

# ==========================================
# 7. 主流程开始
# ==========================================
# 按照要求修改为 13 次常规代理检测
if check_proxy 13; then
    log "✅ 常规巡检通过，代理顺畅。"
    exit 0
fi

log "🚨 连续 13 次探测代理失败，正在排查网络环境..."

# 步骤二：兼容主/旁路由的“防背锅”检测
if check_isp; then
    log "⚠️ 国内网络正常。确认为【代理服务崩溃】，准备执行救援。"
    execute_rescue
else
    log "⚠️ 国内网络也不通！正在排查是物理断网，还是透明代理卡死导致全局断网..."
    
    # 核心动作：停掉代理，清除残留的路由劫持规则
    singctl sb stop 2>/dev/null
    sleep 3
    
    if check_isp; then
        log "✅ 关闭代理后国内网络恢复！确认为【代理规则残留导致全局断网】。准备执行救援。"
        execute_rescue
    else
        log "💀 关闭代理后国内依然断网，确认为【物理宽带/主路由 真实故障】！"
        log "⏸️ 为防止误伤配置，挂起本次救援。仅恢复代理运行状态，等待物理网络恢复。"
        # 宽带断了，别乱动配置，把代理重新跑起来等宽带恢复就好
        singctl sb start >/dev/null 2>&1
        exit 0
    fi
fi
