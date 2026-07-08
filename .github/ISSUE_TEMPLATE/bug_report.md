---
name: Bug report
about: Report a reproducible Thor issue
title: "[Bug]: "
labels: bug
assignees: ""
---

## Summary
Describe the bug clearly.

## Environment
- OS:
- Bash version: `bash --version`
- Thor version: `thor --version`
- Dalfox version: `dalfox version`
- Installation method: zip / git clone / other

## Command used
```bash
thor scan example.com --authorized
```

## Expected behavior
What should have happened?

## Actual behavior
What happened instead?

## Relevant logs
Paste sanitized output from:

```bash
cat results/<domain>/<timestamp>/logs.txt
cat results/<domain>/<timestamp>/dalfox_error.log
cat results/<domain>/<timestamp>/report.json
```

## Safety confirmation
- [ ] I removed cookies, tokens, API keys, and private target data from this issue.
- [ ] The target was authorized or a local lab asset.
