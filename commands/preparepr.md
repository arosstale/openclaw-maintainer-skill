/preparepr

Input
- PR: <number|url>
  - If missing: ALWAYS ask. Never auto-detect from conversation.
  - If ambiguous: ask.

⚠️ CRITICAL: NEVER KILL OR STOP THE OpenClaw GATEWAY
- Do NOT run gateway stop commands.
- Do NOT kill processes.
- Do NOT touch port 18792.
- The gateway is what is running you. Killing it kills your own session.

DO (prep only)
Goal: make the PR branch clean on top of main, fix issues from /reviewpr, run gates, commit fixes, and push back to the PR branch. Do NOT merge to main during this command.

EXECUTION RULE (CRITICAL)
- EXECUTE THIS COMMAND. DO NOT JUST PLAN.
- After you print the TODO checklist, immediately continue and run the shell commands.
- The previous failure mode was: printed a checklist and stopped. Do not do that.
- If you delegate to a subagent, the subagent MUST run the commands and produce real outputs.

Known footguns
- Repo path is ~/Development/openclaw. If you cd into ~/openclaw you will get "not a git repository".
- Do not run git clean -fdx, it would delete .local/ artifacts.

Completion criteria
- You rebased the PR commits onto origin/main.
- You fixed all BLOCKER and IMPORTANT items from .local/review.md.
- You ran gates and they passed.
- You committed any prep changes.
- You pushed the updated HEAD back to the PR head branch.
- You saved a prep summary to .local/prep.md.
- Final output is exactly: PR is ready for /mergepr

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
- Resolve
- git add -A
- git rebase --continue

If the rebase gets confusing, stop and report.

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

5) Run full gates (BEFORE pushing)

```sh
pnpm install
pnpm lint
pnpm build
pnpm test
```

All must pass. If something fails, fix and rerun until green.

6) Commit any fixes you made during prep

Preferred:
```sh
committer "fix: <summary> (#<PR>) (thanks @$contrib)" <changed files>
```

If committer is not available, use git commit.

7) Push updates back to the PR head branch

```sh
# Ensure remote for PR head exists
git remote add prhead "$head_repo_url.git" 2>/dev/null || git remote set-url prhead "$head_repo_url.git"

# Force with lease is required after rebase
git push --force-with-lease prhead HEAD:$head
```

8) Verify PR is not behind main (MANDATORY)
After pushing, confirm the PR branch includes latest main. If this fails, repeat steps 2 through 7.

```sh
git fetch origin main
git fetch origin pull/<PR>/head:pr-<PR>-verify --force
git merge-base --is-ancestor origin/main pr-<PR>-verify && echo "PR is up to date with main" || echo "ERROR: PR is still behind main, rebase again"
git branch -D pr-<PR>-verify 2>/dev/null || true
```

If the PR is still behind main, do NOT proceed. Re-fetch, rebase, and push again.

9) Write prep summary artifacts (MANDATORY)
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

10) Output
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
- Do not run gh pr merge
