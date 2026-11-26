#!/bin/bash
set -euo pipefail
[[ $(uname -s) == Darwin && $(uname -m) == arm64 ]] || { echo 'Apple Silicon macOS required'; exit 1; }
if ! xcode-select -p >/dev/null 2>&1; then xcode-select --install; echo 'Complete the installation and rerun.'; exit 1; fi
BREW=/opt/homebrew/bin/brew
if [[ ! -x "$BREW" ]]; then
 echo 'Install Homebrew from https://brew.sh/ and rerun.'; exit 1
fi
"$BREW" install cmake python sdl3 vulkan-headers vulkan-loader molten-vk shaderc
