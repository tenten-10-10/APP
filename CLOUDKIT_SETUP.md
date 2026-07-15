# CLOUDKIT_SETUP — iCloud / CloudKit セットアップ手順

Simulator でローカル動作させるだけなら設定不要です（CloudKit は無効のまま動きます）。
**実機での iCloud 同期・プロジェクト共有**を使うには、Apple Developer アカウントで
以下を設定します。

---

## 0. 必要なもの

- 有料の Apple Developer Program メンバーシップ
- Xcode 26 以上 / 実機（iOS 15 以上）少なくとも 1 台、共有テストには 2 つの Apple ID

---

## 1. 資格情報を Config.xcconfig に設定

```bash
cp Config.xcconfig.example Config.xcconfig
```

`Config.xcconfig` を編集:

```
PRODUCT_BUNDLE_IDENTIFIER     = com.yourcompany.projectstock
APP_DISPLAY_NAME              = ProjectStock
DEVELOPMENT_TEAM              = ABCDE12345          # 10桁 Team ID
CLOUDKIT_CONTAINER_IDENTIFIER = iCloud.com.yourcompany.projectstock
MARKETING_VERSION             = 1.0.0
CURRENT_PROJECT_VERSION       = 1
```

### この値をビルドに反映する方法（いずれか）

`Config.xcconfig` は秘匿情報を含むため git 管理外です。プロジェクトには既定の
プレースホルダ値が直接埋め込まれているので、自分の値を使うには次のどちらかを行います。

- **方法A（推奨・GUI）**: Xcode で `ProjectStock` プロジェクト →
  *Info* タブ → *Configurations* → Debug/Release の *Based on Configuration File* に
  `Config.xcconfig` を選択。
- **方法B（手動）**: ターゲットの Build Settings で
  `PRODUCT_BUNDLE_IDENTIFIER` / `DEVELOPMENT_TEAM` / `CLOUDKIT_CONTAINER_IDENTIFIER` /
  `APP_DISPLAY_NAME` / `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` を直接編集。

`Info.plist` / `*.entitlements` はこれらの変数を `$(…)` で参照しているため、
ビルド時に自動的に展開されます。

---

## 2. Signing & Capabilities

Xcode でアプリターゲット → *Signing & Capabilities*:

1. **Team** を選択（Automatically manage signing を有効）。
2. **iCloud** を追加 → **CloudKit** にチェック → コンテナに
   `iCloud.com.yourcompany.projectstock` を選択（または `+` で新規作成）。
3. **Background Modes** を追加 → **Remote notifications** にチェック
   （`UIBackgroundModes` と `aps-environment` は同梱の Info.plist / entitlements に既に記載）。
4. **Push Notifications** を追加（CloudKit のサイレントプッシュに必要）。

> 同梱の `ProjectStock/App/ProjectStock.entitlements` には
> `com.apple.developer.icloud-container-identifiers`,
> `com.apple.developer.icloud-services = [CloudKit]`,
> `aps-environment = development` が含まれています。コンテナ ID は
> `$(CLOUDKIT_CONTAINER_IDENTIFIER)` で展開されます。

---

## 3. CloudKit スキーマの初期化（Development）

スキーマは Core Data モデルから自動生成されます。

1. 実機（iCloud にサインイン済み）でアプリを一度起動し、
   プロジェクト・製品・在庫イベントを数件作成します。
2. `NSPersistentCloudKitContainer` が Development 環境にレコードタイプ
   （`CD_Project`, `CD_Product`, … と `cloudkit.share`）を作成します。
3. [CloudKit Console](https://icloud.developer.apple.com/) → 対象コンテナ →
   *Schema* で生成されたレコードタイプを確認します。

> 開発中にモデルを変更したら、Development 環境の該当レコードタイプを削除・再生成するか、
> 互換性のある軽量マイグレーションを行ってください。

---

## 4. 本番（Production）へのスキーマ Deploy

App Store / TestFlight 配布前に必須です。

1. CloudKit Console → 対象コンテナ → **Deploy Schema Changes…**
2. Development のスキーマを **Production** へ反映。
3. Production に必要なレコードタイプ・インデックス（特に共有関連）が揃っているか確認。

> アプリのリリースビルドは Production 環境を使います。Deploy を忘れると
> 「同期できない」状態になります。

---

## 5. 共有のテスト（2 つの Apple ID）

1. 端末 A（Apple ID #1）でプロジェクトを作成 → *共有* セグメント →
   「このプロジェクトを共有」→ `UICloudSharingController` でリンクを送信。
2. 端末 B（Apple ID #2）でリンクを開く → アプリが招待を受諾し、Shared Store に取り込み。
3. 端末 B 側で *読み取り専用 / 編集可* の権限が UI に反映されることを確認。
4. 双方でオフライン編集 → オンライン復帰で両方の在庫イベントが加算されることを確認。

---

## 6. よくあるエラーと対処

| 症状 | 原因 / 対処 |
|---|---|
| 「iCloudにサインインしていません」 | 設定アプリで iCloud にサインイン。 |
| 「iCloudの容量が不足しています」 | iCloud ストレージを確保。 |
| 共有リンクが取得できない | ネットワーク確認後に再試行（自動リトライ）。Production スキーマ未 Deploy も要確認。 |
| 参加者側でデータが出ない | 招待受諾が Shared Store に入っているか、Push 権限と Background Modes を確認。 |
| レコードタイプが見つからない | Development → Production の Deploy 漏れ。 |

すべての CloudKit エラーは `CloudKitErrorMapper` が日本語短文へ変換し、
*設定 → 診断ログ* で原文と最近の import/export イベントを確認できます。
