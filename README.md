# template

[![CI](https://github.com/ycpss91255-docker/template/actions/workflows/ci.yaml/badge.svg)](https://github.com/ycpss91255-docker/template/actions/workflows/ci.yaml)

GitHub Template repository for bootstrapping new downstream repos in the [ycpss91255-docker](https://github.com/ycpss91255-docker) organization.

**[English](README.md)** | **[繁體中文](doc/README.zh-TW.md)** | **[简体中文](doc/README.zh-CN.md)** | **[日本語](doc/README.ja.md)**

---

## Quick Start

1. Click **"Use this template"** on GitHub (or run the command below):

   ```bash
   gh repo create ycpss91255-docker/<repo_name> \
     --template ycpss91255-docker/template --public --clone
   cd <repo_name>
   ```

2. Run bootstrap:

   ```bash
   ./bootstrap.sh            # uses latest base tag
   # or
   ./bootstrap.sh v0.34.1    # pin a specific version
   ```

3. Start developing:

   ```bash
   make build    # build the Docker image
   make run      # run the container
   ```

## What bootstrap.sh does

1. Removes template-specific files (this README, CI workflow, tests)
2. Re-establishes `.base/` as a proper git subtree
3. Runs `.base/init.sh` to generate the full repo scaffold (Dockerfile, symlinks, configs, smoke tests, docs)
4. Deletes itself

After bootstrap, the repo is a standard downstream repo. Use `make upgrade` to pull future `.base/` updates.

## Why is bootstrap needed?

GitHub Template repositories copy files without git history. The `.base/` subtree requires merge metadata to support `git subtree pull` for upgrades. `bootstrap.sh` bridges this gap by re-adding `.base/` as a real subtree.
