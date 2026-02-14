# Prep Output Spec

## .local/prep.md must include

```
prep_head_sha=<sha>
push_branch=<branch>
pushed_head_sha=<sha>
push_verified=yes

PR: #<PR>
Contributor: @<author>

Changes made:
- ...

Gates:
- pnpm build: PASS
- pnpm check: PASS
- pnpm test: PASS
```
