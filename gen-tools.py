#!/usr/bin/env python3
"""Regenerate TOOLS.md from the Brewfile and the mise config.

Both files already group their entries under `# --- Category ---` headers, so
those headers ARE the category source: there is no second list to keep in sync,
and a tool cannot appear in the doc without being declared for installation.

Descriptions and links are read from Homebrew's package metadata rather than
written by hand, so they cannot drift from what the tool actually is. Tools that
Homebrew does not carry fall back to the mise registry's backend reference,
which names the upstream repository.

Usage:  ./gen-tools.py [--check]     (--check exits 1 if TOOLS.md is stale)
"""
import json, os, re, subprocess, sys, urllib.request

SRC = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.expanduser("~/Library/Caches/Homebrew/api")


def render(path, machine):
    """Render a chezmoi template as it would apply on `machine`."""
    cfg = f"/tmp/.gen-tools-{machine}.toml"
    with open(cfg, "w") as fh:
        fh.write(f'[data]\nmachine = "{machine}"\n')
    out = subprocess.run(
        ["chezmoi", "--config", cfg, "--source", SRC, "execute-template"],
        stdin=open(os.path.join(SRC, path)), capture_output=True, text=True)
    os.unlink(cfg)
    if out.returncode:
        sys.exit(f"render failed for {path} ({machine}): {out.stderr.strip()}")
    return out.stdout


def parse(text, pattern):
    """Walk a rendered file, returning [(category, name)] in file order."""
    cat, found = None, []
    for line in text.splitlines():
        m = re.match(r"#\s*---\s*(.+?)\s*---", line)
        if m:
            cat = m.group(1)
            continue
        m = re.match(pattern, line)
        if m:
            found.append((cat, m.group(1)))
    return found


def script_tools(machine):
    """Tools installed by the run_ scripts rather than by brew or mise.

    Each installer declares what it puts on the box with `# tools-category:` and
    either `# tools-installs:` or `# tools-installs-array: <shell array>`, the
    latter parsed from the script's own list so it cannot fall out of step. A
    script that renders empty for this machine does not run there, which is how
    per-machine attribution is decided — the same `.machine` guards chezmoi uses.
    """
    found = []
    for fn in sorted(os.listdir(SRC)):
        if not fn.startswith("run_"):
            continue
        text = render(fn, machine)
        if not text.strip():
            continue
        cat = None
        for line in text.splitlines():
            m = re.match(r"#\s*tools-category:\s*(.+?)\s*$", line)
            if m:
                cat = m.group(1)
            m = re.match(r"#\s*tools-installs:\s*(.+?)\s*$", line)
            if m and cat:
                found += [(cat, n) for n in m.group(1).split()]
            m = re.match(r"#\s*tools-installs-array:\s*(\w+)\s*$", line)
            if m and cat:
                found += [(cat, n) for n in shell_array(text, m.group(1))]
    return found


def shell_array(text, name):
    """Extract the words of a `name=( ... )` shell array, ignoring comments."""
    m = re.search(rf"^{name}=\((.*?)\)", text, re.S | re.M)
    if not m:
        return []
    words = []
    for line in m.group(1).splitlines():
        words += line.split("#", 1)[0].split()
    return words


def brew_meta():
    """name -> (desc, homepage) for every formula and cask Homebrew knows."""
    meta, alias = {}, {}
    installed = subprocess.run(["brew", "info", "--json=v2", "--installed"],
                               capture_output=True, text=True)
    if installed.returncode == 0:
        d = json.loads(installed.stdout)
        for f in d["formulae"]:
            meta[f["name"]] = (f.get("desc"), f.get("homepage"))
        for c in d["casks"]:
            name = c["token"]
            desc = c.get("desc") or (c["name"][0] if c.get("name") else None)
            meta[name] = (desc, c.get("homepage"))
    ap = os.path.join(CACHE, "formula_aliases.txt")
    if os.path.exists(ap):
        for line in open(ap):
            if "|" in line:
                a, real = line.strip().split("|", 1)
                alias[a] = real
    return meta, alias


def core_names():
    p = os.path.join(CACHE, "formula_names.txt")
    return set(open(p).read().split()) if os.path.exists(p) else set()


def cask_names():
    p = os.path.join(CACHE, "cask_names.txt")
    return set(open(p).read().split()) if os.path.exists(p) else set()


def fetch_core(formulae, casks):
    """Descriptions for packages Homebrew knows but this machine has not installed.

    Formulae and casks are queried separately: `brew info --formula` fails for the
    whole batch if one name is a cask, which would silently lose the descriptions
    of everything alongside it. Casks are included so a tool installed here by
    another route — the native Claude Code installer on WSL, say — is still
    described by Homebrew rather than by hand.
    """
    out = {}
    for kind, key, names in (("--formula", "formulae", formulae),
                             ("--cask", "casks", casks)):
        for chunk in [names[i:i + 25] for i in range(0, len(names), 25)]:
            r = subprocess.run(["brew", "info", "--json=v2", kind, *chunk],
                               capture_output=True, text=True)
            if r.returncode:
                continue
            for e in json.loads(r.stdout)[key]:
                name = e["name"] if kind == "--formula" else e["token"]
                if e.get("desc"):
                    out[name] = (e["desc"], e.get("homepage"))
    return out


def registry():
    """mise tool name -> backend reference (aqua:owner/repo, github:owner/repo)."""
    r = subprocess.run(["mise", "registry"], capture_output=True, text=True)
    reg = {}
    if r.returncode == 0:
        for line in r.stdout.splitlines():
            parts = line.split()
            if len(parts) >= 2:
                reg[parts[0]] = parts[1]
    return reg


def ref_url(ref):
    """Turn a mise backend reference into a documentation URL."""
    if not ref or ":" not in ref:
        return None
    backend, path = ref.split(":", 1)
    if backend in ("aqua", "github", "ubi"):
        parts = path.split("/")
        return "https://github.com/" + "/".join(parts[:2])
    if backend == "gitlab":
        return "https://gitlab.com/" + "/".join(path.split("/")[:2])
    if backend == "npm":
        return "https://www.npmjs.com/package/" + path
    if backend == "core":
        return None
    return None


# Homebrew does not carry these, so they are described here by hand. Keep this
# list as short as possible: everything else is derived, and cannot go stale.
OVERRIDES = {
    "python":     ("Python programming language", "https://www.python.org/"),
    "terraform":  ("Build, change and version infrastructure declaratively",
                   "https://www.terraform.io/"),
    "regctl":     ("Registry client for OCI images and artifacts, no daemon needed",
                   "https://github.com/regclient/regclient"),
    "docker-cli": ("The Docker command-line client on its own, without the engine",
                   "https://github.com/docker/cli"),
    "kubens":     ("Switch between Kubernetes namespaces (ships with kubectx)",
                   "https://github.com/ahmetb/kubectx"),
    "calico":     ("Kubernetes networking and network policy (CNI)",
                   "https://github.com/projectcalico/calico"),
    "fantasticon": ("Generate an icon font from a directory of SVG files",
                    "https://github.com/tancredi/fantasticon"),
    "devin":      ("Cognition's software agent, driven from the terminal",
                   "https://docs.devin.ai/"),
    "bpftool":    ("Inspect and manipulate eBPF programs and maps",
                   "https://github.com/libbpf/bpftool"),
    "docker-scout": ("Analyse images for known vulnerabilities and policy compliance",
                     "https://github.com/docker/scout-cli"),
    "dhi":        ("Docker Hardened Images CLI",
                   "https://github.com/docker-hardened-images/dhictl"),
    "access-matrix": ("Show an RBAC access matrix for server resources",
                      "https://krew.sigs.k8s.io/plugins/"),
    "cert-manager": ("Manage cert-manager resources from kubectl",
                     "https://krew.sigs.k8s.io/plugins/"),
    "deprecations": ("Flag deprecated and removed Kubernetes APIs in a cluster",
                     "https://krew.sigs.k8s.io/plugins/"),
    "gadget":     ("Inspektor Gadget — eBPF tooling for inspecting workloads",
                   "https://krew.sigs.k8s.io/plugins/"),
    "grep":       ("Filter Kubernetes resources by matching their names",
                   "https://krew.sigs.k8s.io/plugins/"),
    "snyk":       ("Scan dependencies, containers and IaC for known vulnerabilities",
                   "https://snyk.io/"),
}


def split_key(key):
    """A config key -> (display name, url from its backend reference or None).

    mise keys may be bare registry names (`lnav`) or backend-qualified
    (`github:projectcalico/calico`, `npm:@vscode/vsce`); Brewfile entries may be
    tap-qualified (`junior/tap/skilla`).
    """
    if ":" in key:
        return key.split("/")[-1].split(":")[-1], ref_url(key)
    return key.split("/")[-1], None


def describe(key, meta, alias, reg, extra):
    name, url = split_key(key)
    if name in OVERRIDES:
        desc, home = OVERRIDES[name]
        return name, desc, home
    real = alias.get(name, name)
    desc, home = meta.get(real, extra.get(real, (None, None)))
    return name, desc, home or url or ref_url(reg.get(name))


def main():
    check = "--check" in sys.argv
    meta, alias = brew_meta()
    core = core_names()
    reg = registry()

    MISE = r'"?([A-Za-z0-9_.:@/+-]+?)"?\s*=\s*[{"]'
    brewfile = parse(render("dot_Brewfile.tmpl", "mac-personal"),
                     r'(?:brew|cask)\s+"([^"]+)"')
    mise_mac = parse(render("dot_config/mise/config.toml.tmpl", "mac-personal"), MISE)
    mise_wsl = parse(render("dot_config/mise/config.toml.tmpl", "wsl-work"), MISE)
    scripts_mac = script_tools("mac-personal")
    scripts_wsl = script_tools("wsl-work")

    def group(*sources):
        """[(category, [keys])] merged across sources, first-seen order."""
        order, byname = [], {}
        for src in sources:
            for cat, key in src:
                if cat is None:
                    continue
                if cat not in byname:
                    byname[cat] = []
                    order.append(cat)
                if key not in byname[cat]:
                    byname[cat].append(key)
        return [(c, byname[c]) for c in order]

    # One batched lookup for anything not installed on this machine.
    wanted = [split_key(n)[0] for _, n in
              brewfile + mise_wsl + mise_mac + scripts_mac + scripts_wsl]
    unknown = {alias.get(n, n) for n in wanted if alias.get(n, n) not in meta}
    extra = fetch_core(sorted(unknown & core), sorted(unknown & cask_names()))

    lines = [
        "# Installed tools",
        "",
        "Generated by `./gen-tools.py` — do not edit by hand. Categories come from",
        "the `# --- ... ---` headers in the Brewfile and the mise config, so this",
        "file cannot list a tool that is not actually declared for installation.",
        "Descriptions come from Homebrew's package metadata.",
        "",
    ]

    def section(title, groups, note):
        lines.extend([f"## {title}", "", note, ""])
        for cat, keys in groups:
            lines.extend([f"### {cat}", "", "| Tool | What it is |", "| --- | --- |"])
            for key in keys:
                name, desc, home = describe(key, meta, alias, reg, extra)
                label = f"[{name}]({home})" if home else f"`{name}`"
                lines.append(f"| {label} | {desc or '—'} |")
            lines.append("")

    section("mac-personal", group(brewfile, mise_mac, scripts_mac),
            "Homebrew from `dot_Brewfile.tmpl`, the handful of tools mise owns "
            "here (languages and npm globals), and anything the `run_` installer "
            "scripts put on this machine.")
    section("wsl-work", group(mise_wsl, scripts_wsl),
            "mise from `dot_config/mise/config.toml.tmpl` — no Homebrew on this "
            "box — plus the `run_` installer scripts for what mise cannot carry. "
            "Entries above the machine blocks are installed on both.")

    out = "\n".join(lines).rstrip() + "\n"
    path = os.path.join(SRC, "TOOLS.md")
    if check:
        old = open(path).read() if os.path.exists(path) else ""
        if old != out:
            sys.exit("TOOLS.md is stale — run ./gen-tools.py")
        print("TOOLS.md is current")
        return
    open(path, "w").write(out)
    print(f"TOOLS.md written: {len(brewfile) + len(mise_mac) + len(scripts_mac)} mac, "
          f"{len(mise_wsl) + len(scripts_wsl)} wsl "
          f"(scripts contributed {len(scripts_mac)} + {len(scripts_wsl)})")


if __name__ == "__main__":
    main()
