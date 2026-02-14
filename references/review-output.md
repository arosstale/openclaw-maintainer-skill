# Review Output Spec

## .local/review.md sections

A) TL;DR recommendation (1-3 sentences)
B) What changed
C) What's good
D) Security findings
E) Concerns — numbered, each marked BLOCKER | IMPORTANT | NIT, with file + fix
F) Tests — what exists, what's missing
G) Docs status
H) Changelog — needed? what category?
I) Follow-ups (optional)
J) Suggested PR comment (optional)

## .local/review.json minimum

```json
{
  "recommendation": "READY FOR /prepare-pr",
  "findings": [
    {"id":"F1","severity":"IMPORTANT","title":"...","area":"path","fix":"..."}
  ],
  "tests": {"ran":[],"gaps":[],"result":"pass"},
  "docs": "up_to_date|missing|not_applicable",
  "changelog": "required"
}
```
