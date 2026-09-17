#!/bin/bash

# Create global binary
create_global_binary() {
    local bin_path="/usr/local/bin/promptify"
    [[ "$OS_TYPE" == "termux" ]] && bin_path="$PREFIX/bin/promptify"

    local target_script="$PFY_CORE/promptify.sh"
    [[ -f "$target_script" ]] || target_script="$INSTALL_DIR/promptify.sh"

    # Idempotent: if the wrapper already exists and points at the right target,
    # skip entirely (no sudo prompt on every local apply).
    if [[ -f "$bin_path" ]] && grep -qF "bash \"$target_script\"" "$bin_path" 2>/dev/null; then
        return 0
    fi

    # Wrapper script
    cat << EOF > promptify_wrapper
#!/bin/bash
bash "$target_script" --local "\$@"
EOF

    if [[ "$OS_TYPE" == "termux" ]]; then
        if ! mv promptify_wrapper "$bin_path" 2>/dev/null && ! cat promptify_wrapper > "$bin_path" 2>/dev/null; then
            echo -e "\e[1;31m[✗] Failed to install the 'promptify' command.\e[0m"
            rm -f promptify_wrapper
            return 1
        fi
        chmod +x "$bin_path" 2>/dev/null
    else
        # Sudo fallback
        sudo_notice "Installing the 'promptify' command system-wide"
        if ! $SUDO mv promptify_wrapper "$bin_path" 2>/dev/null; then
            echo -e "\e[1;31m[✗] Failed to install the 'promptify' command (needs write access to $bin_path).\e[0m"
            echo -e "\e[1;33m    Check that sudo works (id -nG) or that '$USER' can write to $bin_path, then re-run apply.\e[0m"
            rm -f promptify_wrapper
            return 1
        fi
        $SUDO chmod +x "$bin_path" 2>/dev/null
    fi
    rm -f promptify_wrapper
}

# Apply the UI: snapshot first, install terminal assets, generate the runtime
# configs and wire the managed one-line profiles. Safe to re-run any number of
# times — snapshots are idempotent and system writes only happen when stale.
setup_ui() {
    local banner_name=$1
    local theme_border=${2:-"red"}
    local theme_tag=${3:-"blue"}
    local font_pref=${4:-"random"}
    local show_banner=${5:-"true"}
    local prompt_style=${6:-"parrot"}

    # First apply on this machine → take the install snapshot (idempotent).
    if [[ ! -f "$PFY_MANIFEST" ]]; then
        capture_snapshot
    fi

    # Record pre-install state (shell, profiles, UI files) BEFORE anything is
    # modified, so uninstall can restore the exact original state.
    record_install_state

    # Write the self-contained uninstaller EARLY (it only needs the snapshot).
    # If anything below fails — a broken dependency, a bad runtime — the user
    # must still have a working path to restore their original config.
    generate_self_uninstaller

    local asset_dir="$INSTALL_DIR/assets"

    # ---- Terminal UI (Termux) / desktop font — snapshotted before writing ----
    sync_termux_ui "$asset_dir"
    if [[ "$OS_TYPE" != "termux" ]]; then
        if cmd_probe figlet; then
            local figlet_dir="/usr/share/figlet"
            [[ -d "/usr/share/figlet/fonts" ]] && figlet_dir="/usr/share/figlet/fonts"

            # Idempotent: only touch the system figlet dir when a bundled font is
            # missing or stale, so repeated applies never prompt for sudo again.
            local need_font_write=false
            local font_file
            for font_file in "${BUNDLED_FONTS[@]}"; do
                if [[ ! -f "$figlet_dir/$font_file" ]] || ! cmp -s "$asset_dir/$font_file" "$figlet_dir/$font_file"; then
                    need_font_write=true
                    break
                fi
            done

            if [[ "$need_font_write" == true ]]; then
                sudo_notice "Installing system-wide figlet banner fonts"
                if [[ ! -d "$figlet_dir" ]]; then
                    $SUDO mkdir -p "$figlet_dir" 2>/dev/null || true
                fi
                backup_bundled_figlet_fonts
                for font_file in "${BUNDLED_FONTS[@]}"; do
                    if [[ ! -f "$figlet_dir/$font_file" ]] || ! cmp -s "$asset_dir/$font_file" "$figlet_dir/$font_file"; then
                        $SUDO cp "$asset_dir/$font_file" "$figlet_dir/" 2>/dev/null || true
                    fi
                done
            fi
        fi

        # Install Nerd Font + auto-set it in common desktop terminals
        apply_desktop_font
    fi

    # Remember what we wrote into user-owned locations (for safe uninstall
    # even after an update changes the bundled assets)
    record_asset_fingerprints

    # ---- Banner + prefs ----
    if [[ "$show_banner" == "true" ]]; then
        cp "$asset_dir/.draw" "$HOME/.draw" 2>/dev/null || true
        chmod +x "$HOME/.draw" 2>/dev/null || true
        snapshot_created "$HOME/.draw"
    else
        rm -f "$HOME/.draw"
    fi
    set_pref NAME "$banner_name"
    set_pref FONT "$font_pref"
    set_pref STYLE "$prompt_style"

    # ---- Ensure assets are persisted inside core/ (app dir) ----
    if [[ "$INSTALL_DIR" != "$PFY_CORE" && -d "$PFY_CORE" ]]; then
        mkdir -p "$PFY_CORE/assets"
        local font_file
        for font_file in "${BUNDLED_FONTS[@]}"; do
            cp "$asset_dir/$font_file" "$PFY_CORE/assets/" 2>/dev/null
        done
        cp "$asset_dir/termux.properties" "$PFY_CORE/assets/" 2>/dev/null
        cp "$asset_dir/colors.properties" "$PFY_CORE/assets/" 2>/dev/null
        cp "$asset_dir/font.ttf" "$PFY_CORE/assets/" 2>/dev/null
        cp "$asset_dir/.draw" "$PFY_CORE/assets/.draw" 2>/dev/null
    fi

    # ---- Global command ----
    create_global_binary

    # ---- Generate runtime + managed profiles ----
    if ! generate_runtime; then
        return 1
    fi
    write_managed_profiles

    # ---- Switch default shell to Zsh (only when zsh genuinely works — a
    # broken host-Termux shim on PATH inside proot-distro must never become
    # the login shell, and the HOST path must never be chsh'ed into a guest,
    # or every future proot-distro login fails) ----
    if [[ "$SHELL" != *"zsh"* ]]; then
        if [[ "$OS_TYPE" == "termux" ]]; then
            chsh -s zsh 2>/dev/null || true
        else
            local zsh_path
            if zsh_path=$(resolve_real_zsh); then
                sudo_notice "Switching your default shell to zsh"
                # chsh only accepts shells listed in /etc/shells — apt adds them
                # automatically, but a custom build may not have done so.
                if ! grep -qxF "$zsh_path" /etc/shells 2>/dev/null; then
                    $SUDO sh -c "grep -qxF '$zsh_path' /etc/shells 2>/dev/null || echo '$zsh_path' >> /etc/shells" 2>/dev/null || true
                fi
                $SUDO chsh -s "$zsh_path" "$(whoami)" 2>/dev/null || true
            else
                center_print "\e[1;33m[i] zsh isn't usable here — leaving your login shell unchanged.\e[0m"
            fi
        fi
    fi

    record_install_fact LAYOUT 2
    return 0
}
