#!/bin/bash

# Fresh-install snapshot: capture the user's original profiles + detect
# Oh-My-Zsh / Powerlevel10k facts BEFORE touching anything. This is the
# "time travel" baseline that uninstall restores exactly.
setup_snapshot() {
    if [[ ! -f "$PFY_MANIFEST" ]]; then
        capture_snapshot
        ask_skip_p10k
    fi
}

# Powerlevel10k detection + consent. p10k pops a configuration wizard on the
# first run of a fresh shell, which blocks the terminal. We only skip it if the
# user explicitly approves — never silently.
ask_skip_p10k() {
    local orig_p10k
    orig_p10k=$(state_fact ORIG_P10K)
    [[ "$orig_p10k" == "1" ]] || return 0

    echo -e "\n \e[1;33m[i]\e[0m Your shell uses \e[1;36mPowerlevel10k\e[0m, which shows a setup wizard on first run."
    echo -e "     Promptify can auto-skip that wizard so the new prompt applies cleanly."
    if [[ "$CONFIRM_ALL" == "true" ]]; then
        set_pref SKIP_P10K "true"
        echo -e " \e[1;32m[✔] p10k wizard skip enabled (auto-approved).\e[0m"
    elif confirm_action "Automatically skip the p10k wizard?" "y"; then
        set_pref SKIP_P10K "true"
        echo -e " \e[1;32m[✔] p10k wizard skip enabled.\e[0m"
    else
        set_pref SKIP_P10K "false"
        echo -e " \e[1;33m[*] p10k wizard will be left alone.\e[0m"
    fi
}

# Environment step: packages + bundled Oh-My-Zsh/plugins (only if the user's
# original config doesn't already load one).
setup_environment() {
    center_print "\033[1;34m[1/3]\033[0m \033[1;33mSetting up Environment...\033[0m"
    echo
    install_dependencies || { center_print "\033[1;31m[!] Dependencies failed.\033[0m"; press_enter; return 1; }

    if [[ "$(state_fact ORIG_OMZ)" == "1" ]]; then
        center_print "\033[1;32m[✔] Reusing your existing Oh-My-Zsh.\033[0m"
    else
        install_omz || { center_print "\033[1;31m[!] Oh-My-Zsh failed.\033[0m"; press_enter; return 1; }
    fi
    install_plugins || { center_print "\033[1;31m[!] Plugins failed.\033[0m"; press_enter; return 1; }
    sync_assets
    echo

    CUR_CHANNEL="$(resolve_channel)"
    save_channel "$CUR_CHANNEL"
    ensure_channel_remote "$CUR_CHANNEL"
    center_print "\033[1;32m[✔] Channel: $CUR_CHANNEL\033[0m"
    echo
    center_print "\033[1;32m[✔] Environment Ready.\033[0m"
    echo
}

# UI preferences: banner toggle + banner name. Stored in prefs.conf (userdata/).
setup_preferences() {
    center_print "\033[1;34m[2/3]\033[0m \033[1;33mCustomizing Your Experience...\033[0m"
    echo

    if confirm_action "Enable ASCII Banner on startup?" "y"; then
        USE_BANNER="true"
        local def_name
        def_name=$(whoami 2>/dev/null || echo "User")

        local new_name
        new_name=$(input_prompt "Enter Banner Name (max 12)" "$def_name" 12 "false")

        if [[ "$new_name" == "CANCELLED" ]]; then
            BANNER_NAME="$def_name"
        else
            BANNER_NAME="$new_name"
        fi
        set_pref NAME "$BANNER_NAME"
        center_print "\033[1;32m[✔] Banner '$BANNER_NAME' Enabled.\033[0m"
    else
        USE_BANNER="false"
        BANNER_NAME="Promptify"
        set_pref NAME "$BANNER_NAME"
        center_print "\033[1;32m[✔] Banner Disabled.\033[0m"
    fi
    echo
}

# Move the bootstrap clone into its permanent home at core/. Never deletes a
# directory the user cloned on purpose (only our own temp clone).
setup_persist() {
    if [[ "$INSTALL_DIR" != "$PFY_CORE" ]]; then
        center_print "\e[1;34m[*] \e[0mInstalling Promptify to system..."
        mkdir -p "$PFY_CORE"
        cp -rf "$INSTALL_DIR/." "$PFY_CORE/" 2>/dev/null
        local bootstrap_clone
        bootstrap_clone="$(pwd)/promptify"
        if [[ "$INSTALL_DIR" == "$bootstrap_clone" ]]; then
            rm -rf "$bootstrap_clone" 2>/dev/null
        fi
        INSTALL_DIR="$PFY_CORE"
        record_install_fact LAYOUT 2
    fi
}

guided_setup() {
    # Already on the new layout? Re-running resets UI settings but keeps the
    # snapshot (your original config stays restorable) and userdata.
    if is_promptify_installed && [[ -f "$PFY_MANIFEST" ]]; then
        echo -e "\n \e[1;33m[!] Promptify is already installed.\e[0m"
        if ! confirm_action "Re-run setup wizard? (This will reset current UI settings)" "n"; then
            return 0
        fi
    fi

    # Legacy installs first move into the new layout (keeps everything).
    if is_legacy_layout; then
        center_print "\e[1;34m[*] \e[0mMigrating previous installation to the new layout..."
        migrate_legacy
    fi

    setup_snapshot

    tput civis
    printf "\033[2J\033[H"

    promptify_header

    local term_w
    term_w=$(tput cols)
    local bar_w=52
    [[ -n "$BOX_WIDTH" && $bar_w -lt "$BOX_WIDTH" ]] && bar_w="$BOX_WIDTH"
    [[ $bar_w -gt $((term_w - 2)) ]] && bar_w=$((term_w - 2))
    [[ $bar_w -lt 40 ]] && bar_w=40

    local spacer
    spacer=$(get_spacer "$bar_w")

    printf "%b\033[1;30mPromptify \033[1;34mv${VERSION}\033[0m\n" "$spacer"
    printf "%b\033[1;34m╔$(repeat_char "═" $((bar_w - 2)))╗\n" "$spacer"
    draw_box_line "\033[1;37mPROMPTIFY INSTALLATION WIZARD" "$bar_w" "║" "\033[1;34m" "$spacer" "center"
    printf "%b\033[1;34m╚$(repeat_char "═" $((bar_w - 2)))╝\033[0m\n\n" "$spacer"

    setup_environment || return 1
    setup_preferences
    setup_persist

    # Re-read prefs written during setup_snapshot (SKIP_P10K, NAME, etc.)
    # so generate_runtime() picks them up.  Without this, load_prefs() ran
    # only at startup (before setup_snapshot) and SKIP_P10K was still "false".
    load_prefs

    # Apply writes the managed ~/.zshrc line, generates the runtime, records
    # install state and writes the early self-contained uninstaller. A failed
    # apply must NEVER end in a false "ALL DONE" — if it broke, say so and
    # point at the uninstaller that was written before anything was touched.
    if ! refresh_ui; then
        center_print "\e[1;31m[✗] Apply failed. Promptify was NOT fully installed.\e[0m"
        echo -e "\e[1;33m    Your original config is untouched and can be restored with:\e[0m"
        echo -e "\e[1;36m    bash $PFY_UNINSTALLER\e[0m"
        echo -e "\e[1;33m    Then fix the failing package (e.g. install zsh) and run Guided Setup again.\e[0m"
        tput cnorm
        press_enter
        return 1
    fi
    echo
    center_print "\033[1;32m[✔] ALL DONE! Promptify is now persistent.\033[0m"
    center_print "\033[1;33m[*] Location: $PFY_SYS_DIR\033[0m"

    tput cnorm
    restart_shell
}
