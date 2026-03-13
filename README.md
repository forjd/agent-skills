# Agent Skills

A collection of [agent skills](https://agentskills.io) for the **forjd** organisation — portable, version-controlled capabilities that any skills-compatible AI agent can discover and use.

## Available Skills

| Skill | Description |
|-------|-------------|
| [`repo-hardening`](skills/repo-hardening) | Audit and harden GitHub repository security settings via the `gh` CLI |
| [`github-pr`](skills/github-pr) | Create standardised pull requests with conventional titles, templates, and reviewers |
| [`pr-review-actioner`](skills/pr-review-actioner) | Action PR review feedback — triage, fix, and reply to unresolved review comments |

## Installation

**Via the [Skills CLI](https://skills.sh/docs/cli)** (no setup required):

```bash
npx skills add forjd/agent-skills
# or
bunx skills add forjd/agent-skills
```

**Via git clone** into your agent's skills directory:

```bash
# Project-level (one project)
git clone https://github.com/forjd/agent-skills.git .agents/skills/forjd

# User-level (all projects)
git clone https://github.com/forjd/agent-skills.git ~/.claude/skills/forjd
```

| Agent | User-level path |
|-------|-----------------|
| Claude Code | `~/.claude/skills/` |
| Cursor | `~/.cursor/skills/` |
| Cross-client | `~/.agents/skills/` |

Individual skills can also be copied directly — each `skills/<name>/` directory is self-contained.

> See the [Agent Skills docs](https://agentskills.io/client-implementation/adding-skills-support) for the full list of supported agents and discovery paths.

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
