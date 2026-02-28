#!/bin/bash

# 动态生成每日日志文件名
LOG_FILE="/var/log/watchdog_$(date +%F).log"
MAX_ATTEMPTS=3
TIMEOUT=10
SUCCESS=0

for i in $(seq 1 $MAX_ATTEMPTS); do
    if curl -s -I -m $TIMEOUT https://www.google.com > /dev/null; then
        SUCCESS=1
        break
    fi
    
    if [ $i -lt $MAX_ATTEMPTS ]; then
        sleep 3
    fi
done

if [ $SUCCESS -eq 1 ]; then
    echo "$(date): ✅ 代理顺畅" >> $LOG_FILE
else
    echo "$(date): 🚨 连续 $MAX_ATTEMPTS 次连通性测试失败，准备执行紧急恢复..." >> $LOG_FILE
    
    singctl stop
    
    if [ -f "/etc/sing-box/config.json.bak" ]; then
        cp /etc/sing-box/config.json.bak /etc/sing-box/config.json
        echo "$(date): 🔄 已回滚至稳定版配置。" >> $LOG_FILE
    else
        echo "$(date): ❌ 未找到备份配置，仅尝试重启服务。" >> $LOG_FILE
    fi
    
    sleep 5
    singctl start
    
    echo "$(date): ✅ 紧急恢复流程执行完毕。" >> $LOG_FILE
fi

# 核心清理逻辑：每次运行完都检查一遍，顺手干掉 3 天前的旧文件
find /var/log/ -name "watchdog_*.log" -mtime +2 | xargs rm -f 2>/dev/null
