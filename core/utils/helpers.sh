#!/bin/bash

repeat_char() {
    local char="$1"
    local count="$2"
    local result
    if [[ $count -gt 0 ]]; then
        printf -v result "%*s" "$count" ""
        echo -n "${result// /$char}"
    fi
}

# Get length without ANSI codes
get_clean_len() {
    local text="$1"
    # Remove ANSI escape sequences precisely using sed
    local clean
    clean=$(printf "%b" "$text" | sed "s/\x1B\[\([0-9]\{1,3\}\(;[0-9]\{1,3\}\)*\)\?[mGK]//g")
    echo -n "${#clean}"
}

# One-time, friendly heads-up before Promptify invokes sudo, so the password
# prompt is never a surprise. Defined in the entry script (promptify.sh) so it's
# available during bootstrap/clone too — the FIRST admin need wins, whether
# that's cloning or the setup wizard. Prints only once per session.

# Functional command probe. A bare `command -v` can match a broken PATH entry —
# e.g. the host Termux's binaries visible inside a proot-distro guest (they're
# on PATH but "cannot execute: required file not found"), or a lolcat whose gem
# was wiped by a Ruby upgrade. Those shims then fail at the first real call and
# the "install skipped" bug silently leaves the system broken. So a command
# counts as installed only when it's on PATH AND a benign probe actually runs.
# Probe map: tput/figlet have no --version; everything else uses it.
# Inside a proot-distro guest the HOST Termux bin dir is prepended to PATH by
# termux-profile.sh, so `command -v zsh` finds the host's Android binary and the
# guest never installs its own zsh. For non-Termux systems we therefore probe
# against a PATH with /data/... entries removed — host shims must never count as
# "installed". Real Termux (OS_TYPE=termux) keeps the full PATH.
cmd_probe() {
    local cmd="$1"
    local probe_path=""
    local p
    # PFY_HOST_BIN marks the HOST's binary dir visible inside a proot guest
    # (default /data/... = Termux); overrideable for tests.
    local host_bin="${PFY_HOST_BIN:-/data/}"
    if [[ "$OS_TYPE" != "termux" && "$PATH" == *"$host_bin"* ]]; then
        local IFS=':'
        for p in $PATH; do
            [[ "$p" == "$host_bin"* ]] || probe_path+="$p:"
        done
        unset IFS
        PATH="$probe_path" command -v "$cmd" &>/dev/null || return 1
        case "$cmd" in
            tput)   PATH="$probe_path" "$cmd" cols &>/dev/null ;;
            figlet) PATH="$probe_path" "$cmd" -v &>/dev/null ;;
            *)      PATH="$probe_path" "$cmd" --version &>/dev/null ;;
        esac
        return $?
    fi
    command -v "$cmd" &>/dev/null || return 1
    case "$cmd" in
        tput)   "$cmd" cols &>/dev/null ;;
        figlet) "$cmd" -v &>/dev/null ;;
        *)      "$cmd" --version &>/dev/null ;;
    esac
}

# Canonical, runnable zsh path. `command -v zsh` can return the HOST Termux's
# Android binary inside a proot-distro guest (its PATH is prepended by
# termux-profile.sh): it even `--version`s fine under proot, but it is NOT the
# guest's login shell — `chsh -s /data/data/com.termux/...` then poisons
# `proot-distro login` ("shell ... is not available in container"). We prefer a
# guest-local /usr/bin , /bin or /usr/local/bin zsh; only on real Termux is the
# /data/... path acceptable. Prints the resolved path, exit 1 if none usable.
resolve_real_zsh() {
    local cand
    for cand in "$(command -v zsh)" /usr/bin/zsh /bin/zsh /usr/local/bin/zsh; do
        [[ -n "$cand" ]] || continue
        [[ "$cand" == "/data/"* && "$OS_TYPE" != "termux" ]] && continue
        [[ -x "$cand" ]] || continue
        if "$cand" --version &>/dev/null; then
            printf '%s' "$cand"
            return 0
        fi
    done
    return 1
}

check_status() {
    local all_found=true
    local cmd
    for cmd in "$@"; do
        if ! cmd_probe "$cmd"; then
            all_found=false
            break
        fi
    done
    [[ "$all_found" == true ]] && printf "\033[1;32m✔\033[0m" || printf "\033[1;31m✘\033[0m"
}

check_path() {
    local all_found=true
    local p
    for p in "$@"; do
        if [[ ! -d "$p" && ! -f "$p" ]]; then
            all_found=false
            break
        fi
    done
    [[ "$all_found" == true ]] && printf "\033[1;32m✔\033[0m" || printf "\033[1;31m✘\033[0m"
}

is_promptify_installed() {
    # New layout: snapshot manifest + runtime present.
    if [[ -d "$PFY_SYS_DIR" && -f "$PFY_MANIFEST" ]]; then
        return 0
    fi
    # Legacy layout: inline marker in the profile OR the old install dir.
    if [[ -f "$HOME/.zshrc" ]] && grep -q "# --- Promptify Config ---" "$HOME/.zshrc" 2>/dev/null; then
        return 0
    fi
    [[ -d "$SYS_DIR" ]]
}

check_setup() {
    # Ensure a legacy install is migrated before requiring the new layout.
    if is_legacy_layout && [[ ! -f "$PFY_MANIFEST" ]]; then
        migrate_legacy
    fi
    if [[ ! -d "$PFY_SYS_DIR" || ! -f "$PFY_RUNTIME_ZSHRC" ]]; then
        echo -e " \e[1;31m[!] Error: Run Guided Setup first.\e[0m"
        press_enter
        return 1
    fi
    return 0
}

draw_separator() {
    local width="$1"
    local spacer="$2"
    local char="${3:-─}"
    local line
    if [[ -n "$width" ]]; then
        line=$(repeat_char "$char" "$width")
    else
        local term_w
        term_w=$(tput cols 2>/dev/null || echo 80)
        line=$(repeat_char "$char" "$((term_w - 2))")
    fi
    printf "%b\e[1;30m%s\e[0m\n" "$spacer" "$line"
}

get_spacer() {
    local width="$1"
    local term_w
    term_w=$(tput cols 2>/dev/null || echo 80)
    local offset=$(( (term_w - width) / 2 ))
    [[ $offset -lt 0 ]] && offset=0
    printf "%${offset}s" ""
}

# Unified box width: content-based (v1.1 style) so boxes hug their content on
# wide terminals too, capped to fit. Used by the banner, dashboard and menus so
# every box stays aligned through resizes.
calc_box_width() {
    local w=$(( $1 ))
    local term_w
    term_w=$(tput cols 2>/dev/null || echo 80)
    [[ $w -gt $((term_w - 2)) ]] && w=$((term_w - 2))
    [[ $w -lt 40 ]] && w=40
    printf "%d" "$w"
}

center_print() {
    local text="$1"
    local clean_len
    clean_len=$(get_clean_len "$text")
    local spacer
    spacer=$(get_spacer "$clean_len")
    printf "\r%b%b\033[0m\033[K\n" "$spacer" "$text"
}

# Cross-platform sed -i
sed_i() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# Box line drawing
# Arguments: content, width, char, color, spacer, align
draw_box_line() {
    local content="$1"
    local box_w="$2"
    local b_char="${3:-║}"
    local b_clr="${4:-\033[1;34m}"
    local offset_spacer="$5"
    local align="${6:-center}"
    local r_clr="\033[0m"
    
    local clean_len
    clean_len=$(get_clean_len "$content")
    local total_pad=$((box_w - clean_len - 4)) # -4 for "B " and " B"
    [[ $total_pad -lt 0 ]] && total_pad=0

    local pad_l=0
    local pad_r=0

    if [[ "$align" == "center" ]]; then
        pad_l=$((total_pad / 2))
        pad_r=$((total_pad - pad_l))
    else
        # Left align: all padding on the right
        pad_r=$total_pad
    fi
    
    local padding_l=""
    local padding_r=""
    [[ $pad_l -gt 0 ]] && padding_l=$(printf "%${pad_l}s" "")
    [[ $pad_r -gt 0 ]] && padding_r=$(printf "%${pad_r}s" "")

    printf "%b%b%s %s%b%s %b%s%b\n" "$offset_spacer" "$b_clr" "$b_char" "$padding_l" "$content" "$padding_r" "$b_clr" "$b_char" "$r_clr"
}
