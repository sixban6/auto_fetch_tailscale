#!/bin/sh

# 1. 定义基础变量
RAW_URL="https://raw.githubusercontent.com/sixban6/auto_fetch_tailscale/main/watchdog.sh"

# 定义加速镜像池 (空格分隔的字符串)
PROXIES="https://gh-proxy.com/ https://ghproxy.net/ https://github.sixleaves.top/6C1abae6/ https://ghfast.top/"

SCRIPT_PATH="/root/watchdog.sh"
TMP_PATH="/tmp/watchdog_temp.sh"

echo "=================================================="
echo "🚀 [$(date +'%Y-%m-%d %H:%M:%S')] 开始执行 Loader 热更新拉取脚本"
echo "=================================================="

# 2. 检测网络状态
echo "🌐 正在检测 Google 连通性..."
if curl -s -I -m 5 https://www.google.com > /dev/null; then
    GOOGLE_OK=true
    echo "   ✅ 网络畅通 (Google 可达)"
else
    GOOGLE_OK=false
    echo "   ❌ 网络异常 (Google 无法访问)"
fi

# 3. 检测 sing-box 进程
echo "📦 正在检测 sing-box 进程状态..."
if pidof sing-box >/dev/null || pidof singbox >/dev/null; then
    SINGBOX_RUNNING=true
    echo "   ✅ sing-box 进程正在运行"
else
    SINGBOX_RUNNING=false
    echo "   ❌ sing-box 进程未运行"
fi

# 4. 决策逻辑
echo "🧠 正在分析状态并制定策略..."
if [ "$SINGBOX_RUNNING" = true ] && [ "$GOOGLE_OK" = false ]; then
    echo "   ⚠️ [策略] 进程存活但断网，可能节点已死。准备停止 sing-box 并使用镜像代理下载..."
    singctl stop
    USE_PROXY=true
elif [ "$SINGBOX_RUNNING" = false ] && [ "$GOOGLE_OK" = false ]; then
    echo "   ⚠️ [策略] 进程已死且断网。准备清理残留并使用镜像代理下载..."
    singctl stop
    USE_PROXY=true
else
    echo "   ✅ [策略] 状态良好或临时直连可用。优先尝试直连 GitHub 下载..."
    USE_PROXY=false
fi

# 5. 核心：动态轮询下载逻辑
DOWNLOAD_SUCCESS=false
echo "⬇️ 开始拉取最新版 watchdog.sh..."

# 尝试直连
if [ "$USE_PROXY" = false ]; then
    echo "   🔗 尝试直连 GitHub..."
    if curl -L -s -m 15 -o "$TMP_PATH" "$RAW_URL" && [ -s "$TMP_PATH" ]; then
        echo "   ✅ 直连下载成功！"
        DOWNLOAD_SUCCESS=true
    else
        echo "   ⚠️ 直连下载失败，将切换至镜像池重试..."
    fi
fi

# 尝试镜像池
if [ "$DOWNLOAD_SUCCESS" = false ]; then
    echo "   🔄 开始轮询镜像池..."
    for PROXY_PREFIX in $PROXIES; do
        FULL_URL="${PROXY_PREFIX}${RAW_URL}"
        echo "   👉 尝试镜像: $PROXY_PREFIX"
        
        if curl -L -s -m 15 -o "$TMP_PATH" "$FULL_URL" && [ -s "$TMP_PATH" ]; then
            echo "   ✅ 镜像加速下载成功！"
            DOWNLOAD_SUCCESS=true
            break
        else
            echo "   ❌ 该镜像源失败，尝试下一个..."
        fi
    done
fi

# 6. 安全校验与执行
echo "--------------------------------------------------"
if [ "$DOWNLOAD_SUCCESS" = true ]; then
    echo "📝 校验通过，正在覆盖本地旧脚本并赋予执行权限..."
    mv -f "$TMP_PATH" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    
    echo "🚀 移交控制权，开始执行最新版 Watchdog 自救逻辑 >>>"
    echo ""
    sh "$SCRIPT_PATH"
else
    echo "🚨 严重警告: GitHub 与所有镜像源全部失效，下载失败！"
    if [ -f "$SCRIPT_PATH" ]; then
        echo "⏪ 尝试执行本地历史版本 Watchdog 进行兜底自救 >>>"
        echo ""
        sh "$SCRIPT_PATH"
    else
        echo "💀 致命错误: 本地无可用历史版本，热更新彻底失败！"
    fi
fi
