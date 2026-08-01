#!/usr/bin/env bash

set -eou pipefail

if ! command -v feh &> /dev/null; then
  echo "Installing feh"
  sudo pacman -Syu feh
fi

IMAGE_NAME="${1:-${IMAGE_NAME:-test.ppm}}"

if ! [[ -e "${IMAGE_NAME}" ]]; then
  echo "Target image doesn't exit!" >&2
  exit 1
fi

killall feh &>/dev/null || true
nohup feh -F "${IMAGE_NAME}" &>/dev/null &
