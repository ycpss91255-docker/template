# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `migrate.sh`: README auto-update for `docker_setup_helper → docker_template` references
- `CHANGELOG.md`

## [v0.1.0] - 2026-03-28

### Added
- **Shared shell scripts**: `build.sh`, `run.sh` (with X11/Wayland support), `exec.sh`, `stop.sh`
- **setup.sh**: `.env` generator merged from `docker_setup_helper` (auto-detect UID/GID, GPU, workspace path, image name)
- **Config files**: bashrc, tmux, terminator, pip configs from `docker_setup_helper`
- **Shared smoke tests** (`smoke_test/`):
  - `script_help.bats` — 16 tests for script help/usage
  - `display_env.bats` — 10 tests for X11/Wayland environment (GUI repos)
  - `test_helper.bash` — unified bats loader
- **Template self-tests** (`test/`): 114 tests with ShellCheck + Bats + Kcov coverage
- **CI reusable workflows**:
  - `build-worker.yaml` — parameterized Docker build + smoke test
  - `release-worker.yaml` — parameterized GitHub Release
  - `self-test.yaml` — template's own CI
- **`migrate.sh`**: batch migration script for converting repos from `docker_setup_helper` to `docker_template`
- `.hadolint.yaml`: shared Hadolint rules
- `.codecov.yaml`: coverage configuration
- Documentation: README (English), README.zh-TW.md, README.zh-CN.md, README.ja.md, TEST.md

### Changed
- `setup.sh` default `_base_path` traverses 1 level up (`/..`) instead of 2 (`/../..`) to match new `docker_template/setup.sh` location

### Migration notes
- Consumer repos replace `docker_setup_helper/` subtree with `docker_template/` subtree
- Shell scripts at root become symlinks to `docker_template/`
- Local `build-worker.yaml` / `release-worker.yaml` replaced by reusable workflow calls in `main.yaml`
- Dockerfile `CONFIG_SRC` path changes: `docker_setup_helper/src/config` → `docker_template/config`
- Shared smoke tests loaded via `COPY docker_template/smoke_test/` in Dockerfile (not symlinks — Docker COPY does not follow symlinks)

[Unreleased]: https://github.com/ycpss91255-docker/docker_template/compare/v0.1.0...HEAD
[v0.1.0]: https://github.com/ycpss91255-docker/docker_template/releases/tag/v0.1.0
