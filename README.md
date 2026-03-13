# Agent Skills

A collection of [agent skills](https://agentskills.io) for the **forjd** organisation — portable, version-controlled capabilities that any skills-compatible AI agent can discover and use.

## Available Skills

| Skill | Description |
|-------|-------------|
| [`repo-hardening`](skills/repo-hardening) | Audit and harden GitHub repository security settings via the `gh` CLI |

## Quick Start

```bash
# Audit a repo's security posture
bash skills/repo-hardening/scripts/harden.sh audit --repo forjd/my-service

# Preview fixes without applying
bash skills/repo-hardening/scripts/harden.sh fix --repo forjd/my-service --dry-run

# Apply fixes
bash skills/repo-hardening/scripts/harden.sh fix --repo forjd/my-service
```

## Structure

```
skills/
└── <skill-name>/
    ├── SKILL.md          # Instructions + metadata (required)
    ├── scripts/          # Executable code
    ├── references/       # Detailed documentation
    └── assets/           # Templates, resources
```

Each skill follows the [Agent Skills specification](https://agentskills.io/specification). See [`docs/skill-guidelines.md`](docs/skill-guidelines.md) for our authoring guidelines.

## Licence

[MIT](LICENCE) — Forjd.dev
