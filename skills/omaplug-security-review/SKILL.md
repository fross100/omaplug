---
name: omaplug-security-review
description: Review Omaplug security before committing or pushing, or review its Marketplace verification request using the local public-review checklist.
---

# Omaplug security review

Read the complete repository-root file
`omarchy-plugin-verify-security-review-public.md` before reviewing. Resolve it
relative to this skill as `../../omarchy-plugin-verify-security-review-public.md`.
It is intentionally gitignored; never stage or force-add it. If unavailable,
report `Incomplete` and stop before commit/push rather than inventing a review.

## Select the review mode

- **Marketplace verification:** follow the document's remote-only, read-only
  procedure unchanged, including exact-SHA evidence and label rules. Do not run
  submitted code or make GitHub mutations during that review.
- **Before commit:** apply its security checklist to the exact staged candidate
  tree and the complete runtime, including callers and sibling paths. Local
  read-only inspection replaces the document's remote-only evidence requirement.
  Record HEAD and staged diff/tree identity. Unstaged fixes do not count as fixes
  in the candidate. Report unstaged/untracked code that affects test validity.
- **Before push:** review the exact outgoing commits and final tree against the
  intended destination. Record full SHAs, check earlier findings and claimed
  fixes, and refresh relevant Marketplace comments when available. A pre-commit
  review is reusable only for unchanged content; inspect changes since it.

For local modes, pending remote validation for an unpublished commit is not by
itself a blocker to publishing a corrective commit. Mark remote approval as
pending/not applicable; never transfer Marketplace approval from an older SHA.
Missing evidence required for the local security decision means `Incomplete`.

## Local review gate

Keep the review itself read-only. Apply the document's trust-boundary,
filesystem, process, network, QML, IPC, and supply-chain checks. Trace every
earlier finding through the proposed fix; look for the same flaw in related
paths. Review tests as evidence, not proof of safety.

Ordinary authorized development tests may run separately using isolated
fixtures and reviewed commands. Do not install/update/remove real plugins or
change the user's shell to obtain review evidence without authorization.

Report concrete findings by severity with file/line, affected candidate,
impact, minimal fix, and a check that would prove the fix. Distinguish reproduced
failures, source-level findings, missing evidence, and untested behavior.

Return `Pass`, `Blocked`, or `Incomplete` for the local operation. Unresolved
security findings block commit/push; disclose unrelated correctness findings
and whether they affect readiness. Do not silently waive blockers. A pass is
not a security certification and does not itself authorize commit or push.

Immediately before an authorized commit/push, confirm the reviewed staged tree
or outgoing SHAs have not changed. Re-review changed content. Do not post
comments, edit issues, apply labels, or trigger releases as part of this gate.
