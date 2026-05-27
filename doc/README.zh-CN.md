# template

[![CI](https://github.com/ycpss91255-docker/template/actions/workflows/ci.yaml/badge.svg)](https://github.com/ycpss91255-docker/template/actions/workflows/ci.yaml)

GitHub Template 仓库，用于在 [ycpss91255-docker](https://github.com/ycpss91255-docker) 组织下快速创建新的下游 repo。

**[English](../README.md)** | **[繁体中文](README.zh-TW.md)** | **[简体中文](README.zh-CN.md)** | **[日本语](README.ja.md)**

---

## 快速开始

1. 在 GitHub 上点击 **"Use this template"**（或执行以下命令）：

   ```bash
   gh repo create ycpss91255-docker/<repo_name> \
     --template ycpss91255-docker/template --public --clone
   cd <repo_name>
   ```

2. 执行 bootstrap：

   ```bash
   ./bootstrap.sh            # 使用最新的 base tag
   # 或
   ./bootstrap.sh v0.34.1    # 指定版本
   ```

3. 开始开发：

   ```bash
   make build    # 构建 Docker 镜像
   make run      # 启动容器
   ```

## bootstrap.sh 做了什么

1. 移除 template 专属文件（本 README、CI workflow、测试）
2. 将 `.base/` 重建为正式的 git subtree
3. 执行 `.base/init.sh` 生成完整的 repo 骨架（Dockerfile、symlinks、配置、smoke test、文档）
4. 删除自己

Bootstrap 完成后，repo 就是标准的下游 repo。使用 `make upgrade` 拉取未来的 `.base/` 更新。

## 为什么需要 bootstrap

GitHub Template 复制文件时不带 git 历史。`.base/` subtree 需要 merge metadata 才能支持 `git subtree pull` 升级。`bootstrap.sh` 通过重新添加 `.base/` 作为真正的 subtree 来解决此问题。
