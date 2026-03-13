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

Audit and fix GitHub repository security settings using `scripts/harden.sh`.

## Prerequisites

Before running the script, ensure:
1. `gh` CLI is installed and authenticated (`gh auth login`)
2. `jq` is installed
3. The user has **admin access** to the target repository

The script checks all three and exits with a clear error if any are missing.

## Workflow

Always follow this sequence:

1. **Audit first** — run the audit to see current state:
   ```bash
   bash scripts/harden.sh audit --repo OWNER/REPO
   ```

2. **Present findings** — summarise the audit results to the user, highlighting `fail` and `warn` items grouped by severity (critical > high > medium > low).

3. **Confirm before fixing** — ask the user which issues to fix. Use `--dry-run` if they want to preview:
   ```bash
   bash scripts/harden.sh fix --repo OWNER/REPO --dry-run
   ```

4. **Apply fixes** — once confirmed:
   ```bash
   bash scripts/harden.sh fix --repo OWNER/REPO
   ```

5. **Verify** — run audit again to confirm all checks pass.

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
gh repo list ORGNAME --json nameWithOwner -q '.[].nameWithOwner' | \
  while read repo; do bash scripts/harden.sh audit --repo "$repo"; done
```

## Limitations

- **GHAS features**: Secret scanning push protection requires GitHub Advanced Security on private repos. The script skips these gracefully.
- **Org-level overrides**: Some settings (Actions policies, required workflows) can be locked at the org level and cannot be changed per-repo.
- **CODEOWNERS content**: The script checks for the file's existence but does not validate its contents.
- **Access checks**: Deploy keys and outside collaborators are reported but not modified — they require human judgement.
