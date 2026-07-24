#!/usr/bin/env bash
# Declarative krew (kubectl plugin manager) plugins — ALL machines.
# chezmoi re-runs this whenever this file changes (edit PLUGINS to add/remove).
#
# The krew binary itself: macOS comes from the Brewfile (brew "krew"); Linux/WSL
# is bootstrapped here from the official release tarball, after which krew
# manages itself as a plugin (~/.krew/bin/kubectl-krew — already on PATH via
# .zshrc). git is required by krew for its plugin index.
set -eu

PLUGINS=(access-matrix cert-manager deprecations gadget grep)

command -v kubectl >/dev/null 2>&1 || { echo "krew-plugins: kubectl not found — skipping"; exit 0; }

KREW_BIN="${KREW_ROOT:-$HOME/.krew}/bin/kubectl-krew"
[ -x "$KREW_BIN" ] || KREW_BIN="$(command -v kubectl-krew 2>/dev/null || true)"

if [ -z "$KREW_BIN" ] || [ ! -x "$KREW_BIN" ]; then
  case "$(uname -s)" in
    Darwin)
      # brew owns the mac install — don't shadow it with a curl bootstrap.
      echo "krew-plugins: krew missing — install it first: brew bundle --file ~/.Brewfile"
      exit 0 ;;
    Linux)
      echo "krew-plugins: bootstrapping krew from the official release..."
      tmp="$(mktemp -d)"
      ( cd "$tmp"
        OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
        ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/' -e 's/armv7l/arm/')"
        KREW="krew-${OS}_${ARCH}"
        curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz"
        tar zxf "${KREW}.tar.gz"
        "./${KREW}" install krew )
      rm -rf "$tmp"
      KREW_BIN="${KREW_ROOT:-$HOME/.krew}/bin/kubectl-krew" ;;
    *)
      echo "krew-plugins: unsupported OS $(uname -s) — skipping"; exit 0 ;;
  esac
fi

# `krew list` prints bare names when piped, but be column-tolerant anyway.
installed="$("$KREW_BIN" list 2>/dev/null | awk '{print $1}')"
for p in "${PLUGINS[@]}"; do
  if printf '%s\n' "$installed" | grep -qx "$p"; then
    echo "krew-plugins: $p already installed"
  else
    echo "krew-plugins: installing $p"
    "$KREW_BIN" install "$p"
  fi
done
