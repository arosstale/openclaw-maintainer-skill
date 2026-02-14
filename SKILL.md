---
name: openclaw-maintainer
description: "Review, prepare, and merge PRs for openclaw/openclaw. Script-first: delegates to OpenClaw's own scripts/pr-* wrappers. Use when asked to review, prep, or merge a PR."
---

# OpenClaw Maintainer

PR pipeline for `openclaw/openclaw`. Three steps, always in order. Repo: `/tmp/openclaw-fork`.

## Safety

- **NEVER push to main.** Code reaches main only through `gh pr merge --squash`.
- All work in isolated worktrees: `.worktrees/pr-<PR>`.
- All pushes go to PR head branches with `--force-with-lease`.

## Pipeline

### 1. Review

Read-only. Produce structured findings.

```bash
cd /tmp/openclaw-fork
scripts/pr-review <PR>
```

The wrapper creates the worktree, fetches meta, and sets up `.local/`. You then:
- Check existing implementations on main: `rg -n "<keyword>" src/`
- Read the diff: `gh pr diff <PR>`
- Evaluate correctness, security, tests, docs, changelog
- Write `.local/review.md` and `.local/review.json`

Recommendation is one of: `READY FOR /prepare-pr`, `NEEDS WORK`, `NEEDS DISCUSSION`, `CLOSE`.

Output spec: `{baseDir}/references/review-output.md`

Structured findings in `.local/review.json`:
```json
{
  "recommendation": "READY FOR /prepare-pr",
  "findings": [{"id":"F1","severity":"IMPORTANT","title":"...","fix":"..."}],
  "tests": {"ran":[],"gaps":[],"result":"pass"},
  "changelog": "required"
}
```

### 2. Prepare

Rebase, fix findings, run gates, push to PR head.

```bash
scripts/pr-prepare init <PR>
```

Then:
1. Resolve all BLOCKER and IMPORTANT findings from `.local/review.json`
2. Commit with `scripts/committer "fix: <summary>" <files>`
3. Run gates: `scripts/pr-prepare gates <PR>`
4. Push: `scripts/pr-prepare push <PR>`
5. Verify: local HEAD sha == remote sha == `gh pr view --json headRefOid`

Output spec: `{baseDir}/references/prep-output.md`

Output: `PR is ready for /merge-pr`

### 3. Merge

Squash merge after review + prep artifacts exist.

```bash
scripts/pr-merge <PR>
```

Go/no-go:
- All findings resolved
- Gates green
- Branch not behind main
- Changelog updated

After merge:
- Verify state is MERGED (never CLOSED)
- Record merge SHA
- New contributor? Run `bun scripts/update-clawtributors.ts`
- Clean up worktree

## Maintainer Checkpoints

**Before prep** (after review):
- What problem are they solving?
- What is the optimal implementation?
- Can we fix everything, or does contributor need to update?

**Before merge** (after prep):
- Is this properly scoped and typed?
- Is existing logic reused (not duplicated)?
- Are tests real, not performative?
- Any security concerns?

## Rules

- Use `pnpm` for all tooling. Gates: `pnpm build`, `pnpm check`, `pnpm test`.
- Commit subjects: concise, action-oriented, no PR numbers (those go in merge commit).
- Merge commit: include `Co-authored-by:` for PR author and maintainer.
- Changelog is mandatory in this workflow.
- Process PRs oldest to newest (older = more likely to conflict).
- Max 3 gate fix-and-rerun cycles. After that, stop and report.
