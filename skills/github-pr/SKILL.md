---
name: github-pr
description: >
  Create standardised GitHub pull requests using the gh CLI. Use when the
  user wants to create a PR, open a pull request, submit changes for review,
  or says things like "PR this", "open a PR", or "submit for review". Enforces
  conventional commit titles, structured body templates, labels, and reviewers.
---

# GitHub PR Creation

Create well-structured pull requests using `gh pr create` with consistent formatting and conventions.

## Prerequisites

1. `gh` CLI is installed and authenticated
2. Current directory is a git repository
3. Changes are committed and on a feature branch (not `main` or `master`)

## Workflow

### 1. Check prerequisites

```bash
# Confirm not on default branch
git branch --show-current

# Ensure branch is pushed to remote
git push -u origin HEAD
```

If the user is on `main`/`master`, ask them to create a feature branch first.

### 2. Determine PR type

Infer the type from the branch name prefix:

| Prefix | Type | Label |
|--------|------|-------|
| `feat/`, `feature/` | Feature | `enhancement` |
| `fix/`, `bugfix/` | Bugfix | `bug` |
| `hotfix/` | Hotfix | `bug`, `priority: critical` |
| `chore/`, `refactor/`, `docs/`, `test/` | Chore | `chore` |

If the branch name doesn't match a known prefix, ask the user what type of PR this is.

### 3. Generate PR title

Convert the branch name to a conventional commit-style title:

- `feat/add-user-auth` → `feat: add user auth`
- `fix/login-crash` → `fix: login crash`
- `hotfix/null-pointer` → `fix: null pointer`

Replace hyphens with spaces. Drop the prefix category from the branch name. Capitalise only where appropriate.

If the branch has a single commit, prefer the commit message as the title instead.

### 4. Fill the PR body

Read the matching template from `assets/` and fill it in based on the changes:

- Feature → [assets/feature.md](assets/feature.md)
- Bugfix → [assets/bugfix.md](assets/bugfix.md)
- Hotfix → [assets/hotfix.md](assets/hotfix.md)
- Chore → use the feature template

To understand what changed, run:

```bash
# See commits on this branch
git log --oneline main..HEAD

# See the full diff
git diff main...HEAD --stat
git diff main...HEAD
```

Fill in the template sections with concrete details from the diff. Remove HTML comments. Do not leave placeholder text.

### 5. Set reviewers

If a `CODEOWNERS` file exists, read it to identify who should review:

```bash
cat .github/CODEOWNERS 2>/dev/null || cat CODEOWNERS 2>/dev/null
```

Use the `--reviewer` flag with relevant code owners. If no CODEOWNERS exists, ask the user who should review.

### 6. Create the PR

```bash
gh pr create \
  --title "feat: add user auth" \
  --body "$(cat <<'EOF'
## Summary

Added user authentication using OAuth2...

## Changes

- Added auth middleware
- Created login/logout endpoints

## Test Plan

- Ran full test suite
- Manual testing against staging

## Checklist

- [x] Changes are scoped to the feature described above
- [x] Tests added or updated
- [x] No unrelated changes included
EOF
)" \
  --label "enhancement" \
  --reviewer "username"
```

Always use a heredoc for the body to preserve formatting.

### 7. Report back

After creating the PR, show the user:
- The PR URL
- Title and labels applied
- Who was assigned to review

## Conventions

- **One PR per feature/fix** — don't bundle unrelated changes
- **Keep diffs small** — if the diff is large (>500 lines), suggest splitting
- **Draft PRs** — use `--draft` if the work is still in progress
- **Base branch** — default to `main`; use `--base` if targeting a different branch
