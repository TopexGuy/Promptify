# Changelog

All notable changes to this project will be documented in this file.

## [1.5.4] - 2026-09-17

### Fixed
- **Freeze after install inside proot-distro / "cannot execute: required file not found"**: the host Termux's binaries leak onto the guest PATH (via `termux-profile.sh`) and a bare `command -v` treated them as installed — so guest `zsh` was never installed and `exec zsh` hit the host's Android ELF. All dependency checks are now **functional**: a command counts as installed only when it actually runs, so the guest's own `zsh`/`lolcat`/`figlet` etc. get installed instead of the broken shim being "detected" as present.
- **No prompt after setup**: if `zsh` still can't run, bash no longer auto-exec's it, `reload_shell` falls back to a usable bash session, and the login shell is never switched to a broken zsh.
- **Wizard printed "[✔] ALL DONE" after a failed apply**: a failed refresh now hard-fails with instructions (and the note points at `~/.promptify/backup/uninstall.sh` to restore). The self-uninstaller is written **before** runtime generation, so it exists even when the rest of setup breaks.
- **Generated zshrc deleted when zsh wasn't usable at all**: "zsh can't run" is no longer treated as a config syntax error; a real `zsh -n` failure still blocks the file, and the generated bashrc is now `bash -n`-checked too.
- **"proot-distro login" broke right after a successful install**: `chsh` recorded the HOST Termux zsh path (found first on the guest PATH) as the guest's login shell, so the next login died with "shell '/data/data/com.termux/files/usr/bin/zsh' is not available in container". Shell resolution now prefers the guest-local `/usr/bin/zsh` (host `/data/...` paths are rejected unless we're genuinely on Termux), and `/etc/shells` is updated so `chsh` accepts it.
- **Confusing sudo failure inside proot-distro**: a broken setuid sudo now explains that sudo is installed but misconfigured (not a "wheel group" issue) and points out that a fresh proot might need `chown root:root /etc/sudo.conf /etc/sudoers` + `chmod 4755 /usr/bin/sudo` from a root session.
- **White Termux banner after a Ruby upgrade**: a broken `lolcat` (gem wiped, exits with `GemNotFoundException`) is caught by the functional probe, the banner falls back to a native ANSI gradient (no lolcat dependency), and Dependencies gains a **Lolcat (banner colors)** item that reports missing/broken and reinstalls the gem (`repair_lolcat`).
- **Banner Management could silently enable an empty banner**: "Add/Update Banner" only `touch`ed `~/.draw`, so when the banner script was missing it created a 0-byte file and the startup hook ran nothing. It now copies the real `.draw` from the installed assets and regenerates the runtime so the startup banner reliably renders.

### Changed
- Main-menu **Apply** and the wizard require a real apply success before reporting success; the status dot for Zsh reflects a *usable* zsh, not just one on PATH.
- **Banner gradient now matches the real lolcat colors exactly**: the banner ports the exact `numeric_rainbow()` algorithm (per-line phase, sin-based RGB, random seed) from busyloop/lolcat instead of a rough approximation, so the startup banner looks like the original ruby lolcat output. Truecolor (24-bit) when the terminal supports it, 256-color cube otherwise, and the banner now exits cleanly (`exit 0`) regardless of --no-civis flags.

### Added
- **Custom keyboard layout editor**: simplified fixed 2×8 (16 buttons) editor under Customization → Keyboard Layout. Edit any key position, add/remove popups, reset to default. Layouts saved to `~/.promptify/userdata/custom-layout.keys`.
- **Key picker with 5 tabs**: Navigation, Modifiers, Fn Keys, Symbols (28 common chars), and Macros (15 presets + custom input).
- **Three keyboard layouts**: Advanced (8-key with popups, default), Simple (8-key plain), Custom (user-designed). All use 2×8 grid.
- **Consistent preview formatting**: all three layout previews use aligned 6-char columns with popup markers.

### Fixed
- **"Could not load extra-keys" error on custom layout save**: the extra-keys output format had missing `\` line continuations, causing Termux to fail parsing the properties file. Both the save function and `sync_termux_ui` now generate valid multi-line `\` format.
- **Custom layout preview now shows popup markers**: preview in the keyboard picker displays `^popup` for keys with popups.
- **Powerlevel10k wizard skip was silently ignored on first install**: added `load_prefs()` before `refresh_ui()` in `guided_setup()` so `SKIP_P10K` is available when the runtime config is generated.
- **Macro keys corrupted by editor save**: editor was wrapping macro tokens in single quotes (`'{macro:...}'`), producing literal text instead of button actions. Now delegates properties generation to `sync_termux_ui` which handles macros correctly.
- **Editor save duplicated properties generation**: removed the drifted duplicate extra-keys generator from `_kb_save_layout` — now saves `.keys` file only and calls `sync_termux_ui` for properties, ensuring snapshot/fingerprint tracking and consistent output.
- **Lowercase key names broke Termux buttons**: typing `esc` or `home` in custom key input validated successfully but emitted lowercase, which Termux doesn't recognize. Now always uppercases known key names.
- **Custom layout with missing `.keys` file silently applied wrong layout**: `sync_termux_ui` now falls back to Advanced and fixes the persisted pref when the custom file is missing.
- **Editor box text centering**: fixed pad_l rounding (ceil division) and minimum box width (8 chars) so key names center properly.
- **Comma key (` ,`) removed from symbol picker**: reserved as the `.keys` file delimiter — selecting it would corrupt saved layouts on reload.

### Removed
- Dead `parse_key_token()` function (never called).
- Redundant single-char branch in `resolve_key_input()` (identical to fallthrough).
- Duplicate extra-keys generator from `_kb_save_layout` (replaced by `sync_termux_ui` call).

## [1.5.2] - 2026-08-14

### Added
- **System Health panel** (replaces Doctor): a boxed, aligned status report (layout, snapshot, runtime, dependencies, profile, binary + leftover junk) rendered directly inside the **Dependencies** menu, with live PASS/FAIL counts.
- **Fix All Issues**: runs the real fixers for every failing check — refreshes the UI/runtime and installs any missing dependencies (previously "fix" only refreshed the UI).
- **Status dots on radio menus**: any menu option can now carry an `ok`/`missing`/`broken`/`outdated` dot (legend auto-shown); the main menu's **Dependencies** entry shows your aggregate install status.
- **Dashboard channel line**: shows the active update channel (stable/testing) alongside system status.
- **Version History** (merges the old "Restore Previous / Restore Older" flows): one screen under **Updates** listing every archived snapshot with its channel and date (`v1.5.0 (testing) · Aug 13 22:59`), an **Updated** row showing your last change ("v1.5.0 → v1.5.2 · testing → stable · Aug 14 09:41" — version and channel tags collapse when unchanged), and a dashboard **Updated** row that mirrors it. The newest snapshot is the default undo; archives are validated and swapped via a temp dir so a corrupt archive can never destroy the running app, and the channel is kept in the snapshot name for safety (restoring only reverts code — your channel preference stays). With no snapshots yet, it falls back to the git-saved previous version.
- **Changelog link**: the Updates panel and the update prompt point straight at the What's New page for your channel.
- **Update history log**: version + channel changes are recorded (last 15 kept) and drive the "Updated" rows above.

### Fixed
- **Main-menu boxes far too wide on desktop terminals**: box width was floored at 60% of the terminal, so the banner, dashboard and menus stretched on wide screens. Restored content-based sizing (v1.1 style) while keeping resize/alignment sync — the banner, dashboard and menus now hug their content on any terminal width.
- **"Updates" menu exited after every action** — it now returns to itself (e.g. re-check after updating) until you choose Back.
- **Rename fallout**: "Quick Setup" → "Guided Setup", "Reload & Apply UI" → "Apply & Reload UI", "Others" → "Power Tools" (including the bat-install hint in Cat styles).

### Changed
- Doctor is gone as a standalone menu item; **System Health** now lives under **Dependencies** (tap Dependencies → health panel → Re-run Health / **Fix / Install Dependencies** (checkbox multi-select) / Fix All / Back).
- Dashboard status now uses the same colored ● dots as the menus.
- Updates flow: the standalone "What's New" preview step was replaced by the changelog link, and the confirm now reads "Update to vX.Y.Z now?".
- The main-menu **Dependencies** entry is back to a plain label (v1.5.1 look — the status dot/legend belongs in the Dependencies submenu, not the main menu), and the "What's new?" link now sits between two separators under the menu hints instead of floating under the panel box.

## [1.5.1] - 2026-08-13

### Fixed
- **Startup banner swallowed on fresh installs**: `.draw` renders to stderr, but the managed profile sources the runtime with `2>/dev/null`, so the banner never appeared. The runtime now merges stderr into stdout for the banner call (zsh and bash).
- **Doctor deps check wrong when bundled deps partial**: `[[ A && B || C ]]` was parsed as `(A && B) || C`, falsely reporting OK when only the system Oh-My-Zsh existed.
- **`prefs.conf` started with a blank line** (empty first write), which confused parsers.
- **Update left stale files when `rsync` was missing**: the plain `cp` fallback now removes files in `core/` that no longer exist upstream (portable `--delete`).
- **Snapshot hash never refreshed for re-applied files**: uninstall could not verify/remove Promptify-created files whose content changed in a newer version (e.g. `.draw`). The recorded hash is now updated in place.
- **Hardcoded backup path in generated profiles**: runtime config now uses `$PFY_BACKUP_FILES`, so it works with any install directory.
- Removed dead code (`backup_file`, `channel_url`, redundant `version.sh` source).

### Changed
- **Bundled font list is now a single source of truth** (`core/env/fonts.sh`); the duplicated lists in install/apply/uninstall were removed.
- **Termux UI setup (colors, font, Android properties, figlet fonts) is now one shared function** used by both setup and "Reload & Apply UI".
- Removed the temporary `tests/` directory (development scaffolding, not part of the product).

## [1.5.0] - 2026-08-09

### Added
- **New APK/AOSP-style layout (`~/.promptify/`)**: Every directory now has one fixed job — `core/` (the program, a full git clone), `deps/` (Oh-My-Zsh + plugins, write-once), `userdata/` (prefs), `runtime/` (generated shell configs), `backup/` (install snapshot + self-contained uninstaller + version archives). Updates replace only `core/`; deps and userdata are never touched.
- **Snapshot "time-travel" install**: The very first install captures every file Promptify will touch (byte-exact copies + sha256 in `backup/system/MANIFEST`) plus facts about your original shell. Uninstall restores the machine to exactly how it was before — and reports PASS/FAIL after a full verify.
- **Works with any pre-existing config (CachyOS fix)**: Your original `~/.zshrc` is snapshotted and sourced first, unchanged; Promptify's prompt wins purely by clearing `RPROMPT` and registering its `precmd` hook last. No theme-specific code, works over p10k, starship, omz, or anything else. Powerlevel10k's first-run wizard is detected and skipped **only with your consent**.
- **One-line managed profile**: `~/.zshrc` is now a single guarded `source ~/.promptify/runtime/zshrc` line (plus comment). Everything lives in `~/.promptify`, so uninstall leaves zero junk.
- **Self-contained uninstaller** (`~/.promptify/backup/uninstall.sh`): generated at install, restores your config even if the program files are gone; `--keep-data` keeps your snapshot/settings.
- **Doctor**: New main-menu option — a 5-point health check (layout, snapshot integrity, runtime syntax, deps, managed profile + global command) with one-command repair.
- **Downgrade**: "Restore Older Version" lists archived `core/` tarballs from `backup/archives/` (kept 5 deep) and restores any previous version, re-applying your settings.
- **Legacy migration**: Installs from ≤1.4.3 (inline-block `~/.zshrc`) auto-migrate to the new layout on next run — original config recovered, deps moved, prefs converted.

### Changed
- Uninstall now restores your original shell config from the snapshot first (time-travel), then cleans UI/assets and removes the directory, then runs a full verification.
- First-run setup captures the snapshot before touching anything, and asks about the p10k wizard as a consent step.
- Oh-My-Zsh/plugins live in `deps/` and are only installed when your original config doesn't already load one.

---

## [1.4.3] - 2026-08-05

### Added
- **Void Linux support**: Package management is now handled through XBPS (`xbps-install`) on Void. Detection recognizes `ID=void` in `/etc/os-release` (and falls back to the `xbps-install` binary when os-release is missing/unrecognized); dependency install/update flows use `sudo xbps-install`.
- **Slackware support**: Package management now works through `slackpkg` on Slackware. Detection recognizes `ID=slackware` in `/etc/os-release` (plus a `slackpkg` binary fallback — useful since old Slackware releases ship no os-release), and install/update run non-interactively via `sudo slackpkg -batch=on -default_answer=y install/update`.

### Fixed
- **Bootstrap on the new distros**: The remote one-liner and the universal core-dependency bootstrap now cover Void (`xbps-install`), Slackware (`slackpkg`) and Gentoo (`emerge`), and `doas` is honored as an alternative to `sudo`. Both bootstraps now verify the tools actually work afterwards and fail loudly with a manual-install hint instead of printing a fake "Done." when nothing was installed.
- **Broken layout after terminal resize / maximize**: The ASCII banner, dashboard and menu boxes each used different width rules, so only the banner grew with the window — maximizing left a huge banner box sitting on a narrow dashboard/menu (and sub-menus kept a stale width the whole session). All boxes now share one width rule (`max(needed, 60% of terminal, 40)` capped to the terminal), the dashboard and menu bars scale with the banner, and menus recalculate on resize so everything re-aligns instantly and stays centered.
- **Install one-liner failed on fish and gave a 404**: The `bash <(curl ...)` install command doesn't work on the fish shell (`fish: Invalid redirection target`), and the URL lost its `.sh` easily (`.../main/promptify` → 404). The README command now uses the shell-agnostic `bash -c "$(curl -fsSL .../promptify.sh)"` form (works on bash, fish, zsh, sh), and a new extensionless `promptify` bootstrap file makes `.../main/promptify` work exactly like `.../main/promptify.sh`, so a missing extension can never 404 again.

---

## [1.4.2] - 2026-08-02

### Fixed
- **Bootstrap on proot-distro (Termux Linux)**: The remote one-liner no longer mistakes the host Termux's `git`/`tput` (visible through proot but unexecutable) for a working install. Bootstrap now checks that `git`/`tput` actually run, picks the package manager from `/etc/os-release` (apt/pacman/dnf/...) before falling back to Termux's `pkg`, and re-hashes bash's command cache (`hash -r`) so the freshly installed binaries are used — installs inside proot-distro now work instead of failing with `cannot execute: required file not found`.
- **Prompt Theme preview showed the wrong layout**: The "Prompt Theme Style" color menu always previewed the Parrot layout. It now previews your active Prompt Style (Parrot/Fish/Minimal) with the hovered theme's colors.
- **Repeated sudo prompts on every "Reload & Apply UI"**: Re-applying (style/color/banner changes — even with no changes at all) no longer re-asks for your password. System-wide figlet fonts are only copied when actually missing or outdated, so sudo is only needed on first setup (dependencies, system fonts, shell switch, `promptify` command). A short note now appears before the password prompt explaining why admin access is needed.
- **Restart shell prompt after applying changes**: Applying a style/theme/banner/font change now asks "Restart Zsh now to apply changes?" — choose **y** to instantly reload into a fresh shell showing the new prompt (no need to exit and reopen the terminal), or **n** to stay. The reloaded shell starts in the directory you launched Promptify from (the v1.3.1 "wrong directory after exit" issue), and the reload is skipped entirely when not attached to a real terminal.
- **Silent dependency-install failures (e.g. on a fresh Arch install)**: Dependencies are no longer reported as "ALL DONE" when they never actually installed. Promptify now (1) fails loudly up front if root is required but `sudo`/`doas` is missing or the user can't elevate, (2) checks every package install result and aborts with the exact failing command plus a fix hint, (3) treats `lolcat` as optional (warns, continues) instead of failing the whole install, and (4) stops suppressing errors when installing the system-wide `promptify` command. The wizard's success message now only shows when dependencies genuinely succeeded. Optional tools like Eza/Bat no longer fail the whole install.
- **Package manager detection could yield "unknown" on Arch and skip every install**: The root cause of the silent installs — `/etc/os-release` detection missed quoted `ID` values (e.g. `ID="arch"`) and unrecognized Arch-based distros, leaving `PKG_MNGR=unknown` so every install was a no-op. Detection now parses `ID`/`ID_LIKE` quote- and list-tolerant (Arch, EndeavourOS, etc. all resolve to `pacman`), and if `os-release` is missing or unrecognized it falls back to whichever package manager binary is actually installed (`pacman`, `apt-get`, `dnf`, `zypper`, `apk`, `emerge`, `brew`).

---

## [1.4.1] - 2026-08-02

### Added
- **Install-State Manifest**: Install now records exactly what it changed (`~/.promptify/.install-state` — pre-install shell, profile existence, UI files, desktop font). Uninstall reads it back so cleanup reverses precisely what was applied, even after repeated re-applies.
- **Version-Based Updates**: Update detection now compares version numbers instead of raw git hashes, so you'll never be offered a downgrade. Same version but newer changes → "hotfix sync" option; a version that can't be read falls back to hash comparison.
- **Update & Channel Flow**: Updates/channel switches now show your current version and the target version ("v1.4.0 → v1.4.1"), auto-apply your settings after switching, and reload the app so the new code takes effect immediately.
- **Rollback**: Each update saves the previous version; "Restore Previous Version" in the Updates menu puts it back and re-applies your settings.
- **What's New Preview**: You can view the changelog of the available update before applying.
- **Stale-Asset Fingerprints**: Files Promptify writes into your Termux/desktop are fingerprinted at apply time, so uninstall can remove them even after an update changed the bundled assets — while never touching files you've edited yourself.

### Fixed
- **Uninstall Cleanliness**: Uninstall now removes only what Promptify added:
  - Termux UI files are removed only when they still match the bundled assets — a user's own `termux.properties` is preserved.
  - Bundled figlet fonts are restored/removed without ever deleting the figlet package's own fonts (`banner.flf`/`slant.flf` originals are backed up before being overwritten).
  - Desktop Nerd Font and terminal config edits (kitty/alacritty/konsole/xfce) are reverted via pre-edit backups.
  - Shell profiles are fully restored: `.bashrc.bak` is now restored too, and empty profiles that Promptify created are removed.
  - The pre-install login shell is restored (bash→bash, zsh→zsh) instead of always reverting to bash.
  - Partial installs (leftover `~/.promptify` with no profile marker) are now detected and cleanable.

---

## [1.4.0] - 2026-08-02

### Added
- **Prompt Styles**: Three prompt layouts — Parrot (default), Fish, and Minimal — selectable under Customization → Prompt Style with a live preview. The active style persists in `~/.username` (`STYLE=`) and is independent of the color theme.

### Fixed
- **Bootstrap Crash (Critical)**: The documented `bash <(curl ...)` install failed on every shell because `local` was used outside a function in the bootstrap.
- **Banner Disable State**: Disabling the banner now removes stale `~/.draw` and the `NAME`/`FONT` prefs, keeping the reloaded state consistent.
- **Preference Corruption**: `set_username_pref` now uses an `awk`-based upsert, so values containing `&`, `|`, `\`, or `"` no longer corrupt `~/.username`.
- **Update Flags**: The auto-restart after an update now preserves `--silent`, `--yes`, and `--channel` flags.
- **Uninstall Shell Revert**: The login shell is only reverted when the user opts to clean the shell profile.
- **Profile Safety**: The generated `.zshrc` block is validated with `zsh -n` before being written.
- **Package Manager Coverage**: All installs route through a single `install_single_pkg` helper, which now includes `emerge` (Gentoo).

---

## [1.3.1] - 2026-08-02

### Fixed
- **Wrong Directory After Exit**: Running `promptify`/`pty` and exiting no longer leaves you stuck in the first clone directory. `restart_shell` no longer spawns a nested shell via `exec zsh`, bootstrap no longer `cd`s into the clone directory, and update checks run without changing the working directory.
- **Cat Preview (Filename Only)**: The "Filename Only" preview no longer shows line numbers — it now renders just the filename header plus content, matching real `bat` output.
- **Cringy Menu Labels**: Removed clunky parenthetical words from menu items (Cat styles, Themes, Dependencies, Power Tools, Uninstall) for clean, minimal labels.

---

## [1.3.0] - 2026-08-01

### Added
- **New Banner Fonts**: Slant, Banner, Poison, and Graffiti styles bundled as assets — all with proper lowercase letter support (Bubble removed).
- **Random Font Option**: The default banner option now picks a random style from Shadow/Simple/Slant/Banner/Poison/Graffiti on every terminal open.
- **Minimal Banner Box**: Removed the extra vertical padding rows so the banner box hugs the glyphs for a clean, compact look.
- **Live Cat Preview**: The Cat Display Style menu now renders a live preview of the highlighted style (Filename Only, Numbers Only, Plain) as you navigate.
- **Dependencies Status Dots**: The Dependencies menu shows unticked options with live status dots — ● Installed (green), ● Missing (red), ● Broken (amber), ● Outdated (dim green) — plus an on-screen legend.
- **Update Channel Auto-Detect**: The setup wizard no longer prompts for a channel; it derives the channel from the cloned repo's origin.

### Fixed
- **Random Shadow Alignment**: Choosing Random could pick Shadow without trimming its blank trailing row, shifting the banner up on terminal open. Descent is now derived from the selected font on every path (force, preference, and random).
- **Cat/Channel Prefs Preserved**: `~/.username` is now upserted key-by-key instead of rewritten, so operations like banner uninstall keep unrelated prefs (CAT, CHANNEL) intact.
- **ESC Cancels Input Cleanly**: Pressing ESC now cancels text prompts and restores your original readline ESC binding instead of clobbering it.
- **Rollback Only on Interrupt**: The setup wizard rolls back only on user interruption (SIGINT/SIGTERM), not on every failed sub-command.

---

## [1.2.0] - 2026-07-31

### Added
- **Cat Display Style**: New Customization option to toggle bat's display (Full / Filename only / Lines only / Plain). Disabled with a note when bat isn't installed.
- **Disabled Menu Items**: `radio_menu` now supports disabled options that are dimmed and skipped during navigation.
- **Others (Eza, Bat)**: New Dependencies option to install optional power tools skipped during setup.
- **Nerd Font Auto-Apply**: Installs JetBrainsMono Nerd Font on desktop and applies it in Kitty, Alacritty, GNOME Terminal, Konsole, and XFCE4 Terminal.
- **Live Install Output**: Installers now show live progress by default; output is only hidden with `--silent`.

### Fixed
- **Nerd Font Icons**: Replaced `font.ttf` with JetBrainsMono Nerd Font so `ls`/eza icons render correctly on Termux and PC.
- **dnf Update Check**: No longer fails the dependency step when no updates are available.

---

## [1.1.1] - 2026-07-31

### Added
- **Update Channels**: Choose between Stable and Testing update channels at first run or from the Updates menu, with channel-aware bootstrap (`--channel` flag supported).

### Fixed
- **Bootstrap cd Error**: Silenced the `/proc/<pid>/fd: No such file or directory` warning that appeared when running via `bash <(curl ...)`.
- **lolcat on Termux**: Gem install failed with "OpenSSL is not available". Now installs `openssl` first and reinstalls Ruby if it can't load OpenSSL.

---

## [1.1.0] - 2026-06-08

### Added
- **Pro-Cat Integration**: Replaced standard `cat` with `bat` (or `batcat` on PC) using a professional `full` style (Grid, Header, Line Numbers).
- **Dual Shell Support**: Configuration now applies consistently to both `.zshrc` and `.bashrc`.
- **Auto-Sync Engine**: Changes in the local repository are now automatically synced to the system directory (`~/.promptify`) during "Reload & Apply UI" or "Updates".
- **Global Command**: Promptify can now be installed as a system package. Use the `promptify`, `Promptify`, or `pty` command from any directory.
- **Persistent Installation**: Repository now migrates to `~/.promptify` for permanent system access.
- **Universal Bootstrap**: Real-time OS detection (Arch, Debian, Termux, etc.) with silent dependency installation.
- **Smart Setup Wizard**: Automated first-run detection that guides new users through the setup with a dedicated rollback system.
- **Improved Previews**: Real-time font and theme previews with active-item persistence and flicker-free rendering.
- **Fallback Engine**: Automatic "Promptify" text fallback in previews if no name is set.
- **Refactored Menu Core**: Modularized menu drawing for perfect alignment across all terminal widths.

### Changed
- **Config Hardening**: Improved shell profile cleaning logic to prevent duplicate or orphaned configuration blocks.
- **Resilient Installation**: Added auto-creation of missing shell profile files and graceful fallbacks for unsupported package managers.
- **Enhanced Aliases**: Standardized `ls`, `ll`, and `l` aliases across all shell environments.
- **Update Safety**: Added checks for uncommitted local changes and network connectivity before performing updates.
- **Optimized Dependencies**: Prioritized native `lolcat` packages for Termux and other distros to reduce installation time and size.
- **UI Refinement**: Switched from harsh green highlights to professional Bold Cyan/White for active settings.
- **Font Selection**: Streamlined options by removing the redundant 'Blocky' font, leaving clear choices: Default, Shadow, and Simple.
- **Input Handling**: Upgraded input prompts to use `readline` for better cursor control and escape key support.

### Fixed
- **Syntax Highlighting**: Resolved the issue where `cat` output was plain white; now forces color output in all terminal states.
- **Sync Lag**: Fixed the bug where code updates in the repo weren't reflecting in the installed system version.
- **Path Resolution**: Restored critical script path detection logic that was causing setup failures.
- **Checkbox Alignment**: Resolved the jitter issue where selecting items pushed text out of alignment.
- **Input Boundaries**: Fixed a bug where the cursor could overwrite the prompt prefix during text entry.
- **Memory Fix**: Customization changes now reflect in the dashboard instantly without a shell restart.

---

## [1.0.0] - 2026-05-10

### Added
- Initial Master Release.
- Modular shell customization engine.
- Interactive radio and checkbox menus.
- Support for Termux, Arch, and Debian.
- Basic font styles: Shadow, Big, Standard.
- Oh-My-Zsh integration and plugin support.
