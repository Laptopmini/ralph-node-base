#!/usr/bin/env bash

ask_continue() { read -n 1 -s -r -p "$*"$'\n' < /dev/tty; }