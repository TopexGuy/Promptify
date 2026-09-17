#!/bin/bash

# Generates the runtime configs (~/.promptify/runtime/zshrc & bashrc) from the
# user's prefs + install-time facts, and writes the single managed source line
# into the real ~/.zshrc / ~/.bashrc. Regenerated on every apply/update.
#
# The runtime zshrc is deliberately theme-agnostic: the user's original config
# is sourced first (opaque), and Promptify's prompt wins by registering its
# precmd hook LAST and clearing RPROMPT. No p10k/starship/theme code is baked in.

manifest_backup_for() {
    local path="$1"
    grep -F "|${path}|" "$PFY_MANIFEST" 2>/dev/null | head -1 | cut -d'|' -f3
}

# Escape a value so it's safe to embed in a double-quoted zsh assignment.
escape_zsh_value() {
    local v="$1"
    v="${v//\\/\\\\}"
    v="${v//\"/\\\"}"
    v="${v//\$/\\\$}"
    v="${v//\`/\\\`}"
    echo "$v"
}

generate_aliases_block() {
    local cat_style="$1"
    cat << EOF
if command -v eza &> /dev/null; then
    alias ls='eza --icons --color=auto'
    alias ll='eza -l --icons --color=auto'
    alias l='eza --icons'
elif command -v exa &> /dev/null; then
    alias ls='exa --color=auto'
    alias ll='exa -l --color=auto'
    alias l='exa'
else
    alias ls='ls --color=auto'
    alias ll='ls -l --color=auto'
    alias l='ls'
fi

if command -v bat &>/dev/null; then
    alias cat='bat --style=$cat_style --paging=never --color=always'
elif command -v batcat &>/dev/null; then
    alias cat='batcat --style=$cat_style --paging=never --color=always'
fi

alias Promptify='promptify'
alias pty='promptify'
alias grep='grep --color=auto'
EOF
}

generate_runtime() {
    mkdir -p "$PFY_RUNTIME" "$PFY_BACKUP_FILES"

    local banner_name="${BANNER_NAME:-Promptify}"
    local border="${CUR_THEME_BORDER:-red}"
    local tag="${CUR_THEME_TAG:-blue}"
    local style="${CUR_PROMPT_STYLE:-parrot}"
    local skip_p10k="${SKIP_P10K:-false}"
    local show_banner=false
    [[ -f "$HOME/.draw" ]] && show_banner=true

    local zsh_backup bash_backup
    zsh_backup=$(manifest_backup_for "$HOME/.zshrc")
    bash_backup=$(manifest_backup_for "$HOME/.bashrc")

    local safe_name
    safe_name=$(escape_zsh_value "$banner_name")

    local aliases_block
    aliases_block=$(generate_aliases_block "${CUR_CAT_STYLE:-full}")

    # Prefer the guest-local zsh (see resolve_real_zsh) so bash in proot execs
    # the container's own shell, never the host Termux binary that only `command
    # -v` would find. Empty means "resolve at runtime".
    local zsh_path_rt
    zsh_path_rt=$(resolve_real_zsh 2>/dev/null) || zsh_path_rt=""
    [[ "$zsh_path_rt" == "/data/"* && "$OS_TYPE" != "termux" ]] && zsh_path_rt=""

    # --- zsh runtime -------------------------------------------------------
    {
        echo "# Promptify — runtime zsh config (auto-generated). Do not edit."
        echo "# Regenerated on every apply/update."
        echo

        if [[ "$skip_p10k" == "true" ]]; then
            echo "# Silence the Powerlevel10k setup wizard (you approved this during setup)"
            echo "export POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true"
            echo
        fi

        if [[ -n "$zsh_backup" && -f "$PFY_BACKUP_FILES/$zsh_backup" ]]; then
            echo "# Your original shell config (unchanged — loaded first)"
            echo "source \"$PFY_BACKUP_FILES/$zsh_backup\""
            echo
        fi

        # Only load the bundled Oh-My-Zsh if your original config didn't already
        # load one (that sets $ZSH). Runtime check — no string-sniffing needed,
        # so it works over cachyos-config, a distro omz, or anything else.
        if [[ -f "$PFY_DEPS_OMZ/oh-my-zsh.sh" ]]; then
            echo "# Bundled Oh-My-Zsh (only when your config didn't already load one)"
            echo "if [[ -z \"\${ZSH:-}\" ]]; then"
            echo "  export ZSH=\"\$HOME/.promptify/deps/oh-my-zsh\""
            echo "  ZSH_THEME=\"\""
            echo "  source \"\$ZSH/oh-my-zsh.sh\""
            echo "fi"
            echo
        fi

        echo "# Helper plugins (standalone — work with or without oh-my-zsh)"
        echo "[[ -f \"\$HOME/.promptify/deps/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh\" ]] && source \"\$HOME/.promptify/deps/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh\""
        echo "[[ -f \"\$HOME/.promptify/deps/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh\" ]] && source \"\$HOME/.promptify/deps/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh\""
        echo "export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=245'"
        echo

        if [[ "$show_banner" == "true" ]]; then
            echo "# Startup banner"
            echo "printf '\\033[2J\\033[H'"
            echo "# .draw renders to stderr (menus draw there), but the managed profile sources"
            echo "# this runtime with 2>/dev/null — so merge stderr into stdout to survive it."
            echo "[[ -f \"\$HOME/.draw\" ]] && PROMPTIFY_DIR=\"\$PROMPTIFY_DIR\" bash \"\$HOME/.draw\" 2>&1"
            echo
        fi

        echo "# --- Promptify prompt (theme-agnostic override) ---"
        echo "P_CLR_BORDER=\"$border\""
        echo "P_CLR_TAG=\"$tag\""
        echo "P_CLR_USER=\"green\""
        echo "P_CLR_PATH=\"green\""
        echo "P_CLR_GIT=\"red\""
        echo
        echo "autoload -Uz vcs_info"
        echo "zstyle ':vcs_info:*' enable git"
        echo "zstyle ':vcs_info:git:*' formats ' %B%F{blue}(%F{red}%b%F{blue})%f'"
        echo "zstyle ':vcs_info:git:*' actionformats ' %B%F{blue}(%F{red}%b|%a%F{blue})%f'"
        echo
        echo "TNAME=\"$safe_name\""
        echo

        # get_prompt_block already emits literal zsh (quoted heredoc) + registers
        # the precmd hook. We unregister/register again below so ours is ALWAYS last.
        get_prompt_block "$style"

        echo
        echo "# Win over any theme: clear the right prompt, be the last precmd hook"
        echo "autoload -Uz add-zsh-hook"
        echo "RPROMPT=\"\""
        echo "add-zsh-hook -d precmd build_prompt 2>/dev/null"
        echo "add-zsh-hook precmd build_prompt"
        echo
        echo "export LS_COLORS='rs=0:di=01;34:ln=01;36:mh=00:pi=40;33:so=01;35:do=01;35:bd=40;33:cd=40;33:or=40;31;01:mi=00:su=37;41:sg=30;43:ca=30;41:tw=30;42:ow=34;42:st=37;44:ex=01;32'"
        echo
        echo "$aliases_block"
        echo "printf '\\e[4 q'"
    } > "$PFY_RUNTIME_ZSHRC"

    # --- bash runtime ------------------------------------------------------
    {
        echo "# Promptify — runtime bash config (auto-generated). Do not edit."
        echo

        if [[ -n "$bash_backup" && -f "$PFY_BACKUP_FILES/$bash_backup" ]]; then
            echo "# Your original bash config (unchanged — loaded first)"
            echo "source \"$PFY_BACKUP_FILES/$bash_backup\""
            echo
        fi

        echo "export PROMPTIFY_DIR=\"$PFY_SYS_DIR\""
        echo
        echo "# Auto-start Zsh in interactive bash sessions (only when zsh is really usable)"
        echo "if [[ -n \"\$BASH_VERSION\" && -z \"\$ZSH_VERSION\" && -t 0 ]]; then"
        if [[ -n "$zsh_path_rt" ]]; then
            echo "  ZSHPROBE=\"$zsh_path_rt\""
            echo "  [[ -x \"\$ZSHPROBE\" ]] || ZSHPROBE=\"\$(command -v zsh)\""
        else
            echo "  ZSHPROBE=\"\$(command -v zsh)\""
        fi
        echo "  if [[ -x \"\$ZSHPROBE\" ]] && \"\$ZSHPROBE\" --version &>/dev/null; then"
        echo "    exec \"\$ZSHPROBE\""
        echo "  fi"
        echo "fi"
        echo
        if [[ "$show_banner" == "true" ]]; then
            echo "# Show the banner if staying in Bash"
            echo "[[ -f \"\$HOME/.draw\" ]] && PROMPTIFY_DIR=\"\$PROMPTIFY_DIR\" bash \"\$HOME/.draw\" 2>&1"
            echo
        fi
        echo "# Aliases"
        echo "$aliases_block"
    } > "$PFY_RUNTIME_BASHRC"

    # Validate the generated zsh config before it ever reaches the login shell,
    # and the generated bash config too. "zsh isn't usable" (missing, or a
    # broken host-Termux shim on PATH inside proot-distro) must NOT look like a
    # config error — the config is fine, the shell just can't run yet. So:
    #   - zsh really runs → a syntax error deletes the file (never ship it).
    #   - zsh can't run at all → keep the file (it's valid zsh) and warn.
    if cmd_probe zsh; then
        if ! zsh -n "$PFY_RUNTIME_ZSHRC" 2>/dev/null; then
            center_print "\e[1;31m[!] Generated zsh config failed validation. Not applying.\e[0m"
            rm -f "$PFY_RUNTIME_ZSHRC"
            return 1
        fi
    elif command -v zsh &>/dev/null; then
        center_print "\e[1;33m[i] zsh is present but not working yet (installed via a package manager will fix it).\e[0m"
    else
        center_print "\e[1;33m[i] zsh is not installed — install it (e.g. 'zsh' via your package manager) to activate the prompts.\e[0m"
    fi

    # A generated bashrc that fails bash -n would break every bash login —
    # cheap to catch here before write_managed_profiles ships it.
    if ! bash -n "$PFY_RUNTIME_BASHRC" 2>/dev/null; then
        center_print "\e[1;31m[!] Generated bash config failed validation. Not applying.\e[0m"
        rm -f "$PFY_RUNTIME_BASHRC"
        rm -f "$PFY_RUNTIME_ZSHRC"
        return 1
    fi

    return 0
}

# Write the single managed source line into the real profiles.
write_managed_profiles() {
    {
        echo "$PFY_PROFILE_COMMENT"
        echo "$PFY_PROFILE_ZSHRC"
    } > "$HOME/.zshrc"

    {
        echo "$PFY_PROFILE_COMMENT"
        echo "$PFY_PROFILE_BASHRC"
    } > "$HOME/.bashrc"

    snapshot_created "$HOME/.zshrc"
    snapshot_created "$HOME/.bashrc"
}
