#!/bin/bash

function cleanup() {
    echo "Script interrupted."
    exit 1
}

trap cleanup INT
trap '' SIGTERM

base_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

function init() {
    devil binexec on
    reset
    prepare_cloudflared
    prepare_node
    prepare_xray
}

function run_cloudflared() {
    local uuid=$(uuidgen)
    local port=$(reserve_port)
    local id=$(echo $uuid | tr -d '-')
    local session="cf"
    tmux kill-session -t $session
    tmux new-session -s $session -d "cd $base_dir/cloudflared && ./cloudflared tunnel --url localhost:$port --edge-ip-version auto --no-autoupdate -protocol http2 2>&1 | tee $base_dir/cloudflared/session_$session.log"
    sleep 10
    local log=$(<"$base_dir/cloudflared/session_$session.log")
    local cloudflared_address=$(echo "$log" | pcregrep -o1 'https://([^ ]+\.trycloudflare\.com)' | sed 's/https:\/\///')
    generate_node_env $port $uuid $id $cloudflared_address
    generate_xray_config $port $uuid
}

function run_nodejs() {
    local session="no"
    tmux kill-session -t $session
    tmux new-session -s $session -d "cd $base_dir/node && node index.js 2>&1 | tee $base_dir/node/session_$session.log"
    after_run $session
}

function run_xray() {
    local session="xr"
    tmux kill-session -t $session
    tmux new-session -s $session -d "cd $base_dir/xray && ./xray 2>&1 | tee $base_dir/xray/session_$session.log"
    after_run $session
}

function extract_vars() {
    local pattern="$1"
    local env_file="$base_dir/node/.env"

    if [ -f "$env_file" ]; then
        grep "$pattern" "$env_file" | sed 's/^[^=]*=//'
    else
        echo "Error: .env file not found in $base_dir/node/"
        return 1
    fi
}

function show_links() {
    local type="$1"

    case "$type" in
        "all")
            extract_vars '^VLESS_'
            ;;
        "xray")
            extract_vars '^VLESS_XRAY'
            ;;
        "node")
            extract_vars '^VLESS_NODE'
            ;;
        *)
            echo "Error: Invalid type specified. Please specify 'all', 'xray', or 'node'."
            return 1
            ;;
    esac
}

function reset() {
    tmux kill-session -a
    local ports=$(devil port list | awk '/[0-9]+/ {print $1}' | sort -u)
    for port in $ports; do
        devil port del tcp $port 2>/dev/null
        devil port del udp $port 2>/dev/null
    done
}

function prepare_cloudflared() {
    mkdir -p $base_dir/cloudflared
    cd $base_dir/cloudflared
    curl -Lo cloudflared.7z https://cloudflared.bowring.uk/binaries/cloudflared-freebsd-latest.7z
    7z x cloudflared.7z
    rm cloudflared.7z
    mv $(find . -name 'cloudflared*') cloudflared
    rm -rf temp
    chmod +x cloudflared
}

function prepare_node() {
    mkdir -p $base_dir/node
    cd $base_dir/node
    npm install
}

function prepare_xray() {
    mkdir -p $base_dir/xray
    cd $base_dir/xray
    curl -Lo xray.zip https://github.com/xtls/xray-core/releases/latest/download/xray-freebsd-64.zip
    unzip -o xray.zip
    rm xray.zip
    chmod +x xray
}

function reserve_port() {
    local port
    while true; do
        port=$(jot -r 1 1024 64000)
        tcp_output=$(devil port add tcp $port 2>&1)
        udp_output=$(devil port add udp $port 2>&1)
        if ! echo "$tcp_output" | grep -q "\[Error\]" && ! echo "$udp_output" | grep -q "\[Error\]"; then
            echo $port
            break
        else
            devil port del tcp $port >/dev/null 2>&1
            devil port del udp $port >/dev/null 2>&1
        fi
    done
}

function after_run() {
    local job_type=$1
    local cron_job=""
    if [ "$job_type" == "no" ]; then
        cron_job="*/5 * * * *    $base_dir/start.sh 3"
        tmux kill-session -t xr
    elif [ "$job_type" == "xr" ]; then
        cron_job="0 * * * *    $base_dir/start.sh 4"
        tmux kill-session -t no
    fi
    crontab -rf
    if [ -n "$cron_job" ]; then
        echo "$cron_job" > temp_crontab
        crontab temp_crontab
    fi
    rm temp_crontab
}

function generate_node_env() {
    local port="$1"
    local uuid="$2"
    local id="$3"
    local cloudflared_address="$4"
    local vless_node="vless://${id}@zula.ir:443?security=tls&sni=${cloudflared_address}&alpn=h2,http/1.1&fp=chrome&type=ws&path=/&host=${cloudflared_address}&encryption=none#[pl]%20[vl-tl-ws]%20[at-ar-no]"
    local vless_xray="vless://${uuid}@zula.ir:443?security=tls&sni=${cloudflared_address}&alpn=h2,http/1.1&fp=chrome&type=ws&path=/ws?ed%3D2048&host=${cloudflared_address}&encryption=none#[pl]%20[vl-tl-ws]%20[at-ar]"
    cd $base_dir/node
    echo "PORT=$port" > .env
    echo "UUID=$uuid" >> .env
    echo "ID=$id" >> .env
    echo "" >> .env
    echo "VLESS_NODE=$vless_node" >> .env
    echo "VLESS_XRAY=$vless_xray" >> .env
}

function generate_xray_config() {
    local port="$1"
    local uuid="$2"
    cd $base_dir/xray
    cat > config.json << EOF
{
  "log": {
    "loglevel": "none"
  },
  "inbounds": [
    {
      "port": ${port},
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "level": 0,
            "email": "wuqb2i4f@duck.com"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/ws?ed=2048"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF
}

function main() {
    case $1 in
        0)
            init >/dev/null 2>&1
            run_cloudflared >/dev/null 2>&1
            run_xray >/dev/null 2>&1
            show_links "xray"
            ;;
        1)
            init >/dev/null 2>&1
            ;;
        2)
            run_cloudflared >/dev/null 2>&1
            ;;
        3)
            run_nodejs >/dev/null 2>&1
            ;;
        4)
            run_xray >/dev/null 2>&1
            ;;
        5)
            show_links "all"
            ;;
        *)
            echo "Usage: $0 {0|1|2|3|4|5}"
            exit 1
            ;;
    esac
}

main "$@"
