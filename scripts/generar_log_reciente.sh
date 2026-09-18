#!/bin/bash

export RCLONE_CONFIG=/home/lsd/.config/rclone/rclone.conf
export HOME=/home/lsd

SYNC_REMOTE=$(awk -F'=' '/^SYNC_REMOTE/{print $2}' /home/lsd/config_general.txt | tr -d ' \r')
SYNC_PATH=$(awk -F'=' '/^SYNC_PATH/{print $2}' /home/lsd/config_general.txt | tr -d ' \r')
SYNC_REMOTE=${SYNC_REMOTE:-servidor}
SYNC_PATH=${SYNC_PATH:-data}

HOY=$(date +%Y-%m-%d)
AYER=$(date -d "yesterday" +%Y-%m-%d)

grep -aE "^\[($HOY|$AYER)" /home/lsd/log_sistema.txt > /home/lsd/log_reciente.txt

timeout 90 rclone copy /home/lsd/log_reciente.txt "$SYNC_REMOTE:$SYNC_PATH/"
