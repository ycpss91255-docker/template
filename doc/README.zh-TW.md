# template

[![CI](https://github.com/ycpss91255-docker/template/actions/workflows/ci.yaml/badge.svg)](https://github.com/ycpss91255-docker/template/actions/workflows/ci.yaml)

GitHub Template 倉庫，用於在 [ycpss91255-docker](https://github.com/ycpss91255-docker) 組織下快速建立新的下游 repo。

**[English](../README.md)** | **[繁體中文](README.zh-TW.md)** | **[简体中文](README.zh-CN.md)** | **[日本語](README.ja.md)**

---

## 快速開始

1. 在 GitHub 上點擊 **"Use this template"**（或執行以下指令）：

   ```bash
   gh repo create ycpss91255-docker/<repo_name> \
     --template ycpss91255-docker/template --public --clone
   cd <repo_name>
   ```

2. 執行 bootstrap：

   ```bash
   ./bootstrap.sh            # 使用最新的 base tag
   # 或
   ./bootstrap.sh v0.34.1    # 指定版本
   ```

3. 開始開發：

   ```bash
   make build    # 建置 Docker 映像
   make run      # 啟動容器
   ```

## bootstrap.sh 做了什麼

1. 移除 template 專屬檔案（本 README、CI workflow、測試）
2. 將 `.base/` 重建為正式的 git subtree
3. 執行 `.base/init.sh` 產生完整的 repo 骨架（Dockerfile、symlinks、設定、smoke test、文件）
4. 刪除自己

Bootstrap 完成後，repo 就是標準的下游 repo。使用 `make upgrade` 拉取未來的 `.base/` 更新。

## 為什麼需要 bootstrap

GitHub Template 複製檔案時不帶 git 歷史。`.base/` subtree 需要 merge metadata 才能支援 `git subtree pull` 升級。`bootstrap.sh` 透過重新加入 `.base/` 作為真正的 subtree 來解決此問題。
