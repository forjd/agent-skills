---
name: repo-hardening
description: >
  Audit and harden GitHub repository security settings using the gh CLI.
  Use when the user wants to review or improve repository security posture,
  enforce branch protection, enable secret scanning, configure merge policies,
  lock down GitHub Actions permissions, or apply security best practices.
  Triggers on requests to "harden", "secure", "lock down", or "audit" a
  GitHub repository, even if they just say "make this repo more secure".
---

# Repo Hardening

Audit and fix GitHub repository security settings using the bundled `scripts/harden.sh`.

## Prerequisites

Before running the script, ensure:
1. `gh` CLI is installed and authenticated (`gh auth login`)
2. `jq` is installed
3. The user has **admin access** to the target repository

The script checks all three and exits with a clear error if any are missing.

## Workflow

Always follow this sequence:

1. **Resolve the script path** — run the bundled script via the path to this skill directory, not the current project directory:
   ```bash
   SKILL_DIR="/path/to/repo-hardening"  # directory containing this SKILL.md
   HARDEN_SCRIPT="$SKILL_DIR/scripts/harden.sh"
   ```

2. **Audit first** — run the audit to see current state:
   ```bash
   bash "$HARDEN_SCRIPT" audit --repo OWNER/REPO
   ```

3. **Present findings** — summarise the audit results to the user, highlighting `fail` and `warn` items grouped by severity (critical > high > medium > low).

4. **Confirm before fixing** — ask the user which categories to fix. Use `--checks` to scope fixes to the confirmed categories. Use `--dry-run` if they want to preview:
   ```bash
   bash "$HARDEN_SCRIPT" fix --repo OWNER/REPO --checks branches,security --dry-run
   ```

   If branch protection has no existing required status checks, pass each CI context explicitly:
   ```bash
   bash "$HARDEN_SCRIPT" fix --repo OWNER/REPO --checks branches --required-check "test"
   ```

5. **Apply fixes** — once confirmed, keep the same scoped `--checks` and any `--required-check` options from the preview:
   ```bash
   bash "$HARDEN_SCRIPT" fix --repo OWNER/REPO --checks branches,security
   ```

6. **Verify** — run audit again to confirm all checks pass.

## Check Categories

| Category   | Flag               | What it covers                                                  |
|------------|--------------------|-----------------------------------------------------------------|
| `repo`     | `--checks repo`    | Auto-delete branches, suggest PR updates, wiki/projects         |
| `branches` | `--checks branches`| Branch protection: require PRs, reviews, code owners, checks    |
| `security` | `--checks security`| Dependabot, secret scanning, push protection                    |
| `merge`    | `--checks merge`   | Merge strategy enforcement (rebase by default)                  |
| `actions`  | `--checks actions` | Actions permissions, workflow token, PR approval restrictions    |
| `access`   | `--checks access`  | CODEOWNERS, deploy keys, outside collaborators (report only)    |

Run all categories with `--checks all` (the default).

## Key Options

- `--merge-strategy rebase|squash|any` — which merge method to enforce (default: rebase)
- `--min-reviewers N` — minimum required PR reviewers (default: 1)
- `--branch BRANCH` — branch to protect (default: repo's default branch)
- `--required-check NAME` — required status check context for branch protection; repeat for multiple checks
- `--format json|text` — output format (default: json)

## Interpreting Results

**Audit statuses:**
- `pass` — meets the hardened policy
- `fail` — does not meet policy; fixable by the script
- `warn` — informational; needs human review (e.g. deploy keys, wiki)
- `skip` — not applicable or insufficient permissions (e.g. GHAS features on private repos)

**Severity levels:** `critical` > `high` > `medium` > `low`

For detailed documentation of each check, see [references/checks.md](references/checks.md).

## Multi-Repo Hardening

To audit all repos in an org:
```bash
gh repo list ORGNAME --limit 1000 --json nameWithOwner -q '.[].nameWithOwner' | \
  while read -r repo; do bash "$HARDEN_SCRIPT" audit --repo "$repo"; done
```

## Limitations

- **GHAS features**: Secret scanning push protection requires GitHub Advanced Security on private repos. The script skips these gracefully.
- **Org-level overrides**: Some settings (Actions policies, required workflows) can be locked at the org level and cannot be changed per-repo.
- **CODEOWNERS content**: The script checks for the file's existence but does not validate its contents.
- **Access checks**: Deploy keys and outside collaborators are reported but not modified — they require human judgement.
