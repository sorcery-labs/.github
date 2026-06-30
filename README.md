# sorcery-labs — Engineering Workflow

This repository (`.github`) is the home of our org-wide engineering conventions: the shared **issue templates**, the canonical **label set**, and the **automation** that keeps work flowing onto the [**OrgWide Work** project board](https://github.com/orgs/sorcery-labs/projects/10). Files here are inherited by every repo in the organisation, so this is the single source of truth for how we track work.

> **TL;DR for engineers:** file work from the issue template for your workstream — it auto-applies the right `workstream:*` label. Within ~5 minutes the issue appears on the OrgWide Work board with its **Workstream** set. That's the whole flow.

---

## How it's wired (read this first)

Two GitHub Actions and two scripts hold the whole system together. The Actions run continuously; the scripts are run by hand when the *shape* of things changes.

### The two sync Actions (`.github/workflows/`)

Both authenticate with **one shared fine-grained PAT**, stored as the **`LABEL_SYNC_TOKEN`** repo secret (Repository → Issues: Read/Write, Organization → Projects: Read/Write, all repos).

**1. `sync-labels.yml` — label propagation.**
- *Triggers:* push to `master` touching `.github/labels.yml`, plus manual dispatch. **Not** per-issue.
- *Does:* reads `.github/labels.yml` and creates/updates that label set in **every active org repo** (`gh label create --force` — additive, never deletes other labels).
- *Why it exists:* GitHub has no org-wide labels. A template can only apply a label that already exists in the target repo, so this guarantees every repo has the full set — otherwise templates would silently drop their labels.

**2. `sync-workstream-field.yml` — board membership + the Workstream field.**
- *Triggers:* every 5 minutes (cron) + manual dispatch. **Not** per-issue.
- *Does:* for every **open** issue org-wide carrying a `workstream:*` label, adds it to the OrgWide Work board and sets its **Workstream** field from the label. Membership rule = "has a workstream label." It is **set-only** (never clears a field, so drafts and manual values are safe) and uses `is:open` (so closed/archived items aren't disturbed).
- *Latency:* up to ~5 minutes. This is the bridge between the **label** you set and the project **field** the board groups by.

> **Field vs. label — the one thing to understand.** The `workstream:*` **label** lives on the issue and is the source of truth. The **Workstream field** is a project-only mirror that the reconcile keeps in sync (a board can only group/slice by a *field*, not a label). **Set the label; let the field follow.** If you set the field by hand on a *labelled* issue, the reconcile will revert it to match the label within 5 minutes. On *drafts/unlabelled* items the reconcile leaves the field alone, so manual values there stick.

### The two setup scripts (`scripts/`)

Run locally with the `gh` CLI — these are not CI.

**`generate-issue-templates.mjs`** — the generator. Produces the per-workstream issue templates, `config.yml`, **and** `labels.yml` from a single list (`WORKSTREAMS` + `LABELS`) inside the script, so templates and labels can never drift. A drift guard fails if a template references a label not in the registry. Run it whenever the workstream or label set changes, then commit the output:
```bash
node scripts/generate-issue-templates.mjs
```
Generated files carry a "do not hand-edit" header — **edit the generator, not the output.**

**`setup-org-work-project.sh`** — the one-time bootstrap that created the OrgWide Work project (#10): its fields (Workstream, Priority, Start, Target date), the re-optioned Status field, and the initial backfill of existing issues. Kept for reference / disaster recovery. Needs the `project` scope (`gh auth refresh -s project --hostname github.com`).

---

## Repository contents

| Path | What it is |
|---|---|
| `.github/ISSUE_TEMPLATE/` | Per-workstream issue templates + `config.yml` (blank issues disabled) — inherited org-wide |
| `.github/labels.yml` | Canonical label manifest (source of truth, applied by `sync-labels.yml`) |
| `.github/workflows/` | The two sync Actions above |
| `scripts/` | The generator and the project bootstrap script |

---

## The operating model

### Workstreams

Every issue carries exactly **one** `workstream:*` label identifying its board lane:

| Workstream | Label | Scope |
|---|---|---|
| Super-duper | `workstream:super-duper` | Super-duper client work |
| Trading | `workstream:trading` | Trading ops and dev |
| Platform | `workstream:platform` | Infrastructure, iac, monitoring, alerting, app health |
| Sorcery | `workstream:sorcery` | Cross-cutting / org-wide; the catch-all and home for drafts/ideas |
| Tiny-markets | `workstream:tiny-markets` | Tiny-markets work |

**Platform** absorbed the former Infrastructure and Monitoring workstreams. Within Platform, work is optionally sub-tagged **`area:iac`** or **`area:monitoring`** to keep the infra-vs-monitoring split (this replaces the old two-board setup).

### Labels

Defined in `labels.yml`, synced everywhere by `sync-labels.yml`: the five `workstream:*`, plus `area:iac`, `area:monitoring`, and `blocked`. **Priority** and **Status** are *project fields*, not labels. "Which repo" comes free from the native **Repository** facet (we don't use a `component:*` label).

### Issue templates

Live in `.github/ISSUE_TEMPLATE/`, one per workstream, each with a hard-coded `labels:` value so the right `workstream:*` (and `area:*`, for Platform) label is applied at creation. `config.yml` sets `blank_issues_enabled: false`, so every UI-created issue must use a template — which guarantees a workstream label. The "Create new issue" button on the board also offers these templates, so filing from the board is fine.

### The OrgWide Work board (#10)

One project holds all work. Fields:
- **Status** — Backlog · In Progress · In Review · Done
- **Workstream** — the five above (set by the reconcile from the label)
- **Priority** — Critical · High · Medium · Low
- **Start** / **Target date** — power the Roadmap view

Membership = issues that have a workstream label (added by the reconcile). Status transitions are handled by the project's built-in workflows (item added → Backlog; issue closed / PR-that-closes-it merged → Done; reopened → In Progress).

### Key views

- **All Work — Master** (Table, grouped by Workstream, filter `-status:Done`) — the master list, including unstatus'd items.
- **Kanban** (Board, columns = Status, sliced by Workstream) — leadership drill-down.
- **Roadmap** (grouped by Workstream; needs Start/Target dates).
- **Per-workstream boards** — filter `workstream:"<name>"`; Platform has **IAC** / **Monitoring** sub-views via `label:"area:iac"` / `label:"area:monitoring"`.
- **No Workstream** (safety net) — filter by *negated labels* (`-label:"workstream:super-duper" …`) so it reacts the instant you label something. (The field-based `no:workstream` lags the 5-min reconcile.)
- **Critical / High**, **Blocked** (`label:blocked`), **Full Backlog**, **Done**, and **Super-duper — Done This Week** for client reporting.

### Weekly triage (~10–15 min)

1. **No Workstream safety net — org-wide search** (the true net, since unlabelled issues never reach the board):
   ```
   org:sorcery-labs is:issue is:open -label:workstream:super-duper -label:workstream:trading -label:workstream:platform -label:workstream:sorcery -label:workstream:tiny-markets
   ```
   Label each result (add `area:*` for Platform) and set Priority; if unclear, use `workstream:sorcery`.
2. **Sweep the backlog** for items >2 weeks stale — reprioritise, defer, or close.
3. **Promote drafts** that are now scoped into real issues.
4. **Check In Progress** — anything idle 5+ days gets a nudge or the `blocked` label.
5. **Verify milestones** on In-Progress items.
6. **Platform + Sorcery pass** — milestone slippage; confirm `area:iac` vs `area:monitoring` split is clean.

> When you add a workstream, the negated-label search and the No-Workstream view both need a new `-label:` term, or the net leaks.

### Milestones

Repo-level only — GitHub has no org/project-level milestone. A milestone that spans repos must be created in **each** repo with the **same name**, so the board's Milestone filter groups them. Suggested naming: Super-duper → contract/billing periods; Trading → time-based; Platform → change-based (e.g. "VPC Migration"); Tiny-markets → version/time; Sorcery → by quarter.

### GitHub vs. Notion

**If it has a completion state (task, bug, PR) → GitHub. If it's durable reference (spec, decision, runbook) → Notion.** Link between them; don't sync. GitHub owns *what is happening and when*; Notion owns *why and how*.

---

## Common flows

- **Simple bug, one repo, one workstream:** file from that workstream's template → label is applied → it lands on the board → PR `Fixes #N` → merge closes it → Status → Done. Done.
- **Shared-repo work (e.g. `grease`, `iac`):** file in the shared repo, labelled with the *consuming* workstream. The native Repository facet shows it's a `grease`/`iac` change.
- **Platform / infra change spanning repos:** use the **Infrastructure Change** template (`workstream:platform`, `area:iac`); list affected repos and a rollback plan; reference it from each repo's PRs.
- **Vague / org-wide idea:** create a **draft** on the board under Sorcery, set its Workstream field by hand (drafts have no labels and the reconcile ignores them); convert to a real issue once scoped.

---

## Adding or changing a workstream

1. Edit `WORKSTREAMS` (and `LABELS`) in `scripts/generate-issue-templates.mjs`.
2. `node scripts/generate-issue-templates.mjs` and commit the regenerated templates + `labels.yml` (merging `labels.yml` fires `sync-labels.yml`).
3. Add the new option to the project's **Workstream** field.
4. Add a `-label:` term to the No-Workstream search and view, and a per-workstream board view.
