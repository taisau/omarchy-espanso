#!/bin/bash
set -e

printf '\n\033[1;34m==>\033[0m \033[1mInstalling Espanso for Omarchy\033[0m\n'
printf '%s\n' '---------------------------------------'

if command -v espanso >/dev/null 2>&1; then
    printf 'Espanso is already installed.\n'
else
    if command -v omarchy >/dev/null 2>&1; then
        echo "Installing espanso-wayland via omarchy package manager..."
        omarchy pkg add espanso-wayland || yay -S --needed espanso-wayland
    elif command -v yay >/dev/null 2>&1; then
        echo "Installing espanso-wayland via yay..."
        yay -S --needed espanso-wayland
    elif command -v paru >/dev/null 2>&1; then
        echo "Installing espanso-wayland via paru..."
        paru -S --needed espanso-wayland
    else
        echo "Installing espanso-wayland via pacman..."
        sudo pacman -S --needed espanso-wayland
    fi
fi

printf '\n\033[1;34m==>\033[0m \033[1mEnabling and starting Espanso service...\033[0m\n'
systemctl --user daemon-reload || true
systemctl --user enable --now espanso || (espanso service register && espanso start)

printf '\n\033[1;32m✓ Done!\033[0m Espanso is installed and running.\n'
printf 'Press Enter to close this window. '
read -r _
