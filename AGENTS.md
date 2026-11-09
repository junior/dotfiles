# Agents: setting up a machine from these dotfiles

For coding agents (Claude Code, Codex, Devin and others) that set up or look after a
machine from github.com/junior/dotfiles or from a fork of it. [README.md](README.md)
explains the design at length; this file is the short form, with the rules. chezmoi
never applies this file or CLAUDE.md to a home folder: `.chezmoiignore` lists both.

## Scope

- This repository is a **public core**: one chezmoi source for three kinds of machine,
  the profiles `mac-personal`, `wsl-work` and `linux-minimal`. It changes only
  upstream, through its maintainer (see [Changing the core](#changing-the-core)).
- In a fork, propose a change upstream, as an issue or a pull request against
  github.com/junior/dotfiles, instead of making the fork diverge. Change the fork
  itself only when your user decides to, knowing that later upstream merges will
  then conflict.
- Whatever one machine or one employer needs goes outside the core, in the places
  listed under [Where a machine's own things go](#where-a-machines-own-things-go).

## Setting up a machine

1. Use upstream, or a fork that only tracks it. Keep a fork in step with GitHub's
   **Sync fork** button, or in its source folder (`chezmoi cd`):
   `git fetch upstream && git merge upstream/main`.
2. On a work machine, set up its private overlay first (next section) and run the
   overlay's `install.sh`, before the first `chezmoi init --apply` or `up`, so the
   first apply already has its package changes.
3. Install as the README's "First-time setup" says: `bootstrap.sh`, or
   `chezmoi init --apply <repo>`. chezmoi asks for the profile: pick the KIND of
   machine, never invent a name. linux-minimal also asks for a bigger filesystem and
   optional extras; mac-personal asks for roles and lab hosts. Give the roles
   there, before anything is applied: a Mac that takes `appliance` or
   `docker-engine` later keeps what the earlier apply installed (README,
   "Machine roles").
4. Put the user's own name and email in `~/.gitconfig.local`. The public
   `~/.gitconfig` carries the maintainer's identity and includes that file last,
   so without it every commit on the machine would carry the maintainer's name.
5. Run `up`.

## Where a machine's own things go

| what | where |
| --- | --- |
| profile, roles, signing key, lab hosts, extras | local chezmoi data, `~/.config/chezmoi/chezmoi.toml`: answered at `chezmoi init`, changed by editing that file, shown by `chezconf` |
| a Mac that lets the Claude desktop app update itself | `claude_desktop_auto_updates = true` under `[data]` in that file, added by hand and kept by `chezmoi init`: the check that the app's updater is blocked then stays quiet |
| anything for work: identity, hosts, aliases, tools | a private overlay cloned to `~/.local/share/dotfiles-overlay`: copy [examples/overlay/](examples/overlay/) into a PRIVATE repository of its own; never a fork, never public |
| a public package to skip, or to take in another build | `~/.config/dotfiles/packages.toml` (linked from the overlay): `skip = [...]`, `[replace] old = new`; README, "Replacing or skipping a public package" |
| extra Homebrew packages (Mac) | `~/.Brewfile.local`, added at the end of `~/.Brewfile`; on an appliance, the service's own formulae, pinned by hand (`brew pin NAME`) and listed with `pin: true`, which Homebrew honours only from its first release after 7.0.12, so that `up` does not upgrade them under the running service; the libraries under a pin still move, so `up` runs there in the service's window (README, "Machine roles") |
| extra command-line tools | `~/.config/mise/conf.d/*.toml`; mise cannot change a tool the public config declares from there, so skip or replace that one in `packages.toml` first |
| git name and email | `~/.gitconfig.local`, which `~/.gitconfig` includes last |
| the machines a Mac watches with `peer-watch` | `~/.config/peer-watch/hosts`, a file of the user's own that chezmoi never writes; `chezmoi apply` loads the watch while it lists a machine (README, "Watching the other Macs") |
| shell aliases and environment | `~/.config/zsh/local.d/*.zsh`; on linux-minimal `~/.config/bash/local.bash` or `local.d/*.bash` |
| ssh hosts | files in `~/.ssh/config.d/` |

## Don'ts

- Never rename `mac-personal`, `wsl-work` or `linux-minimal` after a machine, and
  never make a template branch on a machine's name. What a machine does is a role
  (`session-host`, `docker-engine`, `secrets`, `appliance`); what it has of its
  own goes in the places above.
- Never remove a profile, even one you do not use: upstream keeps all three, and a
  fork without one no longer merges upstream cleanly.
- Before adding a tool, look in [TOOLS.md](TOOLS.md): it lists everything each
  profile installs. Claude Code (`claude-code@latest` on a Mac, the stable
  `claude-code` on a session host) and the Claude desktop app (`claude`) are
  already there. A different build of a listed tool is a
  replacement in `packages.toml`, not a second entry.
- Never put names, email addresses, host names, internal URLs, keys, tokens or other
  secrets in this repository or a fork of it: both are public.
- Never edit a file chezmoi manages in place (`chezmoi managed` lists them): the next
  apply overwrites it, or stops to ask.

## Commands

| command | what it does | when to run it |
| --- | --- | --- |
| `up` | Syncs the private overlay where there is one (pull, then its `install.sh`; skipped with a message when the overlay's host does not resolve), then the dotfiles (`chezmoi update`; on linux-minimal `chezmoi git pull` and `chezmoi init --apply`), then the packages: on a Mac `brew update`, `brew bundle install --global`, `brew upgrade`, `brew cleanup` and `cask-update --check`; on WSL `mise self-update --no-plugins`, then `mise plugins update` with its output kept back (a plugin is named only when its commit moved, and errors still show); everywhere `mise install`, `mise upgrade` and `mise prune`; on linux-minimal also the krew plugins. Prints the toolchain by category at the end, and `footprint` on linux-minimal. Run in Ghostty on a Mac, it says when the open Ghostty is older than the installed one: brew upgrades Ghostty but never quits the app it runs in. | To bring a machine current, after an upstream change, after editing local data. It upgrades everything and can take minutes or ask for a password (casks with installers), so with the user's go-ahead. |
| `chezmoi diff` | Shows what an apply would change. Read-only. | Before every `chezmoi apply`. |
| `chezmoi apply [TARGET...]` | Writes the managed files, and runs the `run_` scripts. | After `chezmoi diff`, to apply a change. |
| `chezmoi edit FILE` | Opens the source of a managed file. The only way to change a templated file (`*.tmpl` in the source). | To change a managed file, in the core only (see Scope). |
| `chezmoi re-add FILE` | Copies a change made in a live, non-templated file back into the source. chezmoi cannot un-template, so never for a templated file. | Rarely; prefer `chezmoi edit`. |
| `chezmoi init` | Regenerates `~/.config/chezmoi/chezmoi.toml` from the config template. Answers already there are kept, and so is `claude_desktop_auto_updates`; only new questions are asked. Anything else added to that file by hand is dropped. | When `up` reports that the config template changed. Run `chezconf` first. |
| `chezconf` (zsh) | Prints this machine's chezmoi data: profile, roles, lab hosts, signing key, CA URL, bigdisk, extras. Read-only. | Before `chezmoi init`, or to see how a machine is set up. |
| `tools` | Counts the tools each category declares, read from the `# --- Category ---` headers of `~/.Brewfile` and the mise config. Read-only. | To see the shape of a machine's toolchain; TOOLS.md has the long form. |
| `cask-update` (Mac) | `cask-update --check` names the pinned casks whose app is behind its cask (what `up` runs). `cask-update [-y] NAME...` quits the app if it runs, unpins, upgrades, pins again and reopens it; it refuses to update the Claude desktop app from a shell inside that app. | `--check` any time. An update only when the user asks: it quits the app. |
| `claude-signin` (Mac) | Prints the age of the Claude desktop app's sign-in and when it is expected to lapse, about 30 days after it (`up` prints it too); every session the app hosts stops when it lapses. `claude-signin check` is what its launchd job runs every 15 minutes, warning before the lapse; `claude-signin reminders on` adds the warnings to Reminders. Writes only its own state, under `~/.local/state/claude-signin`. | When sessions fail with a 401, and before a trip. Signing in again is the user's, in the app. |
| `peer-watch` (Mac) | Shows each machine listed in `~/.config/peer-watch/hosts` and whether it answers. Its launchd job runs `peer-watch check` every minute while the file lists a machine: a notification when one has not answered for 5 minutes, another when it is back; `peer-watch reminders on` adds reminders; `peer-watch home` prints the line that keeps a travelling Mac's watch to the home network. Probes only the listed machines, on the local network, and writes only its own state, under `~/.local/state/peer-watch`. Not on lab nodes or appliances. | To see which machines answer, and after the user edits the list (then `chezmoi apply`). |
| `kcx` | One kubeconfig file per cluster under `~/.kube`; `kcx -h` lists the commands (`kc`, `kcc`, `kn` and `knc` are its aliases; kubectx and kubens are gone). Every shell shares one current context, so switching it in one session moves every other session to another cluster. | Never switch the context: name the cluster per command, `kubectl --context NAME ...` or `kcx run NAME -- COMMAND`, and use `kcx -r NAME -- COMMAND` for anything that only reads. `kcx add` and `kcx temp create` switch only with `--use`. A shell computes `KUBECONFIG` when it starts, so in the command that adds a cluster, reach it with `kcx run`; `kubectl --context` sees it from the next shell on. |
| `rkind`, `rkind-fix-kubeconfig`, `rkind-load-image` (WSL) | `rkind ARGS` runs kind as root on podman, for clusters whose agents load eBPF programs, hands the kubeconfig back and, after `create`, points it at the control-plane container. `rkind-fix-kubeconfig [CLUSTER]` does that pointing again (after a WSL restart). `rkind-load-image IMAGE` copies an image from rootless to rootful podman and loads it into the cluster. They use sudo. | Only for a cluster that needs root; plain `kind` otherwise. |
| `footprint` (linux-minimal) | Disk use of the setup, part by part, in MB, and the free space in the home filesystem. Read-only. | On a small home, before and after adding an extra. |
| `./gen-tools.py [--check]` | Regenerates TOOLS.md from the Brewfile, the mise config and the `run_` installers; `--check` fails when TOOLS.md is stale. Needs a Mac with Homebrew and mise, whose package metadata it reads. | After adding or removing a tool, in a change to the core. |

`tx` (a file-transfer client) and `vaults` (a status line per Obsidian vault) are the
maintainer's own tools: leave them alone.

## Changing the core

Upstream only: the maintainer's changes, and changes proposed to upstream.

- Edit the source (`chezmoi cd`), never a live file.
- A command-line tool added to the Mac's Brewfile also goes in the mise
  config's block for Intel Macs and lab nodes when its project publishes macOS
  builds for both chips, and its Brewfile line takes the `# from mise here:`
  prefix that comments it out there; with a build for one chip only, key both on
  that chip, as yh is. With no Intel build anywhere, an Intel Mac compiles it
  from source once, when it first installs it (`up` never upgrades formulae
  there), so leave it out on Intel and lab nodes when that is not worth it, as
  lnav is.
- Branch templates on profiles (`.machine`), roles, `.chezmoi.arch` or
  `.chezmoi.os`, never on a machine's name. Read optional data through `hasKey`: a
  missing key stops the template.
- Render every profile before and after the change, and compare: mac-personal on
  Apple silicon and on Intel (`--override-data '{"chezmoi":{"arch":"amd64"}}'`), a
  lab node (role `docker-engine`), an appliance (role `appliance`), wsl-work,
  linux-minimal with and without extras.
  Use a throwaway config for each,
  `chezmoi --config THROWAWAY.toml --source TREE execute-template < FILE`, with
  `--source` at the tree being rendered: the Brewfile and the mise config render
  themselves a second time from there.
- Run the checks that apply: `./gen-tools.py --check`; `brew bundle list --file` on
  a rendered Brewfile; a TOML parser on a rendered mise config; `zsh -n` or
  `bash -n` on rendered shell files; `chezmoi managed` per profile after a
  `.chezmoiignore` change; shellcheck on changed scripts.
- A `run_` script starts with its guard (one that renders empty never runs), stays
  silent when there is nothing to do, and warns instead of failing when something
  it needs is missing: a failing script stops the whole apply.
- Plain ASCII in files and commit messages. No employer names or content, no
  secrets, no personal addresses: what is specific goes in local data or an
  overlay, as above.
