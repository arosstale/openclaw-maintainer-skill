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
Goal: make the PR branch clean on top of main, fix issues from /reviewpr, run gates, commit fixes, and push back to the PR branch. Do NOT merge to main during this command.

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
- You saved a prep summary to .local/prep.md.
- Final output is exactly: PR is ready for /mergepr

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
head_repo_url=$(gh pr view <PR> --json headRepository --jq .headRepository.url)
```

2) Fetch the PR branch tip into a local ref

```sh
git fetch origin pull/<PR>/head:pr-<PR>
```

3) Rebase PR commits onto latest main

```sh
# Move worktree to the PR tip first
git reset --hard pr-<PR>

# Rebase onto current main
git fetch origin main
git rebase origin/main
```

If conflicts happen:
- Resolve each conflicted file
- `git add <resolved_file>` for each file (do NOT use `git add -A`)
- `git rebase --continue`

If the rebase gets confusing or you have resolved conflicts 3+ times, stop and report.

4) Fix issues from .local/review.md
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

5) Update CHANGELOG.md (if flagged in review)

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

6) Update docs (if flagged in review)

Check .local/review.md section G for docs guidance. If the review flagged missing or outdated docs:
- Update only the docs directly related to the PR changes
- Keep scope tight, do not rewrite unrelated docs

If the review did not flag docs, skip this step.

7) Commit any fixes you made during prep

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

8) Run full gates (BEFORE pushing)

Gates run on the committed state, which is what will be pushed.

```sh
pnpm install
pnpm lint
pnpm build
pnpm test
```

All must pass. If something fails, fix, commit the fix, and rerun.
MAX 3 ATTEMPTS. If gates still fail after 3 fix-and-rerun cycles, stop and report the failures. Do not loop indefinitely.

9) Push updates back to the PR head branch

IMPORTANT: You are pushing to the PR's head branch, NEVER to main.
If the PR is from a fork, you need push access to the fork repo. If push fails with permission denied, stop and report.

```sh
# Ensure remote for PR head exists
git remote add prhead "$head_repo_url.git" 2>/dev/null || git remote set-url prhead "$head_repo_url.git"

# Force with lease is required after rebase
# Double check: $head must NOT be "main" or "master"
echo "Pushing to branch: $head"
if [ "$head" = "main" ] || [ "$head" = "master" ]; then
  echo "ERROR: head branch is main/master. This is wrong. Stopping."
  exit 1
fi
git push --force-with-lease prhead HEAD:$head
```

10) Verify PR is not behind main (MANDATORY)
After pushing, confirm the PR branch includes latest main. If this fails, repeat steps 2 through 9.

```sh
git fetch origin main
git fetch origin pull/<PR>/head:pr-<PR>-verify --force
git merge-base --is-ancestor origin/main pr-<PR>-verify && echo "PR is up to date with main" || echo "ERROR: PR is still behind main, rebase again"
git branch -D pr-<PR>-verify 2>/dev/null || true
```

If the PR is still behind main, do NOT proceed. Re-fetch, rebase, and push again.

11) Write prep summary artifacts (MANDATORY)
Update .local/prep.md with:
- current HEAD sha (git rev-parse HEAD)
- a short bullet list of what you changed
- gate results
- push confirmation
- rebase verification result (up to date with main: yes/no)

EXECUTE THIS, DO NOT JUST SAY YOU DID IT:
- Use your file write tool to create or overwrite .local/prep.md.
- Then verify it exists and is non empty.

```sh
git rev-parse HEAD
ls -la .local/prep.md
wc -l .local/prep.md
```

12) Output
Include a diff stat summary showing lines added vs removed. Run:
```sh
git diff --stat origin/main..HEAD
git diff --shortstat origin/main..HEAD
```

Report the total: X files changed, Y insertions(+), Z deletions(-)

- If gates passed and push succeeded, print exactly:
  PR is ready for /mergepr
- Otherwise, list remaining failures and stop.

Rules
- Worktree only
- Do not delete the worktree on success, /mergepr may reuse it
- Do not run `gh pr merge`
- NEVER push to main. Only push to the PR head branch.
- All gates must pass before pushing. No pushing broken code.
