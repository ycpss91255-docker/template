# Changelog

## [Unreleased]

### Fixed
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
- Initial release
