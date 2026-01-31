/reviewpr

Input
- PR: <number|url>
  - If missing: ALWAYS ask. Never auto-detect from conversation.
  - If ambiguous: ask.

DO (review only)
Goal: produce a thorough review and a clear recommendation (READY for /preparepr vs NEEDS WORK). Do NOT merge, do NOT push, do NOT make code changes that you intend to keep.

EXECUTION RULE (CRITICAL)
- EXECUTE THIS COMMAND. DO NOT JUST PLAN.
- After you print the TODO checklist, immediately continue and run the shell commands.
- If you delegate to a subagent, the subagent MUST run the commands and produce real outputs, not a plan.

Known failure modes (read this)
- If you see "fatal: not a git repository", you are in the wrong directory. The repo is at ~/Development/openclaw, not ~/openclaw.
- Do not stop after printing the checklist. That is not completion.

Writing style for all output
- casual, direct
- no em dashes or en dashes, ever
- use commas or separate sentences instead

Safety
- Do NOT stop or kill the gateway. Do not run gateway stop commands, do not kill processes on port 18792.

Completion criteria
- You ran the commands in the worktree and inspected the PR, you are not guessing.
- You produced the structured review A through H.
- You saved the full review to .local/review.md inside the worktree.

## First: Create a TODO checklist
Create a checklist of all review steps. Print it. Then keep going and execute.

## Setup: Use a Worktree

All review work happens in an isolated worktree.

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

# Local scratch space that persists across /reviewpr -> /preparepr -> /mergepr
mkdir -p .local
```

From here on, ALL commands run inside the worktree directory.

0) Claim the PR first
Assign yourself so others know someone is reviewing.

```sh
gh_user=$(gh api user --jq .login)
gh pr edit <PR> --add-assignee "$gh_user"
```

1) Identify PR meta and context

```sh
gh pr view <PR> --json number,title,state,isDraft,author,baseRefName,headRefName,headRepository,url,body,labels,assignees,reviewRequests,files,additions,deletions --jq '{number,title,url,state,isDraft,author:.author.login,base:.baseRefName,head:.headRefName,headRepo:.headRepository.nameWithOwner,additions,deletions,files:.files|length,body}'
```

2) Check if this already exists in main (before looking at PR branch)
You are currently on origin/main in the worktree.

- Identify the core feature or fix.
- Search for existing implementations.

```sh
# Prefer rg if available
rg -n "<relevant_keyword>" -S src packages apps ui || true

# Or grep
grep -R "<relevant_keyword>" src/ --include="*.ts" || true

git log --oneline --all --grep="<related keyword>" | head -20
```

If it already exists, call it out as a BLOCKER or at least IMPORTANT.

3) Read the PR description carefully
Use the body from step 1. Summarize goal, scope, and missing context.

4) Read the diff thoroughly

Minimum:
```sh
gh pr diff <PR>
```

If you need full code context locally, fetch the PR head to a local ref and diff it, do not create a merge commit.

```sh
git fetch origin pull/<PR>/head:pr-<PR>
# See changes without modifying the working tree

git diff --stat origin/main..pr-<PR>
git diff origin/main..pr-<PR>
```

If you want to browse the PR version of files directly, you may temporarily check out pr-<PR> in the worktree, but do not commit, do not push.
Afterwards, return to temp/pr-<PR> and reset to origin/main.

```sh
# Optional, only if needed
# git checkout pr-<PR>
# ...inspect files...

git checkout temp/pr-<PR>
git reset --hard origin/main
```

5) Validate the change is needed and valuable
Be honest. Call out low value AI slop.

6) Evaluate implementation quality
Correctness, design, performance, ergonomics.

7) Security review (do not skip)
OpenClaw run with access to user tools, files, messages, and APIs.
Check auth, input validation, secrets, dependencies, tool safety, privacy.

8) Tests and verification
What exists, what is missing, and what would be a minimal regression test.

9) Key question
Can /preparepr fix the issues ourselves, or does the contributor need to update the PR.

10) Save findings to the worktree (MANDATORY)
Write the full structured review (sections A through H) to:
- .local/review.md

EXECUTE THIS, DO NOT JUST SAY YOU DID IT:
- Use your file write tool to create or overwrite .local/review.md.
- Then verify it exists and is non empty.

```sh
ls -la .local/review.md
wc -l .local/review.md
```

This is required so /preparepr and /mergepr can read it.

11) Output (structured)
Produce a review with these sections, and make it match what you saved to .local/review.md.

A) TL;DR recommendation
- One of: READY FOR /preparepr | NEEDS WORK | NEEDS DISCUSSION | NOT USEFUL (CLOSE)
- 1 to 3 sentences.

B) What changed

C) What's good

D) Security findings

E) Concerns / questions (actionable)
- Numbered list
- Mark each item as BLOCKER, IMPORTANT, or NIT
- For each, point to file or area and propose a concrete fix

F) Tests

G) Follow ups (optional)

H) Suggested PR comment (optional)

Guardrails
- Worktree only
- Do not delete the worktree after review
- Review only, do not merge, do not push
