#!/bin/bash

# Instant UI refresh without full reboot
refresh_ui() {
    printf "\033[2J\033[H"
    
    # Auto-sync core files when running from a local/dev repo into the app dir
    if [[ "$INSTALL_DIR" != "$PFY_CORE" && -d "$PFY_CORE" ]]; then
        cp -rf "$INSTALL_DIR/core" "$PFY_CORE/" 2>/dev/null
        cp -rf "$INSTALL_DIR/modules" "$PFY_CORE/" 2>/dev/null
        cp -rf "$INSTALL_DIR/assets" "$PFY_CORE/" 2>/dev/null
        cp -f "$INSTALL_DIR/promptify.sh" "$PFY_CORE/" 2>/dev/null
    fi

    setup_ui "$BANNER_NAME" "$CUR_THEME_BORDER" "$CUR_THEME_TAG" "$CUR_FONT" "$USE_BANNER" "$CUR_PROMPT_STYLE"
}

# Start a fresh interactive Zsh so applied changes are visible immediately,
# without exiting and reopening the terminal. The fresh shell starts in the
# directory Promptify was launched from, never in the clone/system dir. When
# zsh is missing or broken (e.g. a host-Termux shim inside proot-distro), stay
# in a usable bash session instead of freezing on a dead exec.
reload_shell() {
    cd -- "${ORIGINAL_DIR:-$HOME}" 2>/dev/null
    if cmd_probe zsh; then
        exec zsh
    fi
    echo -e "\e[1;33m[i] zsh isn't usable here (missing or broken install). Staying in bash.\e[0m"
    exec bash
}

is_interactive() {
    [[ -t 0 ]]
}

# Ask whether to reload the shell after changes are applied. On "no" — or when
# not attached to a real terminal — just show the notice instead.
restart_shell() {
    echo
    if is_interactive && cmd_probe zsh; then
        if confirm_action "Restart Zsh now to apply changes?" "y"; then
            echo -e "\e[1;34m[*] \e[32mRestarting shell...\e[0m"
            sleep 0.5
            reload_shell
        fi
    fi
    echo -e "\e[1;32m[✔] Changes applied!\e[0m"
    echo -e "\e[1;33m[*] Start a new terminal session (or run: source ~/.zshrc) to see them.\e[0m"
    press_enter
}

# Exit script cleanup
exit_script() {
    tput cnorm
    exit 0
}

# Cleanup banner files (keeps other prefs like CAT/CHANNEL in prefs.conf)
remove_banner_files() {
    rm -f "$HOME/.draw"
}
