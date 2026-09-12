# Omaplug 1.5.1

## Fixed

- Secured runtime state, cache, lock, installer, and keep-open writes against symlink and replacement races.
- Replaced PID-directory locking with exclusive OS-managed locks.
- Added bounded, supervised helper processes and consistent XDG configuration paths.
- Fixed nested bar-widget removal so host layouts retain remaining widgets and failures stop the disable operation.
- Kept installer completion status separate from untrusted command output.

## Tests

- Added behavioral nested-widget regression coverage.
- Added isolated filesystem safety regressions.
- Full shell and Quickshell test suite passes locally.
