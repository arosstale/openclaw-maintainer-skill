/preparepr

Input
- PR: <number|url>
  - If missing: ALWAYS ask. Never auto-detect from conversation.
  - If ambiguous: ask.

SAFETY (read before doing anything)
- NEVER push to `main` or `origin/main`. All pushes go to the PR head branch only.
- NEVER run `git push` without specifying the remote and branch explicitly. No bare `git push`.
- Do NOT run gateway stop commands. Do NOT kill processes. Do NOT touch port 18792. The gateway is what is running you.

DO (prep only)
Goal: make the PR branch clean on top of main, fix issues from /reviewpr, run gates, commit fixes, and push back to the PR head branch.
Do NOT merge to main during this command.

EXECUTION RULE (CRITICAL)
- EXECUTE THIS COMMAND. DO NOT JUST PLAN.
- After you print the TODO checklist, immediately continue and run the shell commands.
- The previous failure mode was: printed a checklist and stopped. Do not do that.
- If you delegate to a subagent, the subagent MUST run the commands and produce real outputs.

Known footguns
- Repo path is ~/Development/openclaw. If you cd into ~/openclaw you will get "not a git repository".
- Do not run `git clean -fdx`, it would delete .local/ artifacts.
- Do not run `git add -A` or `git add .` blindly. Always stage specific files you changed.

Completion criteria
- You rebased the PR commits onto origin/main.
- You fixed all BLOCKER and IMPORTANT items from .local/review.md.
- You ran gates and they passed.
- You committed any prep changes.
- You pushed the updated HEAD back to the PR head branch.
- You VERIFIED the push by comparing local HEAD sha vs the remote branch sha and gh PR head sha.
- You saved a prep summary to .local/prep.md.
- Final output is exactly: PR is ready for /mergepr

**CRITICAL**
- The push step is NOT optional.
- Do not write "PR is ready for /mergepr" unless push verification succeeded.

## Step 0: Verify gh auth

```sh
gh auth status
```
If this fails, stop and report. Do not proceed without valid GitHub auth.

## First: Create a TODO checklist
Create a checklist of all prep steps. Print it. Then keep going and execute.

## Setup: Use a Worktree

All prep work happens in an isolated worktree.

```sh
cd ~/Development/openclaw
# Sanity: confirm you are in the repo
git rev-parse --show-toplevel

PR=<PR>
WORKTREE_DIR=".worktrees/pr-$PR"
WORKTREE_BRANCH="pr/$PR"

git fetch origin main

# Reuse existing worktree if it exists, otherwise create new
if [ -d "$WORKTREE_DIR" ]; then
  cd "$WORKTREE_DIR"
  git checkout "$WORKTREE_BRANCH" 2>/dev/null || git checkout -b "$WORKTREE_BRANCH"
  git fetch origin main
  git reset --hard origin/main
else
  git worktree add "$WORKTREE_DIR" -b "$WORKTREE_BRANCH" origin/main
  cd "$WORKTREE_DIR"
fi

mkdir -p .local

# Sanity, from here on, ALL commands run inside the worktree
pwd
```

From here on, ALL commands run inside the worktree directory.

## Load Review Findings (MANDATORY)

```sh
if [ -f .local/review.md ]; then
  echo "Found review findings from /reviewpr"
else
  echo "Missing .local/review.md. Run /reviewpr first and save findings."
  exit 1
fi

# Actually read it
sed -n '1,200p' .local/review.md
```

Use .local/review.md to drive what you fix, especially the Concerns section.

## Steps

1) Identify PR meta (author, head branch, head repo URL)

```sh
gh pr view <PR> --json number,title,author,headRefName,baseRefName,headRepository,body --jq '{number,title,author:.author.login,head:.headRefName,base:.baseRefName,headRepo:.headRepository.nameWithOwner,body}'
contrib=$(gh pr view <PR> --json author --jq .author.login)
head=$(gh pr view <PR> --json headRefName --jq .headRefName)
base=$(gh pr view <PR> --json baseRefName --jq .baseRefName)
head_repo_url=$(gh pr view <PR> --json headRepository --jq .headRepository.url)

# Safety, never target main branches
if [ -z "$head" ]; then
  echo "ERROR: could not determine PR headRefName"
  exit 1
fi
if [ "$head" = "main" ] || [ "$head" = "master" ] || [ "$base" != "main" ]; then
  echo "ERROR: unexpected head/base branch, refusing to proceed"
  echo "head=$head"
  echo "base=$base"
  exit 1
fi
```

2) Configure a remote that points at the PR head repo

```sh
# Ensure remote for PR head exists
# gh returns the repo URL without .git most of the time
prhead_url="$head_repo_url.git"

git remote add prhead "$prhead_url" 2>/dev/null || git remote set-url prhead "$prhead_url"
# Optional, helps debugging
(git remote -v | rg '^prhead\s') || true
```

3) Fetch the PR head branch tip

This is the commit we must update and push back to.

```sh
# Update origin main
git fetch origin main

# Fetch the PR head branch from the PR head repo
git fetch prhead "$head"

# Also keep a local snapshot via the upstream pull ref, useful for comparisons
git fetch origin pull/<PR>/head:pr-<PR> --force
```

4) Rebase PR commits onto latest main

```sh
# Move worktree to the PR head commit
git reset --hard "prhead/$head"

# Rebase onto current main
git rebase origin/main
```

If conflicts happen:
- Resolve each conflicted file
- `git add <resolved_file>` for each file (do NOT use `git add -A`)
- `git rebase --continue`

If the rebase gets confusing or you have resolved conflicts 3+ times, stop and report.

5) Fix issues from .local/review.md
Requirements:
- Fix all BLOCKER and IMPORTANT items.
- NITs optional.
- Keep scope tight, no drive by refactors.

As you fix things, keep a running log in:
- .local/prep.md
Include:
- which review items you fixed
- what files you touched
- any behavior changes

6) Update CHANGELOG.md (if flagged in review)

Check .local/review.md section H for changelog guidance. If the review flagged a missing changelog entry:

```sh
# Check if CHANGELOG.md exists
ls CHANGELOG.md 2>/dev/null
```

If it exists and the PR is user-facing (feature, fix, breaking change):
- Read the existing format and follow it
- Add an entry under the appropriate section (Added, Changed, Fixed, Removed)
- Reference the PR number and contributor
- Keep the entry concise, one line

If the review did not flag changelog, skip this step.

7) Update docs (if flagged in review)

Check .local/review.md section G for docs guidance. If the review flagged missing or outdated docs:
- Update only the docs directly related to the PR changes
- Keep scope tight, do not rewrite unrelated docs

If the review did not flag docs, skip this step.

8) Commit any fixes you made during prep

Stage only the specific files you changed (never `git add -A` or `git add .`):
```sh
git add <file1> <file2> ...
```

Preferred commit tool (OpenClaw CLI tool, available on this machine):
```sh
committer "fix: <summary> (#<PR>) (thanks @$contrib)" <changed files>
```

If `committer` is not found, fall back to:
```sh
git commit -m "fix: <summary> (#<PR>) (thanks @$contrib)"
```

9) Run full gates (BEFORE pushing)

Gates run on the committed state, which is what will be pushed.

```sh
pnpm install
pnpm format:fix
pnpm lint
pnpm build
pnpm test
```

All must pass. If something fails, fix, commit the fix, and rerun.
MAX 3 ATTEMPTS. If gates still fail after 3 fix-and-rerun cycles, stop and report the failures. Do not loop indefinitely.

10) **PUSH AND VERIFY** (MANDATORY, DO NOT SKIP)

You must push the updated HEAD to the PR head branch and verify it landed.

If the PR is from a fork, you need push access to the fork repo.
If push fails with permission denied, stop and report.

```sh
# Safety, never push to main
if [ "$head" = "main" ] || [ "$head" = "master" ]; then
  echo "ERROR: head branch is main/master. This is wrong. Stopping."
  exit 1
fi

local_sha=$(git rev-parse HEAD)
echo "local_sha=$local_sha"
echo "Pushing to: prhead $head"

# Force with lease is required after rebase
git push --force-with-lease prhead HEAD:"$head"

# Verify remote branch sha matches local sha
remote_sha=$(git ls-remote prhead "refs/heads/$head" | awk '{print $1}' | head -n 1)
pr_sha=$(gh pr view <PR> --json headRefOid --jq .headRefOid)

echo "remote_sha=$remote_sha"
echo "pr_sha=$pr_sha"

if [ -z "$remote_sha" ]; then
  echo "ERROR: could not read remote sha for prhead/$head"
  exit 1
fi

if [ "$remote_sha" != "$local_sha" ]; then
  echo "ERROR: push verification failed, remote branch sha does not match local HEAD"
  exit 1
fi

if [ "$pr_sha" != "$local_sha" ]; then
  echo "ERROR: push verification failed, gh PR head sha does not match local HEAD"
  echo "This usually means the push did not land, or gh is pointing at a different head repo"
  exit 1
fi

echo "push_verified=yes"
```

**STOP** if verification fails. Do not proceed, do not claim success.

11) Verify PR is not behind main (MANDATORY)

After pushing, confirm the PR head commit includes latest main.

```sh
git fetch origin main

# Use the verified PR head sha from gh
# If this fails, repeat steps 3 through 10
git merge-base --is-ancestor origin/main "$pr_sha" && echo "PR is up to date with main" || (echo "ERROR: PR is still behind main, rebase again" && exit 1)
```

12) Update review.md verdict (MANDATORY)

After all gates pass and push is verified, update .local/review.md so /mergepr knows the blockers were resolved.

Replace the first line that starts with `**NEEDS WORK**` or `**NOT USEFUL**` or `**NEEDS DISCUSSION**` with `**APPROVED (post-prep)** - All blockers resolved during /preparepr. Gates passing, push verified.`

If review.md already says `**APPROVED**` or `**GOOD TO MERGE**`, leave it as is.

Use your file edit tool to make this change. Then verify:
```sh
head -5 .local/review.md
```

13) Write prep summary artifacts (MANDATORY)

Write a prep summary to .local/prep.md.

It MUST include these machine readable lines near the top so /mergepr can verify:
- prep_head_sha=<sha>
- push_branch=<branch>
- pushed_head_sha=<sha>
- push_verified=yes

Template you can copy, then fill in the bullets:

```md
prep_head_sha=<REPLACE_WITH_LOCAL_SHA>
push_branch=<REPLACE_WITH_HEAD_BRANCH>
pushed_head_sha=<REPLACE_WITH_LOCAL_SHA>
push_verified=yes

PR: #<PR>
Contributor: @$contrib
Pushed to: $head_repo_url ($head)

Changes made
- ...

Gates
- pnpm lint: PASS
- pnpm build: PASS
- pnpm test: PASS

Rebase status
- up to date with main: yes
```

EXECUTE THIS, DO NOT JUST SAY YOU DID IT:
- Use your file write tool to create or overwrite .local/prep.md.
- Then verify it exists and is non empty.

```sh
git rev-parse HEAD
ls -la .local/prep.md
wc -l .local/prep.md
```

14) Return the MAIN repo checkout to main (best effort)

This is only to avoid confusing editor sync states. Do not destroy local work.

```sh
cd ~/Development/openclaw

# Only switch if there are no tracked changes
if git diff --quiet && git diff --cached --quiet; then
  git switch main 2>/dev/null || git checkout main || true
else
  echo "NOTE: ~/Development/openclaw has local changes, not switching branches"
  git status -sb || true
fi
```

15) Output

Include a diff stat summary showing lines added vs removed. Run:
```sh
final_sha=$(git -C "$WORKTREE_DIR" rev-parse HEAD)
git -C "$WORKTREE_DIR" diff --stat origin/main..$final_sha
git -C "$WORKTREE_DIR" diff --shortstat origin/main..$final_sha
```

Report the total: X files changed, Y insertions(+), Z deletions(-)

- If gates passed AND push_verified=yes, print exactly:
  PR is ready for /mergepr
- Otherwise, list remaining failures and stop.

Rules
- Worktree only
- Do not delete the worktree on success, /mergepr may reuse it
- Do not run `gh pr merge`
- NEVER push to main. Only push to the PR head branch.
- All gates must pass before pushing. No pushing broken code.
