# Vine レビュー下書き自動生成ツール

Amazon Vine の「レビューを書く」ページからレビュー待ち商品を自動取得し、
ChatGPT に毎回商品名をコピペしていた作業を Claude API で自動化するツールです。
生成されたレビュー下書きは `data/reviews/` にどんどん溜まっていきます。

**自動でやらないこと**: Amazonへのレビュー投稿そのもの（規約違反になるため）。
生成された下書きを自分で確認して、コピペで投稿してください。

## 仕組み

```
fetch（商品リスト取得） → memo（感想メモ入力） → generate（レビュー生成） → data/reviews/ に蓄積
```

メモ入力のステップがあるのは意図的です。プロンプト自体が
「ユーザーのメモを最優先」「言っていないことを勝手に作らない」という方針なので、
実際の感想メモなしでレビューを生成すると中身が捏造になってしまいます。
商品名のコピペは不要になり、メモと星だけ入れれば済む形になります。

## セットアップ（初回のみ）

ローカルPC（ブラウザが開ける環境）で実行してください。

```bash
cd vine-review
pip install -r requirements.txt
playwright install chromium
export ANTHROPIC_API_KEY=sk-ant-...   # https://console.anthropic.com で取得
```

## 使い方

### 1. レビュー待ち商品を取得

```bash
python vine_review.py fetch
```

- Chromiumが開きます。**初回だけ**Amazonにログインしてください（最大5分待ちます）。
  ログイン情報は `data/browser-profile/` に保存され、2回目以降は自動です。
- レビュー待ち商品が `data/queue.json` に追加されます（既存分は保持・マージ）。

### 2. 状態を確認

```bash
python vine_review.py list
```

```
[pending  ] B0ABC12345  星未設定 / メモ未入力  ワイヤレスイヤホン Bluetooth5.3 ...
[generated] B0XYZ67890  星4 / メモあり  前髪カーラー ヘアクリップ ...
```

### 3. 使った感想をメモ

```bash
python vine_review.py memo B0ABC12345 --stars 4 "接続は速い。低音は控えめ。通勤で3日使った。ケースが少し大きい"
```

雑な箇条書きでOK。プロンプト側が自然なレビュー文に整えます。

### 4. レビュー生成

```bash
python vine_review.py generate            # メモ入力済みの未生成分をまとめて生成
python vine_review.py generate --asin B0ABC12345   # 1件だけ
python vine_review.py generate --force    # 生成済みでも作り直す（メモを直したときなど）
```

生成結果は `data/reviews/YYYYMMDD_ASIN.md` に保存されます。
タイトルと本文はコードブロックで出力されるので、そのままコピペできます。

## プロンプトの調整

レビューの文体ルールは `prompt.md` にそのまま入っています（ChatGPTプロジェクトで使っていたもの）。
言い回しの癖を直したいときは `prompt.md` を編集して `generate --force` で再生成してください。

## 設定

| 環境変数 | 説明 | デフォルト |
|---|---|---|
| `ANTHROPIC_API_KEY` | Claude APIキー（必須） | — |
| `VINE_MODEL` | 使用モデル | `claude-opus-4-8` |

## トラブルシューティング

- **商品が0件になる**: Amazonのページ構造が変わった可能性があります。
  `data/debug_page.html` が保存されるので、それを添えて相談してください。
- **毎回ログインを求められる**: `data/browser-profile/` を消してしまっていないか確認。
- **`data/` はgit管理外です**（ログイン情報・生成物を含むため）。バックアップしたい場合は
  `data/reviews/` だけ別の場所にコピーしてください。
