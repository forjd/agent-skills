# Agent Skills

A collection of [agent skills](https://agentskills.io) for the **forjd** organisation — portable, version-controlled capabilities that any skills-compatible AI agent can discover and use.

## Available Skills

| Skill | Description |
|-------|-------------|
| [`repo-hardening`](skills/repo-hardening) | Audit and harden GitHub repository security settings via the `gh` CLI |
| [`github-pr`](skills/github-pr) | Create standardised pull requests with conventional titles, templates, and reviewers |
| [`pr-review-actioner`](skills/pr-review-actioner) | Action PR review feedback — triage, fix, and reply to unresolved review comments |
| [`browse`](skills/browse) | Browser automation CLI for navigating, testing, screenshotting, and interacting with web pages |

## Installation

**Via the [Skills CLI](https://skills.sh/docs/cli)** (no setup required):

```bash
npx skills add forjd/agent-skills
# or
bunx skills add forjd/agent-skills
```

**Via git clone**, then copy the skill directories into your agent's skills directory. Most clients discover direct child directories that contain `SKILL.md`, so copy `skills/*` rather than relying on the collection repo root being scanned.

```bash
# Project-level (one project)
git clone https://github.com/forjd/agent-skills.git /tmp/agent-skills
mkdir -p .agents/skills
cp -R /tmp/agent-skills/skills/* .agents/skills/

# User-level (all projects)
git clone https://github.com/forjd/agent-skills.git /tmp/agent-skills
mkdir -p ~/.agents/skills
cp -R /tmp/agent-skills/skills/* ~/.agents/skills/
```

| Agent | User-level path |
|-------|-----------------|
| Claude Code | `~/.claude/skills/` |
| Cursor | `~/.cursor/skills/` |
| Cross-client | `~/.agents/skills/` |

Individual skills can also be copied directly because each `skills/<name>/` directory is self-contained.

> See the [Agent Skills docs](https://agentskills.io/client-implementation/adding-skills-support) for the full list of supported agents and discovery paths.

## Quick Start

```bash
# Audit a repo's security posture
bash skills/repo-hardening/scripts/harden.sh audit --repo forjd/my-service

# Preview fixes without applying
bash skills/repo-hardening/scripts/harden.sh fix --repo forjd/my-service --checks branches --required-check "test" --dry-run

# Apply confirmed fixes
bash skills/repo-hardening/scripts/harden.sh fix --repo forjd/my-service --checks branches --required-check "test"
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
