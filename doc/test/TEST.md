# TEST.md

**14 tests** total.

## test/smoke/template-v0.41_env.bats (1)

| Test | Description |
|------|-------------|
| `entrypoint.sh exists and is executable` | Entrypoint check |

## test/integration/bootstrap_spec.bats (13)

Drives the real `bootstrap.sh` against a bare fake `base` remote seeded
with annotated tags spanning both base layouts (`init.sh` at the subtree
root pre-v0.42.0, `dist/script/base/init.sh` after), a pre-release tag, a
tag carrying no `init.sh` at all, and a tag whose `init.sh` creates files
and then fails. No network access required.

| Test | Description |
|------|-------------|
| `bootstrap.sh v0.9.7: rebuilds subtree, runs init.sh, self-deletes` | Full run against an explicit pre-dist tag |
| `bootstrap.sh (no arg): picks latest tag from remote` | Default path: highest released tag, not the peeled `^{}` row, not a pre-release |
| `a completed bootstrap dangles no symlink and leaves just --list working` | What "it worked" means to the user: wrappers resolve, `just` runs |
| `bootstrap.sh v0.10.0 (dist layout): resolves dist/script/base/init.sh` | v0.42.0+ layout reaches step 5 |
| `bootstrap.sh v0.9.5 (pre-dist layout): still resolves the root init.sh` | Old layout is not broken by the resolution |
| `bootstrap.sh prefers the dist init.sh when a tag ships both layouts` | Candidate ordering |
| `bootstrap.sh fails naming both paths when no init.sh exists` | Error names every candidate tried |
| `bootstrap.sh fails fast when git identity is missing` | Guard before any mutation |
| `bootstrap.sh refuses to run when subtree history already exists` | Re-bootstrap guard |
| `bootstrap.sh refuses when .base/ holds an ignored file, and changes nothing` | Precondition fires before any mutation; repo untouched and still bootstrappable |
| `bootstrap.sh refuses when .base/ holds an untracked file, and changes nothing` | Same guard, non-ignored path |
| `a failure after step 2 has committed rolls the repo all the way back` | Rollback: commit undone, created paths swept, user's files kept, re-runnable |
| `after bootstrap at v0.9.5, subtree pull to v0.9.7 succeeds` | Subtree history is intact for upgrades |
