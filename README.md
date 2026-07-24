# dotfiles

Cross-machine dotfiles managed with [chezmoi](https://www.chezmoi.io).
One templated source, two machines:

- **mac-personal** — personal MacBook (Homebrew, full freedom)
- **wsl-work** — work laptop, WSL2 Ubuntu (mise, Podman, corporate tooling)

The `.zshrc` is ~85% identical between the two; chezmoi keeps that shared core
single-sourced and isolates the differences in a handful of clearly-labelled
template blocks, so the two machines never drift apart.

## What's here

| Source file          | Deploys to     | Notes                                       |
|----------------------|----------------|---------------------------------------------|
| `dot_zshrc.tmpl`     | `~/.zshrc`     | Templated; per-machine blocks for pkg manager, certs, Podman, aliases |
| `dot_gitconfig.tmpl` | `~/.gitconfig` | delta pager; personal identity, work email layered in via overlay |
| `dot_p10k.zsh`       | `~/.p10k.zsh`  | Powerlevel10k prompt (plain file, not templated) |
| `.chezmoi.toml.tmpl` | chezmoi config | Prompts once for machine identity on init   |

## First-time setup

Do **wsl-work first**, validate it fully, then **mac-personal**.

1. Install chezmoi:
   - wsl-work: `mise use -g chezmoi`
   - mac-personal: `brew install chezmoi`
2. Initialise from this repo:
   ```sh
   chezmoi init --apply git@your-remote:you/dotfiles.git
   ```
   chezmoi prompts once for the machine (`wsl-work` or `mac-personal`), then
   writes `~/.zshrc`, `~/.gitconfig`, etc.
3. Reload: `exec zsh`

## Creating the repo the first time

If the remote doesn't exist yet:

```sh
chezmoi init                         # creates ~/.local/share/chezmoi
cp -r ./* ./.chezmoi* "$(chezmoi source-path)"/
chezmoi apply
cd "$(chezmoi source-path)"
git init && git add . && git commit -m "initial dotfiles"
git remote add origin git@your-remote:you/dotfiles.git
git push -u origin main
```

## Daily workflow

| Action                              | Command                       |
|-------------------------------------|-------------------------------|
| Edit a managed file                 | `chezmoi edit ~/.zshrc`       |
| Apply pending changes               | `chezmoi apply`               |
| Preview pending changes             | `chezmoi diff`                |
| Pull a manual edit back into source | `chezmoi re-add ~/.zshrc`     |
| Sync from the remote (other machine)| `chezmoi update`              |
| Open the source repo                | `chezmoi cd`                  |

Note: templated files (`*.tmpl`) must be edited via `chezmoi edit` — editing
`~/.zshrc` directly and then `re-add` won't work cleanly because chezmoi can't
un-template. `dot_p10k.zsh` is plain, so `re-add` is fine for it.

## Work overlay (keeping employer-specific bits private)

This public repo is the **core**. Anything employer-specific — internal tool
registries, work email, corporate git hosts — lives in a separate **private
overlay** repo, never here. The two are joined entirely by each tool's *native*
include mechanism, so the public core stays standalone and clonable by anyone:

| Layer | Public core | Private overlay |
|-------|-------------|-----------------|
| mise tools | `~/.config/mise/config.toml` | `~/.config/mise/conf.d/*.toml` (mise auto-merges) |
| git email | personal default | `~/.gitconfig.local` (via `[include]`) |
| ssh hosts | `Include ~/.ssh/config.d/*` | files in `~/.ssh/config.d/` |
| shell | sources `~/.config/zsh/local.d/*.zsh` | files in `~/.config/zsh/local.d/` |

The overlay is a plain repo with an `install.sh` that symlinks its fragments into
those paths; the `up` shell function keeps it in sync. Result: one public repo to
share, zero employer details in it, and a work machine that's still fully configured.

## Powerlevel10k prompt

`dot_p10k.zsh` is included (plain file). Tweak with `chezmoi edit ~/.p10k.zsh`,
or re-run `p10k configure` and `chezmoi re-add ~/.p10k.zsh`.
