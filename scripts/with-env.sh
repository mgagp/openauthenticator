#!/usr/bin/env bash
# Runs a command with the toolchain paths from dev-env.local (JAVA_HOME, FLUTTER_ROOT).
# Usage: scripts/with-env.sh flutter doctor -v
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="$root/dev-env.local"

if [ ! -f "$config" ]; then
  echo "error: $config not found. Copy dev-env.example to dev-env.local and set the paths for this machine." >&2
  exit 1
fi

to_unix() {
  if command -v cygpath > /dev/null 2>&1; then cygpath -u "$1"; else printf '%s' "$1"; fi
}

while IFS='=' read -r key value || [ -n "$key" ]; do
  key="${key//[[:space:]]/}"
  value="${value%$'\r'}"
  case "$key" in ''|\#*) continue ;; esac
  [ -z "$value" ] && continue
  case "$key" in
    JAVA_HOME)
      if [ ! -x "$(to_unix "$value")/bin/java" ] && [ ! -f "$(to_unix "$value")/bin/java.exe" ]; then
        echo "error: JAVA_HOME=$value has no bin/java." >&2
        exit 1
      fi
      export JAVA_HOME="$value"
      PATH="$(to_unix "$value")/bin:$PATH"
      ;;
    FLUTTER_ROOT)
      if [ ! -d "$(to_unix "$value")/bin" ]; then
        echo "error: FLUTTER_ROOT=$value has no bin/ directory." >&2
        exit 1
      fi
      PATH="$(to_unix "$value")/bin:$PATH"
      ;;
    *)
      export "$key=$value"
      ;;
  esac
done < "$config"
export PATH

# Flutter ignores JAVA_HOME when Android Studio's bundled JBR is installed; its own `jdk-dir` setting wins.
# Keep that (user-global) setting in sync with dev-env.local.
if [ -n "${JAVA_HOME:-}" ] && command -v flutter > /dev/null 2>&1; then
  if [ -n "${APPDATA:-}" ]; then settings="$(to_unix "$APPDATA")/.flutter_settings"; else settings="${XDG_CONFIG_HOME:-$HOME/.config}/flutter/settings"; fi
  current="$(sed -n 's/.*"jdk-dir": *"\(.*\)".*/\1/p' "$settings" 2> /dev/null | sed 's/\\\\/\\/g')"
  if [ "$current" != "$JAVA_HOME" ]; then
    echo "with-env: setting flutter jdk-dir to $JAVA_HOME" >&2
    flutter config --jdk-dir "$JAVA_HOME" > /dev/null
  fi
fi

if [ "$#" -eq 0 ]; then
  echo "JAVA_HOME=${JAVA_HOME:-<unset>}"
  command -v java flutter dart 2> /dev/null || true
  exit 0
fi

exec "$@"
