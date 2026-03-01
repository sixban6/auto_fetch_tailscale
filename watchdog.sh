#!/bin/sh

# 1. 基础配置
LOG_FILE="/var/log/watchdog_$(date +%F).log"
TIMEOUT=13

# 2. 封装网络检测函数 (参数1: 尝试次数)
check_network() {
    local max_attempts=$1
    for i in $(seq 1 "$max_attempts"); do
        if curl -s -I -m "$TIMEOUT" https://www.google.com > /dev/null; then
            return 0 # 连通成功，返回状态码 0
        fi
        
        # 如果没成功，且不是最后一次，则等待 3 秒
        if [ "$i" -lt "$max_attempts" ]; then
            sleep 3
        fi
    done
    return 1 # 全部失败，返回状态码 1
}

# -------------------- 主程序开始 --------------------

# 步骤一：常规连通性巡检 (尝试 34 次)
if check_network 34; then
    echo "$(date): ✅ 常规巡检通过，代理顺畅。" >> "$LOG_FILE"
else
    echo "$(date): 🚨 连续 34 次常规测试失败，疑似断网。" >> "$LOG_FILE"
    echo "$(date): 🔧 启动 [第一级救援]: 尝试保留当前配置，仅重启服务..." >> "$LOG_FILE"
    
    # 尝试软重启
    singctl stop
    sleep 5
    singctl gen
    singctl start || singctl stop
    
    echo "$(date): ⏳ 服务已重启，等待 60 秒让节点建立连接..." >> "$LOG_FILE"
    sleep 60
    
    # 步骤二：重启后的二次复测 (尝试 3 次)
    echo "$(date): 🔄 开始二次复测..." >> "$LOG_FILE"
    if check_network 3; then
        echo "$(date): ✅ 二次复测通过！服务重启成功，避免了配置回滚。" >> "$LOG_FILE"
    else
        echo "$(date): 💀 二次复测依然失败，当前配置可能已损坏或节点彻底失效。" >> "$LOG_FILE"
        echo "$(date): 💣 启动 [第二级救援]: 准备执行紧急配置回滚..." >> "$LOG_FILE"
        
        singctl stop
        
        # 核心回滚逻辑
        if [ -f "/etc/sing-box/config.json.bak" ]; then
            cp /etc/sing-box/config.json.bak /etc/sing-box/config.json
            echo "$(date): 🔄 已用 config.json.bak 覆盖当前配置。" >> "$LOG_FILE"
        else
            echo "$(date): ❌ 致命错误：未找到备份配置文件，无法回滚！" >> "$LOG_FILE"
        fi
        
        sleep 5
        singctl start || singctl stop
        
        echo "$(date): ✅ 紧急回滚流程执行完毕，等待下一轮定时任务巡检。" >> "$LOG_FILE"
    fi
fi

# -------------------- 清理工作 --------------------
# 每次运行完都检查一遍，顺手干掉 3 天前的旧日志
find /var/log/ -name "watchdog_*.log" -mtime +2 | xargs rm -f 2>/dev/null
