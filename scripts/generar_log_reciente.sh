#!/bin/bash

export RCLONE_CONFIG=/home/lsd/.config/rclone/rclone.conf
export HOME=/home/lsd

HOY=$(date +%Y-%m-%d)
AYER=$(date -d "yesterday" +%Y-%m-%d)

grep -E "^\[($HOY|$AYER)" /home/lsd/log_sistema.txt > /home/lsd/log_reciente.txt

timeout 90 rclone copy /home/lsd/log_reciente.txt gdrive:Laboratorio\ 6/
