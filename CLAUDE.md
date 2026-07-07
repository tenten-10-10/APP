# タナミル / ProjectStock — 開発メモ（毎セッション必読）

SwiftUI製のQR在庫管理iOSアプリ（Core Data + CloudKit 3ストア構成）。
恒久ナレッジは `docs/DEV_NOTES_JA.md` に集約。**リリース/審査まわりを触る前に
必ず §3 を読むこと。**

## ⛔ リリース事故を繰り返さないための鉄則（最優先）

**「TestFlight」と「App Store審査（review）」は完全に別物。混同するな。**

- **TestFlight** = ベータ配信（テスター向け）。一般ユーザーには出ない。
- **App Store審査（review）** = 一般公開のための審査。ここでの
  取り下げ/提出は**取り返しがつかない**（キャンセルすると審査待ちの列は
  最後尾に戻り、失った時間は復元不能）。

過去の実害（1.2.51）: 「1.3.0を**テストフライトから**取り下げて1.2.51を
あげて」を審査操作と誤解し、`release.yml` を実行。**審査中だった1.2.11を
却下**してしまった。ユーザーの意図はTestFlightビルドのexpireだった。

→ **「取り下げ／あげて／出して」は曖昧語。対象が TestFlight なのか
App Store審査 なのかを、reject/submit のような不可逆操作の前に必ず確認する。**

## ワークフロー対応表（どれを回すと何が起きるか）

| 目的 | ワークフロー / レーン | 影響範囲 |
| --- | --- | --- |
| ビルドしてTestFlightに上げる | `testflight.yml` / `beta` | TestFlightのみ |
| App Store審査に提出（＝一般公開へ） | `release.yml` / `release` | **審査中の版を却下し得る（不可逆）** |
| 特定バージョンのTestFlightビルドをexpire | `expire-build.yml` / `expire_train version:X.Y.Z` | TestFlightのみ（審査に触れない） |

- `release` レーンは `reject_if_possible: true` + `automatic_release: true`。
  = 審査中の版を却下して最新TestFlightビルドを提出、承認後は自動公開。
  **軽々に回さない。** どの版が審査中かを把握してから。
- ビルドはアップロード直後だと処理未完。`release` 前に約20〜25分待つ。
- CIの `conclusion:success` を鵜呑みにせず、ログで
  `Uploaded build N` / `Successfully submitted the app for review!` /
  `Expired ... TestFlight build(s)` を必ず確認する。

## バージョン・ブランチ

- `MARKETING_VERSION` の単一ソースは `Scripts/generate_pbxproj.py`
  （＋ `Config.xcconfig.example`）。ビルド番号はfastlaneが自動採番。
- 開発ブランチは指定されたfeatureブランチのみに積む（勝手にmain等へ出さない）。

## その他の必読ポイント（詳細は docs/DEV_NOTES_JA.md）

- CloudKit同期・共有の地雷（§9）: 本番の `cloudkit.share` / `CD_moveReceipt` 型。
- iOS15制約（§4）: alert内TextField不可→シート方式、ToolbarContentBuilder
  直下の `if` は不可、巨大bodyは型チェックタイムアウト→計算プロパティに層分割。
- 「実装済みだが未配線」に注意（§10.6）。画面を作ったら呼び出し元まで通す。
