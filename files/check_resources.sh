#!/bin/bash

#####
##### Resource usage script that runs via cronjob
##### Sends Alerts via webhook to services that support them
#####

### Connects to a webhook to send resource usage 
#WEBHOOK_URL=""

CPU_THRESHOLD=80
RAM_THRESHOLD=80
DISK_THRESHOLD=85

HOSTNAME="DevSrv"

send_alert() {
    local message="$1"
    curl -s -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "{\"text\": \"$message\"}"
} 

### Debugging 
#send_alert() {
#    local message="$1"
#    printf "%b\n" "$message"
#}

CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | cut -d',' -f1 | xargs printf "%.0f")

RAM_TOTAL=$(free | awk '/Mem:/ {print $2}')
RAM_USED=$(free | awk '/Mem:/ {print $3}')
RAM_USAGE=$(awk "BEGIN {printf \"%.0f\", ($RAM_USED/$RAM_TOTAL)*100}")

DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | tr -d '%')

ALERTS=""
ALERT_ROWS=""

check_metric() {
    local name="$1"
    local emoji="$2"
    local usage="$3"
    local threshold="$4"
    local unit="%"

    if [ "$usage" -ge "$threshold" ]; then
        local bar=""
        local filled=$(( usage / 10 ))
        local empty=$(( 10 - filled ))
        for ((i=0; i<filled; i++)); do bar+="█"; done
        for ((i=0; i<empty; i++)); do bar+="░"; done

        ALERT_ROWS+="${emoji} **${name}** | \`${bar}\` | **${usage}${unit}** | threshold: ${threshold}${unit}\n"
        ALERTS="yes"
    fi
}

check_metric "CPU"  "🔥" "$CPU_USAGE"  "$CPU_THRESHOLD"
check_metric "RAM"  "🧠" "$RAM_USAGE"  "$RAM_THRESHOLD"
check_metric "DISK" "💾" "$DISK_USAGE" "$DISK_THRESHOLD"

if [ -n "$ALERTS" ]; then
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    MESSAGE="🚨 **RESOURCE ALERT** — \`${HOSTNAME}\`\n"
    MESSAGE+="🕐 ${TIMESTAMP}\n"
    MESSAGE+="─────────────────────────────\n"
    MESSAGE+="${ALERT_ROWS}"
    MESSAGE+="─────────────────────────────\n"

    send_alert "$MESSAGE"
fi

