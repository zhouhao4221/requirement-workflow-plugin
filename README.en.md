# DevFlow

🌐 [English](README.en.md) | [中文](README.md) | [한국어](README.ko.md)

AI-driven software lifecycle management toolkit. Covers requirements analysis, development guidance, testing, project management, and API integration — end-to-end. Built on the Claude Code plugin system.

## Plugins

| Plugin | Description | Version |
|--------|-------------|---------|
| **req** | Full requirements workflow — from analysis to archival | v3.0.1 |
| **pm** | Project management helper — weekly/monthly reports, stats, risk scan, plans | v0.1.0 |
| **api** | API integration — Swagger parsing, field mapping, code generation | v0.2.0 |

---

## Installation

> Requires Claude Code v1.0.33 or higher (v2.1+ recommended).

> **Upgrading from aiforge**: The marketplace name changed from `aiforge` to `devflow`. Existing users must uninstall and reinstall:
> ```bash
> claude plugins uninstall req@aiforge
> claude plugins marketplace remove aiforge
> claude plugins marketplace add https://github.com/zhouhao4221/devflow-claude
> claude plugins install req@devflow
> ```

```bash
# Install from GitHub
claude plugins marketplace add https://github.com/zhouhao4221/devflow-claude
claude plugins install req@devflow    # Requirements management
claude plugins install pm@devflow     # Project management helper
claude plugins install api@devflow    # API integration
```

```bash
# Local install (for development)
git clone https://github.com/zhouhao4221/devflow-claude.git
claude plugins marketplace add ./devflow-claude
claude plugins install req@devflow
```

```bash
# Plugin management
claude plugins list                   # List installed plugins
claude plugins update req@devflow     # Update a plugin
claude plugins uninstall req@devflow  # Uninstall a plugin
```

---

## Smart Model Tiering

Every command declares a `model` field in frontmatter, chosen by task complexity to balance speed and reasoning depth:

| Model | Purpose | Typical commands |
|-------|---------|------------------|
| **Haiku** | Read-only / list / help | `/req`, `/req:status`, `/req:show`, `/pm:standup`, `/api:help` |
| **Sonnet** | Standard create / edit / Git ops | `/req:new`, `/req:edit`, `/req:commit`, `/pm:stats`, `/api:config` |
| **Opus** | Deep analysis / plan generation / AI review | `/req:dev`, `/req:fix`, `/req:review-pr`, `/pm:weekly`, `/api:gen` |

Each command also restricts its `allowed-tools` to a whitelist, so read-only commands cannot trigger writes.

---

## req plugin — Requirements management

Covers the full lifecycle from analysis, review, development, testing, to archival.

### Core features

- **AI-guided requirements analysis**: AI asks questions round by round, then generates a complete document in one shot
- **Full lifecycle**: Draft → In Review → Approved → In Development → In Testing → Done
- **Dual tracks**: formal requirements (REQ) and quick fixes (QUICK)
- **Smart development**: `/req:do` — describe your intent and AI picks the flow, creates a branch, and drafts the plan
- **Development guidance**: reads your project's layered architecture from CLAUDE.md and guides layer by layer (stack-agnostic)
- **Live doc maintenance during dev**: AI flags deviations and prompts to update the requirement doc
- **Branch management**: GitHub Flow / Git Flow / Trunk-Based
- **Front/back collaboration**: frontend REQ describes interaction, `dev` stage auto-matches backend APIs
- **PR review & merge**: AI code review, auto-submit comments, one-click merge
- **Git issue integration**: `--from-issue=#N` creates a requirement directly from a Gitea/GitHub issue; branches/commits/done auto-link and auto-close
- **Cross-repo sharing**: front/back repos share the same requirement set (local-first + global cache)
- **Conventional commits**: auto-attach the requirement ID
- **Changelog**: generated from Git history

### Quick start

**New projects only need two steps to launch** (the plugin will prompt you at the start of every session — both are required):

```bash
# 1. Initialize the project (creates docs/requirements/, generates PRD, binds the repo)
/req:init my-project

# 2. Configure branch strategy (GitHub Flow / Git Flow / Trunk-Based + hosting type)
/req:branch init
```

Then the daily workflow:

```bash
# 3. Create a requirement (AI asks questions → generates doc in one shot)
/req:new user points system

# 4. Review
/req:review pass

# 5. Develop (AI generates a plan and guides you layer by layer)
/req:dev

# 6. Test
/req:test

# 7. Archive
/req:done
```

### Command reference

#### Requirements

| Command | Description |
|---------|-------------|
| `/req` | List all requirements; supports `--type` and `--module` filters |
| `/req:new [title]` | Create a formal requirement (AI Q&A → generate doc) |
| `/req:new-quick [title]` | Create a quick fix (small bug / small feature) |
| `/req:do <description>` | Smart development (optimize/refactor/upgrade/tweak, no doc) |
| `/req:fix <description>` | Lightweight fix (bug fix, no doc) |
| `/req:edit [REQ-XXX]` | Edit a requirement |
| `/req:show [REQ-XXX]` | Show requirement details (read-only) |
| `/req:status [REQ-XXX]` | Show requirement status |
| `/req:review [pass\|reject]` | Submit / approve / reject review |
| `/req:dev [REQ-XXX]` | Start or continue development |
| `/req:test [REQ-XXX]` | Full test verification |
| `/req:test_regression` | Run existing automated tests |
| `/req:test_new` | Create new test cases for a new feature |
| `/req:done [REQ-XXX]` | Complete and archive |
| `/req:upgrade <QUICK-XXX>` | Upgrade a quick fix to a formal requirement |
| `/req:split [description]` | Granularity analysis and split suggestions |

#### PR review & merge

| Command | Description |
|---------|-------------|
| `/req:pr [REQ-XXX]` | Create PR (auto-detects GitHub / Gitea) |
| `/req:review-pr` | Show PR status |
| `/req:review-pr review` | AI code review, submit comments |
| `/req:review-pr merge` | Merge PR (supports merge/squash/rebase) |

#### Document management

| Command | Description |
|---------|-------------|
| `/req:prd` | PRD status overview |
| `/req:prd-edit [section]` | Edit PRD |
| `/req:modules` | List all modules |
| `/req:specs` | Spec documents (data types, API contracts, etc.) |

#### Versioning & branches

| Command | Description |
|---------|-------------|
| `/req:commit [message]` | Conventional commit with auto-attached requirement ID |
| `/req:changelog <version>` | Generate release notes |
| `/req:branch init` | Configure branch strategy |
| `/req:branch hotfix [description]` | Create a hotfix branch |

#### Project configuration

| Command | Description |
|---------|-------------|
| `/req:init <project-name>` | Initialize a project |
| `/req:use <project-name>` | Switch the bound project |
| `/req:projects` | List all projects |
| `/req:cache <action>` | Cache management |
| `/req:update-template` | Sync the latest templates from the plugin |

### Requirement lifecycle

```
Formal (REQ):   Draft → In Review → Approved → In Development → In Testing → Done
Quick fix (QUICK): Draft → Plan confirmed → In Development → Done
```

### Document structure

| Section | Content | Filled by |
|---------|---------|-----------|
| Requirement definition | I–VI (description, feature list, rules, scenarios, data & UX, test points) | AI Q&A → generated in one shot |
| Process log | VII–IX (review, change log, linked info) | Auto-filled by commands |
| Implementation plan | X (data model, API design, file changes, steps) | Generated by `/req:dev` |

### Cross-repo sharing

```
~/backend/   (primary)  → docs/requirements/  Local store, git-tracked
~/frontend/  (readonly) → Reads from global cache; dev auto-matches backend APIs
~/.claude-requirements/  → Global cache (auto-synced)
```

### AI skills (auto-triggered)

| Skill | Trigger |
|-------|---------|
| `requirement-analyzer` | When creating/editing a requirement — AI Q&A → generate doc |
| `dev-guide` | During development — layered guidance + live doc maintenance |
| `quick-fix-guide` | Quick fixes — fast analysis and plan |
| `test-guide` | Testing stage — regression and new test creation |
| `prd-analyzer` | When editing PRD — assists with each section |
| `code-impact-analyzer` | On requirement change — analyzes code impact |
| `changelog-generator` | Generates release notes |

---

## pm plugin — Project management helper

Extracts project data from PRD, requirement docs, and Git history to generate reports, stats, and plans tailored to different audiences.

- **Read-only**: consumes what req produces; never mutates requirement docs
- **Works without req**: Git stats and free-form Q&A still work without requirement data
- **Optional persistence**: every output can be saved to `docs/reports/`

| Command | Description |
|---------|-------------|
| `/pm` | Project dashboard |
| `/pm:weekly` | Weekly report |
| `/pm:monthly` | Monthly report |
| `/pm:milestone <version>` | Milestone/release summary |
| `/pm:stats` | Multi-dimensional stats |
| `/pm:progress` | Project progress (Gantt view) |
| `/pm:plan <topic>` | Plan document (schedule/technical/resource) |
| `/pm:risk` | Risk scan |
| `/pm:standup` | Standup summary |
| `/pm:ask <question>` | Free-form Q&A over project data |

---

## api plugin — API integration

Frontend API integration toolkit with Swagger/OpenAPI parsing, field mapping, and code generation.

| Command | Description |
|---------|-------------|
| `/api:import` | Import a Swagger document |
| `/api:search <keyword>` | Search endpoints |
| `/api:gen` | Generate TypeScript types and request functions |
| `/api:map` | Field mapping analysis |

---

## Tutorial

Full step-by-step tutorial: [docs/tutorial.en.md](docs/tutorial.en.md).

## License

[Apache License 2.0](LICENSE)
