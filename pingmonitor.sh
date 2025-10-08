#!/bin/bash
# =====================================
# Ping4 Monitoring Script with Log Rotation
# Author: JohnnyToro
# =====================================

# 🧩 Configuration
HOST="192.168.40.32"                         # Host to monitor
LOG_DIR="$HOME/ping4_logs"             # Directory to store logs
ALERT_THRESHOLD=3                      # Consecutive failures before alert
CHECK_INTERVAL=5                       # Seconds between checks

# 🗂️ Ensure log directory exists
mkdir -p "$LOG_DIR"

# 🔢 Internal counters
fail_count=0

# 🕓 Infinite loop
while true; do
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    log_date=$(date '+%Y-%m-%d')
    LOGFILE="$LOG_DIR/ping4_monitor_${log_date}.log"

    # 📡 Ping using IPv4
    ping4 -c 1 -W 2 "$HOST" > /tmp/ping4_tmp.log 2>&1
    if [ $? -eq 0 ]; then
        # ✅ Success
        latency=$(grep 'time=' /tmp/ping4_tmp.log | awk '{print $7}' | cut -d'=' -f2)
        echo "$timestamp - ✅ Host $HOST reachable, latency ${latency}ms" | tee -a "$LOGFILE"
        fail_count=0
    else
        # ❌ Failed ping
        ((fail_count++))
        echo "$timestamp - ⚠️ Host $HOST not reachable (failure $fail_count)" | tee -a "$LOGFILE"
        
        # 🚨 Alert condition
        if [ $fail_count -ge $ALERT_THRESHOLD ]; then
            echo "$timestamp - 🚨 ALERT: Host $HOST is DOWN for $fail_count checks!" | tee -a "$LOGFILE"
        fi
    fi

    # 🧹 Optional cleanup: remove logs older than 7 days
    find "$LOG_DIR" -type f -name "ping4_monitor_*.log" -mtime +7 -delete

    sleep "$CHECK_INTERVAL"
done
