#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HARDEN_SCRIPT="$ROOT_DIR/skills/repo-hardening/scripts/harden.sh"
TMP_DIR=$(mktemp -d)

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TMP_DIR/bin"

cat > "$TMP_DIR/bin/gh" <<'MOCK_GH'
#!/usr/bin/env bash
set -euo pipefail

log_file=${GH_LOG:?}
payload_file=${GH_PAYLOAD:?}
scenario=${TEST_SCENARIO:?}

printf '%s\n' "$*" >> "$log_file"

has_arg() {
  local needle="$1"
  shift
  local arg
  for arg in "$@"; do
    [[ "$arg" == "$needle" ]] && return 0
  done
  return 1
}

jq_expr() {
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--jq" ]]; then
      printf '%s\n' "$2"
      return 0
    fi
    shift
  done
  return 1
}

if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
  exit 0
fi

if [[ "${1:-}" != "api" ]]; then
  echo "unexpected gh command: $*" >&2
  exit 1
fi

shift
endpoint="$1"
shift
expr=$(jq_expr "$@" || true)

if [[ "$endpoint" == "repos/org/repo" && "$expr" == ".permissions.admin // false" ]]; then
  [[ "$scenario" == "audit-no-admin" ]] && printf 'admin-check\n' >> "$log_file"
  [[ "$scenario" == "audit-no-admin" ]] && echo "false" || echo "true"
  exit 0
fi

if [[ "$endpoint" == "repos/org/repo" && "$expr" == ".default_branch" ]]; then
  echo "main"
  exit 0
fi

if [[ "$endpoint" == "repos/org/repo" ]]; then
  cat <<'JSON'
{
  "delete_branch_on_merge": true,
  "allow_update_branch": true,
  "has_wiki": false,
  "has_projects": false,
  "allow_squash_merge": false,
  "allow_merge_commit": false,
  "allow_rebase_merge": true
}
JSON
  exit 0
fi

if [[ "$endpoint" == "repos/org/repo/branches/main/protection" && "$scenario" == "fetch-error" && "$(has_arg "-i" "$@" && echo yes || echo no)" == "yes" ]]; then
  echo "HTTP/2.0 403 Forbidden"
  exit 1
fi

if [[ "$endpoint" == "repos/org/repo/branches/main/protection" && "$scenario" == "no-checks" && "$(has_arg "-i" "$@" && echo yes || echo no)" == "yes" ]]; then
  echo "HTTP/2.0 404 Not Found"
  exit 1
fi

if [[ "$endpoint" == "repos/org/repo/branches/main/protection" && "$(has_arg "-i" "$@" && echo yes || echo no)" == "yes" ]]; then
  echo "HTTP/2.0 200 OK"
  exit 0
fi

if [[ "$endpoint" == "repos/org/repo/branches/main/protection" && "$(has_arg "-X" "$@" && echo yes || echo no)" == "yes" ]]; then
  cat > "$payload_file"
  exit 0
fi

if [[ "$endpoint" == "repos/org/repo/branches/main/protection" ]]; then
  cat <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["build"],
    "checks": [{"context": "security", "app_id": 123}]
  },
  "enforce_admins": {"enabled": true},
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "require_last_push_approval": false
  },
  "allow_force_pushes": {"enabled": false},
  "allow_deletions": {"enabled": false},
  "required_linear_history": {"enabled": true},
  "required_conversation_resolution": {"enabled": true},
  "block_creations": {"enabled": false},
  "lock_branch": {"enabled": false},
  "allow_fork_syncing": {"enabled": false},
  "restrictions": null
}
JSON
  exit 0
fi

echo "unexpected gh api endpoint: $endpoint $*" >&2
exit 1
MOCK_GH

chmod +x "$TMP_DIR/bin/gh"

run_harden() {
  local scenario="$1"
  shift
  : > "$TMP_DIR/gh.log"
  : > "$TMP_DIR/payload.json"
  TEST_SCENARIO="$scenario" \
    GH_LOG="$TMP_DIR/gh.log" \
    GH_PAYLOAD="$TMP_DIR/payload.json" \
    PATH="$TMP_DIR/bin:$PATH" \
    "$HARDEN_SCRIPT" "$@" > "$TMP_DIR/stdout" 2> "$TMP_DIR/stderr"
}

assert_no_branch_put() {
  if grep -q -- '-X PUT' "$TMP_DIR/gh.log"; then
    echo "expected no branch protection PUT, got:" >&2
    cat "$TMP_DIR/gh.log" >&2
    exit 1
  fi
}

test_no_required_checks_aborts_before_put() {
  if run_harden no-checks fix --repo org/repo --checks branches; then
    echo "expected fix without required checks to fail" >&2
    exit 1
  fi
  assert_no_branch_put
  jq -e '.errors[] | select(.id == "branches.status-checks")' "$TMP_DIR/stdout" >/dev/null
}

test_branch_fetch_error_aborts_before_put() {
  if run_harden fetch-error fix --repo org/repo --checks branches --required-check test; then
    echo "expected branch protection fetch error to fail" >&2
    exit 1
  fi
  assert_no_branch_put
  jq -e '.errors[] | select(.id == "branches.protection")' "$TMP_DIR/stdout" >/dev/null
}

test_required_check_preserves_existing_checks() {
  run_harden preserve fix --repo org/repo --checks branches --required-check test
  jq -e '.required_status_checks.contexts == ["build", "test"]' "$TMP_DIR/payload.json" >/dev/null
  jq -e '.required_status_checks.checks == [{"context": "security", "app_id": 123}]' "$TMP_DIR/payload.json" >/dev/null
}

test_audit_does_not_require_admin() {
  run_harden audit-no-admin audit --repo org/repo --checks repo
  jq -e '.summary.pass >= 1' "$TMP_DIR/stdout" >/dev/null
  if grep -q '^admin-check$' "$TMP_DIR/gh.log"; then
    echo "audit unexpectedly checked admin permission" >&2
    exit 1
  fi
}

test_min_reviewers_upper_bound() {
  if run_harden preserve fix --repo org/repo --checks branches --min-reviewers 7; then
    echo "expected --min-reviewers 7 to fail validation" >&2
    exit 1
  fi
  grep -q -- '--min-reviewers must be an integer from 1 to 6' "$TMP_DIR/stderr"
}

test_fix_requires_explicit_checks() {
  if run_harden preserve fix --repo org/repo --dry-run; then
    echo "expected fix without --checks to fail validation" >&2
    exit 1
  fi
  grep -q -- 'fix requires an explicit --checks value' "$TMP_DIR/stderr"
}

test_no_required_checks_aborts_before_put
test_branch_fetch_error_aborts_before_put
test_required_check_preserves_existing_checks
test_audit_does_not_require_admin
test_min_reviewers_upper_bound
test_fix_requires_explicit_checks

echo "harden tests passed"
