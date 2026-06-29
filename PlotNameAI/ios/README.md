# PlotName AI — iOS / iPadOS app

AI マンガ・プロット／ネーム（ネーム＝storyboard）生成アプリの SwiftUI 実装。
一行のアイデアから **Save the Cat ジャンル分類 → 13フェーズ構造 → 35ページのページプラン → コマ割り → セリフ** を生成し、iPad では「ネームキャンバス」でコマを編集できます。

完全オフライン（Mock AI プロバイダー）で全画面が動作します。バックエンドや API キーは不要です。

## 必要環境

- Xcode 16 以降
- iOS / iPadOS 17 以降
- [XcodeGen](https://github.com/yonyz/XcodeGen)（`brew install xcodegen`）

外部 Swift Package 依存はありません。使用フレームワークはすべて標準：**SwiftUI / PDFKit / PencilKit（将来用）/ StoreKit2（将来用）**。

## プロジェクトの生成と起動

```bash
cd ios
xcodegen generate          # project.yml から PlotNameAI.xcodeproj を生成
open PlotNameAI.xcodeproj   # Xcode で開く
# ターゲット PlotNameAI を iPhone / iPad シミュレータで Run
```

`xcodegen` を入れたくない場合は、Xcode で「iOS App」テンプレートから新規プロジェクトを作り、`PlotNameAI/` 以下のファイル群を追加しても動作します（Bundle ID: `com.plotname.ai`、Deployment Target: iOS 17、Universal）。

## アーキテクチャ

- **適応レイアウト** — iPhone は `NavigationStack`（企画フロー）、iPad / regular 幅は 3 カラム `NavigationSplitView`（左: チャット/フェーズ/ページ ｜ 中央: キャンバス ｜ 右: インスペクタ）。`RootView` が `horizontalSizeClass` で切替。
- **状態管理** — すべて `@Observable`（Observation framework）で統一。`AppEnvironment` が合成ルートで、各サービスを `.environment(...)` で配布。
- **AI プロバイダー** — `AIProvider` プロトコルに `MockAIProvider`（既定・オフライン・決定論的）と `OpenAIProvider`（スタブ。キー未設定なら `notConfigured` を throw）が準拠。`AppConfig.makeProvider()` で選択。
- **生成パイプライン（FABLE）** — `GenerationService` が `safetyCheck → classifyGenre → generatePhases → generatePagePlan → (ページごとに) generateLayout + generateDialogue → critique` を実行し、ステージ／ページ単位で進捗を publish。
- **永続化** — `ProjectStore` がプロジェクト束（`ProjectBundle`）を Codable で Application Support に保存。初回はサンプル作品でシード。
- **課金ゲート** — `BillingService` が `Feature` 単位で機能を解放。`UsageService` がクレジット台帳を管理。

## データモデル（バックエンドとフィールド名を一致）

`Models/` 配下：`Format` / `SaveTheCatType`(10) / `Phase`(1...13) / `Density` / `Plan`、
`Project` / `StoryBrief`(+`Protagonist`/`Antagonist`/`World`) / `PhaseCard` / `PagePlan` /
`PanelSpec`(+`PanelLayout`) / `GenerationJob` / `UsageLedgerEntry` / `SubscriptionEntitlement`。

## ネームキャンバス

`PanelCanvasView` が `PanelLayout` の **0...1 相対座標** をページ矩形へ実寸変換して描画します。
マンガの **右開き（右上→左→下）** 読み順を表現するため、X 座標をミラーリングしてコマ番号バッジを振ります。
コマをタップすると `PanelInspectorView` で内容・セリフ・カメラを編集し、`ProjectStore` に保存します。

## 課金プラン（`PaywallView`）

| プラン | 価格 | 主な解放機能 |
|---|---|---|
| Free | 無料 | プロット生成（1プロジェクト/月3クレジット） |
| Plus | ¥980/月 | + PDF書き出し |
| Pro | ¥2,980/月 | + iPad ネーム編集・ラフ画像生成 |
| Studio | ¥6,800/月 | 全機能・無制限 |

iPad キャンバス編集とラフ画像生成は **Pro 以上**、PDF 書き出しは **Plus 以上** でゲートされます。

## 著作権セーフティ

`SafetyService` / `SafetyEngine` が、実在のマンガ・作者名・「○○先生風」等の作風模倣表現を含む入力を
`StoryChatView` と `NewProjectView`、生成パイプライン入口でブロックします（デニーリストは代表例。実運用で拡充）。

## Xcode 側で要確認・要実装の項目

- **StoreKit2**：`BillingService.setPlan` は現状ローカル状態のみ。実購入は StoreKit 構成ファイル（`.storekit`）と
  `Product`/`Transaction` 連携の実装が必要。
- **PencilKit**：手描きラフ用に予約済み（フレームワーク言及のみ）。`PanelCanvasView` への `PKCanvasView` 重畳は未実装。
- **OpenAIProvider**：ネットワーク実装は未着手（メソッドは `notConfigured` を throw）。`Info.plist` の
  `OPENAI_API_KEY` か `AppConfig.openAIKey` 経由でキーを注入する想定。
- **AppIcon**：`Assets.xcassets/AppIcon.appiconset` は 1024 画像が未配置（プレースホルダ）。
- **アイコン用 SF Symbols**：使用シンボルは標準のもののみだが、iOS バージョンによる可用性は実機で確認推奨。
