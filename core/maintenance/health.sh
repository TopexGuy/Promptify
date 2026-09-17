#!/bin/bash

# System Health: verification panel for a Promptify install. Every check maps
# to a real fixer so "Fix All" can actually repair the install, not just
# refresh the UI.

HEALTH_ROWS=()   # "label|status|detail"  (status: ok | fail | warn)
HEALTH_FIXES=()  # parallel: fixer function name, or "none"
HEALTH_PASS=0
HEALTH_FAIL=0
HEALTH_NOTE=0

run_health_checks() {
    HEALTH_ROWS=()
    HEALTH_FIXES=()
    HEALTH_PASS=0
    HEALTH_FAIL=0
    HEALTH_NOTE=0

    local label status detail

    # 1. Layout / migration state
    if is_legacy_layout && [[ ! -f "$PFY_MANIFEST" ]]; then
        HEALTH_ROWS+=("Layout|warn|Legacy install — migrating recommended")
        HEALTH_FIXES+=(migrate_legacy)
        HEALTH_NOTE=$((HEALTH_NOTE + 1))
    elif [[ -f "$PFY_MANIFEST" ]]; then
        HEALTH_ROWS+=("Layout|ok|Promptify installed")
        HEALTH_FIXES+=(none)
        HEALTH_PASS=$((HEALTH_PASS + 1))
    else
        HEALTH_ROWS+=("Layout|fail|Not installed — run Guided Setup")
        HEALTH_FIXES+=(guided_setup)
        HEALTH_FAIL=$((HEALTH_FAIL + 1))
    fi

    # 2. Snapshot integrity (every captured file must exist in backup/system/files)
    if [[ -f "$PFY_MANIFEST" ]]; then
        local missing=0 total=0 kind path rel
        while IFS='|' read -r kind path rel _; do
            [[ "$kind" == "P" ]] || continue
            total=$((total + 1))
            [[ -f "$PFY_BACKUP_FILES/$rel" ]] || missing=$((missing + 1))
        done < "$PFY_MANIFEST"
        if [[ "$total" -eq 0 ]]; then
            HEALTH_ROWS+=("Snapshot|ok|Nothing captured — fresh profile")
            HEALTH_FIXES+=(none)
            HEALTH_PASS=$((HEALTH_PASS + 1))
        elif [[ "$missing" -eq 0 ]]; then
            HEALTH_ROWS+=("Snapshot|ok|$total original files backed up")
            HEALTH_FIXES+=(none)
            HEALTH_PASS=$((HEALTH_PASS + 1))
        else
            HEALTH_ROWS+=("Snapshot|fail|$missing of $total original files missing")
            HEALTH_FIXES+=(none)
            HEALTH_FAIL=$((HEALTH_FAIL + 1))
        fi
    fi

    # 3. Runtime shell config
    if [[ -f "$PFY_RUNTIME/zshrc" ]]; then
        if ! cmd_probe zsh; then
            HEALTH_ROWS+=("Runtime|warn|zsh not usable — install zsh")
            HEALTH_FIXES+=(none)
            HEALTH_NOTE=$((HEALTH_NOTE + 1))
        elif zsh -n "$PFY_RUNTIME/zshrc" &>/dev/null; then
            HEALTH_ROWS+=("Runtime|ok|zshrc valid")
            HEALTH_FIXES+=(none)
            HEALTH_PASS=$((HEALTH_PASS + 1))
        else
            HEALTH_ROWS+=("Runtime|fail|zsh syntax error")
            HEALTH_FIXES+=(refresh_ui)
            HEALTH_FAIL=$((HEALTH_FAIL + 1))
        fi
    else
        HEALTH_ROWS+=("Runtime|fail|zshrc missing")
        HEALTH_FIXES+=(refresh_ui)
        HEALTH_FAIL=$((HEALTH_FAIL + 1))
    fi

    # 4. Dependencies (bundled deps/)
    local deps_ok=false
    if [[ -d "$PFY_DEPS_PLUGINS" && -f "$PFY_DEPS_OMZ/oh-my-zsh.sh" ]]; then
        deps_ok=true
    elif [[ -f "/usr/share/oh-my-zsh/oh-my-zsh.sh" ]]; then
        deps_ok=true
    fi
    if [[ "$deps_ok" == "true" ]]; then
        HEALTH_ROWS+=("Dependencies|ok|Oh-My-Zsh + plugins present")
        HEALTH_FIXES+=(none)
        HEALTH_PASS=$((HEALTH_PASS + 1))
    else
        HEALTH_ROWS+=("Dependencies|fail|Incomplete — use Fix / Install Deps")
        HEALTH_FIXES+=(fix_deps)
        HEALTH_FAIL=$((HEALTH_FAIL + 1))
    fi

    # 5. Managed profile line
    if grep -q "promptify/runtime/zshrc" "$HOME/.zshrc" 2>/dev/null; then
        HEALTH_ROWS+=("Profile|ok|Managed line present in ~/.zshrc")
        HEALTH_FIXES+=(none)
        HEALTH_PASS=$((HEALTH_PASS + 1))
    else
        HEALTH_ROWS+=("Profile|fail|~/.zshrc not managed")
        HEALTH_FIXES+=(refresh_ui)
        HEALTH_FAIL=$((HEALTH_FAIL + 1))
    fi

    # 6. Global binary
    if [[ -x "$PREFIX/bin/promptify" || -x "/usr/local/bin/promptify" ]]; then
        HEALTH_ROWS+=("Binary|ok|Global 'promptify' available")
        HEALTH_FIXES+=(none)
        HEALTH_PASS=$((HEALTH_PASS + 1))
    else
        HEALTH_ROWS+=("Binary|fail|'promptify' command not installed")
        HEALTH_FIXES+=(refresh_ui)
        HEALTH_FAIL=$((HEALTH_FAIL + 1))
    fi

    # 7. Junk files (informational)
    local junk=()
    [[ -e "$HOME/.zshrc.pre-promptify" ]] && junk+=("~/.zshrc.pre-promptify")
    [[ -e "$HOME/.promptify_font.flf" ]] && junk+=("~/.promptify_font.flf")
    if [[ ${#junk[@]} -gt 0 ]]; then
        HEALTH_ROWS+=("Junk|warn|Leftover files: ${junk[*]}")
        HEALTH_FIXES+=(remove_health_junk)
        HEALTH_NOTE=$((HEALTH_NOTE + 1))
    fi
}

remove_health_junk() {
    rm -f "$HOME/.zshrc.pre-promptify" "$HOME/.promptify_font.flf"
}

# Fixer: install missing bundled dependencies (best-effort, non-interactive).
fix_deps() {
    install_dependencies skip_power
    [[ -f "$PFY_DEPS_OMZ/oh-my-zsh.sh" ]] || install_omz
    if [[ -f "$PFY_DEPS_OMZ/oh-my-zsh.sh" ]] &&
       [[ ! -f "$PFY_DEPS_PLUGINS/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
        install_plugins
    fi
}

# Render the health panel as a boxed, aligned status report. Used as the
# Dependencies menu header, so it exports BOX_WIDTH for menu synchronization.
health_panel() {
    run_health_checks

    local b_clr="\033[1;34m"
    local t_clr="\033[1;36m"
    local r_clr="\033[0m"

    local label_w=0
    local row label
    for row in "${HEALTH_ROWS[@]}"; do
        label="${row%%|*}"
        [[ ${#label} -gt $label_w ]] && label_w=${#label}
    done
    label_w=$((label_w + 2))

    local content_w=0
    local lines=()
    local rest status detail glyph glyph_c plain_lw
    for row in "${HEALTH_ROWS[@]}"; do
        label="${row%%|*}"
        rest="${row#*|}"
        status="${rest%%|*}"
        detail="${rest#*|}"
        case "$status" in
            ok)   glyph="✔"; glyph_c="\033[1;32m" ;;
            fail) glyph="✘"; glyph_c="\033[1;31m" ;;
            warn) glyph="!"; glyph_c="\033[1;33m" ;;
        esac
        plain_lw=$(( label_w + 1 + ${#detail} + 2 ))  # padded label + dot + detail
        [[ $plain_lw -gt $content_w ]] && content_w=$plain_lw
        lines+=("$glyph|$glyph_c|$status|$label|$detail")
    done
    [[ $content_w -lt 24 ]] && content_w=24

    local box_w
    box_w=$(calc_box_width $((content_w + 6)))
    export BOX_WIDTH=$box_w

    local spacer
    spacer=$(get_spacer "$box_w")

    local title=" System Health "
    local total_side_len=$((box_w - 2 - ${#title}))
    local side_len=$((total_side_len / 2))
    local side_line
    side_line=$(repeat_char "─" "$side_len")

    local line_top="${spacer}${b_clr}╭${side_line}${t_clr}${title}${b_clr}${side_line}"
    [[ $((total_side_len % 2)) -ne 0 ]] && line_top+="─"
    line_top+="╮${r_clr}"
    printf "%b\n" "$line_top" >&2

    local pad_l pad_r filler plain
    for row in "${lines[@]}"; do
        glyph="${row%%|*}"; rest="${row#*|}"
        glyph_c="${rest%%|*}"; rest="${rest#*|}"
        status="${rest%%|*}"; rest="${rest#*|}"
        label="${rest%%|*}"; detail="${rest#*|}"
        filler=$((content_w - label_w - ${#detail} - 2))
        local content
        content=$(printf "%s %-*s \033[2;37m%s\033[0m %s" \
            "${glyph_c}${glyph}${r_clr}" "$label_w" "$label" \
            "$(repeat_char "·" "$filler")" \
            "${glyph_c}${detail}${r_clr}")
        draw_box_line "$content" "$box_w" "│" "$b_clr" "$spacer" "left" >&2
    done

    local result_line
    result_line="\033[1;36mResult:\033[0m \033[1;32m$HEALTH_PASS passed\033[0m, \033[1;31m$HEALTH_FAIL failed\033[0m, \033[1;33m$HEALTH_NOTE noted\033[0m"
    draw_box_line "$result_line" "$box_w" "│" "$b_clr" "$spacer" "left" >&2

    printf "%b\n" "${spacer}${b_clr}╰$(repeat_char "─" $((box_w - 2)))╯${r_clr}" >&2
}

# Fix every failing check. Fix All from the Dependencies menu.
fix_all_issues() {
    if [[ "$HEALTH_FAIL" -eq 0 ]]; then
        center_print "\e[1;32m[✔] All health checks passed — nothing to fix.\e[0m"
        press_enter
        return
    fi
    if ! confirm_action "Fix all failing checks now? (installs missing packages)" "y"; then
        return
    fi

    local i fixer
    for i in "${!HEALTH_ROWS[@]}"; do
        local row="${HEALTH_ROWS[i]}"
        local status="${row#*|}"
        status="${status%%|*}"
        fixer="${HEALTH_FIXES[i]}"
        [[ "$status" == "fail" && "$fixer" != "none" && -n "$fixer" ]] || continue
        echo -e "\n\e[1;34m[*] Fixing:\e[0m ${row%%|*}"
        "$fixer"
    done

    echo
    center_print "\e[1;32m[✔] Repair pass complete. Re-running health checks...\e[0m"
    press_enter
}
