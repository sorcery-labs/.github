#!/usr/bin/env bash
#
# Creates the "Org Work" GitHub Project (Option 1 — single source of truth)
# and its fields. Workstream/Priority as single-selects, Status re-optioned to
# Backlog/In Progress/In Review/Done, plus optional Roadmap date fields.
#
# NO Component field — we use the native Repository facet instead (automatic,
# never required, nothing to configure).
#
# Prereqs:
#   - gh CLI authed with the `project` scope:
#       gh auth refresh -s project --hostname github.com
#   - jq installed
#
set -euo pipefail

ORG="sorcery-labs"     # the organisation that owns the project
TITLE="Org Work"

# ---------------------------------------------------------------------------
# 1) Create the org-owned project, capture its number + GraphQL node id.
# ---------------------------------------------------------------------------
PROJECT_NUMBER=$(gh project create --owner "$ORG" --title "$TITLE" --format json | jq -r '.number')
PROJECT_ID=$(gh project view "$PROJECT_NUMBER" --owner "$ORG" --format json | jq -r '.id')
echo "Created project #$PROJECT_NUMBER  (node id: $PROJECT_ID)"

# ---------------------------------------------------------------------------
# 2) Custom single-select fields.
# ---------------------------------------------------------------------------
# Platform = the consolidated old Infrastructure + Monitoring workstreams.
# The iac/monitoring split now lives in area:* labels, not the Workstream field,
# so it's filtered (label:area:monitoring), not grouped — no Area field needed.
gh project field-create "$PROJECT_NUMBER" --owner "$ORG" \
  --name "Workstream" --data-type SINGLE_SELECT \
  --single-select-options "Super-duper,Trading,Platform,Sorcery,Tiny-markets"

gh project field-create "$PROJECT_NUMBER" --owner "$ORG" \
  --name "Priority" --data-type SINGLE_SELECT \
  --single-select-options "Critical,High,Medium,Low"

# Optional — power the Roadmap view (skip if you'd rather drive it off Milestone).
gh project field-create "$PROJECT_NUMBER" --owner "$ORG" --name "Start"       --data-type DATE
gh project field-create "$PROJECT_NUMBER" --owner "$ORG" --name "Target date" --data-type DATE

# ---------------------------------------------------------------------------
# 3) Re-option the built-in Status field to our four values.
#    A new project ships with Status = Todo/In Progress/Done; we replace the
#    option set. Matching names (In Progress, Done) are preserved; Todo is
#    dropped; Backlog + In Review are added.
# ---------------------------------------------------------------------------
STATUS_FIELD_ID=$(gh project field-list "$PROJECT_NUMBER" --owner "$ORG" --format json \
  | jq -r '.fields[] | select(.name=="Status") | .id')

gh api graphql -f query='
mutation($field: ID!) {
  updateProjectV2Field(input: {
    fieldId: $field,
    singleSelectOptions: [
      {name: "Backlog",     color: GRAY,   description: ""},
      {name: "In Progress", color: YELLOW, description: ""},
      {name: "In Review",   color: BLUE,   description: ""},
      {name: "Done",        color: GREEN,  description: ""}
    ]
  }) {
    projectV2Field {
      ... on ProjectV2SingleSelectField { id name options { name } }
    }
  }
}' -f field="$STATUS_FIELD_ID"
# If your server rejects singleSelectOptions on updateProjectV2Field (older GHES),
# edit the Status options once in the UI instead — everything else still applies.

# ---------------------------------------------------------------------------
# 4) Backfill: add every OPEN issue from each feeding repo to the project.
#    (Auto-add workflows — step 5 — only catch NEW items, so seed existing ones.)
# ---------------------------------------------------------------------------
# Backfill is intentionally scoped to this explicit repo set (distinct from the
# all-org label sync) — only these repos' existing OPEN issues seed the board.
for repo in grease iac rolodex turnkey merlin markoor ManagedVault ManagedVaultFrontend; do
  gh issue list --repo "$ORG/$repo" --state open --limit 1000 --json url -q '.[].url' \
  | while read -r url; do
      gh project item-add "$PROJECT_NUMBER" --owner "$ORG" --url "$url"
    done
done

# ---------------------------------------------------------------------------
# 5) Verify.
# ---------------------------------------------------------------------------
echo "Fields:"
gh project field-list "$PROJECT_NUMBER" --owner "$ORG" --format json \
  | jq -r '.fields[] | "  - \(.name) (\(.type))"'
echo "Open it: $(gh project view "$PROJECT_NUMBER" --owner "$ORG" --format json | jq -r '.url')"
