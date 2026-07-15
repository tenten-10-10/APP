# APP_STORE_CHECKLIST — 提出準備チェックリスト

## 1. アセット / 表示

- [x] **App Icon を同梱済み**
  - `ProjectStock/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`
    に 1024×1024（RGB・透過なし）の生成済みアイコンを配置しています。
  - 再生成・微調整は `python3 Scripts/generate_app_icon.py`（要 Pillow）。
  - [ ] 独自デザインに差し替える場合は、同じ 1024×1024 PNG（角丸・透過なし）で
    `AppIcon.png` を上書きしてください（Xcode 14+ の単一サイズ App Icon）。
- [x] Launch Screen（`Info.plist` の `UILaunchScreen`、`LaunchBackground` 色を使用）
- [x] Accent Color（`AccentColor` カラーセット）
- [ ] スクリーンショット（iPhone 6.7" / 6.5" / 5.5" など各サイズ）を撮影
      （`-uiTesting` でサンプルデータを使うと安定します）

## 2. バンドル設定

- [x] `CFBundleDisplayName` = `$(APP_DISPLAY_NAME)`
- [x] `NSCameraUsageDescription` =
      「QRコードを読み取り、在庫の確認・更新・移動を行うためにカメラを使用します。」
- [x] `NSPhotoLibraryUsageDescription`（製品写真用）
- [x] `ITSAppUsesNonExemptEncryption = false`（輸出コンプライアンス回避）
- [ ] `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` を更新（TestFlight 毎に build 番号 +1）
- [ ] Bundle ID / Team ID / CloudKit Container ID を自分の値に（`CLOUDKIT_SETUP.md`）

## 3. CloudKit

- [ ] Development スキーマを生成（実機で数件作成）
- [ ] **Production へ Deploy**（CloudKit Console、`CLOUDKIT_SETUP.md` §4）
- [ ] 2 つの Apple ID で共有（Owner / read-write / read-only）を確認

## 4. プライバシー

- [x] 外部解析 / 広告 SDK なし、第三者ライブラリなし
- [x] カメラ映像を保存しない / QR に個人情報・名称・Record ID を含めない
- [x] 端末 ID はアプリ内生成 UUID（広告識別子不使用）
- [x] 貸出先（借り手名）は任意入力の自由テキスト。ユーザーの iCloud にのみ保存し、
      運営者サーバーへは送信しません（収集なし）
- [x] 返却期限・有効期限の通知はすべて端末内で完結する**ローカル通知**
      （リモートプッシュやサーバー送信は行いません）
- [ ] **App Privacy（Nutrition Label）回答**:
  - データ収集: **なし**（運営者サーバーへ送信しない）。iCloud はユーザー自身のアカウント。
  - トラッキング: **なし**
- [ ] **Privacy Manifest**: 第三者 SDK がないため必須の理由 API 宣言は最小限。
      `UserDefaults` を使用するため、必要に応じて `PrivacyInfo.xcprivacy` に
      `NSPrivacyAccessedAPICategoryUserDefaults`（理由コード `CA92.1`）を追加。
- [ ] サポート URL / プライバシーポリシー URL を設定（現状 placeholder）

## 5. 審査メモ（Review Notes 草案）

```
本アプリは iPhone 用の在庫管理アプリです。外部サーバー・ログインはなく、データは
ユーザーの iCloud（プライベートDB）に保存されます。

確認手順:
1. 「プロジェクト」タブ右上の … →「サンプルを生成」でデモデータが1タップで作成されます。
2. 製品を開くと QR ラベルを作成・書き出し（PNG/PDF/EPS）できます。
3. 「スキャン」タブでカメラ権限を許可するとQRを読み取れます。
   カメラを拒否しても、サンプルデータの閲覧・編集・QR書き出しなど主要機能は確認できます。
4. iCloud共有: プロジェクト詳細の「共有」セグメントから、別Apple IDへ共有できます
   （実機 + iCloudサインインが必要）。
5. 個体管理の製品では「貸出」で借り手と返却期限を記録でき、期限超過はローカル通知で
   お知らせします（「スキャン」タブ右上 →「貸出中」で一覧表示）。通知の許可を求める
   ことがありますが、許可しなくても全機能を利用できます。
6. ロット管理の製品では、ロット（製造単位）ごとに数量・有効期限・QRラベルを管理できます。

QRには商品名や数量は含まれず、短い不透明IDのみを格納します。
```

- [ ] デモ用サンプル Project がワンタップ生成できることを確認（実装済み）
- [ ] カメラ拒否時でも他機能が使えることを確認（実装済み: 権限ゲート + 手動導線）

## 6. ビルド / 品質ゲート

- [ ] `xcodebuild ... build`（Simulator）がクリーンに通る
- [ ] `xcodebuild ... test`（Unit + UI）が通る
- [ ] 警告を可能な限り解消（残存警告は README に理由を記載）
- [ ] 提出ビルドで Debug メニューを無効化
      （本アプリは独立した Debug メニューを持ちません。診断ログは設定内に常設で、
       製品名・メモを含めない設計です）

## 7. リリース / TestFlight（手順）

事前に §2 のバンドル設定（Team ID / Bundle ID / CloudKit Container ID）と §3 の
CloudKit Production Deploy を済ませておきます。Mac + Xcode 26 で実施します。

1. **Signing**: Xcode の Target → Signing & Capabilities で実機 Team を選択し、
   「Automatically manage signing」を有効化。Capabilities に iCloud(CloudKit) /
   Push Notifications / Background Modes(Remote notifications) が付いていることを確認。
2. **aps-environment**: 配布ビルドでは `production` である必要があります。自動署名なら
   Xcode が配布用プロファイルに合わせて設定します（`ProjectStock.entitlements` の
   既定値は開発用 `development`）。
3. **バージョン**: `MARKETING_VERSION`（例 1.0.0）/ `CURRENT_PROJECT_VERSION`（build）を設定。
   TestFlight に上げるたびに build 番号を +1。
4. **Archive**: Scheme を Release・宛先を「Any iOS Device (arm64)」にして
   Product → Archive。
5. **アップロード**: Organizer → Distribute App → App Store Connect → Upload。
   （初回は App Store Connect でアプリレコード作成が必要。Bundle ID を一致させる）
6. **輸出コンプライアンス**: `ITSAppUsesNonExemptEncryption=false` 済みのため追加質問なし。
7. **TestFlight**: 内部テスターを追加し、配布。以下を実機で最終確認:
   - QR スキャン / ラベル印刷の読み取り（実紙）
   - 貸出 → 返却期限超過の**ローカル通知**着信（期限を直近に設定して確認）
   - ロットの数量更新・有効期限バッジ
   - 2 つの Apple ID でのプロジェクト共有（Owner / read-write / read-only）
8. **メタデータ**: App Store 用説明文 / キーワード（`docs/APP_STORE_COPY_JA.md`）を登録。

> ローカル通知のみを使用するため、Push 用の APNs キー設定は不要です（CloudKit 同期の
> サイレントプッシュは iCloud 権限で動作します）。
