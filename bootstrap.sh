#!/bin/sh
if grep -q "$(printf '\r')" "$0" 2>/dev/null; then tr -d '\r' < "$0" > "$0.lf" && mv -f "$0.lf" "$0" && exec sh "$0" "$@"; fi # heals CRLF from a Windows paste; keep on one line
# bootstrap.sh - put chezmoi on a host that has no package manager, then apply
# these dotfiles. Intended for the "linux-minimal" profile: a box where you get a
# home directory and nothing else, such as a jump host, a Raspberry Pi or a NUC.
#
# Downloads the release tarball and its published checksum file and verifies one
# against the other before unpacking. Nothing is piped into a shell, nothing needs
# root, and nothing is written outside $HOME.
#
# Usage:
#   sh bootstrap.sh                      install chezmoi, then `chezmoi init --apply`
#   sh bootstrap.sh --chezmoi-only       just install chezmoi
#   sh bootstrap.sh --repo USER/REPO     apply someone else's fork
#   sh bootstrap.sh --version v2.72.2    pin an exact chezmoi release
#   sh bootstrap.sh --bigdisk DIR        home is small: put chezmoi and all temp
#                                        files on DIR (a directory you own on a
#                                        larger filesystem). Give the same DIR
#                                        when chezmoi asks for "bigdisk".
#   sh bootstrap.sh --uninstall          show what removing the profile would do
#   sh bootstrap.sh --uninstall --yes    do it: managed files, links, chezmoi,
#                                        mise, the shell tools. Distro defaults
#                                        come back from /etc/skel. The big-disk
#                                        directory is listed, never deleted.
set -eu

REPO_DEFAULT="junior/dotfiles"
CHEZMOI_REPO="twpayne/chezmoi"
PINNED="v2.72.2"

REPO=$REPO_DEFAULT; ONLY=0; VER=$PINNED; BIG=""; UNINSTALL=0; YES=0
while [ $# -gt 0 ]; do
  case $1 in
    --chezmoi-only) ONLY=1 ;;
    --uninstall)    UNINSTALL=1 ;;
    --yes)          YES=1 ;;
    --bigdisk)      BIG=${2:?--bigdisk needs a directory}; shift ;;
    --repo)         REPO=${2:?--repo needs USER/REPO}; shift ;;
    --version)      VER=${2:?--version needs a tag}; shift ;;
    -h|--help)      sed -n '/^# bootstrap.sh/,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "bootstrap: unknown argument '$1' (try --help)" >&2; exit 2 ;;
  esac
  shift
done

die()  { echo "bootstrap: $*" >&2; exit 1; }
note() { echo "  $*"; }

# ---------------------------------------------------------------- uninstall --
if [ "$UNINSTALL" = 1 ]; then
  CFG="$HOME/.config/chezmoi/chezmoi.toml"
  big=$(sed -n 's/^[[:space:]]*bigdisk[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$CFG" 2>/dev/null | head -1)
  managed=""
  if command -v chezmoi >/dev/null 2>&1 || [ -x "$HOME/.local/bin/chezmoi" ]; then
    managed=$(PATH="$HOME/.local/bin:$PATH" chezmoi managed --include=files,symlinks 2>/dev/null || true)
  fi
  run() { if [ "$YES" = 1 ]; then "$@"; else echo "    would: $*"; fi; }
  echo "uninstall of the linux-minimal profile$( [ "$YES" = 1 ] || echo ' (dry run: add --yes to do it)')"
  echo "  1. chezmoi-managed files:"
  if [ -n "$managed" ]; then
    printf '%s\n' "$managed" | while IFS= read -r f; do [ -n "$f" ] && run rm -f "$HOME/$f"; done
  else
    for f in .bashrc .bash_profile .inputrc .vimrc .tmux.conf .config/bash/bc-compat.bash .config/mise/config.toml \
             .local/bin/tx .local/bin/oscopy .local/bin/tmux-tidy; do [ -e "$HOME/$f" ] && run rm -f "$HOME/$f"; done
  fi
  for d in "$HOME/.config/bash" "$HOME/.config/mise"; do      # only if now empty
    [ -d "$d" ] && [ -z "$(ls -A "$d" 2>/dev/null)" ] && run rmdir "$d"
  done
  echo "  2. distro defaults back from /etc/skel:"
  for f in .bashrc .bash_profile .bash_logout; do [ -f "/etc/skel/$f" ] && run cp "/etc/skel/$f" "$HOME/$f"; done
  echo "  3. links into the big filesystem, and what was parked there:"
  for l in "$HOME/.local/share" "$HOME/.cache" "$HOME/.krew" "$HOME/.local/bin/mise" "$HOME/.local/bin/chezmoi"; do
    [ -L "$l" ] && run rm -f "$l"
  done
  echo "  4. chezmoi's own state, source and temp:"
  for d in "$HOME/.config/chezmoi" "$HOME/.chezmoi-tmp" "$HOME/.local/share/chezmoi" "$HOME/.config/jump"; do
    [ -e "$d" ] && run rm -rf "$d"
  done
  for f in "$HOME/.local/bin/chezmoi" "$HOME/.local/bin/mise"; do [ -f "$f" ] && run rm -f "$f"; done
  echo "  5. tool installs and caches left in the home (only when nothing was relocated):"
  for d in "$HOME/.local/share/mise" "$HOME/.local/share/blesh" "$HOME/.local/share/fzf" "$HOME/.local/share/bash-completion" "$HOME/.cache/mise" "$HOME/.cache/blesh"; do
    [ -d "$d" ] && [ ! -L "$HOME/.local/share" ] && run rm -rf "$d"
  done
  echo "  6. NOT touched: your kube config, ssh keys, history, or anything you made."
  if [ -n "$big" ] && [ -d "$big" ]; then
    echo "  7. the big-filesystem directory is yours to delete when you are sure:"
    echo "       $big   ($(du -sh "$big" 2>/dev/null | cut -f1))      rm -rf '$big'"
  fi
  [ "$YES" = 1 ] && echo "done. Start a new login shell: exec bash -l"
  exit 0
fi

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v tar  >/dev/null 2>&1 || die "tar is required"
[ "$(uname -s)" = Linux ] || die "this bootstrap is for Linux; on a Mac use Homebrew"

case "$(uname -m)" in
  x86_64|amd64)  ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  armv7l|armv6l) ARCH=armv7  ;;      # 32-bit Raspberry Pi OS
  *) die "unsupported architecture: $(uname -m)" ;;
esac

NUM=${VER#v}
SUMS="chezmoi_${NUM}_checksums.txt"
BASE="https://github.com/$CHEZMOI_REPO/releases/download/$VER"

if [ -n "$BIG" ]; then
  mkdir -p "$BIG/bin" "$BIG/tmp" 2>/dev/null || die "cannot create $BIG/bin and $BIG/tmp"
  [ -w "$BIG/tmp" ] || die "$BIG is not writable"
  chmod 700 "$BIG" 2>/dev/null || true
  TMPDIR="$BIG/tmp"; export TMPDIR         # every download and unpack from here on
fi
tmp=$(mktemp -d) || die "cannot create a temp directory"
trap 'rm -rf "$tmp"' EXIT INT TERM
DEST="$HOME/.local/bin/chezmoi"
REAL=$DEST; [ -n "$BIG" ] && REAL="$BIG/bin/chezmoi"

fetch() {
  code=$(curl -fsSL --connect-timeout 10 --max-time 300 -w '%{http_code}' -o "$2" "$1" 2>"$tmp/err") || {
    die "download failed: $1
    HTTP ${code:-none} $(head -1 "$tmp/err" 2>/dev/null)
    (a TLS error here means the host is missing a certificate authority)"
  }
  [ -s "$2" ] || die "empty download: $1"
}

echo "bootstrap: chezmoi $VER for linux-$ARCH"
note "downloading $SUMS"; fetch "$BASE/$SUMS" "$tmp/$SUMS"

sha_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 "$1" | sed 's/.*= *//'
  else die "need sha256sum or openssl to verify the download"; fi
}

# Try the statically linked musl build first. It runs on any libc, whereas the
# glibc build is compiled against a newer one than enterprise LTS distros ship
# (chezmoi 2.72 needs GLIBC_2.32; RHEL 8 and Oracle Linux 8 have 2.28).
installed=""
for LIBC in musl glibc; do
  ASSET="chezmoi_${NUM}_linux-${LIBC}_${ARCH}.tar.gz"
  grep -q "$ASSET" "$tmp/$SUMS" 2>/dev/null || { note "no $LIBC build published for $ARCH, skipping"; continue; }
  note "trying the $LIBC build: $ASSET"
  fetch "$BASE/$ASSET" "$tmp/$ASSET"
  want=$(tr -d '\r' < "$tmp/$SUMS" | while read -r h f _r; do
    [ "${f##*/}" = "$ASSET" ] && { printf '%s' "$h"; break; }
  done)
  [ -n "$want" ] || die "no checksum line for $ASSET in $SUMS"
  got=$(sha_of "$tmp/$ASSET")
  [ "$want" = "$got" ] || die "CHECKSUM MISMATCH for $ASSET
    expected $want
    got      $got
    Do not use this file."
  note "checksum OK"
  rm -rf "$tmp/x"; mkdir -p "$tmp/x"; tar xzf "$tmp/$ASSET" -C "$tmp/x"
  # -f, never -x: on a noexec filesystem (hardened hosts mount /tmp that way)
  # the kernel fails the executable test even for a 0755 file.
  [ -f "$tmp/x/chezmoi" ] || die "unexpected archive layout: no chezmoi inside $ASSET"
  mkdir -p "$HOME/.local/bin"
  cp "$tmp/x/chezmoi" "$REAL.new"
  chmod 755 "$REAL.new"
  if err=$("$REAL.new" --version 2>&1); then
    mv -f "$REAL.new" "$REAL"
    [ "$REAL" = "$DEST" ] || ln -sfn "$REAL" "$DEST"
    installed=$LIBC
    note "installed ($LIBC): $(printf '%s' "$err" | head -1 | cut -c1-60)"
    break
  fi
  rm -f "$REAL.new"
  note "the $LIBC build will not run here: $(printf '%s' "$err" | head -1 | cut -c1-80)"
done
[ -n "$installed" ] || die "no published chezmoi build runs on this host"

case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH"; export PATH ;; esac

# chezmoi runs its scripts from a temp dir; /tmp is noexec on hardened hosts, so
# give it a directory that permits execution. With --bigdisk that is already the
# big filesystem; otherwise a small directory under $HOME (fine for script files).
if [ -z "$BIG" ]; then
  mkdir -p "$HOME/.chezmoi-tmp"
  TMPDIR="$HOME/.chezmoi-tmp"; export TMPDIR
fi

if [ "$ONLY" = 1 ]; then
  echo
  echo "next:  chezmoi init --apply $REPO"
  exit 0
fi

echo
if command -v git >/dev/null 2>&1; then
  echo "bootstrap: applying $REPO (you will be asked which machine this is)"
  exec "$HOME/.local/bin/chezmoi" init --apply "$REPO"
else
  echo "bootstrap: git is not installed here, so chezmoi cannot clone $REPO."
  echo "Either install git, or copy the source tree over and apply it directly:"
  echo "    chezmoi init --apply --source /path/to/dotfiles"
  exit 0
fi
