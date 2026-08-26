# Changelog

## [Unreleased]

### Fixed
- `bootstrap.sh` removes the template's `Dockerfile` along with the other
  template-specific files. `init.sh` branches on `[[ -f Dockerfile ]]` as
  its proxy for "this repo has been set up before", so leaving it behind
  sent every newly created repo down the existing-repo path: no
  `.github/workflows/main.yaml`, no `doc/changelog/CHANGELOG.md` and no
  smoke tree. The template's copy is redundant -- `init.sh` installs a
  `Dockerfile` from the target base tag, while the template's is a
  snapshot of whatever base shipped when it last synced (#13).
- `bootstrap.sh` refuses to start when `.base/` holds a file git does not
  track, naming the offending paths. `git rm -r` removes tracked files
  only, so one untracked or ignored file (`.base/.env` and friends, which
  `just setup` / `just build` generate) survived step 2, `git subtree add`
  then refused the existing prefix, and the failure landed after step 2
  had committed.
- `bootstrap.sh` rolls back when a step fails after step 2 has committed:
  the repo returns to its pre-bootstrap commit, the files the aborted run
  created are swept, and `bootstrap.sh` is still there and still
  runnable. It used to leave a repo that was neither the template nor a
  bootstrapped repo, with dangling wrapper symlinks and a precondition
  that the previous run itself had broken (#10, same shape as
  ycpss91255-docker/base#915).
- `bootstrap.sh` resolves `init.sh` inside the subtree instead of naming
  it: `dist/script/base/init.sh` (base v0.42.0+) first, then `init.sh`
  (pre-dist), failing with both paths named when neither exists. A
  no-argument bootstrap resolves to the latest base tag, so it had been
  dying at step 4 and leaving the new repo with a subtree and no
  generated scaffolding (ycpss91255-docker/base#916).
- `bootstrap.sh` no longer resolves the latest tag to the peeled
  `vX.Y.Z^{}` row that `git ls-remote` lists for annotated tags, which
  `git subtree add` rejects as a ref, and skips pre-release tags.
- `bootstrap.sh` advertises `just upgrade` / `just base upgrade` per
  installed layout, instead of the `make upgrade` wrapper base dropped in
  v0.41.0.

### Added
- Integration coverage for `bootstrap.sh` across both base layouts, a
  pre-release tag, and a subtree carrying no `init.sh`.
- Integration coverage for what `init.sh` actually installed -- the build
  CI, the changelog, the smoke tree, and the `Dockerfile`'s provenance --
  rather than only that `bootstrap.sh` exited 0.
- Initial release
