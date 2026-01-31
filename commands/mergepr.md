/mergepr

Input
- PR: <number|url>
  - If missing: ALWAYS ask. Never auto-detect from conversation.
  - If ambiguous: ask.

SAFETY (read before doing anything)
- The ONLY way code reaches main is `gh pr merge --squash`. No `git push` to main, ever.
- Do NOT run gateway stop commands. Do NOT kill processes. Do NOT touch port 18792.
- Do NOT run `git push` at all during merge. The only push-like operation is `gh pr merge`.

DO (merge only)
Goal: PR must end in GitHub state = MERGED (never CLOSED). Assumes /preparepr already ran.
Use gh pr merge with --squash.

EXECUTION RULE (CRITICAL)
- EXECUTE THIS COMMAND. DO NOT JUST PLAN.
- After you print the TODO checklist, immediately continue and run the shell commands.
- If you delegate to a subagent, the subagent MUST run the commands and produce real outputs.

Known footguns
- Repo path is ~/Development/openclaw.
- This command must read .local/review.md and .local/prep.md in the worktree. Do not skip.
- Cleanup must remove the real worktree directory .worktrees/pr-<PR>, not a different path.
- After cleanup, .local/ artifacts are gone. This is expected.

Completion criteria
- gh pr merge succeeded
- PR state is MERGED
- merge sha recorded
- cleanup only after successful merge

## Step 0: Verify gh auth

```sh
gh auth status
```
If this fails, stop and report. Do not proceed without valid GitHub auth.

## First: Create a TODO checklist
Create a checklist of all merge steps. Print it. Then keep going and execute.

## Setup: Use a Worktree

All merge work happens in an isolated worktree.

```sh
cd ~/Development/openclaw
# Sanity: confirm you are in the repo
git rev-parse --show-toplevel

WORKTREE_DIR=".worktrees/pr-<PR>"
git fetch origin main

# Reuse existing worktree if it exists, otherwise create new
if [ -d "$WORKTREE_DIR" ]; then
  cd "$WORKTREE_DIR"
  git checkout temp/pr-<PR> 2>/dev/null || git checkout -b temp/pr-<PR>
  git fetch origin main
  git reset --hard origin/main
else
  git worktree add "$WORKTREE_DIR" -b temp/pr-<PR> origin/main
  cd "$WORKTREE_DIR"
fi

mkdir -p .local
```

From here on, ALL commands run inside the worktree directory.

## Load local artifacts (MANDATORY)

These files should exist from earlier steps:
- .local/review.md from /reviewpr
- .local/prep.md from /preparepr

```sh
ls -la .local || true

if [ -f .local/review.md ]; then
  echo "Found .local/review.md"
  sed -n '1,120p' .local/review.md
else
  echo "Missing .local/review.md. Stop and run /reviewpr, then /preparepr."
  exit 1
fi

if [ -f .local/prep.md ]; then
  echo "Found .local/prep.md"
  sed -n '1,120p' .local/prep.md
else
  echo "Missing .local/prep.md. Stop and run /preparepr first."
  exit 1
fi
```

If review.md says NEEDS WORK, NEEDS DISCUSSION, or NOT USEFUL, stop.

## Steps

1) Identify PR meta

```sh
gh pr view <PR> --json number,title,state,isDraft,author,headRefName,baseRefName,headRepository,body --jq '{number,title,state,isDraft,author:.author.login,head:.headRefName,base:.baseRefName,headRepo:.headRepository.nameWithOwner,body}'
contrib=$(gh pr view <PR> --json author --jq .author.login)
head=$(gh pr view <PR> --json headRefName --jq .headRefName)
head_repo_url=$(gh pr view <PR> --json headRepository --jq .headRepository.url)
```

2) Sanity checks
Stop if any of these are true:
- PR is a draft
- required checks are failing
- branch is behind main

```sh
# Checks
gh pr checks <PR>

# Behind main?
git fetch origin main
git fetch origin pull/<PR>/head:pr-<PR>
git merge-base --is-ancestor origin/main pr-<PR> || echo "PR branch is behind main, run /preparepr"
```

If anything is failing or behind, stop and say to run /preparepr.

3) Merge PR (squash and delete branch)

If any checks are still running, use --auto to queue the merge:
```sh
# Check status first
check_status=$(gh pr checks <PR> 2>&1)
if echo "$check_status" | grep -q "pending\|queued"; then
  echo "Checks still running, using --auto to queue merge"
  gh pr merge <PR> --squash --delete-branch --auto
  echo "Merge queued. Monitor with: gh pr checks <PR> --watch"
else
  gh pr merge <PR> --squash --delete-branch
fi
```

If merge fails, report the error and stop. Do not retry in a loop.
If the PR needs changes beyond what /preparepr already did, stop and say to run /preparepr again.

4) Get merge sha

```sh
merge_sha=$(gh pr view <PR> --json mergeCommit --jq '.mergeCommit.oid')
echo "merge_sha=$merge_sha"
```

5) Optional: comment

```sh
gh pr comment <PR> --body "Merged via squash.

- Merge commit: $merge_sha

Thanks @$contrib!"
```

6) Verify PR state == MERGED

```sh
gh pr view <PR> --json state --jq .state
```

7) Cleanup worktree (only on success)
Only run cleanup if step 6 returned MERGED. Note: this deletes .local/ artifacts (review.md, prep.md).

```sh
cd ~/Development/openclaw

git worktree remove ".worktrees/pr-<PR>" --force

git branch -D temp/pr-<PR> 2>/dev/null || true
git branch -D pr-<PR> 2>/dev/null || true
```

Rules
- Worktree only
- Do not close PRs
- PR must end in MERGED state
- Only cleanup after merge success
- NEVER push to main. `gh pr merge --squash` is the only path to main.
- Do NOT run `git push` at all in this command.
