---
name: openclaw-maintainer
description: PR review and merge automation for OpenClaw maintainers. Review with opus, prep and merge with a gpt subagent. Use when asked to review, prep, or merge a PR.
---

# OpenClaw Maintainer

PR review + prep + merge automation. Uses opus for review, gpt for prep and merge.

## SAFETY: NEVER PUSH TO MAIN

Subagents have full disk access. The one inviolable rule:
- NEVER force-push, push, or directly commit to `main` or `origin/main`.
- All pushes go to PR head branches only.
- The only way code reaches main is through `gh pr merge --squash`.
- If gates (lint/build/test) have not passed, do NOT merge.

## Command Files

The actual command files live in this skill's `commands/` folder. Subagents read these directly (they do NOT read this SKILL.md file).
- `commands/reviewpr.md` - review only
- `commands/preparepr.md` - rebase, fix, run gates, push fixes, but do NOT merge
- `commands/mergepr.md` - merge only

## Workflow Overview (3 step)

1. **User:** "review PR #2403"
2. **Main agent:** spawns opus subagent via `sessions_spawn`. Subagent reads `commands/reviewpr.md` and executes.
3. **Opus subagent:** reviews, pings back findings
4. **Main agent:** summarizes for user (ready for prep, needs work, concerns)
5. **User:** "ok prep it" / "fix X first" / "don't merge"
6. **Main agent:** if approved, spawns gpt subagent (high thinking) via `sessions_spawn`. Subagent reads `commands/preparepr.md`.
7. **GPT subagent:** rebases, fixes, runs gates, pushes updates to PR branch (never main), pings back `PR is ready for /mergepr`
8. **User:** "merge it"
9. **Main agent:** spawns gpt subagent (high thinking) via `sessions_spawn`. Subagent reads `commands/mergepr.md`.
10. **GPT subagent:** merges via `gh pr merge --squash` (the only path to main), pings back merge SHA
11. **Main agent:** confirms to user with merge SHA

## ⚠️ ALWAYS USE SUBAGENT

Review, prep, and merge are long running tasks. NEVER run in the main thread. Always use `sessions_spawn` to create a subagent.

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
sessions_spawn task:"Review PR #<number> in openclaw repo. Read commands/reviewpr.md and follow its instructions exactly." model:opus runTimeoutSeconds:600
```

If opus isn't configured, omit the model param to use the session default.

## Prep Workflow (/preparepr)

Spawn a subagent for prep (only after user approves):

```
sessions_spawn task:"Prepare PR #<number> in openclaw repo. Read commands/preparepr.md and follow its instructions exactly." model:gpt thinking:high runTimeoutSeconds:1800
```

If gpt isn't configured, omit the model param. Thinking is optional but recommended.

## Merge Workflow (/mergepr)

Spawn a subagent for merge (only after prep is done and user says yes):

```
sessions_spawn task:"Merge PR #<number> in openclaw repo. Read commands/mergepr.md and follow its instructions exactly." model:gpt thinking:high runTimeoutSeconds:900
```

## Important Notes

- Subagents read the command file directly, they do NOT read this SKILL.md
- Each command file is self-contained with all setup, steps, and safety rules
- If checks or gates fail, report failure and stop, do not force merge
- If merge fails, report and do NOT retry in a loop
- PR must end in MERGED state, never CLOSED
- Code only reaches main through `gh pr merge --squash`, never through direct push
