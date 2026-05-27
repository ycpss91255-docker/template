# template

[![CI](https://github.com/ycpss91255-docker/template/actions/workflows/ci.yaml/badge.svg)](https://github.com/ycpss91255-docker/template/actions/workflows/ci.yaml)

[ycpss91255-docker](https://github.com/ycpss91255-docker) 組織配下に新しいダウンストリームリポジトリを素早く作成するための GitHub Template リポジトリ。

**[English](../README.md)** | **[繁體中文](README.zh-TW.md)** | **[简体中文](README.zh-CN.md)** | **[日本語](README.ja.md)**

---

## クイックスタート

1. GitHub で **"Use this template"** をクリック（またはコマンドを実行）：

   ```bash
   gh repo create ycpss91255-docker/<repo_name> \
     --template ycpss91255-docker/template --public --clone
   cd <repo_name>
   ```

2. bootstrap を実行：

   ```bash
   ./bootstrap.sh            # 最新の base タグを使用
   # または
   ./bootstrap.sh v0.34.1    # バージョンを指定
   ```

3. 開発を開始：

   ```bash
   make build    # Docker イメージをビルド
   make run      # コンテナを起動
   ```

## bootstrap.sh の動作

1. テンプレート固有のファイルを削除（この README、CI ワークフロー、テスト）
2. `.base/` を正式な git subtree として再構築
3. `.base/init.sh` を実行してリポジトリの完全なスキャフォールドを生成（Dockerfile、シンボリックリンク、設定、スモークテスト、ドキュメント）
4. 自身を削除

bootstrap 完了後、リポジトリは標準のダウンストリームリポジトリになります。`make upgrade` で将来の `.base/` の更新を取得できます。

## bootstrap が必要な理由

GitHub Template はファイルをコピーする際に git 履歴を含めません。`.base/` subtree はアップグレード用の `git subtree pull` をサポートするためにマージメタデータが必要です。`bootstrap.sh` は `.base/` を本物の subtree として再追加することでこの問題を解決します。
