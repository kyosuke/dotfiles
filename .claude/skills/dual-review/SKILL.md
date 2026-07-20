---
name: dual-review
description: Codex と Antigravity（agy）で並列コードレビューし、統合結果を提示する。明らかな問題は修正し、判断が要る指摘はユーザーに諮る。
---

# Dual Review（Codex + Antigravity 並列レビュー）

Codex CLI と Antigravity CLI（`agy`）で同時にコードレビューし、結果を統合して提示する。

## 1. レビュー対象を決める

`$ARGUMENTS` にベースブランチ指定があればそれを、なければ `main` を使う。

```bash
git diff --stat <base>...HEAD
```

ブランチ差分がなければ未コミットの変更を対象にする。`git status --short` でステージ済み・未ステージ・untracked を確認し、いずれかがあればそれをレビューする。何もなければユーザーに確認する。

## 2. 2系統を並列で走らせる

Codex と agy を**同時に**起動する（1つのメッセージで両方の Bash を呼ぶ）。どちらも Bash の timeout は 600000（ミリ秒。10分）にし、停滞・タイムアウトした側は結果なしとして扱ってもう一方だけで進める。

**Codex**（リポジトリを自分で読む）:

```bash
codex review --base <base>     # ブランチ差分
codex review --uncommitted     # 未コミットを対象にする場合
```

**Antigravity（agy）**（diff をプロンプトに直接渡す）:

```bash
agy -p --print-timeout 10m "以下は git diff の出力です。この diff の内容だけを根拠にコードレビューし、バグ・ロジックエラー、セキュリティ、パフォーマンス、型安全性、テストカバレッジの欠落の観点で分析してください。各指摘は severity（critical / warning / note）、file（パスと行番号）、issue、suggestion（あれば）の形式で報告し、ツールは使わず与えられたテキストのみで判断すること。

$(git diff <base>...HEAD)"
```

agy にはリポジトリを読ませず、diff を直接渡す。ヘッドレスの `agy -p` はツール承認をその場で得られず無出力で止まるため、自己完結したテキストだけで判断させる。`$(...)` はシェルが実行時に展開するので、diff は Claude のコンテキストには載らない（コスト増にならない）。

未コミットを対象にする場合は `$(git diff <base>...HEAD)` を `$(git diff HEAD)` に置き換える（ステージ済みと未ステージの両方を含む）。untracked files は `git diff` に出ないため、レビューが必要なら次のように内容を追記する。Codex 側は `--uncommitted` がステージ済み・未ステージ・untracked をまとめて扱う。

```bash
$(git diff HEAD; git ls-files --others --exclude-standard | while read -r f; do echo "--- new file: $f ---"; cat "$f"; done)
```

## 3. 統合して提示

- **重複排除**: 同じファイル・同じ問題を指す指摘はまとめる
- **出典**: 各指摘に `[Codex]` `[agy]` `[両方]` のラベルを付ける
- **severity 順**: critical → warning → note の順で並べる
- **番号付き**: ユーザーが「3番と5番を修正して」と指定できるようにする

## 4. 修正

統合結果を次の2つに分けて対応する。

- **自動修正する**: 明らかなバグ・セキュリティ・型エラーなど、直すべきことが明確な指摘
- **ユーザーに諮る**: トレードオフのある変更（パフォーマンス対可読性など）、設計方針に関わる指摘、指摘自体の妥当性が分かれるもの

修正時は指摘を鵜呑みにせず自分で妥当性を検証し、該当箇所のみ変更する。自動修正した内容と判断を仰ぐ内容は分けて報告する。
