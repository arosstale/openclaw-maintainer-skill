---
name: moltbot-maintainer
description: PR review and merge automation for Moltbot maintainers. Review with opus, prep and merge with a gpt subagent. Use when asked to review, prep, or merge a PR.
---

# Moltbot Maintainer

PR review + prep + merge automation. Uses opus for review, gpt for prep and merge. No external coding CLIs needed.

## Setup

Run the setup script to create symlinks:

```bash
./setup.sh
```

This links the command files to:
- `~/.claude/commands/` for Claude Code
- `~/.codex/prompts/` for Codex CLI

## Command Files

The actual command files live in this skill's `commands/` folder:
- `commands/reviewpr.md` - review only
- `commands/preparepr.md` - rebase, fix, run gates, push fixes, but do NOT merge
- `commands/mergepr.md` - merge only

## Workflow Overview (3 step)

1. **User:** "review PR #2403"
2. **Main agent:** spawns opus subagent for /reviewpr
3. **Opus subagent:** reviews, pings back findings
4. **Main agent:** summarizes for user (ready for prep, needs work, concerns)
5. **User:** "ok prep it" / "fix X first" / "don't merge"
6. **Main agent:** if approved, spawns gpt subagent (high thinking) for /preparepr
7. **GPT subagent:** rebases, fixes, runs gates, pushes updates, pings back `PR is ready for /mergepr`
8. **User:** "merge it"
9. **Main agent:** spawns gpt subagent (high thinking) for /mergepr
10. **GPT subagent:** merges via squash, pings back merge SHA
11. **Main agent:** confirms to user with merge SHA

## ⚠️ ALWAYS USE SUBAGENT

Review, prep, and merge are long running tasks. NEVER run in the main thread.

## Model Preferences

Preferred models (fall back to session default if not available):
- Review: `model:opus` (best for nuanced code review)
- Prep: `model:gpt` with `thinking:high` (methodical fixes + gates)
- Merge: `model:gpt` with `thinking:high` (careful merge flow)

## Config (optional)

Create `config.yaml` in this skill folder to override defaults:

```yaml
# ~/openclaw/skills/openclaw-maintainer/config.yaml
models:
  review: opus          # or anthropic/claude-opus-4-5, or leave blank for default
  prepare: gpt          # or openai-codex/gpt-5.2, or leave blank for default
  merge: gpt            # or openai-codex/gpt-5.2, or leave blank for default
  prepare_thinking: high
  merge_thinking: high
```

If config not present or model not available, uses session default model.

## Review Workflow (/reviewpr)

Spawn a subagent with a task referencing the command file:

```
sessions_spawn task:"Review PR #<number> in moltbot repo. First read ~/.claude/commands/reviewpr.md and follow its instructions exactly. cd ~/Development/moltbot before running any gh commands." model:opus runTimeoutSeconds:600
```

If opus isn't configured, omit the model param to use the session default.

The command file contains all review steps, evaluation criteria, and output format.

## Prep Workflow (/preparepr)

Spawn a subagent for prep (only after user approves):

```
sessions_spawn task:"Prepare PR #<number> in moltbot repo. First read ~/.claude/commands/preparepr.md and follow its instructions exactly. cd ~/Development/moltbot before running any gh commands." model:gpt thinking:high runTimeoutSeconds:1800
```

If gpt isn't configured, omit the model param. Thinking is optional but recommended.

The command file handles:
- worktree setup
- fetch + rebase on latest main
- fixes from review
- full gate (lint/build/test)
- pushing updates back to the PR branch

## Merge Workflow (/mergepr)

Spawn a subagent for merge (only after prep is done and user says yes):

```
sessions_spawn task:"Merge PR #<number> in moltbot repo. First read ~/.claude/commands/mergepr.md and follow its instructions exactly. cd ~/Development/moltbot before running any gh commands." model:gpt thinking:high runTimeoutSeconds:900
```

The command file handles:
- sanity checks (draft, checks failing, behind main)
- optional changelog only commit (if needed)
- merge via `gh pr merge --squash --delete-branch`
- verify PR state is MERGED
- cleanup worktree only on success

## Important Notes

- Subagents must read the command file first before doing anything
- If checks or gates fail, report failure and stop, do not force merge
- If merge fails, report and do NOT retry in a loop
- PR must end in MERGED state, never CLOSED
