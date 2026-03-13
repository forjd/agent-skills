# Hardening Checks Reference

Detailed documentation of each check, the GitHub API endpoints used, and what the fix applies.

## Repository Settings (`--checks repo`)

### repo.auto-delete-branches
- **Severity**: high
- **API**: `PATCH /repos/{owner}/{repo}` — `delete_branch_on_merge`
- **Expected**: `true`
- **Why**: Prevents stale branches from accumulating after PRs are merged.

### repo.suggest-update-branch
- **Severity**: medium
- **API**: `PATCH /repos/{owner}/{repo}` — `allow_update_branch`
- **Expected**: `true`
- **Why**: Shows an "Update branch" button on PRs when they're behind the base branch.

### repo.wiki-disabled
- **Severity**: low
- **API**: `PATCH /repos/{owner}/{repo}` — `has_wiki`
- **Expected**: `false`
- **Why**: Disables the wiki if unused, reducing attack surface and avoiding stale documentation.

### repo.projects-disabled
- **Severity**: low
- **API**: `PATCH /repos/{owner}/{repo}` — `has_projects`
- **Expected**: `false`
- **Why**: Disables projects if unused.

## Branch Protection (`--checks branches`)

All branch protection checks use `PUT /repos/{owner}/{repo}/branches/{branch}/protection`. This is an atomic PUT that replaces the entire protection configuration, so the script reads current settings, merges desired values, and PUTs back.

### branches.protected
- **Severity**: critical
- **Why**: Branch protection is the foundation — all other branch checks depend on it being enabled.

### branches.require-pr
- **Severity**: critical
- **Expected**: `required_pull_request_reviews` section present
- **Why**: Ensures all changes go through pull requests rather than direct pushes.

### branches.require-reviews
- **Severity**: critical
- **Expected**: `required_approving_review_count >= MIN_REVIEWERS` (default: 1)
- **Why**: Ensures at least one person reviews every change.

### branches.dismiss-stale-reviews
- **Severity**: high
- **Expected**: `dismiss_stale_reviews: true`
- **Why**: Invalidates approvals when new commits are pushed, preventing approved-then-modified PRs from being merged without re-review.

### branches.require-code-owners
- **Severity**: critical
- **Expected**: `require_code_owner_reviews: true`
- **Why**: Ensures that changes to owned paths require approval from the designated code owners (defined in CODEOWNERS file).

### branches.status-checks
- **Severity**: high
- **Expected**: `required_status_checks.strict: true`
- **Why**: Requires CI checks to pass before merge. Strict mode requires the branch to be up to date, preventing merge skew.

### branches.no-force-push
- **Severity**: critical
- **Expected**: `allow_force_pushes: false`
- **Why**: Prevents history rewriting on the default branch.

### branches.restrict-deletions
- **Severity**: high
- **Expected**: `allow_deletions: false`
- **Why**: Prevents accidental deletion of the default branch.

### branches.linear-history
- **Severity**: high
- **Expected**: `required_linear_history: true`
- **Why**: Enforces a clean, linear commit history (no merge commits on the default branch).

### branches.conversation-resolution
- **Severity**: medium
- **Expected**: `required_conversation_resolution: true`
- **Why**: Prevents merging while review comments are still unresolved.

### branches.enforce-admins
- **Severity**: high
- **Expected**: `enforce_admins: true`
- **Why**: Applies all branch protection rules to repository administrators too, preventing bypass.

## Security Features (`--checks security`)

### security.vulnerability-alerts
- **Severity**: high
- **API**: `PUT /repos/{owner}/{repo}/vulnerability-alerts`
- **Expected**: Enabled (204 response on GET)
- **Why**: Enables Dependabot alerts for known vulnerabilities in dependencies.

### security.automated-fixes
- **Severity**: medium
- **API**: `PUT /repos/{owner}/{repo}/automated-security-fixes`
- **Expected**: `enabled: true`
- **Why**: Automatically creates PRs to fix known vulnerable dependencies.

### security.secret-scanning
- **Severity**: high
- **API**: `PATCH /repos/{owner}/{repo}` — `security_and_analysis.secret_scanning.status`
- **Expected**: `enabled`
- **Why**: Scans for accidentally committed secrets (API keys, tokens, etc.).
- **Note**: Requires GitHub Advanced Security (GHAS) on private repositories. Reports `skip` if unavailable.

### security.push-protection
- **Severity**: high
- **API**: `PATCH /repos/{owner}/{repo}` — `security_and_analysis.secret_scanning_push_protection.status`
- **Expected**: `enabled`
- **Why**: Blocks pushes that contain known secret patterns before they enter the repository.
- **Note**: Requires GHAS on private repositories. Reports `skip` if unavailable.

## Merge Settings (`--checks merge`)

### merge.rebase-enabled / merge.squash-enabled
- **Severity**: high
- **API**: `PATCH /repos/{owner}/{repo}` — `allow_rebase_merge` / `allow_squash_merge`
- **Expected**: Only the chosen strategy enabled (default: rebase)
- **Why**: Enforces a consistent merge strategy across the team.

### merge.merge-disabled
- **Severity**: high
- **API**: `PATCH /repos/{owner}/{repo}` — `allow_merge_commit`
- **Expected**: `false`
- **Why**: Disables merge commits to maintain linear history (complements `branches.linear-history`).

### merge.squash-disabled / merge.rebase-disabled
- **Severity**: high
- **Why**: Disables the non-chosen merge strategy.

### merge.squash-pr-title (squash strategy only)
- **Severity**: medium
- **API**: `PATCH /repos/{owner}/{repo}` — `squash_merge_commit_title`
- **Expected**: `PR_TITLE`
- **Why**: Uses the PR title as the squash commit message, producing cleaner history.

## GitHub Actions (`--checks actions`)

### actions.restricted
- **Severity**: high
- **API**: `PUT /repos/{owner}/{repo}/actions/permissions`
- **Expected**: `allowed_actions: selected`
- **Why**: Prevents arbitrary third-party actions from running in CI.

### actions.verified-only
- **Severity**: high
- **API**: `PUT /repos/{owner}/{repo}/actions/permissions/selected-actions`
- **Expected**: `github_owned_allowed: true, verified_allowed: true`
- **Why**: Only allows actions from GitHub and verified creators.

### actions.token-read-only
- **Severity**: high
- **API**: `PUT /repos/{owner}/{repo}/actions/permissions/workflow`
- **Expected**: `default_workflow_permissions: read`
- **Why**: Limits the default GITHUB_TOKEN to read-only, requiring explicit write permissions per workflow.

### actions.no-pr-approval
- **Severity**: medium
- **API**: `PUT /repos/{owner}/{repo}/actions/permissions/workflow`
- **Expected**: `can_approve_pull_request_reviews: false`
- **Why**: Prevents GitHub Actions from approving PRs, which could be used to bypass review requirements.

## Access (`--checks access`)

These checks are **report-only** — the `fix` command does not modify them as they require human judgement.

### access.codeowners
- **Severity**: medium
- **API**: `GET /repos/{owner}/{repo}/contents/.github/CODEOWNERS` (also checks repo root)
- **Expected**: File exists
- **Why**: CODEOWNERS defines who must review changes to specific paths. Without it, `require_code_owner_reviews` has no effect.

### access.deploy-keys
- **Severity**: medium
- **API**: `GET /repos/{owner}/{repo}/keys`
- **Expected**: Review for necessity
- **Why**: Deploy keys grant access to the repository. Unused or overly-permissioned keys should be removed.

### access.outside-collaborators
- **Severity**: medium
- **API**: `GET /repos/{owner}/{repo}/collaborators?affiliation=outside`
- **Expected**: Review for necessity
- **Why**: Outside collaborators have direct access outside of org membership. Ensure all are still needed.
