#!/bin/bash

is_installed() {
    cmd_probe "$1"
}

# Many of these boxes are proot-distro guests (the host Termux dir is visible
# inside the guest). Sudo there only escalates when it was configured AS ROOT
# first; otherwise every sudo call dies with setuid/ownership errors that have
# nothing to do with the user being in a 'wheel' group. Give the real answer.
proot_env_hint() {
    [[ -d "/data/data/com.termux/files" ]] || return 0
    echo -e "\e[1;33m    (proot/Termux) You are a non-root user inside proot-distro, but sudo is broken\n"
    echo -e "\e[1;33m    here and cannot escalate. apt needs to run as the guest root. Easiest: exit\n"
    echo -e "\e[1;33m    this shell and start the guest as root instead, then re-run Promptify:\n"
    echo -e "\e[1;33m        proot-distro login <distro>       (run this on the host Termux)\n"
    echo -e "\e[1;33m    To keep a normal user, fix sudo AS root inside the guest first:\n"
    echo -e "\e[1;33m        chown root:root /etc/sudo.conf /etc/sudoers 2>/dev/null; chmod 4755 /usr/bin/sudo;"
    echo -e "\e[1;33m        usermod -aG sudo <user>\e[0m"
}

install_dependencies() {
    local skip_power="${1:-false}"
    local sudo_err
    # --- Admin access check: fail loudly & early if we can't elevate. Only for
    # system package managers (Termux's pkg and Homebrew don't need root) ---
    case "$PKG_MNGR" in
        apt|pacman|dnf|zypper|apk|emerge|xbps|slackpkg)
            if [[ "$(id -u)" -ne 0 ]]; then
                if [[ -z "$SUDO" ]]; then
                    echo -e "\e[1;31m[✗] Dependencies need root, but no 'sudo' or 'doas' was found.\e[0m"
                    proot_env_hint
                    echo -e "\e[1;33m    On a regular system, install sudo as root and add your user to the wheel group, then re-run.\e[0m"
                    return 1
                fi
                sudo_notice "Installing system dependencies"
                if [[ "$SUDO" == "sudo" ]]; then
                    if ! sudo_err=$($SUDO -v 2>&1); then
                        # Distinguish a broken sudo (setuid/ownership/config) from an
                        # ordinary "user not permitted" refusal so the advice fits.
                        if [[ "$sudo_err" == *setuid* || "$sudo_err" == *"owned by"* || "$sudo_err" == *"must be owned"* ]]; then
                            echo -e "\e[1;31m[✗] sudo is installed but broken here (it cannot escalate).\e[0m"
                            [[ -n "$sudo_err" ]] && echo -e "\e[1;33m    (sudo said: $(printf '%s' "$sudo_err" | head -1))\e[0m"
                            proot_env_hint
                        else
                            echo -e "\e[1;31m[✗] Admin (sudo) access is required to install dependencies.\e[0m"
                            echo -e "\e[1;33m    Your user must be allowed to sudo (e.g. add to the 'wheel' group: usermod -aG wheel ${USER}), then log out and back in.\e[0m"
                        fi
                        return 1
                    fi
                else
                    $SUDO true || {
                        echo -e "\e[1;31m[✗] Admin (doas) access is required to install dependencies.\e[0m"
                        proot_env_hint
                        return 1
                    }
                fi
            fi
            ;;
    esac

    echo -e "\033[1;34m[*] \033[32mUpdating package list...\033[0m"
    
    case $PKG_MNGR in
        pkg) pkg update -y || return 1 ;;
        apt) $SUDO apt update -y || return 1 ;;
        pacman) $SUDO pacman -Sy --noconfirm || return 1 ;;
        dnf) $SUDO dnf check-update -y || true ;;
        zypper) $SUDO zypper refresh || return 1 ;;
        xbps) $SUDO xbps-install -S || return 1 ;;
        slackpkg) $SUDO slackpkg -batch=on -default_answer=y update || return 1 ;;
        apk) $SUDO apk update || return 1 ;;
        brew) brew update || return 1 ;;
        unknown) echo -e "\e[1;33m[!] Unknown package manager. Skipping update...\e[0m" ;;
    esac

    echo -e "\033[1;34m[*] \033[32mChecking and installing dependencies...\033[0m"

    # Base Packages
    local base_pkgs=("figlet" "git" "zsh")
    local dep_failed=false
    for pkg in "${base_pkgs[@]}"; do
        if ! is_installed "$pkg"; then
            echo -e "\033[1;34m[*] \033[32mInstalling $pkg...\033[0m"
            install_single_pkg "$pkg" || dep_failed=true
        fi
    done

    # Terminal Helpers (package name varies by manager)
    if ! is_installed tput; then
        local tput_pkg="ncurses"
        case $PKG_MNGR in
            pkg) tput_pkg="ncurses-utils" ;;
            apt) tput_pkg="ncurses-bin" ;;
            xbps) tput_pkg="ncurses" ;;
        esac
        install_single_pkg "$tput_pkg" || dep_failed=true
    fi

    # Termux Specifics
    if [[ "$OS_TYPE" == "termux" ]]; then
        for tpkg in "termux-api" "termux-tools"; do
             if ! is_installed "$tpkg"; then
                 install_single_pkg "$tpkg" || dep_failed=true
             fi
        done
    fi

    # lolcat (optional — the banner falls back to an ANSI gradient when it's
    # missing, and reinstall/repair is available from Dependencies)
    if ! is_installed lolcat; then
        install_lolcat \
            || echo -e "\e[1;33m[!] Could not install lolcat (optional, continuing without it).\e[0m"
    fi

    # Optional Power Tools (skipped when the caller already offers them, e.g.
    # the Dependencies menu's separate "Others (Eza, Bat)" item)
    if [[ "$skip_power" == "true" ]]; then
        :
    elif [[ "$CONFIRM_ALL" == "false" ]]; then
        local opts=()
        local pkgs=()
        
        if ! is_installed eza && ! is_installed exa; then
            opts+=("Eza|selected")
            pkgs+=("eza")
        fi
        if ! is_installed bat && ! is_installed batcat; then
            opts+=("Bat|selected")
            pkgs+=("bat")
        fi

        if [[ ${#opts[@]} -gt 0 ]]; then
            echo -e "\n\e[1;34m[*] Optional Power Tools:\e[0m"
            local choices
            choices=$(checkbox_menu "Select Power Tools to Install" \
"Recommended: install both. Eza & Bat make 'ls' and 'cat' look nicer (icons, colors).
Skip for now? You can add them anytime later from Dependencies → Others." \
"${opts[@]}")
            if [[ "$choices" != "CANCELLED" ]]; then
                for idx in $choices; do
                    install_single_pkg "${pkgs[$idx]}"
                done
            fi
        fi
    else
        # Unattended defaults
        ! is_installed eza && ! is_installed exa && install_single_pkg "eza"
        ! is_installed bat && ! is_installed batcat && install_single_pkg "bat"
    fi

    if [[ "$dep_failed" == "true" ]]; then
        echo -e "\e[1;31m[✗] Some required packages failed to install (see messages above).\e[0m"
        return 1
    fi

    return 0
}

install_single_pkg() {
    local pkg="$1"
    echo -e "\033[1;34m[*] \033[32mInstalling $pkg...\033[0m"
    local cmd=()
    case $PKG_MNGR in
        pkg)     cmd=(pkg install "$pkg" -y) ;;
        apt)     cmd=($SUDO apt install "$pkg" -y) ;;
        pacman)  cmd=($SUDO pacman -S --noconfirm "$pkg") ;;
        dnf)     cmd=($SUDO dnf install -y "$pkg") ;;
        zypper)  cmd=($SUDO zypper install -y "$pkg") ;;
        xbps)    cmd=($SUDO xbps-install -y "$pkg") ;;
        slackpkg) cmd=($SUDO slackpkg -batch=on -default_answer=y install "$pkg") ;;
        apk)     cmd=($SUDO apk add "$pkg") ;;
        emerge)  cmd=($SUDO emerge --ask n "$pkg") ;;
        brew)    cmd=(brew install "$pkg") ;;
        *)
            echo -e "\e[1;31m[✗] No installer known for package manager '$PKG_MNGR'.\e[0m"
            return 1
            ;;
    esac

    if "${cmd[@]}"; then
        return 0
    fi

    echo -e "\e[1;31m[✗] Failed to install '$pkg'.\e[0m"
    echo -e "\e[1;33m    Command used: ${cmd[*]}\e[0m"
    echo -e "\e[1;33m    Fix: run it manually (add 'sudo' if needed), then re-run Promptify.\e[0m"
    return 1
}

# Install lolcat the right way for the current OS/package manager.
install_lolcat() {
    if [[ "$OS_TYPE" == "termux" ]]; then
        echo -e "\033[1;34m[*] \033[32mInstalling lolcat via gem (Termux)...\033[0m"
        if ! is_installed ruby; then
            install_single_pkg "ruby"
        fi
        # Termux Ruby needs the openssl package at runtime for gem HTTPS
        if ! is_installed openssl; then
            install_single_pkg "openssl"
        fi
        # If Ruby still can't load openssl, reinstall it to fix the linkage
        if ! ruby -e 'require "openssl"' &>/dev/null; then
            echo -e "\033[1;34m[*] \033[32mReinstalling Ruby with OpenSSL support...\033[0m"
            pkg reinstall ruby -y || pkg install ruby -y
        fi
        gem install lolcat --no-document
    else
        case $PKG_MNGR in
            apt|pacman|dnf|zypper|apk|brew|xbps|slackpkg)
                install_single_pkg "lolcat"
                ;;
            *)
                echo -e "\033[1;34m[*] \033[32mInstalling lolcat via gem...\033[0m"
                if ! is_installed ruby; then
                    install_single_pkg "ruby"
                fi
                $SUDO gem install lolcat --no-document
                ;;
        esac
    fi
}

# Repair a broken or missing lolcat. A Ruby upgrade that wipes the gem leaves a
# dead lolcat on PATH (`command -v` says installed, every run fails with a
# GemNotFoundException) — the functional is_installed probe catches that.
repair_lolcat() {
    if is_installed lolcat; then
        echo -e "\033[1;32m[✔] Lolcat is working.\033[0m"
        return 0
    fi
    if command -v lolcat &>/dev/null; then
        echo -e "\e[1;33m[!] lolcat found but not working (broken gem install?). Reinstalling...\e[0m"
    fi
    if install_lolcat && is_installed lolcat; then
        echo -e "\033[1;32m[✔] lolcat repaired.\033[0m"
        return 0
    fi
    echo -e "\e[1;33m[!] Could not repair lolcat (optional — the banner uses an ANSI gradient instead).\e[0m"
    return 1
}

install_power_tools() {
    echo -e "\033[1;34m[*] \033[32mInstalling Others (Eza, Bat)...\033[0m"
    local ok=true
    if is_installed eza || is_installed exa; then
        echo -e "\033[1;32m[✔] Eza/Exa already present.\033[0m"
    else
        install_single_pkg "eza" || ok=false
    fi
    if is_installed bat || is_installed batcat; then
        echo -e "\033[1;32m[✔] Bat already present.\033[0m"
    else
        install_single_pkg "bat" || ok=false
    fi
    [[ "$ok" == "true" ]]
}

sync_assets() {
    echo -e "\033[1;34m[*] \033[32mSyncing UI Assets...\033[0m"
    local asset_dir="$INSTALL_DIR/assets"

    # Ensure the app dir (core/) has the assets
    mkdir -p "$PFY_CORE/assets"
    local font_file
    for font_file in "${BUNDLED_FONTS[@]}"; do
        cp "$asset_dir/$font_file" "$PFY_CORE/assets/" 2>/dev/null || true
    done
    cp "$asset_dir/.draw" "$PFY_CORE/assets/.draw" 2>/dev/null || true
    cp "$asset_dir/termux.properties" "$PFY_CORE/assets/" 2>/dev/null || true
    cp "$asset_dir/colors.properties" "$PFY_CORE/assets/" 2>/dev/null || true
    cp "$asset_dir/font.ttf" "$PFY_CORE/assets/" 2>/dev/null || true

    # Refresh the live banner renderer only if the banner is currently enabled
    if [[ -f "$HOME/.draw" ]]; then
        cp "$asset_dir/.draw" "$HOME/.draw" 2>/dev/null || true
        chmod +x "$HOME/.draw" 2>/dev/null || true
        snapshot_created "$HOME/.draw"
    fi

    # PC: install Nerd Font + auto-set in common desktop terminals
    if [[ "$OS_TYPE" != "termux" ]]; then
        apply_desktop_font
    fi

    sync_termux_ui "$asset_dir"

    record_install_state
}
