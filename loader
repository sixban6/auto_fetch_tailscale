#!/bin/bash

# 1. 定义基础变量
RAW_URL="https://raw.githubusercontent.com/sixban6/auto_fetch_tailscale/main/watchdog.sh"

# 定义加速镜像池 (数组格式，你可以随时在里面增删可用的镜像源)
PROXIES=(
    "https://gh-proxy.com/"
    "https://ghproxy.net/"
    "https://github.sixleaves.top/6C1abae6/"
    "https://ghfast.top/"
)

SCRIPT_PATH="/root/watchdog.sh"
TMP_PATH="/tmp/watchdog_temp.sh"

# 2. 检测网络状态
if curl -s -I -m 5 https://www.google.com > /dev/null; then
    GOOGLE_OK=true
else
    GOOGLE_OK=false
fi

# 3. 检测 sing-box 进程
if pidof sing-box >/dev/null || pidof singbox >/dev/null; then
    SINGBOX_RUNNING=true
else
    SINGBOX_RUNNING=false
fi

# 4. 决策逻辑：判断是否需要强制走代理
if [ "$SINGBOX_RUNNING" = true ] && [ "$GOOGLE_OK" = false ]; then
    singctl stop
    USE_PROXY=true
elif [ "$SINGBOX_RUNNING" = false ] && [ "$GOOGLE_OK" = false ]; then
    singctl stop
    USE_PROXY=true
else
    USE_PROXY=false
fi

# 5. 核心：动态轮询下载逻辑
DOWNLOAD_SUCCESS=false

# 如果网络畅通，优先尝试直连 GitHub 下载
if [ "$USE_PROXY" = false ]; then
    if curl -L -s -m 15 -o "$TMP_PATH" "$RAW_URL" && [ -s "$TMP_PATH" ]; then
        DOWNLOAD_SUCCESS=true
    fi
fi

# 如果直连失败，或者被判定必须走代理，则开始遍历镜像池
if [ "$DOWNLOAD_SUCCESS" = false ]; then
    for PROXY_PREFIX in "${PROXIES[@]}"; do
        FULL_URL="${PROXY_PREFIX}${RAW_URL}"
        
        # 尝试下载，如果 curl 返回 0 且文件非空 (-s)，则判定成功
        if curl -L -s -m 15 -o "$TMP_PATH" "$FULL_URL" && [ -s "$TMP_PATH" ]; then
            DOWNLOAD_SUCCESS=true
            break # 拿到有效文件，立刻跳出循环，不再尝试后续镜像
        fi
    done
fi

# 6. 安全校验与执行
if [ "$DOWNLOAD_SUCCESS" = true ]; then
    # 覆盖旧脚本并赋予执行权限
    mv -f "$TMP_PATH" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    
    # 移交控制权，执行热更新后的 watchdog
    bash "$SCRIPT_PATH"
else
    # 极端情况：直连和所有镜像全军覆没。使用本地老版本兜底运行，尝试自救
    if [ -f "$SCRIPT_PATH" ]; then
        bash "$SCRIPT_PATH"
    fi
fi
