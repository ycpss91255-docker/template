# TEST.md

**19 tests** total.

## test/smoke/template-v0.41_env.bats (2)

| Test | Description |
|------|-------------|
| `entrypoint.sh is installed and executable` | Entrypoint present + executable |
| `bash is available on PATH` | bash resolvable on PATH |

## test/integration/bootstrap_spec.bats (17)

Drives the real `bootstrap.sh` against a bare fake `base` remote seeded
with annotated tags spanning both base layouts (`init.sh` at the subtree
root pre-v0.42.0, `dist/script/base/init.sh` after), a pre-release tag, a
tag carrying no `init.sh` at all, and a tag whose `init.sh` creates files
and then fails. The `init.sh` stubs model the one branch the real script
takes on the way in -- `-f Dockerfile` as its "already set up" proxy --
and install the new-repo scaffold on the other side of it, so the specs
can assert what the resulting repo CONTAINS. No network access required.

| Test | Description |
|------|-------------|
| `bootstrap.sh v0.9.7: rebuilds subtree, runs init.sh, self-deletes` | Full run against an explicit pre-dist tag |
| `bootstrap.sh: init.sh takes the new-repo path, not the existing-repo path` | The `-f Dockerfile` branch: no template Dockerfile survives to invert it |
| `bootstrap.sh: the new repo has build CI, a changelog and a smoke tree` | What `_create_new_repo` installs is actually present |
| `bootstrap.sh: the Dockerfile comes from the bootstrapped tag, not the template` | Provenance: byte-identical to the landed subtree's copy |
| `bootstrap.sh (dist layout): the new-repo scaffold lands there too` | Same two properties against the v0.42.0 layout |
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
