---
name: automatic-workflow
description: "Set up the autowf pipeline (Claude plans and reviews, agy writes code) in the current project. Use when the user asks to apply AutomaticWorkFlow / autowf to a project."
---

# automatic-workflow

Prepare the current repository so the user can run the `autowf` pipeline
(`~/.local/bin/autowf`, a link to `auto.sh` in this skill's folder, installed by the dotfiles
`install.sh`): Claude writes/reviews, the Antigravity CLI (`agy`) codes,
the script runs `TEST_CMD` itself and commits each passing task on an `auto/*` branch.

Invoked as `/automatic-workflow <goal>`. Talk to the user in the language they use;
write every file (PLAN.md, .autowf.env, commit messages) in English.

**Never run the pipeline (`autowf` without `--check`) inside Claude Code.** It is long-running
and must run in the user's own Terminal.

## a. Survey the repo

1. Work from the git root (`git rev-parse --show-toplevel`). If it is not a git repo, ask the user
   before running `git init`.
2. Identify: languages, package manager (lockfiles), existing test command and framework
   (`package.json` scripts, `pyproject.toml`/`pytest.ini`, `go test`, `cargo test`, Makefile...),
   directory layout, entry points, current branch and `git status`.
3. Git hooks: autowf commits every passing task, so a hook that rejects the commit costs a round.
   Check for `.pre-commit-config.yaml`, `.husky/`, `lefthook.yml`, and an executable
   `$(git rev-parse --git-path hooks)/pre-commit` or `commit-msg` (this honours `core.hooksPath`).
   If hooks exist, note what they run and whether they call tools from PATH (pre-commit
   `language: system` hooks such as ruff/mypy from a venv, `npx lint-staged`, ...). Step b makes
   TEST_CMD run the same checks so the agent sees hook failures while it can still fix them.
4. Stop and ask the user when:
   - the goal is missing → ask exactly ONE question to get it;
   - `git status --porcelain` is not empty → ask how to handle the uncommitted changes
     (autowf refuses to run on a dirty tree and never commits on the user's behalf);
   - there is no test framework at all → ask which one to add (do not pick silently).

## b. Write PLAN.md

Build on the existing code — do not plan a rewrite. Required format (autowf validates it):

```markdown
# <Project> — <goal>

TEST_CMD: <the repo's real test command, one line, e.g. npm test -- --watch=false>

## Overview
Short: stack, layout, conventions, how to run things. Reviewers only see this
overview plus one task, so put shared context here.

## Task 1: <title>
- Files to create/modify
- Steps
**Acceptance criteria:** checks verifiable by tests (TEST_CMD exits 0, specific test names/behaviours)

## Task 2: ...
```

Rules:
- Tasks numbered `## Task 1`, `## Task 2`, ... consecutively; each small enough for one agent run.
- Keep tasks small (few files, one concern): the agent's token cost grows with every file it reads
  and every step it takes. autowf quotes the overview + the task into the agent's prompt, so the
  overview must stay short and every task section must name the files it touches.
- Make TEST_CMD print compact output (`pytest -q`, `vitest run --reporter=dot`, `go test` without
  `-v`): the agent reads that output on every run.
- Task 1 guarantees `TEST_CMD` runs (installs deps / test config if needed). If it already runs,
  Task 1 can be the first real change, but still verify TEST_CMD passes.
- Every acceptance criterion must be checkable by the test suite.
- If the repo has git hooks (step a.3), TEST_CMD must also run them, after the tests, on the
  staged files — autowf runs `git add -A` right before TEST_CMD, so staged = every changed or new
  file, exactly what the commit will contain. E.g. pre-commit: `TEST_CMD: .venv/bin/pytest -q && pre-commit run`
  (not `--all-files`: that also fails on old lint errors in files the task never touched);
  husky + lint-staged: `npm test -- --watch=false && npx lint-staged`. Before writing it, run
  `git add -A` and that hook command once yourself to see it works in this repo, then
  `git reset -q` to unstage. In the overview tell the agent that commits must pass the hooks and
  how to check with allowed commands, one per call: `git add -A`, then the hook command (add its
  program, e.g. `pre-commit` or `npx`, to AGY_ALLOWED_CMDS).
- Mention the command restriction in the overview: the agent may only run the commands listed
  in `.autowf.env` (see step c), one per call, no `;`, `&&`, `|`, `$(...)`.
- Unless the project uses AGY_ALLOW_MCP, also state: do not use MCP tools, use CLI commands only.
- Flutter/Dart projects: `TEST_CMD: flutter test`; tell the agent to verify with the CLI
  (`flutter test`, `flutter analyze`, `dart format`) — not with a running app, DTD or MCP.

Summarize the plan for the user (in their language: goal, TEST_CMD, one line per task) and
**wait for approval**. Apply requested changes. Only after approval:
`git add PLAN.md && git commit -m "Add PLAN.md for autowf"` (commit PLAN.md alone).

## c. Create .autowf.env

```sh
AGY_ALLOWED_CMDS="git, node, npm, ls, mkdir"
```

- List exactly the commands this stack needs to build and test (the program name as the agent
  will type it). Examples: Node `git, node, npm, ls, mkdir`; Python venv
  `git, python3, .venv/bin/python, ls, mkdir`; Go `git, go, ls, mkdir`;
  Flutter/Dart `git, flutter, dart, ls, mkdir` (with `TEST_CMD: flutter test`).
  Include what TEST_CMD starts with.
- Every entry must exist on disk before you write the file: bare names via `command -v <cmd>`,
  paths via `test -x <path>` (from the repo root). Do not assume a layout — e.g. a venv made with
  `uv venv` has no `.venv/bin/pip` (use `uv pip ...` / `uv` instead). Drop or replace any entry that
  is missing, and apply the same check to the first program of every part of TEST_CMD.
- MCP: by default grant **no** MCP access — leave `AGY_ALLOW_MCP` unset, so autowf tells the agent
  to use CLI commands only. Only if the user confirms the project truly needs an MCP tool, add it
  as `AGY_ALLOW_MCP="<server>/<tool>"` (comma-separated for several), e.g.
  `AGY_ALLOW_MCP="flutter_dart-mcp-server/dtd"`.
- If TEST_CMD needs an external service (database, queue, docker compose stack...), add a cheap
  readiness check, e.g. `REQUIRE_CMD="docker compose exec -T postgres pg_isready"`. autowf runs it
  before every try and again when tests fail; while it fails autowf waits (up to
  `REQUIRE_WAIT_MINS`, default 30) instead of burning tries or tripping the repeated-failure breaker,
  then stops with exit 6. Run it once yourself to check it succeeds.
- Add `REVIEW_MODEL=...` (or other variables: CODER, FALLBACK_CODER, PLAN_MODEL, MAX_TRIES,
  MAX_EXTRA_TRIES — extra tries after MAX_TRIES while the reviewer reports progress, default 2,
  MAX_WAIT_HOURS) only when the user asks.
- Commit: `git add .autowf.env && git commit -m "Add .autowf.env"`.

## d. Grant agy permissions

agy in headless mode ignores `~/.gemini/antigravity-cli/settings.json`; it reads
`userSettings.globalPermissionGrants.allow` in `~/.gemini/config/config.json`. Rules match the whole
command line unless they use `regex:`.

1. Back up: `cp ~/.gemini/config/config.json ~/.gemini/config/config.json.bak`.
2. Merge (keep all other keys; add only missing rules) with a small Python script:
   - one rule per command in AGY_ALLOWED_CMDS, in this narrow anchored form (regex-escape the
     command, e.g. `\.venv/bin/python`); it forbids chaining another command via `; & | $ backtick`:
     `command(regex:^<cmd>( [^;&|`$]*)?$)` — except `git`, which gets only read-only subcommands
     (autowf stages and commits itself; the agent must not commit, push or reset):
     `command(regex:^git (status|diff|log|show|ls-files|grep)( [^;&|`$]*)?$)`
   - one file-write rule for this repo, using the absolute physical path (`pwd -P`):
     `write_file(<absolute repo root>)`
   - only for entries listed in AGY_ALLOW_MCP (none by default): `mcp(<server>/<tool>)`
3. **Never** grant `command(*)`, `rm`, `sudo`, `curl`, `wget`, any network tool, any broad regex
   such as `command(regex:.*)`, and never use `--dangerously-skip-permissions`. If the stack seems
   to need one of these, stop and ask the user.
   `agy -p` also loads the grants in `~/.gemini/config/projects/default-cli-project.json`
   (`permissionGrants.permissionGrants.allow`), which override the narrow rules. If it holds a
   broad rule — bare `command(git)`, `command(*)`, or a `regex:` without a leading `^` — show it
   to the user and, with their OK, back the file up and remove it (`autowf --preflight` warns about
   these too).
4. Show the user which rules were added.

```python
import json, os, re
p = os.path.expanduser("~/.gemini/config/config.json")
c = json.load(open(p))
allow = c.setdefault("userSettings", {}).setdefault("globalPermissionGrants", {}).setdefault("allow", [])
cmds = [x.strip() for x in AGY_ALLOWED_CMDS.split(",") if x.strip()]
rules = ["command(regex:^git (status|diff|log|show|ls-files|grep)( [^;&|`$]*)?$)" if x == "git" else
         "command(regex:^%s( [^;&|`$]*)?$)" % re.escape(x).replace("\\ ", " ") for x in cmds]
rules.append("write_file(%s)" % REPO_ROOT)
rules += ["mcp(%s)" % x.strip() for x in AGY_ALLOW_MCP.split(",") if x.strip()]  # "" by default
added = [r for r in rules if r not in allow]
allow.extend(added)
json.dump(c, open(p, "w"), indent=2, ensure_ascii=False)
print("\n".join(added) or "(nothing new)")
```

## e. Permission preflight

From the repo root run:

```sh
autowf --preflight
```

It asks agy (headless) to: reply once (login check), run one harmless probe per command in
AGY_ALLOWED_CMDS (`git status --short`, `<cmd> --version`, ...), create and delete
`.autowf-probe.txt` (file-write check), and checks that TEST_CMD's executable is in
AGY_ALLOWED_CMDS and that every AGY_ALLOW_MCP entry has its `mcp(<server>/<tool>)` rule in
config.json. It also checks git hooks with the current PATH (see ❌ Git hook below). It prints a ✅/❌ table, logs to `.auto-logs/preflight-*.log`, exits 0 when
everything passes (and stores `.auto-logs/preflight.ok`), or exits 5 and prints the exact rules
to add to `userSettings.globalPermissionGrants.allow`.

On exit 5:
- ❌ login (AUTH): stop and tell the user to run `agy` in a Terminal to sign in. Do not retry.
- ❌ broken agent hook (ENV_HOOK, e.g. a plugin's `PreToolUse` hook in
  `~/.gemini/config/plugins/<plugin>/hooks.json` fails): every agent tool is blocked, so adding
  rules will not help. Show the user the printed "Cách xử lý" (the plugin and every hooks.json
  that registers it — agy loads plugins by the name in plugin.json, so renaming the folder or
  `"enabled": false` in config.json does not turn the hook off); only with their OK, back up and
  fix the hook command in each of those files. The same error during a run stops it at once
  (exit 2) without using up the task's tries.
- ❌ command / file write / TEST_CMD: add the suggested narrow rules to
  `~/.gemini/config/config.json` (back it up to `.bak` first; merge, keep other keys, add only
  missing rules). If TEST_CMD's executable is missing from AGY_ALLOWED_CMDS, also add it to
  `.autowf.env` and commit that change.
- ❌ MCP: add `mcp(<server>/<tool>)` only for entries the user approved in AGY_ALLOW_MCP.
- Only accept rules of the forms `command(regex:^<cmd>( [^;&|`$]*)?$)`,
  `write_file(<absolute repo root>)` and approved `mcp(<server>/<tool>)`. **Never** add `command(*)`, `rm`, `sudo`, `curl`, `wget`, a
  broad regex, or use `--dangerously-skip-permissions`; if a suggested rule would need one of
  these, stop and ask the user.
- ❌ Git hook: autowf made a throwaway commit in a temporary worktree (after
  `pre-commit run --all-files` when the repo uses pre-commit) and the hook rejected it; the output
  is in `.auto-logs/preflight-hooks.log`. The worktree gets symlinks to every untracked
  `node_modules`, `.venv` and `venv` at any depth, and autowf puts `.venv/bin` first on PATH by
  itself, so "not found" usually means a dependency is not installed in the main tree: JS tools →
  `npm`/`pnpm install` in the folder with that package.json (e.g. `frontend/`); Python tools →
  install into `.venv`. If the tool lives in some other environment (conda, a venv not named
  `.venv`), re-run with it activated; if that passes, the hand-off command in step f must
  activate it the same way. If it reports lint
  errors that already exist on HEAD, show them to the user and ask whether to fix them first
  (commit on its own) — do not disable or bypass hooks.
- Re-run `autowf --preflight`. At most 3 rounds in total; if it still fails, stop and report to the
  user with the ❌ lines and the relevant `.auto-logs/preflight-*.log` contents.

## f. Final check and hand-off

Only when `autowf --preflight` passed: run `autowf --check` in the repo. It must report the tools
installed, PLAN.md valid, git clean, preflight passed and the git hook check passed. Then tell the user to open a separate
Terminal tab in the repo and run:

```sh
caffeinate -i autowf            # macOS (keeps the Mac awake)
tmux new -s autowf autowf       # Linux / GitHub Codespaces (survives a closed browser tab)
```

If `autowf` is not on PATH, use `~/.claude/skills/automatic-workflow/auto.sh` instead.

No need to activate `.venv` first — autowf does it. If the hooks or TEST_CMD only worked with some
other activated environment (step e), give the command with that prefix instead, e.g.
`conda activate foo && caffeinate -i autowf` (on Linux without `caffeinate -i`), and say why: autowf checks the hooks at start (and
stops with exit 5 if they fail), since a Terminal without that environment cannot commit.

Phone alerts: if `NTFY_TOPIC` is not set (`autowf --check` says so), offer ntfy — the user adds
`export NTFY_TOPIC=<hard-to-guess name>` to `~/.zshrc` (or `~/.bashrc` on Linux/Codespaces) (never to `.autowf.env`, which is committed:
anyone who knows the topic can read the alerts), subscribes to it in the ntfy app, and runs
`autowf --notify-test`.

Mention: progress in `.auto-logs/run.log` (also shown in the Terminal; while agy works, each step it takes —
file read, command, file edit, error — is printed live and saved to `.auto-logs/task<N>-try<M>-code.log.steps`;
`AGY_WATCH=0` turns this off), result and stop reason ("Nguyên nhân") in
`.auto-logs/summary.md` (with agy model calls/tokens per task; `AGY_TOKEN_WARN` sets the warning threshold),
the agent writes its task summary to `TASK_SUMMARY.md` and autowf appends it to PROGRESS.md at commit, work lands on an `auto/*` branch; rerunning `autowf` resumes and skips
tasks already committed since the task headings in PLAN.md last changed (editing a task's body
keeps them); a reviewer `plan-gap` stops the run (exit 7) for a decision the plan does not make —
write it into that task's section of PLAN.md, commit PLAN.md alone, `git stash -u`, rerun; the permission preflight is skipped while the permission
config, the agy plugins (`hooks.json` etc.) and the agy version are unchanged (the git hook check still runs every time). If the user finishes or fixes a task
by hand, `autowf --adopt N` runs TEST_CMD and commits the changes (or renames the HEAD commit) as
`Task N: <title>` so the next run skips it — no hand-written commit names. Non-blocking reviewer
remarks on passing tasks are listed in `summary.md` and kept across runs in `.auto-logs/nits.md`. To stop cleanly after the current task, run `autowf --stop-after` in the repo from another tab
(cancel: `autowf --no-stop-after`); Ctrl-C stops mid-task and leaves uncommitted work. Do not start the pipeline yourself.
