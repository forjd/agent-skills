#!/usr/bin/env bash
set -euo pipefail

# repo-hardening: Audit and fix GitHub repository security settings
# Requires: gh (authenticated with admin access), jq

VERSION="1.0.0"

# Defaults
COMMAND=""
REPO=""
CHECKS="all"
MERGE_STRATEGY="rebase"
MIN_REVIEWERS=1
BRANCH=""
DRY_RUN=false
FORMAT="json"

# --- Output helpers ---

results=()
changes=()
errors=()

add_result() {
  local id="$1" category="$2" status="$3" current="$4" expected="$5" severity="$6"
  results+=("$(jq -n \
    --arg id "$id" \
    --arg category "$category" \
    --arg status "$status" \
    --arg current "$current" \
    --arg expected "$expected" \
    --arg severity "$severity" \
    '{id: $id, category: $category, status: $status, current: $current, expected: $expected, severity: $severity}')")
}

add_change() {
  local id="$1" action="$2" before="$3" after="$4"
  changes+=("$(jq -n \
    --arg id "$id" \
    --arg action "$action" \
    --arg before "$before" \
    --arg after "$after" \
    '{id: $id, action: $action, before: $before, after: $after}')")
}

add_error() {
  local id="$1" message="$2"
  errors+=("$(jq -n \
    --arg id "$id" \
    --arg message "$message" \
    '{id: $id, message: $message}')")
}

print_audit_results() {
  local pass=0 fail=0 warn=0 skip=0
  for r in "${results[@]}"; do
    case "$(echo "$r" | jq -r '.status')" in
      pass) ((pass++)) ;;
      fail) ((fail++)) ;;
      warn) ((warn++)) ;;
      skip) ((skip++)) ;;
    esac
  done

  local results_json
  results_json=$(printf '%s\n' "${results[@]}" | jq -s '.')

  if [[ "$FORMAT" == "text" ]]; then
    echo "Repository: $REPO"
    echo "Summary: $pass pass, $fail fail, $warn warn, $skip skip"
    echo ""
    echo "$results_json" | jq -r '.[] | "\(.status | ascii_upcase)\t\(.severity)\t\(.id)\t\(.current)"'
  else
    jq -n \
      --arg repo "$REPO" \
      --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --argjson pass "$pass" \
      --argjson fail "$fail" \
      --argjson warn "$warn" \
      --argjson skip "$skip" \
      --argjson checks "$results_json" \
      '{repository: $repo, timestamp: $timestamp, summary: {pass: $pass, fail: $fail, warn: $warn, skip: $skip}, checks: $checks}'
  fi
}

print_fix_results() {
  local changes_json="[]"
  local errors_json="[]"

  if [[ ${#changes[@]} -gt 0 ]]; then
    changes_json=$(printf '%s\n' "${changes[@]}" | jq -s '.')
  fi
  if [[ ${#errors[@]} -gt 0 ]]; then
    errors_json=$(printf '%s\n' "${errors[@]}" | jq -s '.')
  fi

  if [[ "$FORMAT" == "text" ]]; then
    echo "Repository: $REPO"
    if [[ "$DRY_RUN" == true ]]; then
      echo "Mode: dry-run (no changes applied)"
    fi
    echo ""
    if [[ ${#changes[@]} -gt 0 ]]; then
      echo "$changes_json" | jq -r '.[] | "\(.action)\t\(.id)\t\(.before) -> \(.after)"'
    else
      echo "No changes needed."
    fi
    if [[ ${#errors[@]} -gt 0 ]]; then
      echo ""
      echo "Errors:"
      echo "$errors_json" | jq -r '.[] | "  \(.id): \(.message)"'
    fi
  else
    jq -n \
      --arg repo "$REPO" \
      --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --argjson dry_run "$DRY_RUN" \
      --argjson changes "$changes_json" \
      --argjson errors "$errors_json" \
      '{repository: $repo, timestamp: $timestamp, dry_run: $dry_run, changes: $changes, errors: $errors}'
  fi
}

# --- API helpers ---

gh_api() {
  gh api "$@" 2>/dev/null || true
}

gh_api_status() {
  local response
  response=$(gh api "$@" -i 2>/dev/null || true)
  echo "$response" | head -1 | awk '{print $2}'
}

# --- Check: Repository settings ---

check_repo_settings() {
  local repo_data
  repo_data=$(gh_api "repos/$REPO")

  if [[ -z "$repo_data" || "$repo_data" == "null" ]]; then
    add_result "repo.accessible" "repo" "skip" "Could not fetch repo data" "Accessible" "critical"
    return
  fi

  # Auto-delete head branches
  local delete_on_merge
  delete_on_merge=$(echo "$repo_data" | jq -r '.delete_branch_on_merge')
  if [[ "$delete_on_merge" == "true" ]]; then
    add_result "repo.auto-delete-branches" "repo" "pass" "Auto-delete enabled" "Auto-delete enabled" "high"
  else
    add_result "repo.auto-delete-branches" "repo" "fail" "Auto-delete disabled" "Auto-delete enabled" "high"
  fi

  # Always suggest updating PRs
  local allow_update_branch
  allow_update_branch=$(echo "$repo_data" | jq -r '.allow_update_branch // false')
  if [[ "$allow_update_branch" == "true" ]]; then
    add_result "repo.suggest-update-branch" "repo" "pass" "Suggest updating PRs enabled" "Suggest updating PRs enabled" "medium"
  else
    add_result "repo.suggest-update-branch" "repo" "fail" "Suggest updating PRs disabled" "Suggest updating PRs enabled" "medium"
  fi

  # Wiki
  local has_wiki
  has_wiki=$(echo "$repo_data" | jq -r '.has_wiki')
  if [[ "$has_wiki" == "true" ]]; then
    add_result "repo.wiki-disabled" "repo" "warn" "Wiki enabled" "Wiki disabled" "low"
  else
    add_result "repo.wiki-disabled" "repo" "pass" "Wiki disabled" "Wiki disabled" "low"
  fi

  # Projects
  local has_projects
  has_projects=$(echo "$repo_data" | jq -r '.has_projects')
  if [[ "$has_projects" == "true" ]]; then
    add_result "repo.projects-disabled" "repo" "warn" "Projects enabled" "Projects disabled" "low"
  else
    add_result "repo.projects-disabled" "repo" "pass" "Projects disabled" "Projects disabled" "low"
  fi
}

fix_repo_settings() {
  local repo_data
  repo_data=$(gh_api "repos/$REPO")

  if [[ -z "$repo_data" || "$repo_data" == "null" ]]; then
    add_error "repo.settings" "Could not fetch repo data"
    return
  fi

  local delete_on_merge allow_update_branch has_wiki has_projects
  delete_on_merge=$(echo "$repo_data" | jq -r '.delete_branch_on_merge')
  allow_update_branch=$(echo "$repo_data" | jq -r '.allow_update_branch // false')
  has_wiki=$(echo "$repo_data" | jq -r '.has_wiki')
  has_projects=$(echo "$repo_data" | jq -r '.has_projects')

  local patch='{}'
  if [[ "$delete_on_merge" != "true" ]]; then
    patch=$(echo "$patch" | jq '. + {delete_branch_on_merge: true}')
    add_change "repo.auto-delete-branches" "updated" "Auto-delete disabled" "Auto-delete enabled"
  fi
  if [[ "$allow_update_branch" != "true" ]]; then
    patch=$(echo "$patch" | jq '. + {allow_update_branch: true}')
    add_change "repo.suggest-update-branch" "updated" "Disabled" "Enabled"
  fi
  if [[ "$has_wiki" == "true" ]]; then
    patch=$(echo "$patch" | jq '. + {has_wiki: false}')
    add_change "repo.wiki-disabled" "updated" "Wiki enabled" "Wiki disabled"
  fi
  if [[ "$has_projects" == "true" ]]; then
    patch=$(echo "$patch" | jq '. + {has_projects: false}')
    add_change "repo.projects-disabled" "updated" "Projects enabled" "Projects disabled"
  fi

  if [[ "$patch" != "{}" && "$DRY_RUN" == false ]]; then
    gh api "repos/$REPO" -X PATCH --input - <<< "$patch" > /dev/null 2>&1 || \
      add_error "repo.settings" "Failed to update repository settings"
  fi
}

# --- Check: Security features ---

check_security() {
  local repo_data
  repo_data=$(gh_api "repos/$REPO")

  # Vulnerability alerts (Dependabot)
  local vuln_status
  vuln_status=$(gh_api_status "repos/$REPO/vulnerability-alerts")
  if [[ "$vuln_status" == "204" ]]; then
    add_result "security.vulnerability-alerts" "security" "pass" "Enabled" "Enabled" "high"
  else
    add_result "security.vulnerability-alerts" "security" "fail" "Disabled" "Enabled" "high"
  fi

  # Automated security fixes (Dependabot updates)
  local auto_fix_status
  auto_fix_status=$(gh_api_status "repos/$REPO/automated-security-fixes")
  if [[ "$auto_fix_status" == "200" ]]; then
    local auto_fix_enabled
    auto_fix_enabled=$(gh api "repos/$REPO/automated-security-fixes" 2>/dev/null | jq -r '.enabled // false')
    if [[ "$auto_fix_enabled" == "true" ]]; then
      add_result "security.automated-fixes" "security" "pass" "Enabled" "Enabled" "medium"
    else
      add_result "security.automated-fixes" "security" "fail" "Disabled" "Enabled" "medium"
    fi
  else
    add_result "security.automated-fixes" "security" "fail" "Disabled" "Enabled" "medium"
  fi

  # Secret scanning
  local secret_scanning
  secret_scanning=$(echo "$repo_data" | jq -r '.security_and_analysis.secret_scanning.status // "not_available"')
  if [[ "$secret_scanning" == "enabled" ]]; then
    add_result "security.secret-scanning" "security" "pass" "Enabled" "Enabled" "high"
  elif [[ "$secret_scanning" == "not_available" ]]; then
    add_result "security.secret-scanning" "security" "skip" "Not available (requires GHAS)" "Enabled" "high"
  else
    add_result "security.secret-scanning" "security" "fail" "Disabled" "Enabled" "high"
  fi

  # Secret scanning push protection
  local push_protection
  push_protection=$(echo "$repo_data" | jq -r '.security_and_analysis.secret_scanning_push_protection.status // "not_available"')
  if [[ "$push_protection" == "enabled" ]]; then
    add_result "security.push-protection" "security" "pass" "Enabled" "Enabled" "high"
  elif [[ "$push_protection" == "not_available" ]]; then
    add_result "security.push-protection" "security" "skip" "Not available (requires GHAS)" "Enabled" "high"
  else
    add_result "security.push-protection" "security" "fail" "Disabled" "Enabled" "high"
  fi
}

fix_security() {
  # Vulnerability alerts
  local vuln_status
  vuln_status=$(gh_api_status "repos/$REPO/vulnerability-alerts")
  if [[ "$vuln_status" != "204" ]]; then
    add_change "security.vulnerability-alerts" "updated" "Disabled" "Enabled"
    if [[ "$DRY_RUN" == false ]]; then
      gh api "repos/$REPO/vulnerability-alerts" -X PUT > /dev/null 2>&1 || \
        add_error "security.vulnerability-alerts" "Failed to enable vulnerability alerts"
    fi
  fi

  # Automated security fixes
  local auto_fix_enabled="false"
  local auto_fix_status
  auto_fix_status=$(gh_api_status "repos/$REPO/automated-security-fixes")
  if [[ "$auto_fix_status" == "200" ]]; then
    auto_fix_enabled=$(gh api "repos/$REPO/automated-security-fixes" 2>/dev/null | jq -r '.enabled // false')
  fi
  if [[ "$auto_fix_enabled" != "true" ]]; then
    add_change "security.automated-fixes" "updated" "Disabled" "Enabled"
    if [[ "$DRY_RUN" == false ]]; then
      gh api "repos/$REPO/automated-security-fixes" -X PUT > /dev/null 2>&1 || \
        add_error "security.automated-fixes" "Failed to enable automated security fixes"
    fi
  fi

  # Secret scanning + push protection
  local repo_data
  repo_data=$(gh_api "repos/$REPO")
  local secret_scanning push_protection
  secret_scanning=$(echo "$repo_data" | jq -r '.security_and_analysis.secret_scanning.status // "not_available"')
  push_protection=$(echo "$repo_data" | jq -r '.security_and_analysis.secret_scanning_push_protection.status // "not_available"')

  local security_patch='{}'
  if [[ "$secret_scanning" == "disabled" ]]; then
    security_patch=$(echo "$security_patch" | jq '. + {security_and_analysis: {secret_scanning: {status: "enabled"}}}')
    add_change "security.secret-scanning" "updated" "Disabled" "Enabled"
  fi
  if [[ "$push_protection" == "disabled" ]]; then
    security_patch=$(echo "$security_patch" | jq '.security_and_analysis += {secret_scanning_push_protection: {status: "enabled"}}')
    add_change "security.push-protection" "updated" "Disabled" "Enabled"
  fi

  if [[ "$security_patch" != "{}" && "$DRY_RUN" == false ]]; then
    gh api "repos/$REPO" -X PATCH --input - <<< "$security_patch" > /dev/null 2>&1 || \
      add_error "security.settings" "Failed to update security settings (may require GHAS)"
  fi
}

# --- Check: Branch protection ---

get_default_branch() {
  if [[ -n "$BRANCH" ]]; then
    echo "$BRANCH"
  else
    gh api "repos/$REPO" --jq '.default_branch' 2>/dev/null
  fi
}

check_branches() {
  local branch
  branch=$(get_default_branch)
  if [[ -z "$branch" ]]; then
    add_result "branches.default-branch" "branches" "skip" "Could not determine default branch" "Known" "critical"
    return
  fi

  local protection
  protection=$(gh_api "repos/$REPO/branches/$branch/protection")

  if [[ -z "$protection" || "$protection" == *"Branch not protected"* || "$protection" == *"Not Found"* ]]; then
    add_result "branches.protected" "branches" "fail" "No branch protection" "Branch protection enabled" "critical"
    add_result "branches.require-pr" "branches" "fail" "PRs not required" "Require PRs" "critical"
    add_result "branches.require-reviews" "branches" "fail" "No reviews required" ">= $MIN_REVIEWERS reviewer(s)" "critical"
    add_result "branches.dismiss-stale-reviews" "branches" "fail" "Not configured" "Dismiss stale reviews" "high"
    add_result "branches.require-code-owners" "branches" "fail" "Not configured" "Require code owner reviews" "critical"
    add_result "branches.status-checks" "branches" "fail" "Not configured" "Require status checks" "high"
    add_result "branches.no-force-push" "branches" "fail" "Not configured" "Block force pushes" "critical"
    add_result "branches.restrict-deletions" "branches" "fail" "Not configured" "Restrict deletions" "high"
    add_result "branches.linear-history" "branches" "fail" "Not configured" "Require linear history" "high"
    add_result "branches.conversation-resolution" "branches" "fail" "Not configured" "Require conversation resolution" "medium"
    add_result "branches.enforce-admins" "branches" "fail" "Not configured" "Enforce for admins" "high"
    return
  fi

  add_result "branches.protected" "branches" "pass" "Branch protection enabled" "Branch protection enabled" "critical"

  # Require PRs (check if required_pull_request_reviews exists)
  local has_pr_reviews
  has_pr_reviews=$(echo "$protection" | jq -r '.required_pull_request_reviews // null')
  if [[ "$has_pr_reviews" != "null" ]]; then
    add_result "branches.require-pr" "branches" "pass" "PRs required" "Require PRs" "critical"
  else
    add_result "branches.require-pr" "branches" "fail" "PRs not required" "Require PRs" "critical"
  fi

  # Required reviews
  local review_count
  review_count=$(echo "$protection" | jq -r '.required_pull_request_reviews.required_approving_review_count // 0')
  if [[ "$review_count" -ge "$MIN_REVIEWERS" ]]; then
    add_result "branches.require-reviews" "branches" "pass" "$review_count reviewer(s) required" ">= $MIN_REVIEWERS reviewer(s)" "critical"
  else
    add_result "branches.require-reviews" "branches" "fail" "$review_count reviewer(s) required" ">= $MIN_REVIEWERS reviewer(s)" "critical"
  fi

  # Dismiss stale reviews
  local dismiss_stale
  dismiss_stale=$(echo "$protection" | jq -r '.required_pull_request_reviews.dismiss_stale_reviews // false')
  if [[ "$dismiss_stale" == "true" ]]; then
    add_result "branches.dismiss-stale-reviews" "branches" "pass" "Enabled" "Dismiss stale reviews" "high"
  else
    add_result "branches.dismiss-stale-reviews" "branches" "fail" "Disabled" "Dismiss stale reviews" "high"
  fi

  # Require code owner reviews
  local code_owners
  code_owners=$(echo "$protection" | jq -r '.required_pull_request_reviews.require_code_owner_reviews // false')
  if [[ "$code_owners" == "true" ]]; then
    add_result "branches.require-code-owners" "branches" "pass" "Enabled" "Require code owner reviews" "critical"
  else
    add_result "branches.require-code-owners" "branches" "fail" "Disabled" "Require code owner reviews" "critical"
  fi

  # Status checks
  local strict_checks
  strict_checks=$(echo "$protection" | jq -r '.required_status_checks.strict // false')
  if [[ "$strict_checks" == "true" ]]; then
    add_result "branches.status-checks" "branches" "pass" "Strict status checks enabled" "Require status checks" "high"
  else
    add_result "branches.status-checks" "branches" "fail" "Strict status checks disabled" "Require status checks" "high"
  fi

  # Force pushes
  local force_push
  force_push=$(echo "$protection" | jq -r '.allow_force_pushes.enabled // false')
  if [[ "$force_push" == "false" ]]; then
    add_result "branches.no-force-push" "branches" "pass" "Force pushes blocked" "Block force pushes" "critical"
  else
    add_result "branches.no-force-push" "branches" "fail" "Force pushes allowed" "Block force pushes" "critical"
  fi

  # Branch deletion
  local allow_deletion
  allow_deletion=$(echo "$protection" | jq -r '.allow_deletions.enabled // false')
  if [[ "$allow_deletion" == "false" ]]; then
    add_result "branches.restrict-deletions" "branches" "pass" "Deletions restricted" "Restrict deletions" "high"
  else
    add_result "branches.restrict-deletions" "branches" "fail" "Deletions allowed" "Restrict deletions" "high"
  fi

  # Linear history
  local linear
  linear=$(echo "$protection" | jq -r '.required_linear_history.enabled // false')
  if [[ "$linear" == "true" ]]; then
    add_result "branches.linear-history" "branches" "pass" "Linear history required" "Require linear history" "high"
  else
    add_result "branches.linear-history" "branches" "fail" "Linear history not required" "Require linear history" "high"
  fi

  # Conversation resolution
  local conv_resolution
  conv_resolution=$(echo "$protection" | jq -r '.required_conversation_resolution.enabled // false')
  if [[ "$conv_resolution" == "true" ]]; then
    add_result "branches.conversation-resolution" "branches" "pass" "Conversation resolution required" "Require conversation resolution" "medium"
  else
    add_result "branches.conversation-resolution" "branches" "fail" "Conversation resolution not required" "Require conversation resolution" "medium"
  fi

  # Enforce admins
  local enforce_admins
  enforce_admins=$(echo "$protection" | jq -r '.enforce_admins.enabled // false')
  if [[ "$enforce_admins" == "true" ]]; then
    add_result "branches.enforce-admins" "branches" "pass" "Enforced for admins" "Enforce for admins" "high"
  else
    add_result "branches.enforce-admins" "branches" "fail" "Not enforced for admins" "Enforce for admins" "high"
  fi
}

fix_branches() {
  local branch
  branch=$(get_default_branch)
  if [[ -z "$branch" ]]; then
    add_error "branches" "Could not determine default branch"
    return
  fi

  # Get current protection (may not exist)
  local protection
  protection=$(gh_api "repos/$REPO/branches/$branch/protection")
  local has_protection=true
  if [[ -z "$protection" || "$protection" == *"Branch not protected"* || "$protection" == *"Not Found"* ]]; then
    has_protection=false
  fi

  # Read current values to track what changes
  local current_review_count=0
  local current_dismiss_stale=false
  local current_code_owners=false
  local current_strict=false
  local current_contexts='[]'
  local current_enforce_admins=false
  local current_force_push=true
  local current_deletion=true
  local current_linear=false
  local current_conv=false

  if [[ "$has_protection" == true ]]; then
    current_review_count=$(echo "$protection" | jq -r '.required_pull_request_reviews.required_approving_review_count // 0')
    current_dismiss_stale=$(echo "$protection" | jq -r '.required_pull_request_reviews.dismiss_stale_reviews // false')
    current_code_owners=$(echo "$protection" | jq -r '.required_pull_request_reviews.require_code_owner_reviews // false')
    current_strict=$(echo "$protection" | jq -r '.required_status_checks.strict // false')
    current_contexts=$(echo "$protection" | jq '.required_status_checks.contexts // []')
    current_enforce_admins=$(echo "$protection" | jq -r '.enforce_admins.enabled // false')
    current_force_push=$(echo "$protection" | jq -r '.allow_force_pushes.enabled // false')
    current_deletion=$(echo "$protection" | jq -r '.allow_deletions.enabled // false')
    current_linear=$(echo "$protection" | jq -r '.required_linear_history.enabled // false')
    current_conv=$(echo "$protection" | jq -r '.required_conversation_resolution.enabled // false')
  fi

  # Track changes
  if [[ "$has_protection" != true ]]; then
    add_change "branches.protected" "created" "No protection" "Branch protection enabled"
  fi
  if [[ "$current_review_count" -lt "$MIN_REVIEWERS" ]]; then
    add_change "branches.require-reviews" "updated" "$current_review_count reviewer(s)" "$MIN_REVIEWERS reviewer(s)"
  fi
  if [[ "$current_dismiss_stale" != "true" ]]; then
    add_change "branches.dismiss-stale-reviews" "updated" "Disabled" "Enabled"
  fi
  if [[ "$current_code_owners" != "true" ]]; then
    add_change "branches.require-code-owners" "updated" "Disabled" "Enabled"
  fi
  if [[ "$current_strict" != "true" ]]; then
    add_change "branches.status-checks" "updated" "Disabled" "Enabled"
  fi
  if [[ "$current_enforce_admins" != "true" ]]; then
    add_change "branches.enforce-admins" "updated" "Not enforced" "Enforced"
  fi
  if [[ "$current_force_push" != "false" ]]; then
    add_change "branches.no-force-push" "updated" "Allowed" "Blocked"
  fi
  if [[ "$current_deletion" != "false" ]]; then
    add_change "branches.restrict-deletions" "updated" "Allowed" "Restricted"
  fi
  if [[ "$current_linear" != "true" ]]; then
    add_change "branches.linear-history" "updated" "Not required" "Required"
  fi
  if [[ "$current_conv" != "true" ]]; then
    add_change "branches.conversation-resolution" "updated" "Not required" "Required"
  fi

  # If nothing changed, skip the API call
  local branch_changes_count=0
  if [[ ${#changes[@]} -gt 0 ]]; then
    for c in "${changes[@]}"; do
      local cid
      cid=$(echo "$c" | jq -r '.id')
      if [[ "$cid" == branches.* ]]; then
        ((branch_changes_count++))
      fi
    done
  fi

  if [[ "$branch_changes_count" -eq 0 ]]; then
    return
  fi

  if [[ "$DRY_RUN" == true ]]; then
    return
  fi

  # Build and apply the full protection payload (PUT replaces everything)
  local payload
  payload=$(jq -n \
    --argjson review_count "$MIN_REVIEWERS" \
    --argjson contexts "$current_contexts" \
    '{
      required_pull_request_reviews: {
        required_approving_review_count: $review_count,
        dismiss_stale_reviews: true,
        require_code_owner_reviews: true
      },
      required_status_checks: {
        strict: true,
        contexts: $contexts
      },
      enforce_admins: true,
      required_linear_history: true,
      required_conversation_resolution: true,
      allow_force_pushes: false,
      allow_deletions: false,
      restrictions: null
    }')

  gh api "repos/$REPO/branches/$branch/protection" \
    -X PUT \
    --input - <<< "$payload" > /dev/null 2>&1 || \
    add_error "branches.protection" "Failed to update branch protection"
}

# --- Check: Merge settings ---

check_merge() {
  local repo_data
  repo_data=$(gh_api "repos/$REPO")

  if [[ -z "$repo_data" || "$repo_data" == "null" ]]; then
    add_result "merge.settings" "merge" "skip" "Could not fetch repo data" "Configured" "medium"
    return
  fi

  local allow_squash allow_merge allow_rebase
  allow_squash=$(echo "$repo_data" | jq -r '.allow_squash_merge // false')
  allow_merge=$(echo "$repo_data" | jq -r '.allow_merge_commit // true')
  allow_rebase=$(echo "$repo_data" | jq -r '.allow_rebase_merge // true')

  case "$MERGE_STRATEGY" in
    rebase)
      if [[ "$allow_rebase" == "true" ]]; then
        add_result "merge.rebase-enabled" "merge" "pass" "Rebase merge enabled" "Rebase merge enabled" "high"
      else
        add_result "merge.rebase-enabled" "merge" "fail" "Rebase merge disabled" "Rebase merge enabled" "high"
      fi
      if [[ "$allow_merge" == "false" ]]; then
        add_result "merge.merge-disabled" "merge" "pass" "Merge commits disabled" "Merge commits disabled" "high"
      else
        add_result "merge.merge-disabled" "merge" "fail" "Merge commits enabled" "Merge commits disabled" "high"
      fi
      if [[ "$allow_squash" == "false" ]]; then
        add_result "merge.squash-disabled" "merge" "pass" "Squash merge disabled" "Squash merge disabled" "high"
      else
        add_result "merge.squash-disabled" "merge" "fail" "Squash merge enabled" "Squash merge disabled" "high"
      fi
      ;;
    squash)
      local squash_title
      squash_title=$(echo "$repo_data" | jq -r '.squash_merge_commit_title // "COMMIT_OR_PR_TITLE"')
      if [[ "$allow_squash" == "true" ]]; then
        add_result "merge.squash-enabled" "merge" "pass" "Squash merge enabled" "Squash merge enabled" "high"
      else
        add_result "merge.squash-enabled" "merge" "fail" "Squash merge disabled" "Squash merge enabled" "high"
      fi
      if [[ "$allow_merge" == "false" ]]; then
        add_result "merge.merge-disabled" "merge" "pass" "Merge commits disabled" "Merge commits disabled" "high"
      else
        add_result "merge.merge-disabled" "merge" "fail" "Merge commits enabled" "Merge commits disabled" "high"
      fi
      if [[ "$allow_rebase" == "false" ]]; then
        add_result "merge.rebase-disabled" "merge" "pass" "Rebase merge disabled" "Rebase merge disabled" "high"
      else
        add_result "merge.rebase-disabled" "merge" "fail" "Rebase merge enabled" "Rebase merge disabled" "high"
      fi
      if [[ "$squash_title" == "PR_TITLE" ]]; then
        add_result "merge.squash-pr-title" "merge" "pass" "Squash title uses PR title" "PR title" "medium"
      else
        add_result "merge.squash-pr-title" "merge" "fail" "Squash title: $squash_title" "PR title" "medium"
      fi
      ;;
    any)
      add_result "merge.any-strategy" "merge" "pass" "All merge strategies allowed" "Any strategy" "low"
      ;;
  esac
}

fix_merge() {
  local repo_data
  repo_data=$(gh_api "repos/$REPO")

  if [[ -z "$repo_data" || "$repo_data" == "null" ]]; then
    add_error "merge.settings" "Could not fetch repo data"
    return
  fi

  local patch='{}'
  local allow_squash allow_merge allow_rebase
  allow_squash=$(echo "$repo_data" | jq -r '.allow_squash_merge // false')
  allow_merge=$(echo "$repo_data" | jq -r '.allow_merge_commit // true')
  allow_rebase=$(echo "$repo_data" | jq -r '.allow_rebase_merge // true')

  case "$MERGE_STRATEGY" in
    rebase)
      if [[ "$allow_rebase" != "true" ]]; then
        patch=$(echo "$patch" | jq '. + {allow_rebase_merge: true}')
        add_change "merge.rebase-enabled" "updated" "Disabled" "Enabled"
      fi
      if [[ "$allow_merge" != "false" ]]; then
        patch=$(echo "$patch" | jq '. + {allow_merge_commit: false}')
        add_change "merge.merge-disabled" "updated" "Enabled" "Disabled"
      fi
      if [[ "$allow_squash" != "false" ]]; then
        patch=$(echo "$patch" | jq '. + {allow_squash_merge: false}')
        add_change "merge.squash-disabled" "updated" "Enabled" "Disabled"
      fi
      ;;
    squash)
      local squash_title
      squash_title=$(echo "$repo_data" | jq -r '.squash_merge_commit_title // "COMMIT_OR_PR_TITLE"')
      if [[ "$allow_squash" != "true" ]]; then
        patch=$(echo "$patch" | jq '. + {allow_squash_merge: true}')
        add_change "merge.squash-enabled" "updated" "Disabled" "Enabled"
      fi
      if [[ "$allow_merge" != "false" ]]; then
        patch=$(echo "$patch" | jq '. + {allow_merge_commit: false}')
        add_change "merge.merge-disabled" "updated" "Enabled" "Disabled"
      fi
      if [[ "$allow_rebase" != "false" ]]; then
        patch=$(echo "$patch" | jq '. + {allow_rebase_merge: false}')
        add_change "merge.rebase-disabled" "updated" "Enabled" "Disabled"
      fi
      if [[ "$squash_title" != "PR_TITLE" ]]; then
        patch=$(echo "$patch" | jq '. + {squash_merge_commit_title: "PR_TITLE"}')
        add_change "merge.squash-pr-title" "updated" "$squash_title" "PR_TITLE"
      fi
      ;;
    any)
      ;;
  esac

  if [[ "$patch" != "{}" && "$DRY_RUN" == false ]]; then
    gh api "repos/$REPO" -X PATCH --input - <<< "$patch" > /dev/null 2>&1 || \
      add_error "merge.settings" "Failed to update merge settings"
  fi
}

# --- Check: GitHub Actions permissions ---

check_actions() {
  local actions_perms
  actions_perms=$(gh_api "repos/$REPO/actions/permissions")

  if [[ -z "$actions_perms" || "$actions_perms" == "null" ]]; then
    add_result "actions.permissions" "actions" "skip" "Could not fetch actions permissions" "Configured" "high"
    return
  fi

  local allowed_actions
  allowed_actions=$(echo "$actions_perms" | jq -r '.allowed_actions // "all"')
  if [[ "$allowed_actions" == "selected" ]]; then
    add_result "actions.restricted" "actions" "pass" "Actions restricted to selected" "Restricted to selected" "high"
  else
    add_result "actions.restricted" "actions" "fail" "Actions: $allowed_actions" "Restricted to selected" "high"
  fi

  if [[ "$allowed_actions" == "selected" ]]; then
    local selected
    selected=$(gh_api "repos/$REPO/actions/permissions/selected-actions")
    local github_owned verified
    github_owned=$(echo "$selected" | jq -r '.github_owned_allowed // false')
    verified=$(echo "$selected" | jq -r '.verified_allowed // false')

    if [[ "$github_owned" == "true" && "$verified" == "true" ]]; then
      add_result "actions.verified-only" "actions" "pass" "GitHub-owned and verified actions allowed" "Verified actions only" "high"
    else
      add_result "actions.verified-only" "actions" "fail" "github_owned=$github_owned, verified=$verified" "Verified actions only" "high"
    fi
  fi

  local workflow_perms
  workflow_perms=$(gh_api "repos/$REPO/actions/permissions/workflow")

  if [[ -n "$workflow_perms" && "$workflow_perms" != "null" ]]; then
    local default_perms can_approve
    default_perms=$(echo "$workflow_perms" | jq -r '.default_workflow_permissions // "write"')
    can_approve=$(echo "$workflow_perms" | jq -r '.can_approve_pull_request_reviews // true')

    if [[ "$default_perms" == "read" ]]; then
      add_result "actions.token-read-only" "actions" "pass" "Default token: read" "Read-only token" "high"
    else
      add_result "actions.token-read-only" "actions" "fail" "Default token: $default_perms" "Read-only token" "high"
    fi

    if [[ "$can_approve" == "false" ]]; then
      add_result "actions.no-pr-approval" "actions" "pass" "Actions cannot approve PRs" "No PR approval" "medium"
    else
      add_result "actions.no-pr-approval" "actions" "fail" "Actions can approve PRs" "No PR approval" "medium"
    fi
  fi
}

fix_actions() {
  local actions_perms
  actions_perms=$(gh_api "repos/$REPO/actions/permissions")

  if [[ -z "$actions_perms" || "$actions_perms" == "null" ]]; then
    add_error "actions.permissions" "Could not fetch actions permissions"
    return
  fi

  local allowed_actions
  allowed_actions=$(echo "$actions_perms" | jq -r '.allowed_actions // "all"')
  if [[ "$allowed_actions" != "selected" ]]; then
    add_change "actions.restricted" "updated" "$allowed_actions" "selected"
    if [[ "$DRY_RUN" == false ]]; then
      gh api "repos/$REPO/actions/permissions" \
        -X PUT \
        -f enabled=true \
        -f allowed_actions=selected > /dev/null 2>&1 || \
        add_error "actions.permissions" "Failed to restrict actions"
    fi
  fi

  # Set selected actions policy (need to do after enabling selected mode)
  local selected
  selected=$(gh_api "repos/$REPO/actions/permissions/selected-actions")
  if [[ -n "$selected" && "$selected" != "null" ]]; then
    local github_owned verified
    github_owned=$(echo "$selected" | jq -r '.github_owned_allowed // false')
    verified=$(echo "$selected" | jq -r '.verified_allowed // false')

    if [[ "$github_owned" != "true" || "$verified" != "true" ]]; then
      add_change "actions.verified-only" "updated" "github_owned=$github_owned, verified=$verified" "github_owned=true, verified=true"
      if [[ "$DRY_RUN" == false ]]; then
        gh api "repos/$REPO/actions/permissions/selected-actions" \
          -X PUT \
          --input - <<< '{"github_owned_allowed": true, "verified_allowed": true, "patterns_allowed": []}' \
          > /dev/null 2>&1 || \
          add_error "actions.selected-actions" "Failed to set selected actions policy"
      fi
    fi
  fi

  # Workflow token permissions
  local workflow_perms
  workflow_perms=$(gh_api "repos/$REPO/actions/permissions/workflow")

  if [[ -n "$workflow_perms" && "$workflow_perms" != "null" ]]; then
    local default_perms can_approve
    default_perms=$(echo "$workflow_perms" | jq -r '.default_workflow_permissions // "write"')
    can_approve=$(echo "$workflow_perms" | jq -r '.can_approve_pull_request_reviews // true')

    local needs_update=false
    if [[ "$default_perms" != "read" ]]; then
      add_change "actions.token-read-only" "updated" "$default_perms" "read"
      needs_update=true
    fi
    if [[ "$can_approve" != "false" ]]; then
      add_change "actions.no-pr-approval" "updated" "Allowed" "Blocked"
      needs_update=true
    fi

    if [[ "$needs_update" == true && "$DRY_RUN" == false ]]; then
      gh api "repos/$REPO/actions/permissions/workflow" \
        -X PUT \
        --input - <<< '{"default_workflow_permissions": "read", "can_approve_pull_request_reviews": false}' \
        > /dev/null 2>&1 || \
        add_error "actions.workflow-permissions" "Failed to update workflow permissions"
    fi
  fi
}

# --- Check: Access (report only) ---

check_access() {
  # CODEOWNERS
  local codeowners_status
  codeowners_status=$(gh_api_status "repos/$REPO/contents/.github/CODEOWNERS")
  if [[ "$codeowners_status" == "200" ]]; then
    add_result "access.codeowners" "access" "pass" "CODEOWNERS file exists" "CODEOWNERS present" "medium"
  else
    codeowners_status=$(gh_api_status "repos/$REPO/contents/CODEOWNERS")
    if [[ "$codeowners_status" == "200" ]]; then
      add_result "access.codeowners" "access" "pass" "CODEOWNERS file exists (repo root)" "CODEOWNERS present" "medium"
    else
      add_result "access.codeowners" "access" "warn" "No CODEOWNERS file found" "CODEOWNERS present" "medium"
    fi
  fi

  # Deploy keys
  local deploy_keys
  deploy_keys=$(gh_api "repos/$REPO/keys")
  local key_count=0
  if [[ -n "$deploy_keys" && "$deploy_keys" != "null" ]]; then
    key_count=$(echo "$deploy_keys" | jq 'length')
  fi
  if [[ "$key_count" -gt 0 ]]; then
    local key_summary
    key_summary=$(echo "$deploy_keys" | jq -r '[.[] | "\(.title) (read_only=\(.read_only))"] | join(", ")')
    add_result "access.deploy-keys" "access" "warn" "$key_count deploy key(s): $key_summary" "Review deploy keys" "medium"
  else
    add_result "access.deploy-keys" "access" "pass" "No deploy keys" "No unnecessary deploy keys" "medium"
  fi

  # Outside collaborators
  local collaborators
  collaborators=$(gh_api "repos/$REPO/collaborators?affiliation=outside")
  local collab_count=0
  if [[ -n "$collaborators" && "$collaborators" != "null" ]]; then
    collab_count=$(echo "$collaborators" | jq 'length')
  fi
  if [[ "$collab_count" -gt 0 ]]; then
    local collab_summary
    collab_summary=$(echo "$collaborators" | jq -r '[.[] | .login] | join(", ")')
    add_result "access.outside-collaborators" "access" "warn" "$collab_count outside collaborator(s): $collab_summary" "Review outside collaborators" "medium"
  else
    add_result "access.outside-collaborators" "access" "pass" "No outside collaborators" "No outside collaborators" "medium"
  fi
}

# --- Category dispatch ---

should_run_check() {
  local category="$1"
  [[ "$CHECKS" == "all" ]] || [[ ",$CHECKS," == *",$category,"* ]]
}

run_audit() {
  if should_run_check "repo"; then check_repo_settings; fi
  if should_run_check "security"; then check_security; fi
  if should_run_check "branches"; then check_branches; fi
  if should_run_check "merge"; then check_merge; fi
  if should_run_check "actions"; then check_actions; fi
  if should_run_check "access"; then check_access; fi
  print_audit_results
}

run_fix() {
  if should_run_check "repo"; then fix_repo_settings; fi
  if should_run_check "security"; then fix_security; fi
  if should_run_check "branches"; then fix_branches; fi
  if should_run_check "merge"; then fix_merge; fi
  if should_run_check "actions"; then fix_actions; fi
  print_fix_results
}

# --- CLI ---

show_help() {
  cat <<'HELP'
Usage: harden.sh <command> [options]

Audit and harden GitHub repository security settings.

Commands:
  audit     Read-only check of repository security settings
  fix       Apply recommended security settings

Options:
  --repo OWNER/REPO      Target repository (default: inferred by gh)
  --checks CATEGORIES    Comma-separated categories to check
                         (all,repo,branches,security,merge,actions,access)
  --merge-strategy STR   Merge strategy: rebase|squash|any (default: rebase)
  --min-reviewers N      Minimum required reviewers (default: 1)
  --branch BRANCH        Branch to protect (default: repo's default branch)
  --dry-run              Show what would change without applying (fix only)
  --format FORMAT        Output format: json|text (default: json)
  --help                 Show this help message
  --version              Show version

Examples:
  harden.sh audit --repo forjd/my-service
  harden.sh audit --repo forjd/my-service --checks branches,security
  harden.sh fix --repo forjd/my-service --dry-run
  harden.sh fix --repo forjd/my-service
  harden.sh fix --repo forjd/my-service --merge-strategy squash --min-reviewers 2

Exit codes:
  0    Success
  1    Error (invalid arguments, API failure)
HELP
}

parse_args() {
  if [[ $# -eq 0 ]]; then
    show_help
    exit 1
  fi

  COMMAND="$1"
  shift

  if [[ "$COMMAND" == "--help" || "$COMMAND" == "-h" ]]; then
    show_help
    exit 0
  fi

  if [[ "$COMMAND" == "--version" ]]; then
    echo "harden.sh $VERSION"
    exit 0
  fi

  if [[ "$COMMAND" != "audit" && "$COMMAND" != "fix" ]]; then
    echo "Error: Unknown command '$COMMAND'. Expected 'audit' or 'fix'." >&2
    echo "Run 'harden.sh --help' for usage." >&2
    exit 1
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        REPO="${2:?Error: --repo requires a value (OWNER/REPO)}"
        shift 2
        ;;
      --checks)
        CHECKS="${2:?Error: --checks requires a value}"
        shift 2
        ;;
      --merge-strategy)
        MERGE_STRATEGY="${2:?Error: --merge-strategy requires a value}"
        if [[ "$MERGE_STRATEGY" != "rebase" && "$MERGE_STRATEGY" != "squash" && "$MERGE_STRATEGY" != "any" ]]; then
          echo "Error: --merge-strategy must be one of: rebase, squash, any. Received: '$MERGE_STRATEGY'" >&2
          exit 1
        fi
        shift 2
        ;;
      --min-reviewers)
        MIN_REVIEWERS="${2:?Error: --min-reviewers requires a value}"
        if ! [[ "$MIN_REVIEWERS" =~ ^[0-9]+$ ]]; then
          echo "Error: --min-reviewers must be a positive integer. Received: '$MIN_REVIEWERS'" >&2
          exit 1
        fi
        shift 2
        ;;
      --branch)
        BRANCH="${2:?Error: --branch requires a value}"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --format)
        FORMAT="${2:?Error: --format requires a value}"
        if [[ "$FORMAT" != "json" && "$FORMAT" != "text" ]]; then
          echo "Error: --format must be one of: json, text. Received: '$FORMAT'" >&2
          exit 1
        fi
        shift 2
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
      --version)
        echo "harden.sh $VERSION"
        exit 0
        ;;
      *)
        echo "Error: Unknown option '$1'." >&2
        echo "Run 'harden.sh --help' for usage." >&2
        exit 1
        ;;
    esac
  done
}

# --- Prerequisites ---

check_prerequisites() {
  if ! command -v gh &> /dev/null; then
    echo "Error: 'gh' CLI is not installed. Install it from https://cli.github.com/" >&2
    exit 1
  fi

  if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' is not installed. Install it from https://jqlang.github.io/jq/" >&2
    exit 1
  fi

  if ! gh auth status &> /dev/null; then
    echo "Error: 'gh' is not authenticated. Run 'gh auth login' first." >&2
    exit 1
  fi

  # Infer repo if not specified
  if [[ -z "$REPO" ]]; then
    REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || true)
    if [[ -z "$REPO" ]]; then
      echo "Error: Could not infer repository. Use --repo OWNER/REPO or run from within a repo." >&2
      exit 1
    fi
  fi

  # Check admin access
  local permission
  permission=$(gh api "repos/$REPO" --jq '.permissions.admin // false' 2>/dev/null || echo "false")
  if [[ "$permission" != "true" ]]; then
    echo "Error: You do not have admin access to '$REPO'. Admin access is required to change repository settings." >&2
    exit 1
  fi
}

# --- Main ---

main() {
  parse_args "$@"
  check_prerequisites

  case "$COMMAND" in
    audit) run_audit ;;
    fix)   run_fix ;;
  esac
}

main "$@"
