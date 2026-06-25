# ProjectStock — iPhone QR 在庫管理アプリ

プロジェクト単位で部品・製品・備品・試作品・消耗品を管理し、QRラベルを貼って
iPhoneでスキャンしながら入出庫・移動・棚卸しを行う、App Store 公開可能な iOS
アプリです。データは **Core Data + NSPersistentCloudKitContainer** に保存され、
iCloud 経由で **プロジェクト単位** にチーム共有できます。外部サーバー・独自ログイン・
解析/広告SDK・第三者ライブラリは一切使用していません。

> 仕様書 `ios_qr_inventory_master_prompt_ja.md` の MVP 要件をすべて実装しています。

---

## 主な機能

- **プロジェクト / フォルダ / 製品 / 保管場所（任意階層）** の管理
- **数量管理** と **個体管理（StockUnit）** の 2 モード
- **追跡可能な在庫イベント台帳**（receive / consume / adjust / transfer / checkout / return / create / retire / correction）。数量は台帳から再計算でき、`cachedQuantity` は表示用キャッシュにすぎません。
- **AVFoundation QR スキャナ**（iOS 15 / iPhone SE 第1世代対応、Micro QR は対応端末で受付）
- **空QRの先刷り・後付け登録**（未割当ラベルを一括生成 → 現場で貼って後から紐付け）
- **コンテナQRと一括移動**（箱・棚の中身をまとめて別の場所へ）
- **QR ラベル書き出し**: 透過 PNG / ベクター PDF / 自前生成のベクター EPS（+ SVG 構造）
- **QR Fit（読取信頼性）エンジン**: モジュール寸法・Quiet Zone・DPI から推奨/注意/非推奨を提示
- **印刷校正シート**（複数サイズ・誤り訂正比較・Quiet Zone 警告例・チェック欄）
- **iCloud 同期 & プロジェクト共有**（CKShare / UICloudSharingController、読み取り専用権限を UI に反映）
- **オフライン動作**と分かりやすい同期状態表示（ローカルのみ / 同期中 / オフライン / エラー…）
- **活動履歴**・低在庫表示・サンプルデータ生成・JSON 書き出し・診断ログ共有

---

## 動作要件 / 技術スタック

| 項目 | 値 |
|---|---|
| Deployment Target | **iOS 15.0**（iPhone SE 第1世代を含む） |
| 提出ビルド | **Xcode 26 / iOS 26 SDK 以上** |
| UI | SwiftUI（iOS15非対応APIはAvailabilityまたはUIKitラッパー） |
| 永続化 | Core Data + `NSPersistentCloudKitContainer`（Private + Shared の2ストア） |
| 共有 | CloudKit / `CKShare` / `UICloudSharingController` |
| スキャン | AVFoundation（`AVCaptureSession` / `AVCaptureMetadataOutput`） |
| QR生成 | Core Image `CIQRCodeGenerator` → 独自 `QRCodeMatrix` |
| 描画 | Core Graphics / UIKit / ImageIO / UniformTypeIdentifiers |
| アーキテクチャ | MVVM + Repository/Service |
| 依存 | Apple 標準フレームワークのみ |

---

## セットアップ

このリポジトリには Xcode プロジェクトが含まれます。プロジェクトファイルは
スキャンベースのジェネレータ `Scripts/generate_pbxproj.py` で生成しており、
ファイルを追加したら再生成できます。

```bash
# 1. プロジェクトを開く
open ProjectStock.xcodeproj

# 2. （任意）自分の Apple Developer 情報を設定する
cp Config.xcconfig.example Config.xcconfig
#   → Config.xcconfig を編集（Bundle ID / Team ID / CloudKit Container ID）
#   設定の反映方法は CLOUDKIT_SETUP.md を参照
```

> **Simulator ビルドは資格情報なしでそのまま通ります。** 既定の Bundle ID /
> CloudKit Container ID はプレースホルダ値がプロジェクトに埋め込まれています。
> 実機・iCloud・共有を使うには Apple Developer アカウントの設定が必要です
> （`CLOUDKIT_SETUP.md`）。

### ビルド & テスト（Mac / Xcode 26）

```bash
# Simulator 向けクリーンビルド
xcodebuild -project ProjectStock.xcodeproj -scheme ProjectStock \
  -destination 'platform=iOS Simulator,name=iPhone 15' build

# Unit / UI テスト
xcodebuild -project ProjectStock.xcodeproj -scheme ProjectStock \
  -destination 'platform=iOS Simulator,name=iPhone 15' test
```

UI テストは `-uiTesting` 起動引数で in-memory ストア + モックスキャナに切り替わるため、
iCloud アカウントや実機カメラなしで実行できます。

### プロジェクトファイルの再生成

```bash
python3 Scripts/generate_pbxproj.py
```

---

## ディレクトリ構成

```
ProjectStock/
  App/            アプリ起動・AppDelegate（CKShare受諾）・Info.plist・entitlements
  Persistence/    2ストアCloudKitコンテナ / StoreRouter / 同期モニタ / エラーマッパ
  Model/          Core Dataモデル(.xcdatamodeld) と NSManagedObject サブクラス, enum
  Services/       コード生成 / 在庫台帳 / プロジェクト / 階層 / 棚卸し / 書き出し
  QR/             QRエンコード・行列・PNG/PDF/EPS/SVG・読取評価・各種シート
  Scanner/        AVFoundationスキャナ / 結果ルーティング / 権限
  Sharing/        CKShareサービス / UICloudSharingController ラッパー
  Settings/       端末ID / アプリ設定
  Utilities/      設定読取 / 画像縮小 / 触覚 / 色
  ViewModels/     QR Studio など
  Views/          SwiftUI 画面群（Projects / Products / Scan / QR / Activity / Settings）
  Resources/      Assets.xcassets（AppIcon 1024px / AccentColor / Launch色）
ProjectStockTests/      Unit テスト
ProjectStockUITests/    UI テスト
Scripts/                pbxproj ジェネレータ
docs/                   App Store 用文言など
```

詳細な設計は `ARCHITECTURE.md` を参照してください。

---

## 既知の制限 / 警告について

- **App Icon は 1024px の生成済みアイコンを同梱**しています（ブランドQRモチーフ／透過なし）。
  `python3 Scripts/generate_app_icon.py` で再生成でき、独自デザインに差し替える場合は
  `APP_STORE_CHECKLIST.md` を参照してください。
- **初回起動時のオンボーディング**を実装済み（4ページのウェルカム＋サンプル生成）。
  設定 →「使い方をもう一度見る」で再表示できます。
- CloudKit 本番スキーマの Deploy、TestFlight での 2 Apple ID 共有、実機での印刷読取
  などは Apple Developer アカウント / 実機が必要です。手順は各ドキュメントに記載しています。
- 数量は精度よりも実装簡潔性を優先して `Double` で保持しています（仕様で許容）。
  小数在庫が必要な場合の桁あふれには注意してください。

---

## ドキュメント

| ファイル | 内容 |
|---|---|
| `ARCHITECTURE.md` | レイヤ構成・2ストア戦略・在庫台帳・QRパイプライン |
| `CLOUDKIT_SETUP.md` | iCloud コンテナ作成・資格情報・本番スキーマ Deploy 手順 |
| `APP_STORE_CHECKLIST.md` | 提出前チェックリスト・アイコン差し替え・審査メモ |
| `TEST_PLAN.md` | Unit / UI / 手動実機テスト計画 |
| `PRIVACY_POLICY_JA.md` | プライバシーポリシー（日本語・完全版） |
| `docs/APP_STORE_COPY_JA.md` | 説明文・キーワード・権限説明の草案 |
