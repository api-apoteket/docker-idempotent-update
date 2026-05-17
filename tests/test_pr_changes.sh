#!/usr/bin/env bash
# Tests for PR-changed configuration and documentation files.
# Validates YAML syntax, JSON structure, GitHub workflow fields, and Markdown content.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

assert_contains() {
    local file="$1" pattern="$2" label="$3"
    if grep -qF -- "$pattern" "$file"; then
        pass "$label"
    else
        fail "$label (pattern not found: $pattern)"
    fi
}

assert_not_contains() {
    local file="$1" pattern="$2" label="$3"
    if ! grep -qF -- "$pattern" "$file"; then
        pass "$label"
    else
        fail "$label (unexpected pattern found: $pattern)"
    fi
}

assert_json_eq() {
    local file="$1" jq_expr="$2" expected="$3" label="$4"
    actual="$(jq -r "$jq_expr" "$file" 2>/dev/null)"
    if [ "$actual" = "$expected" ]; then
        pass "$label"
    else
        fail "$label (expected '$expected', got '$actual')"
    fi
}

assert_yaml_field() {
    local file="$1" py_expr="$2" expected="$3" label="$4"
    actual="$(python3 -c "
import yaml, sys
data = yaml.safe_load(open('$file'))
result = $py_expr
print(str(result))
" 2>/dev/null)"
    if [ "$actual" = "$expected" ]; then
        pass "$label"
    else
        fail "$label (expected '$expected', got '$actual')"
    fi
}

# ---------------------------------------------------------------------------
echo "=== YAML syntax validation ==="

for f in \
    ".github/ISSUE_TEMPLATE/bug_report.yml" \
    ".github/ISSUE_TEMPLATE/config.yml" \
    ".github/ISSUE_TEMPLATE/feature_request.yml" \
    ".github/workflows/ci.yml"
do
    full="$REPO_ROOT/$f"
    if python3 -c "import yaml; yaml.safe_load(open('$full'))" 2>/dev/null; then
        pass "$f is valid YAML"
    else
        fail "$f is valid YAML"
    fi
done

# ---------------------------------------------------------------------------
echo "=== bug_report.yml: GitHub issue form structure ==="

BUG="$REPO_ROOT/.github/ISSUE_TEMPLATE/bug_report.yml"

assert_yaml_field "$BUG" "data['name']" "Bug report" "bug_report: name is 'Bug report'"
assert_yaml_field "$BUG" "data['title']" "bug: " "bug_report: title prefix is 'bug: '"
assert_yaml_field "$BUG" "data['labels'][0]" "bug" "bug_report: first label is 'bug'"

# body field IDs present
assert_yaml_field "$BUG" "str([f['id'] for f in data['body'] if f.get('type')=='textarea'])" \
    "['description', 'steps', 'expected', 'environment']" \
    "bug_report: textarea field IDs are description, steps, expected, environment"

# required fields
assert_yaml_field "$BUG" \
    "str([f['id'] for f in data['body'] if f.get('validations', {}).get('required')])" \
    "['description', 'steps', 'expected']" \
    "bug_report: required fields are description, steps, expected"

# environment is NOT required (optional)
assert_yaml_field "$BUG" \
    "str(any(f.get('validations', {}).get('required') for f in data['body'] if f.get('id')=='environment'))" \
    "False" \
    "bug_report: environment field is optional (not required)"

# steps placeholder contains numbered list starters
assert_contains "$BUG" "1." "bug_report: steps placeholder starts numbered list"

# ---------------------------------------------------------------------------
echo "=== config.yml: issue template config ==="

CONFIG="$REPO_ROOT/.github/ISSUE_TEMPLATE/config.yml"

assert_yaml_field "$CONFIG" "data['blank_issues_enabled']" "False" \
    "config: blank_issues_enabled is false"
assert_yaml_field "$CONFIG" "str(data['contact_links'])" "[]" \
    "config: contact_links is empty list"

# ---------------------------------------------------------------------------
echo "=== feature_request.yml: GitHub issue form structure ==="

FEAT="$REPO_ROOT/.github/ISSUE_TEMPLATE/feature_request.yml"

assert_yaml_field "$FEAT" "data['name']" "Feature request" "feature_request: name is 'Feature request'"
assert_yaml_field "$FEAT" "data['title']" "feat: " "feature_request: title prefix is 'feat: '"
assert_yaml_field "$FEAT" "data['labels'][0]" "enhancement" "feature_request: first label is 'enhancement'"

# required fields: problem and proposal
assert_yaml_field "$FEAT" \
    "str([f['id'] for f in data['body'] if f.get('validations', {}).get('required')])" \
    "['problem', 'proposal']" \
    "feature_request: required fields are problem and proposal"

# alternatives field exists but is NOT required
assert_yaml_field "$FEAT" \
    "str(any(f.get('id')=='alternatives' for f in data['body']))" \
    "True" \
    "feature_request: alternatives field exists"
assert_yaml_field "$FEAT" \
    "str(any(f.get('validations', {}).get('required') for f in data['body'] if f.get('id')=='alternatives'))" \
    "False" \
    "feature_request: alternatives field is optional"

# ---------------------------------------------------------------------------
echo "=== pull_request_template.md: required sections and checklist ==="

PRTEMPLATE="$REPO_ROOT/.github/pull_request_template.md"

assert_contains "$PRTEMPLATE" "## Summary" "pr_template: has Summary section"
assert_contains "$PRTEMPLATE" "## Testing" "pr_template: has Testing section"
assert_contains "$PRTEMPLATE" "## Checklist" "pr_template: has Checklist section"
assert_contains "$PRTEMPLATE" "Tests pass locally" "pr_template: has 'Tests pass locally' checklist item"
assert_contains "$PRTEMPLATE" "PR is focused and isolated" "pr_template: has 'PR is focused and isolated' checklist item"
assert_contains "$PRTEMPLATE" "No unrelated changes are included" "pr_template: has 'No unrelated changes' checklist item"
assert_contains "$PRTEMPLATE" "No credentials or secrets are committed" "pr_template: has 'No credentials or secrets' checklist item"

# Checklist items use GitHub markdown task list syntax
assert_contains "$PRTEMPLATE" "- [ ]" "pr_template: uses unchecked task list syntax"

# Summary section has a placeholder bullet
assert_contains "$PRTEMPLATE" "-" "pr_template: Summary section has content placeholder"

# ---------------------------------------------------------------------------
echo "=== renovate.json: JSON validity and automerge settings ==="

RENOVATE="$REPO_ROOT/.github/renovate.json"

if jq empty "$RENOVATE" 2>/dev/null; then
    pass "renovate.json is valid JSON"
else
    fail "renovate.json is valid JSON"
fi

assert_json_eq "$RENOVATE" '."$schema"' \
    "https://docs.renovatebot.com/renovate-schema.json" \
    "renovate.json: schema URL is correct"

# Patch-only automerge rule (key PR change: minor was removed)
assert_json_eq "$RENOVATE" \
    '[.packageRules[] | select(.matchUpdateTypes != null)] | length' \
    "1" \
    "renovate.json: exactly one rule uses matchUpdateTypes"

assert_json_eq "$RENOVATE" \
    '[.packageRules[] | select(.matchUpdateTypes != null)] | .[0].matchUpdateTypes | length' \
    "1" \
    "renovate.json: matchUpdateTypes rule has exactly one entry (patch only, not minor+patch)"

assert_json_eq "$RENOVATE" \
    '[.packageRules[] | select(.matchUpdateTypes != null)] | .[0].matchUpdateTypes[0]' \
    "patch" \
    "renovate.json: the sole matchUpdateTypes entry is 'patch'"

# Confirm 'minor' is NOT listed in matchUpdateTypes (regression check for PR change)
actual_types="$(jq -r '[.packageRules[] | select(.matchUpdateTypes != null)] | .[0].matchUpdateTypes | @csv' "$RENOVATE")"
if ! echo "$actual_types" | grep -q "minor"; then
    pass "renovate.json: 'minor' is NOT in matchUpdateTypes (patch-only automerge)"
else
    fail "renovate.json: 'minor' should NOT be in matchUpdateTypes (patch-only automerge)"
fi

# automerge: true for the patch rule (PR change: was false)
assert_json_eq "$RENOVATE" \
    '[.packageRules[] | select(.matchUpdateTypes != null)] | .[0].automerge' \
    "true" \
    "renovate.json: patch rule has automerge: true"

# devDependencies rule has automerge: true (PR change: newly added)
assert_json_eq "$RENOVATE" \
    '[.packageRules[] | select(.matchDepTypes != null and (.matchDepTypes | contains(["devDependencies"])))] | .[0].automerge' \
    "true" \
    "renovate.json: devDependencies rule has automerge: true"

assert_json_eq "$RENOVATE" \
    '[.packageRules[] | select(.matchDepTypes != null and (.matchDepTypes | contains(["devDependencies"])))] | .[0].groupName' \
    "dev-dependencies" \
    "renovate.json: devDependencies rule groupName is 'dev-dependencies'"

# github-actions rule exists and does NOT have automerge set (PR did not change it)
assert_json_eq "$RENOVATE" \
    '[.packageRules[] | select(.matchManagers != null and (.matchManagers | contains(["github-actions"])))] | .[0].groupName' \
    "github-actions" \
    "renovate.json: github-actions rule groupName is 'github-actions'"

assert_json_eq "$RENOVATE" \
    '[.packageRules[] | select(.matchManagers != null and (.matchManagers | contains(["github-actions"])))] | .[0].automerge // "null"' \
    "null" \
    "renovate.json: github-actions rule has no explicit automerge"

# vulnerability alerts enabled with 'security' label
assert_json_eq "$RENOVATE" '.vulnerabilityAlerts.enabled' "true" \
    "renovate.json: vulnerabilityAlerts enabled"
assert_json_eq "$RENOVATE" '.vulnerabilityAlerts.labels[0]' "security" \
    "renovate.json: vulnerabilityAlerts label is 'security'"

# PR limits
assert_json_eq "$RENOVATE" '.prHourlyLimit' "2" "renovate.json: prHourlyLimit is 2"
assert_json_eq "$RENOVATE" '.prConcurrentLimit' "10" "renovate.json: prConcurrentLimit is 10"

# timezone
assert_json_eq "$RENOVATE" '.timezone' "Europe/Stockholm" \
    "renovate.json: timezone is Europe/Stockholm"

# ---------------------------------------------------------------------------
echo "=== ci.yml: GitHub Actions workflow structure ==="

CI="$REPO_ROOT/.github/workflows/ci.yml"

assert_yaml_field "$CI" "data['name']" "CI" "ci.yml: workflow name is 'CI'"

# NOTE: PyYAML parses bare 'on' as boolean True, so we key on data[True].
# Triggered on pull_request
assert_yaml_field "$CI" "str('pull_request' in data[True])" "True" \
    "ci.yml: triggered on pull_request"

# Triggered on push to main
assert_yaml_field "$CI" "str(data[True]['push']['branches'])" "['main']" \
    "ci.yml: push trigger limited to main branch"

# Concurrency: cancel-in-progress
assert_yaml_field "$CI" "str(data['concurrency']['cancel-in-progress'])" "True" \
    "ci.yml: concurrency cancel-in-progress is true"

# Concurrency group references workflow and ref
assert_contains "$CI" "github.workflow" "ci.yml: concurrency group uses github.workflow"
assert_contains "$CI" "github.ref" "ci.yml: concurrency group uses github.ref"

# Permissions: contents: read (least-privilege)
assert_yaml_field "$CI" "data['permissions']['contents']" "read" \
    "ci.yml: permissions.contents is 'read'"

# jobs: docker job exists
assert_yaml_field "$CI" "str('docker' in data['jobs'])" "True" \
    "ci.yml: 'docker' job is defined"

assert_yaml_field "$CI" "data['jobs']['docker']['runs-on']" "ubuntu-latest" \
    "ci.yml: docker job runs on ubuntu-latest"

# Steps: checkout action and docker build
assert_yaml_field "$CI" \
    "str(any('actions/checkout' in str(s.get('uses','')) for s in data['jobs']['docker']['steps']))" \
    "True" \
    "ci.yml: docker job uses actions/checkout"

assert_yaml_field "$CI" \
    "str(any('docker build' in str(s.get('run','')) for s in data['jobs']['docker']['steps']))" \
    "True" \
    "ci.yml: docker job runs docker build"

# Exactly 2 steps: checkout + docker build
assert_yaml_field "$CI" "str(len(data['jobs']['docker']['steps']))" "2" \
    "ci.yml: docker job has exactly 2 steps"

# ---------------------------------------------------------------------------
echo "=== AGENTS.md: required sections and rules ==="

AGENTS="$REPO_ROOT/AGENTS.md"

assert_contains "$AGENTS" "## Allowed" "AGENTS.md: has 'Allowed' section"
assert_contains "$AGENTS" "## Forbidden" "AGENTS.md: has 'Forbidden' section"
assert_contains "$AGENTS" "## Requirements" "AGENTS.md: has 'Requirements' section"

# Allowed actions
assert_contains "$AGENTS" "Create branches" "AGENTS.md: 'Create branches' is allowed"
assert_contains "$AGENTS" "Modify code" "AGENTS.md: 'Modify code' is allowed"
assert_contains "$AGENTS" "Run tests" "AGENTS.md: 'Run tests' is allowed"
assert_contains "$AGENTS" "Open PRs" "AGENTS.md: 'Open PRs' is allowed"

# Forbidden actions — most important safety rules
assert_contains "$AGENTS" "Push directly to main/master" "AGENTS.md: forbids pushing to main/master"
assert_contains "$AGENTS" "Merge PRs" "AGENTS.md: forbids merging PRs"
assert_contains "$AGENTS" "Delete branches" "AGENTS.md: forbids deleting branches"
assert_contains "$AGENTS" "Disable workflows" "AGENTS.md: forbids disabling workflows"
assert_contains "$AGENTS" "Modify secrets" "AGENTS.md: forbids modifying secrets"
assert_contains "$AGENTS" "Change GitHub org settings" "AGENTS.md: forbids changing GitHub org settings"

# Requirements
assert_contains "$AGENTS" "All tests must pass" "AGENTS.md: requires all tests pass"
assert_contains "$AGENTS" "Never commit credentials" "AGENTS.md: requires never commit credentials"
assert_contains "$AGENTS" "Never force push" "AGENTS.md: requires never force push"
assert_contains "$AGENTS" "Keep PRs focused" "AGENTS.md: requires PRs be focused"
assert_contains "$AGENTS" "Never include unrelated changes" "AGENTS.md: requires no unrelated changes"

# Regression: old verbose content (branch prefixes, ownership map) is NOT present
assert_not_contains "$AGENTS" "claude/" "AGENTS.md: no agent-specific branch prefix table"
assert_not_contains "$AGENTS" "Ownership Map" "AGENTS.md: no ownership map section"

# ---------------------------------------------------------------------------
echo "=== CLAUDE.md: required sections and conventions ==="

CLAUDEMD="$REPO_ROOT/CLAUDE.md"

assert_contains "$CLAUDEMD" "## Tech Stack" "CLAUDE.md: has 'Tech Stack' section"
assert_contains "$CLAUDEMD" "## File Overview" "CLAUDE.md: has 'File Overview' section"
assert_contains "$CLAUDEMD" "## Conventions" "CLAUDE.md: has 'Conventions' section"

# Tech stack entries
assert_contains "$CLAUDEMD" "POSIX shell" "CLAUDE.md: mentions POSIX shell"
assert_contains "$CLAUDEMD" "Docker" "CLAUDE.md: mentions Docker"
assert_contains "$CLAUDEMD" "rclone" "CLAUDE.md: mentions rclone"
assert_contains "$CLAUDEMD" "msmtp" "CLAUDE.md: mentions msmtp"

# File overview lists key scripts
assert_contains "$CLAUDEMD" "entrypoint.sh" "CLAUDE.md: lists entrypoint.sh"
assert_contains "$CLAUDEMD" "run.sh" "CLAUDE.md: lists run.sh"
assert_contains "$CLAUDEMD" "rclone_backup.sh" "CLAUDE.md: lists rclone_backup.sh"
assert_contains "$CLAUDEMD" "send_report.sh" "CLAUDE.md: lists send_report.sh"

# Convention: set -euo pipefail required
assert_contains "$CLAUDEMD" "set -euo pipefail" "CLAUDE.md: mandates set -euo pipefail"

# Convention: no hardcoded secrets
assert_contains "$CLAUDEMD" "never hardcoded" "CLAUDE.md: secrets must not be hardcoded"

# Convention: test with docker compose run --rm
assert_contains "$CLAUDEMD" "docker compose run --rm" "CLAUDE.md: test command is docker compose run --rm"

# ---------------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
