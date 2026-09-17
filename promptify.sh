#!/bin/bash
# PROMPTIFY

# 1. Mode Detection 
STABLE_URL="https://github.com/TopexGuy/promptify.git"
TESTING_URL="https://github.com/anonytry/Promptify.git"
CHANNEL_BRANCH="main"
CHANNEL="${CHANNEL:-stable}"
CHANNEL_SET=false
IS_LOCAL=false
CONFIRM_ALL=false
SILENT_MODE=false
POST_UPDATE=false

# Where the user launched Promptify from — the reloaded shell starts here so it
# never lands in the clone/system directory after an apply.
ORIGINAL_DIR="$(pwd)"

# One-time, friendly heads-up before Promptify invokes sudo, so the password
# prompt is never a surprise. Defined early (in the entry script) because the
# FIRST admin need can happen during bootstrap/clone when core deps (git, tput)
# are missing — the wizard's "sudo access" line should appear there instead.
# Prints only once per session: whichever step needs admin first wins.
SUDO_NOTICE_SHOWN=false
sudo_notice() {
    local reason="${1:-make a system change}"
    [[ "$SUDO_NOTICE_SHOWN" == "true" ]] && return 0
    SUDO_NOTICE_SHOWN=true
    echo -e "\033[1;33m[i] ${reason} — needs \033[1;31madmin (sudo)\033[0m\033[1;33m access. You'll be asked once.\033[0m"
}

# Resolve script path
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SOURCE" )" 2>/dev/null && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" 2>/dev/null && pwd )"

# APK/AOSP-style layout constants (needed before bootstrap so a persistent
# install is found even when this script is launched from elsewhere).
SYS_DIR="$HOME/.promptify"
if [[ -f "$SCRIPT_DIR/core/env/layout.sh" ]]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/core/env/layout.sh"
else
    PFY_CORE="$SYS_DIR/core"
fi
export SYS_DIR

# Parse flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --local) IS_LOCAL=true; shift ;;
        --yes|-y) CONFIRM_ALL=true; shift ;;
        --silent|-s) SILENT_MODE=true; CONFIRM_ALL=true; shift ;;
        --channel) CHANNEL="${2:-stable}"; CHANNEL_SET=true; shift 2 || shift ;;
        --post-update) POST_UPDATE=true; shift ;;
        *) shift ;;
    esac
done

# Silent mode helper: show live output unless --silent is used
run_cmd() {
    if [[ "$SILENT_MODE" == "true" ]]; then
        "$@" &>/dev/null
    else
        "$@"
    fi
}

if [[ -f "$SCRIPT_DIR/promptify.sh" && -d "$SCRIPT_DIR/core" ]]; then
    INSTALL_DIR="$SCRIPT_DIR"
elif [[ -f "promptify.sh" && -d "core" ]]; then
    INSTALL_DIR="$(pwd)"
fi

if [[ "$IS_LOCAL" == "false" ]]; then
    if [[ -n "$INSTALL_DIR" ]]; then
        IS_LOCAL=true
    fi
fi

# Persistent install fallback: launched via the global 'promptify' wrapper or a
# path under ~/.promptify, so INSTALL_DIR may be empty. Resolve to the app dir
# (core/) or a legacy flat install before falling through to bootstrap.
if [[ -z "$INSTALL_DIR" ]]; then
    if [[ -f "$PFY_CORE/promptify.sh" ]]; then
        INSTALL_DIR="$PFY_CORE"
        IS_LOCAL=true
    elif [[ -f "$SYS_DIR/promptify.sh" ]]; then
        INSTALL_DIR="$SYS_DIR"
        IS_LOCAL=true
    fi
fi

# 2. Remote Bootstrap Execution
if [[ "$IS_LOCAL" == "false" ]]; then
    INSTALL_DIR="$(pwd)/promptify"
    
    [[ "$SILENT_MODE" == "false" ]] && echo -e "\e[1;34m[*] Promptify: Bootstrap Mode\e[0m"

    # Ensure git actually runs — a bare `command -v` can match a broken PATH
    # entry (e.g. the host Termux's git visible inside a proot-distro Linux),
    # which would make every later git call fail.
    if ! command -v git &>/dev/null || ! git --version &>/dev/null; then
        [[ "$SILENT_MODE" == "false" ]] && echo -ne "\e[1;34m[*] Installing git...\e[0m"
        bs_sudo=""
        if [[ "$(id -u)" -ne 0 ]]; then
            if command -v sudo &>/dev/null; then
                bs_sudo="sudo"
            elif command -v doas &>/dev/null; then
                bs_sudo="doas"
            fi
        fi
        # A dead host-Termux sudo shim (inside proot-distro) or a misconfigured
        # guest sudo passes `command -v` but dies instantly — say so clearly
        # here rather than letting apt fail silently a few lines down.
        if [[ "$bs_sudo" == "sudo" ]]; then
            bs_sudo_err=$($bs_sudo -v 2>&1) || {
                if [[ "$bs_sudo_err" == *setuid* || "$bs_sudo_err" == *"owned by"* || "$bs_sudo_err" == *"must be owned"* ]]; then
                    echo -e " \e[1;31m[!] sudo is installed but broken here (it cannot escalate).\e[0m"
                    [[ -n "$bs_sudo_err" ]] && echo -e " \e[1;33m    (sudo said: $(printf '%s' "$bs_sudo_err" | head -1))\e[0m"
                    if [[ -d "/data/data/com.termux/files" ]]; then
                        echo -e " \e[1;33m    (proot/Termux) Start the guest as root and re-run:  proot-distro login <distro>\e[0m"
                        echo -e " \e[1;33m    (run that on the host Termux)\e[0m"
                    fi
                    exit 1
                fi
            }
        fi
        # First admin need of the session can be right here (deps missing at
        # clone time) — the once-per-session sudo notice belongs at whichever
        # step actually elevates first.
        if [[ -n "$bs_sudo" ]]; then
            sudo_notice "Installing git"
        fi

        if [[ -f /etc/os-release ]]; then
            if command -v apt &>/dev/null; then
                run_cmd $bs_sudo apt update -y
                run_cmd $bs_sudo apt install git -y
            elif command -v pacman &>/dev/null; then
                run_cmd $bs_sudo pacman -Sy --noconfirm git
            elif command -v dnf &>/dev/null; then
                run_cmd $bs_sudo dnf install -y git
            elif command -v zypper &>/dev/null; then
                run_cmd $bs_sudo zypper install -y git
            elif command -v xbps-install &>/dev/null; then
                run_cmd $bs_sudo xbps-install -S
                run_cmd $bs_sudo xbps-install -y git
            elif command -v slackpkg &>/dev/null; then
                run_cmd $bs_sudo slackpkg -batch=on -default_answer=y update
                run_cmd $bs_sudo slackpkg -batch=on -default_answer=y install git
            elif command -v emerge &>/dev/null; then
                run_cmd $bs_sudo emerge --ask n dev-vcs/git
            elif command -v apk &>/dev/null; then
                run_cmd $bs_sudo apk add git
            elif command -v brew &>/dev/null; then
                run_cmd brew install git
            else
                echo -e " \e[1;31m[!] Could not detect a package manager. Install git manually.\e[0m"
                exit 1
            fi
        elif [[ -d "/data/data/com.termux/files/usr/bin" ]]; then
            run_cmd pkg install git -y
        else
            echo -e " \e[1;31m[!] Could not detect a package manager. Install git manually.\e[0m"
            exit 1
        fi
        [[ "$SILENT_MODE" == "false" ]] && echo -e " \e[1;32mDone.\e[0m"
        # Drop bash's cached path for git (it may have resolved to the broken
        # host-Termux binary earlier) so the freshly installed one is used.
        hash -r
        if ! git --version &>/dev/null; then
            echo -e " \e[1;31m[!] git is still not working. Install it manually, then re-run.\e[0m"
            exit 1
        fi
    fi
    hash -r
    
    if [[ -d "$INSTALL_DIR" ]]; then
        if [[ "$CONFIRM_ALL" == "true" ]]; then
            CONF_RECLONE="y"
        else
            echo -ne " \e[1;33m[!] Directory '$INSTALL_DIR' already exists. Overwrite? (y/N): \e[0m"
            read -r CONF_RECLONE
        fi

        if [[ "$CONF_RECLONE" != [Y/y] ]]; then
            echo -e " \e[1;31m[!] Aborting.\e[0m"
            exit 1
        fi
        rm -rf "$INSTALL_DIR"
    fi

    # Channel switcher (first run)
    if [[ "$CHANNEL_SET" == "false" && "$CONFIRM_ALL" == "false" ]]; then
        echo
        echo -e " \e[1;33m[?] Select update channel:\e[0m"
        echo -e "   \e[1;36m1)\e[0m Stable  [default]"
        echo -e "   \e[1;36m2)\e[0m Testing"
        echo -ne " \e[1;33mChoice [1/2]: \e[0m"
        read -r CH_SEL
        [[ "$CH_SEL" == "2" || "$CH_SEL" == "testing" ]] && CHANNEL="testing"
    fi
    
    clone_url="$STABLE_URL"
    [[ "$CHANNEL" == "testing" ]] && clone_url="$TESTING_URL"

    [[ "$SILENT_MODE" == "false" ]] && echo -e " \e[1;34m[*] Cloning Promptify ($CHANNEL channel) into $INSTALL_DIR...\e[0m"
    run_cmd git clone --depth 1 --branch "$CHANNEL_BRANCH" "$clone_url" "$INSTALL_DIR" || { echo "Clone failed."; exit 1; }
    
    # Pass flags to local exec
    ARGS=("--local")
    [[ "$CONFIRM_ALL" == "true" ]] && ARGS+=("--yes")
    [[ "$SILENT_MODE" == "true" ]] && ARGS+=("--silent")
    ARGS+=("--channel" "$CHANNEL")
    
    exec bash "$INSTALL_DIR/promptify.sh" "${ARGS[@]}"
    exit
fi

# 2.5 Universal Bootstrap
# Load detection early
source "$INSTALL_DIR/core/env/detect.sh"
detect_env

if [[ "$IS_LOCAL" == "true" ]]; then
    # Bootstrap core tools (functional checks — a broken PATH entry must not
    # count as installed, e.g. host Termux binaries inside proot-distro)
    if ! tput cols &>/dev/null || ! git --version &>/dev/null; then
        [[ "$SILENT_MODE" == "false" ]] && echo -ne "\e[1;34m[*] Installing core dependencies for your system...\e[0m"

        if [[ -n "$SUDO" ]]; then
            sudo_notice "Installing core dependencies"
        fi

        case $PKG_MNGR in
            pkg) run_cmd pkg install ncurses-utils git -y ;;
            apt) run_cmd $SUDO apt update -y && run_cmd $SUDO apt install ncurses-bin git -y ;;
            pacman) run_cmd $SUDO pacman -Sy --noconfirm ncurses git ;;
            dnf) run_cmd $SUDO dnf install -y ncurses git ;;
            zypper) run_cmd $SUDO zypper install -y ncurses git ;;
            xbps) run_cmd $SUDO xbps-install -S && run_cmd $SUDO xbps-install -y ncurses git ;;
            slackpkg) run_cmd $SUDO slackpkg -batch=on -default_answer=y update \
                        && run_cmd $SUDO slackpkg -batch=on -default_answer=y install ncurses git ;;
            emerge) run_cmd $SUDO emerge --ask n ncurses git ;;
            apk) run_cmd $SUDO apk add ncurses git ;;
            brew) run_cmd brew install ncurses git ;;
            *)
                echo -e " \e[1;31m[!] No package manager detected for core dependencies. Install git & ncurses manually.\e[0m"
                exit 1
                ;;
        esac
        # Drop cached paths so freshly installed tput/git are picked up
        hash -r
        if ! tput cols &>/dev/null || ! git --version &>/dev/null; then
            echo -e " \e[1;31m[!] Core dependencies are still not working. Install git & ncurses manually, then re-run.\e[0m"
            exit 1
        fi
        [[ "$SILENT_MODE" == "false" ]] && echo -e " \e[1;32mDone.\e[0m"
    fi
fi

if [[ ! -w "$HOME" ]]; then
    echo -e "\e[1;31m[!] Error: No write permission in HOME directory ($HOME).\e[0m"
    exit 1
fi

if [[ "$IS_LOCAL" == "true" && ! -w "$(pwd)" ]]; then
    echo -e "\e[1;31m[!] Error: No write permission in current directory ($(pwd)).\e[0m"
    exit 1
fi

export INSTALL_DIR
export CONFIRM_ALL
export SILENT_MODE

# 3. Modular Bootloader (Sourcing all components)
BOOT_DIRS=("core/env" "core/utils" "core/install" "core/ui" "core/maintenance" "modules/dashboard" "modules/setup" "modules/customization")

for dir in "${BOOT_DIRS[@]}"; do
    for file in "$INSTALL_DIR/$dir"/*.sh; do
        # shellcheck disable=SC1090
        # Skip pre-sourced detect.sh
        [[ "$file" == *"core/env/detect.sh" ]] && continue
        [[ -f "$file" ]] && source "$file"
    done
done

# 4. Global State & Signal Handling
trap ':' SIGINT SIGTERM
trap 'tput cnorm' EXIT

# Calculate UI width
calculate_ui_width() {
    local name="${BANNER_NAME:-Promptify}"
    local fig_w=0
    if cmd_probe figlet; then
        fig_w=$(figlet -f "standard" "$name" | awk '{ if (length > max) max = length } END { print max }')
    else
        fig_w=${#name}
    fi
    export BOX_WIDTH=$(calc_box_width $((fig_w + 14)))
}

# shellcheck disable=SC2034
RESIZED=true
trap 'RESIZED=true' SIGWINCH

# shellcheck disable=SC2034
CUR_THEME_BORDER="red"
# shellcheck disable=SC2034
CUR_THEME_TAG="blue"
# shellcheck disable=SC2034
CUR_FONT="random"
# shellcheck disable=SC2034
CUR_CAT_STYLE="full"
# shellcheck disable=SC2034
CUR_CHANNEL="stable"
# shellcheck disable=SC2034
BANNER_NAME="Promptify"
# shellcheck disable=SC2034
USE_BANNER="true"
# shellcheck disable=SC2034
CUR_KEYBOARD="advanced"
load_prefs
calculate_ui_width

update_status() {
    # Status dots (green=ok, red=missing) — matches menu/health status dots
    local ok_dot="\033[1;32m●\033[0m"
    local bad_dot="\033[1;31m●\033[0m"

    STATUS_ZSH=$({ cmd_probe zsh; } && echo "$ok_dot" || echo "$bad_dot")
    STATUS_PKGS=$( { check_status "figlet" "git" >/dev/null; } && echo "$ok_dot" || echo "$bad_dot")
    # OMZ: bundled (deps/) OR any system-wide oh-my-zsh counts as available
    if [[ -f "$PFY_DEPS_OMZ/oh-my-zsh.sh" || -f "/usr/share/oh-my-zsh/oh-my-zsh.sh" ]]; then
        STATUS_OMZ="$ok_dot"
    else
        STATUS_OMZ="$bad_dot"
    fi
    if [[ -d "$PFY_DEPS_PLUGINS/zsh-autosuggestions" && -d "$PFY_DEPS_PLUGINS/zsh-syntax-highlighting" ]]; then
        STATUS_PLUG="$ok_dot"
    else
        STATUS_PLUG="$bad_dot"
    fi
}

update_status

# 4.5 Smart First-Run Trigger
if ! is_promptify_installed; then
    clear
    promptify_header
    echo -e "\n\e[1;34m[!] Welcome to Promptify!\e[0m"
    echo -e "\e[1;33m[*] It looks like Promptify isn't configured yet.\e[0m"
    if confirm_action "Start Guided Setup Wizard?" "y"; then
        guided_setup
        update_status
    fi
fi

# 4.6 Auto-Apply after an update / channel switch / rollback
if [[ "$POST_UPDATE" == "true" ]]; then
    clear
    promptify_header
    echo -e "\n\e[1;34m[*] Applying your settings...\e[0m"
    if check_setup; then
        refresh_ui
    fi
    echo -e "\n\e[1;32m[✔] You're all set (v$VERSION).\e[0m"
    press_enter
fi

# 5. Main Loop
while true; do
    # Real-time sync
    load_prefs
    if [[ "$RESIZED" == "true" ]]; then
        calculate_ui_width
        RESIZED=false
    fi
    
    MAIN_CHOICE=$(radio_menu "Promptify v${VERSION}" "draw_dashboard" "" 0 -1 \
        "Guided Setup" \
        "Apply & Reload UI" \
        "Customization" \
        "Dependencies" \
        "Updates" \
        "Uninstall" \
        "Exit")

    case "$MAIN_CHOICE" in
        "CANCELLED") 
            confirm_action "Exit Promptify?" && exit_script
            continue 
            ;;
        0) guided_setup; update_status ;;
        1)
            check_setup || continue
            if ! refresh_ui; then
                center_print "\e[1;31m[✗] Apply failed — see messages above.\e[0m"
                continue
            fi
            center_print "\e[1;32m[✔] Changes Applied!\e[0m"
            restart_shell
            ;;
        2) 
            check_setup || continue
            manage_customization 
            ;;
        3) 
            check_setup || continue
            manage_dependencies; update_status 
            ;;
        4) updates_menu; update_status ;;
        5) uninstall_promptify ;;
        6) 
            if confirm_action "Exit Promptify?" "y"; then
                exit_script
            fi
            ;;
    esac
done
