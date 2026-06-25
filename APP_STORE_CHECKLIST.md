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

## 7. リリース

- [ ] Archive → App Store Connect へアップロード
- [ ] TestFlight で 2 Apple ID 共有・印刷読取を最終確認
- [ ] App Store 用説明文 / キーワード（`docs/APP_STORE_COPY_JA.md`）を登録
