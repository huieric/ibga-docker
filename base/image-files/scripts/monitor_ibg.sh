#!/bin/bash
#
# 监控 IB Gateway CPU/内存占用，并在超阈值时自动抓取 jstack/jmap
#
# 用法: nohup ./monitor_ibg.sh > monitor.log 2>&1 &

source $(dirname "$BASH_SOURCE")/_env.sh

# 配置
PROCESS_NAME="ibgateway"    # 进程名，可用 ps -ef | grep ibgateway 确认
CPU_THRESHOLD=100           # 单位：%，超过则 dump（多核时可能大于100）
MEM_THRESHOLD=2048          # 单位：MB，超过则 dump
CHECK_INTERVAL=60           # 单位：秒，检查频率
DUMP_DIR="$IBGA_LOG_EXPORT_DIR/ibg_dumps"   # dump 存放目录

# 工具路径（确保 jdk 工具在 PATH 内）
JSTACK=$(which jstack)
JMAP=$(which jmap)

mkdir -p "$DUMP_DIR"

echo "[INFO] Monitoring process: $PROCESS_NAME"
echo "[INFO] Dumps will be saved in: $DUMP_DIR"
echo "[INFO] Thresholds: CPU>${CPU_THRESHOLD}%, MEM>${MEM_THRESHOLD}MB"

while true; do
    PID=$(pgrep -f "$PROCESS_NAME" | head -n 1)

    if [[ -z "$PID" ]]; then
        echo "[WARN] $PROCESS_NAME not running"
        sleep $CHECK_INTERVAL
        continue
    fi

    # 获取 CPU、内存
    CPU=$(ps -p $PID -o %cpu= | awk '{print int($1)}')
    MEM=$(ps -p $PID -o rss= | awk '{print int($1/1024)}')  # MB

    TS=$(date +"%Y%m%d-%H%M%S")

    if (( CPU > CPU_THRESHOLD || MEM > MEM_THRESHOLD )); then
        echo "[ALERT] High usage detected at $TS (CPU=${CPU}%, MEM=${MEM}MB)"
        DUMP_PREFIX="$DUMP_DIR/ibg_${PID}_${TS}"

        if [[ -n "$JSTACK" ]]; then
            $JSTACK -l $PID > "${DUMP_PREFIX}.thread.txt" 2>&1
            echo "[INFO] Thread dump saved: ${DUMP_PREFIX}.thread.txt"
        fi

        if [[ -n "$JMAP" ]]; then
            $JMAP -dump:format=b,file="${DUMP_PREFIX}.heap.hprof" $PID >/dev/null 2>&1
            echo "[INFO] Heap dump saved: ${DUMP_PREFIX}.heap.hprof"
        fi
    else
        echo "[OK] $TS CPU=${CPU}% MEM=${MEM}MB"
    fi

    sleep $CHECK_INTERVAL
done
