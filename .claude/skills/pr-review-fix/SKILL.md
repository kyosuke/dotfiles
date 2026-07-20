---
name: pr-review-fix
description: PRのレビューコメントを確認し、妥当な指摘を修正してコメント返信・Resolve・サマリー提示を行う
disable-model-invocation: true
argument-hint: [pr-number]
allowed-tools: Bash(gh *) Bash(git *) Read Edit Write Grep Glob Agent
---

# PR レビューコメント対応

対象 PR: #$ARGUMENTS

## コンテキスト収集

次を実行して PR の状態を把握する。

1. PR 概要:
```bash
gh pr view $ARGUMENTS --json title,body,headRefName,baseRefName
```

2. レビューコメント一覧:
```bash
gh api repos/{owner}/{repo}/pulls/$ARGUMENTS/comments --jq '.[] | "id=\(.id) path=\(.path) line=\(.original_line) in_reply_to=\(.in_reply_to_id // "none") user=\(.user.login)\n\(.body)\n---"'
```

3. レビュースレッドの Resolve 状態（owner/repo は `gh repo view --json owner,name` で取得）:
```bash
gh api graphql -f query='{ repository(owner: "<OWNER>", name: "<REPO>") { pullRequest(number: $ARGUMENTS) { reviewThreads(first: 50) { nodes { id isResolved comments(first: 1) { nodes { id body path line } } } } } } }'
```

4. PR のブランチに checkout:
```bash
gh pr checkout $ARGUMENTS
```

## 対応手順

1. **未解決コメントを特定する**: Resolved 済みのスレッドはスキップする
2. **妥当性を判断する**: 実際のコードを読み、指摘が妥当かを判断する
3. **妥当な指摘を修正する**
4. **副作用を確認する**: 該当箇所の全体を読み直し、修正で重複や不整合（文章なら重複した主張、コードなら重複コードや不要になった分岐）が生じていないか見る。整合性のための修正はとくに重複を生みやすい。問題があれば直す
5. **コミットする**
6. **返信して Resolve する**: 下のフォーマットで返信し、スレッドを Resolve する
7. **妥当でない指摘**: 理由を簡潔にコメントし、Resolve はしない

## 返信

コメントへの返信:
```bash
gh api repos/{owner}/{repo}/pulls/$ARGUMENTS/comments/<COMMENT_ID>/replies -f body='<返信内容>'
```

スレッドの Resolve:
```bash
gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "<THREAD_ID>"}) { thread { isResolved } } }'
```

返信フォーマット。修正した場合（コメントの主が AI なら前置きの挨拶は不要）:
```
<commit-url> で対応しました。
```

修正不要と判断した場合は、理由を簡潔に説明する。

## push とサマリー

対応が完了したら変更を push する。

```bash
git push
```

最後に、全コメントの対応をユーザーに提示する。

| コメント | ファイル | 対応 |
|---------|--------|------|
| 指摘内容の要約 | ファイルパス:行番号 | 修正済み / 修正不要（理由） |
