#!/bin/bash

# Promptify Version
# NOTE: This is the single source of truth for the version number.
# Bump it here only — the main menu, wizard, and changelog all read from it.
export VERSION="1.5.4"

# Split a version string into numeric MAJOR MINOR PATCH parts (missing = 0).
# "1.4"      -> 1 4 0
# "1.4.0-rc" -> 1 4 0
version_parts() {
    echo "$1" | awk -F. '{ printf "%d %d %d\n", $1+0, $2+0, $3+0 }'
}

# Compare two version numbers. Prints "gt", "lt", or "eq".
semver_compare() {
    local a b
    a=$(version_parts "$1")
    b=$(version_parts "$2")
    local av bv i
    for i in 1 2 3; do
        av=$(echo "$a" | awk -v n="$i" '{print $n}')
        bv=$(echo "$b" | awk -v n="$i" '{print $n}')
        if [[ "$av" -gt "$bv" ]]; then
            echo "gt"
            return 0
        fi
        if [[ "$av" -lt "$bv" ]]; then
            echo "lt"
            return 0
        fi
    done
    echo "eq"
}

# Read the version from a git ref's version.sh (e.g. "origin/main").
# Prints nothing when the ref or file can't be read (callers fall back to
# hash-based detection).
remote_version() {
    local ref="$1"
    git -C "$INSTALL_DIR" show "$ref:core/env/version.sh" 2>/dev/null \
        | grep -oE 'VERSION="[^"]+"' | head -1 | sed 's/VERSION="//;s/"$//'
}
