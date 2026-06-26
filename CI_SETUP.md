# TestFlight 自動配信（GitHub Actions）セットアップ

`claude/confident-rubin-0np4rh` ブランチに **push するたびに**、自動で
ビルド → TestFlight へアップロードされます（手動実行も可）。
ワークフロー定義: `.github/workflows/testflight.yml`

以降、`fastlane beta` を手で叩く必要はありません。

---

## 手順1) GitHub に Secrets を4つ登録（最初の1回だけ）

GitHub の対象リポジトリ → **Settings → Secrets and variables → Actions → New repository secret** で以下を登録:

| Name | Value |
|---|---|
| `ASC_KEY_ID` | `CVBKLF5QY9` |
| `ASC_ISSUER_ID` | `635f0cac-3c33-47be-8f0b-3b0fece9f136` |
| `TANAMIRU_TEAM_ID` | `3FGX27GY77` |
| `ASC_KEY_P8_BASE64` | ↓のコマンド出力（.p8をbase64化したもの） |

`.p8` を base64 にしてクリップボードへコピー（Mac）:

```bash
base64 -i ~/private_keys/AuthKey_CVBKLF5QY9.p8 | pbcopy
```

→ そのまま `ASC_KEY_P8_BASE64` の値に貼り付け。

> Secrets は暗号化保存され、ログにも自動マスクされます。`.p8` 本体・`.env`・`Config.xcconfig` はリポジトリにコミットされません（`.gitignore` 済み）。

## 手順2) 修正とワークフローをコミット＆プッシュ

`~/tanamiru` で実行（ビルドを通すための修正8件＋生成器修正＋CI定義をまとめて反映）:

```bash
cd ~/tanamiru
git add -A
git commit -m "Fix iOS26/iOS15 build issues and add GitHub Actions TestFlight CI"
git push origin claude/confident-rubin-0np4rh
```

> Secrets 登録を**先に**済ませてから push してください（push で初回のCIが走るため）。
> push で認証を聞かれる場合は GitHub Desktop からの push でもOKです。

## これで自動化完了

- 以後 `git push`（このブランチ）するたびに、GitHub の **Actions** タブでビルドが走り、成功すると TestFlight に新ビルドが上がります（ビルド番号は自動採番）。
- 内部テストグループ「社内テスト」は自動配信ONなので、新ビルドはテスターへ自動配信されます。
- 手動で走らせたいときは Actions タブ → 「TestFlight」→ **Run workflow**。

## 進捗・失敗の確認

- GitHub → **Actions** タブ → 最新の実行ログ。
- 失敗時はそのログ（特に `Build & upload to TestFlight` ステップ）を見れば原因がわかります。貼ってもらえれば私が対応します。

## 補足

- ランナーは `macos-latest`（最新安定版 Xcode を自動選択）。iOS 26 SDK でビルド、iOS 15 以降向けにアーカイブします。
- 署名は App Store Connect APIキー＋クラウド署名（`-allowProvisioningUpdates`）。証明書の事前インストールは不要です。
- 非公開リポジトリの GitHub-hosted macOS ランナーはビルド時間が課金対象です。コストを抑えたい場合は、トリガーを「手動(workflow_dispatch)のみ」や「タグ push 時のみ」に変更できます（ご希望あれば変更します）。
