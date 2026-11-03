#!/bin/sh
# Installs Boo from the public releases page (story 20.3). Meant to be run like this:
#
#   curl -fsSL https://raw.githubusercontent.com/encrivolabs/boo-releases/main/install.sh | sh
#
# Why it exists: Boo isn't notarized by Apple yet, so a DMG saved by a browser is blocked the
# first time it opens. A file fetched with curl isn't marked that way, so this opens straight away.
# It checks the download against its published SHA-256 before it installs anything.
#
# Settings (all optional):
#   BOO_VERSION        for example 1.0.0. Default is the latest release.
#   BOO_INSTALL_DIR    where Boo.app goes. Default /Applications, or ~/Applications if that isn't writable.
#   BOO_RELEASES_REPO  Default encrivolabs/boo-releases.
#   BOO_DOWNLOAD_BASE  Where Boo.dmg and Boo.dmg.sha256 are. For tests.
#   BOO_NO_OPEN        Set to anything to skip opening Boo afterwards.
set -eu

repo="${BOO_RELEASES_REPO:-encrivolabs/boo-releases}"
if [ -n "${BOO_DOWNLOAD_BASE:-}" ]; then
  base="$BOO_DOWNLOAD_BASE"
  protocols="=https,file"
elif [ -n "${BOO_VERSION:-}" ]; then
  base="https://github.com/$repo/releases/download/v$BOO_VERSION"
  protocols="=https"
else
  base="https://github.com/$repo/releases/latest/download"
  protocols="=https"
fi

say() { printf '%s\n' "$*"; }
fail() { printf 'Boo could not be installed: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "Boo is a Mac app."
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 14 ] || fail "Boo needs macOS 14 Sonoma or later. This Mac has $(sw_vers -productVersion)."

dest_dir="${BOO_INSTALL_DIR:-/Applications}"
if [ -z "${BOO_INSTALL_DIR:-}" ] && [ ! -w "$dest_dir" ]; then
  dest_dir="$HOME/Applications"
fi
mkdir -p "$dest_dir"

work="$(mktemp -d)"
mnt="$work/mnt"
cleanup() { hdiutil detach "$mnt" -quiet >/dev/null 2>&1 || true; rm -rf "$work"; }
trap cleanup EXIT INT TERM

say "Downloading Boo..."
curl -fL --proto "$protocols" --tlsv1.2 --progress-bar -o "$work/Boo.dmg" "$base/Boo.dmg" || fail "the download didn't finish."
curl -fsSL --proto "$protocols" --tlsv1.2 -o "$work/Boo.dmg.sha256" "$base/Boo.dmg.sha256" || fail "the checksum file isn't there."

say "Checking the download..."
expected="$(awk '{print $1}' "$work/Boo.dmg.sha256")"
actual="$(shasum -a 256 "$work/Boo.dmg" | awk '{print $1}')"
[ -n "$expected" ] && [ "$expected" = "$actual" ] || fail "the download doesn't match its checksum, so nothing was installed."

mkdir -p "$mnt"
hdiutil attach "$work/Boo.dmg" -mountpoint "$mnt" -nobrowse -readonly -quiet || fail "the disk image wouldn't open."
[ -d "$mnt/Boo.app" ] || fail "Boo.app isn't in the disk image."

if pgrep -x Boo >/dev/null 2>&1; then
  say "Closing the running Boo..."
  osascript -e 'tell application "Boo" to quit' >/dev/null 2>&1 || true
  sleep 2
fi

say "Installing to $dest_dir..."
rm -rf "$dest_dir/Boo.app"
ditto "$mnt/Boo.app" "$dest_dir/Boo.app" || fail "it couldn't copy Boo to $dest_dir."
xattr -dr com.apple.quarantine "$dest_dir/Boo.app" >/dev/null 2>&1 || true

say "Boo is installed."
[ -n "${BOO_NO_OPEN:-}" ] || open "$dest_dir/Boo.app"
