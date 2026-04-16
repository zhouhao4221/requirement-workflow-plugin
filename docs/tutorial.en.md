# Tutorial

🌐 [English](tutorial.en.md) | [中文](tutorial.md) | [한국어](tutorial.ko.md)

This tutorial walks through a complete example — from installing the plugin to closing out a requirement.

> Example scenario: implementing "User Points Rule Management" for a backend project.

---

## 1. Installation & initialization

> **Two-step launch**: After installing the plugin, every time you open a Claude Code session, the plugin detects whether the repo is initialized and whether a branch strategy is configured. If either is missing, a guidance message is printed at the start of the session. Complete the two steps below and the message disappears:
>
> 1. `/req:init <project-name>` — initialize the requirements project
> 2. `/req:branch init` — configure the branch strategy
>
> After that, run `/req:new` to create your first requirement.

### 1.1 Install the plugin

```bash
# 1. Add the plugin repo as a marketplace
claude plugins marketplace add https://github.com/zhouhao4221/devflow-claude

# 2. Install the plugin from the marketplace
claude plugins install req@devflow

# Verify installation
claude plugins list
```

### 1.2 Initialize the requirements project

In the project root, start Claude Code and run:

```
/req:init my-saas
```

This will:
- Create the local directory `docs/requirements/` (`active/`, `completed/`, `modules/`, `templates/`)
- Create the global cache `~/.claude-requirements/projects/my-saas/`
- Generate the PRD template `docs/requirements/PRD.md`
- Record the project name and role in `.claude/settings.local.json`

### 1.3 CLAUDE.md architecture description

During init, the plugin checks whether your project CLAUDE.md contains architecture info. If missing, it prompts you to pick a preset template:

```
📋 Pick a project type to generate a CLAUDE.md snippet:

  1. Go backend (Gin + GORM layered architecture)
  2. Java backend (Spring Boot layered architecture)
  3. Frontend project (React/Vue + TypeScript)
  4. Custom (blank template, fill in manually)
  5. Skip
```

The snippet is appended to your project CLAUDE.md and covers tech stack, layered architecture table, coding conventions, testing conventions, etc. `/req:dev` and `/req:test` rely on this info to generate plans and locate test files.

> **Edit later**: just edit the "Project Architecture" section of your project CLAUDE.md.

### 1.4 Configure branch strategy (strongly recommended)

```
/req:branch init
```

> While unconfigured, the session-start banner keeps reminding you; once configured, the reminder disappears. You can still skip configuration — defaults apply (hardcoded `feat/` / `fix/` prefixes, no auto PR).

Pick your team's branch strategy:
- **GitHub Flow** (recommended): branch off `main`, merge back to `main`
- **Git Flow**: feature branches off `develop`, merge back to `develop`
- **Trunk-Based**: short-lived branches, trunk development

Then pick your hosting type:
- **GitHub**: `/req:pr` suggests the `gh pr create` command
- **Gitea**: `/req:pr` calls the Gitea REST API to create the PR
- **Other**: only prints `git merge` instructions

After configuration, `/req:dev`, `/req:commit`, `/req:done`, `/req:pr` all follow the policy.

### 1.5 Reinitialize

Backfill missing files on an existing project (non-destructive):

```
/req:init my-saas --reinit
```

Use cases:
- Pick up new template files after a plugin upgrade
- Backfill missing directories (e.g. `modules/`, `templates/`)
- Redo the CLAUDE.md architecture prompt
- Recover a deleted `PRD.md` or module doc

### 1.6 Rebuild cache

When the global cache is corrupted or missing, rebuild from local storage:

```
/req:cache rebuild
```

Other cache operations:

```
/req:cache info          # Inspect cache state
/req:cache clear         # Clear the current project's cache
/req:cache clear-all     # Clear all projects' caches
/req:cache export        # Export cache data
```

### 1.7 Sync templates (optional)

If the plugin ships new templates:

```
/req:update-template
```

### 1.8 Configure the Gitea token (required for Gitea repos)

If you chose Gitea in `/req:branch init`, a token is required for automated PR creation.

**Create the token:**

1. Log into Gitea → avatar (top right) → **Settings**
2. Left menu → **Applications**
3. "Manage Access Tokens" → enter a name (e.g., `claude-pr`)
4. Choose scopes:

| Category | Scope | Required | Notes |
|----------|-------|----------|-------|
| issue | read/write | ✅ | PRs are issues under the hood; needed for create/query |
| repository | read/write | ✅ | Read repo info, list branches, push code |
| user | read | optional | Validate token |

5. Click **Generate Token** → copy & save (shown only once)

**Configure the token:**

Write it into `branchStrategy.giteaToken` of `.claude/settings.local.json`:

```json
{
  "branchStrategy": {
    "repoType": "gitea",
    "giteaUrl": "https://your-gitea.com",
    "giteaToken": "your-token-here"
  }
}
```

> **Security**: `settings.local.json` must not be committed to Git — make sure it is in `.gitignore`.

**Verify:**

```bash
curl -s -H "Authorization: token your-token-here" \
  https://your-gitea.com/api/v1/user
```

If user info is returned, the token works.

---

## 2. Creating requirements

### 2.1 Formal requirements (REQ)

```
/req:new User Points Rule Management --type=backend
```

AI walks you section by section:

| Section | Content | What you do |
|---------|---------|-------------|
| I. Description | Background, goals, customer scenarios, value | Describe the business context; AI structures it |
| II. Feature list | Checkable list of features | Confirm scope |
| III. Business rules | Validation, state transitions, permissions | Fill in the details |
| IV. Scenarios | Roles, flows, edge cases | Describe typical flows |
| V. API requirements | Endpoint capabilities, I/O, semantics | Confirm API needs |
| VI. Test points | Scenarios to verify | Note test focus |

Generates `docs/requirements/active/REQ-001-user-points-rule-management.md`.

### 2.2 Quick fixes (QUICK)

For small bugs or small features — a lighter flow:

```
/req:new-quick Fix points calculation precision loss
```

The QUICK template is shorter: problem statement → plan → verification.

### 2.3 Granularity suggestions

Not sure if the scope is right?

```
/req:split User points system
```

AI analyzes the granularity and suggests a split (read-only, no doc created).

### 2.4 Create from a Git issue

If your team uses Gitea / GitHub issues as the intake:

```
/req:new --from-issue=#12           # Formal requirement
/req:new-quick --from-issue=#5      # Quick fix
/req:do --from-issue=#42            # No doc; treat issue body as the intent for smart dev
```

**What AI does:**
1. Fetches the issue via the API configured in `branchStrategy.repoType` (Gitea → REST API + `giteaToken`; GitHub → `gh issue view`)
2. Uses the issue title as the default requirement title; the body seeds "Problem & current state"
3. Stores `issue: #N` in the doc's metadata, used for downstream auto-linking

**Prereq for Gitea repos**: `branchStrategy.giteaUrl` and `giteaToken` must be set (see 1.8). AI will **not** guess an HTTPS URL from the SSH remote — it must be configured.

#### Issue ↔ branch/commit auto-linking

When linked to an issue, the whole chain carries the issue number:

| Step | Behavior |
|------|----------|
| `/req:dev` creates the branch | Appends `-iN` (e.g., `feat/REQ-001-user-points-i12`) |
| `/req:commit` | Appends `closes #N` in the commit message (PR merge auto-closes the issue) |
| `/req:done` | Asks whether to close the issue via API |
| `/req:do --from-issue` | Branch gets `-iN`; on completion, asks to close the issue |

**Lookup priority**: doc's `issue` field > `-iN` suffix in branch name. This way, even a doc-less `/req:do` lets `commit` and `done` infer the issue number from the branch.

---

## 3. Review flow

> QUICK skips review and can go straight to development.

### 3.1 Submit for review

```
/req:review
```

Status transitions Draft → In Review.

### 3.2 Review decision

```
/req:review pass     # Approve → Approved
/req:review reject   # Reject → back to Draft
```

After rejection, use `/req:edit` to revise and resubmit.

---

## 4. Development

### 4.1 Start development

```
/req:dev
```

Flow:

```
Prechecks (REQ must be approved)
    ↓
Branch management (auto-create feat/REQ-001-user-points-rule)
    ↓
Read the project architecture from CLAUDE.md (layer order, directory layout)
    ↓
Load requirement context (sections I–VI)
    ↓
Generate implementation plan (Plan Mode)
    ├── 10.1 Data model
    ├── 10.2 API design (from API section + repo code)
    ├── 10.3 File changes (listed by CLAUDE.md layers)
    └── 10.4 Steps (decomposed by CLAUDE.md layer order)
    ↓
Confirm plan → status: In Development
    ↓
Implement layer by layer per CLAUDE.md
```

### 4.2 Branch management

On the first `/req:dev`, AI automatically:

1. Checks the working tree is clean (aborts if dirty)
2. Reads branch strategy (if `/req:branch init` was run)
3. Generates an English branch name from the title and asks you to confirm:
   ```
   Will create dev branch: feat/REQ-001-user-points-rule
   Based on branch: main (from branchStrategy.branchFrom)
   ```
4. On confirm, creates the branch and writes `branch` into the doc

Re-running `/req:dev` just switches to the recorded branch.

Branch naming (prefixes configurable via strategy):
- REQ → `feat/REQ-XXX-<english-slug>[-iN]`
- QUICK → `fix/QUICK-XXX-<english-slug>[-iN]`
- `/req:do --from-issue` → `<prefix><slug>-iN` (prefix chosen by AI from intent)
- Hotfix → `hotfix/<english-slug>` (via `/req:branch hotfix`)
- `-iN`: optional issue suffix (e.g., `-i12`), appended automatically when a Git platform issue is linked (see 2.4)

### 4.2.1 Branch strategy commands

```
/req:branch              # View current strategy and branch status
/req:branch init         # Interactively configure branch strategy + repo type
/req:branch status       # View strategy config and each requirement's branch state
/req:branch hotfix desc  # Create a hotfix branch off main
```

### 4.2.2 Create a PR

When development is done:

```
/req:pr              # Auto-detect the requirement from the current branch
/req:pr REQ-001      # Create a PR for a specific requirement
```

Based on the repo type from `/req:branch init`:
- **Gitea**: calls the Gitea REST API (needs `giteaToken`, see 1.8)
- **GitHub**: uses `gh` CLI
- **Other**: pushes the branch and prints merge instructions

Git Flow hotfix branches get two PRs (→ main + → develop).

### 4.2.3 Review & merge a PR

Use AI review and merge:

```
/req:review-pr              # PR status
/req:review-pr review       # AI code review
/req:review-pr merge        # Merge the PR
```

**Review flow:**
1. AI fetches the PR diff and reviews file by file (correctness, security, conventions, requirement match)
2. Findings are tiered: 🔴 blocker (must fix), 🟡 suggestion, 🔵 info
3. The review is auto-submitted as a PR comment (visible on Gitea/GitHub web)
4. No blockers → `merge` allowed

**Merge method**: read from `branchStrategy.mergeMethod` (default `merge`); supports `merge` / `squash` / `rebase`.

### 4.2.4 Smart development (`/req:do`)

For optimizations, refactors, upgrades — no requirement doc needed:

```
/req:do Optimize order query performance
/req:do Refactor the user service layer
/req:do Upgrade Go to 1.23
/req:do Unify error code formatting
```

AI automatically:
1. **Analyzes intent** — type (optimize/refactor/upgrade/convention/small feature/fix) and scale
2. **Searches the code** — locates relevant files and drafts changes
3. **Confirms the plan** — on confirm, creates a branch (`improve/` / `feat/` / `fix/` chosen by type)
4. **Applies changes** — edits code per the plan

For larger scope, suggests switching to `/req:new-quick` or `/req:new`.

**Difference vs `/req:fix`:**
- `/req:fix` — dedicated to bug fixing; AI performs root-cause analysis
- `/req:do` — non-bug (optimize/refactor/upgrade); AI picks the right flow from intent

### 4.3 Continue development

After an interruption, resume:

```
/req:dev REQ-001
```

Add `--reset` to regenerate the plan:

```
/req:dev REQ-001 --reset
```

### 4.4 Conventional commits

During development, use the conventional commit helper:

```
/req:commit
```

AI analyzes the diff and produces a Conventional Commits message:

```
feat: implement points rule CRUD APIs (REQ-001)
```

---

## 5. Testing

### 5.1 Full test

```
/req:test
```

Runs regression + new feature tests; status → In Testing.

### 5.2 Step-by-step tests

```
/req:test_regression    # Run existing automated tests, produce a regression report
/req:test_new           # Create test cases for the new feature (UT/API/E2E)
```

---

## 6. Archival

```
/req:done
```

Flow:
1. Verify test completion
2. Show summary (features, test points, file stats, timeline)
3. On confirm, archive: `active/REQ-001-*.md` → `completed/`
4. Update PRD index
5. Remind you to merge the dev branch

---

## 7. Browsing & management

### 7.1 Requirements list

```
/req                            # List everything
/req --type=backend             # Filter by type
/req --module=user              # Filter by module
/req --type=frontend --module=user
```

### 7.2 Details

```
/req:show REQ-001     # Read-only full view
/req:status REQ-001   # Status + progress
```

### 7.3 Edit

```
/req:edit REQ-001
```

---

## 8. Module management

Modules are functional-domain docs that help AI understand context.

```
/req:modules                  # List all modules
/req:modules new user         # Create the user module doc
/req:modules show user        # View module details
```

Module docs cover: scope, core features, data model, API overview, key file paths.

---

## 9. PRD management

The PRD is project-level — one per project.

```
/req:prd                     # PRD overview + section fill rate
/req:prd-edit                # Edit PRD with AI assistance
/req:prd-edit Overview       # Edit a specific section
```

The "Requirement Tracking" section of the PRD is auto-maintained:
- `/req:new` appends a row
- `/req:done` updates the status and completion date

---

## 10. Versioning

### 10.1 Generate release notes

```
/req:changelog v1.2.0                          # Auto-detect range
/req:changelog v1.2.0 --from=v1.1.0 --to=HEAD
```

AI classifies Git commits and generates structured release notes.

### 10.2 Upgrade a quick fix

When a QUICK grows mid-flight:

```
/req:upgrade QUICK-003
```

---

## 11. Cross-repo collaboration

For projects split across frontend and backend repos.

### Primary repo (backend)

```
# Initialize the project
/req:init my-saas

# Create and manage requirements normally
/req:new User Points - Backend --type=backend
```

### Linked repo (frontend)

```
# Bind to the same project
/req:use my-saas

# Read-only access
/req
/req:show REQ-001

# Develop based on a requirement (reads from cache)
/req:dev REQ-002
```

Linked repos have role `readonly`:
- Can view and read requirements
- Can develop based on completed requirements
- Cannot create/edit/transition requirements

### 11.1 Sharing spec docs

The primary repo owns spec docs (data types, API contracts, error codes); read-only repos see them in real time.

**Primary (backend):**

```
/req:specs new Order data types
/req:specs edit order-types
/req:specs
```

**Read-only (frontend):**

```
/req:specs
/req:specs show order-types
```

Specs live in `docs/requirements/specs/` and sync via cache automatically. After the backend edits, the frontend sees the latest on next view.

Typical uses:
- Backend defines data types → frontend consumes field definitions
- Shared error codes → implemented on both sides
- API contracts → keep front/back in lockstep

---

## 12. Full flow diagram

```
                  Create requirement
                /req:new <title>
                      │
                      ▼
               ┌─────────────┐
               │ 📝 Draft    │ ← /req:edit
               └──────┬──────┘
                      │ /req:review
                      ▼
               ┌─────────────┐
               │ 👀 In Review│
               └──────┬──────┘
                      │ /req:review pass
                      ▼
               ┌─────────────┐
               │ ✅ Approved │
               └──────┬──────┘
                      │ /req:dev (auto branch)
                      ▼
               ┌─────────────┐
               │ 🔨 In Dev   │ ← /req:commit
               │             │ ← /req:pr
               │             │ ← /req:review-pr review
               │             │ ← /req:review-pr merge
               └──────┬──────┘
                      │ /req:test
                      ▼
               ┌─────────────┐
               │ 🧪 In Test  │
               └──────┬──────┘
                      │ /req:done (merge reminder)
                      ▼
               ┌─────────────┐
               │ 🎉 Done     │ → archived to completed/
               └─────────────┘
```

---

## Cheat sheet

| Scenario | Command |
|----------|---------|
| Browse requirements | `/req` |
| Create a formal requirement | `/req:new <title> --type=backend` |
| Quick fix (with doc) | `/req:new-quick <title>` |
| Lightweight fix (no doc) | `/req:fix <description>` |
| Smart dev (optimize/refactor) | `/req:do <description>` |
| Edit | `/req:edit` |
| Submit for review | `/req:review` |
| Approve | `/req:review pass` |
| Start development | `/req:dev` |
| Commit | `/req:commit` |
| Create PR | `/req:pr` |
| AI review | `/req:review-pr review` |
| Merge PR | `/req:review-pr merge` |
| Run tests | `/req:test` |
| Archive | `/req:done` |
| View PRD | `/req:prd` |
| Generate changelog | `/req:changelog v1.0.0` |
| Configure branch strategy | `/req:branch init` |
| Branch status | `/req:branch status` |
| Hotfix | `/req:branch hotfix <description>` |
| Reinitialize | `/req:init my-project --reinit` |
| Rebuild cache | `/req:cache rebuild` |
| View spec doc | `/req:specs show <name>` |
| Create spec doc | `/req:specs new <name>` |
