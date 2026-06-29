# PlotName AI / プロットネームAI

> 1行アイデアを、Save the Catの話型・13フェイズ構造・35P読み切りのページ割り・iPadで編集できるネームへ。
> **漫画を作る前の、企画・構成・ネームのOS。**

PlotName AI は、漫画・Webtoon・映像企画向けに、Save the Cat の10ストーリータイプ、13フェイズ構造、ページ単位のネーム設計をAI会話で統合する創作支援アプリです。iPhone でプロット設計、iPad でネーム作成まで行えます。

このディレクトリは MVP のモノレポです。既存の `ProjectStock` アプリとは独立しています。

```
PlotNameAI/
├── README.md            ← このファイル
├── docs/                ← 仕様一式
│   ├── PRODUCT_SPEC.md      プロダクト仕様(ターゲット/機能/料金/KPI/ロードマップ)
│   ├── ARCHITECTURE.md      アーキテクチャ(FABLEパイプライン/エージェント/API)
│   ├── AI_PROMPTS.md        各AIエージェントのプロンプトと出力スキーマ
│   └── DATABASE_SCHEMA.sql  PostgreSQL / Supabase スキーマ
├── backend/             ← TypeScript バックエンド(Zod検証 / Mock+OpenAI provider)
│   └── README.md            セットアップ・実行・テスト
└── ios/                 ← SwiftUI iOS/iPadOS アプリ(Mock provider で完全オフライン動作)
    └── README.md            Xcode での生成・実行手順
```

## クイックスタート

### バックエンド(この環境で実行・検証可能)

```bash
cd backend
npm install
npm run demo      # サンプルアイデアで FABLE パイプラインを実行し 35P プランを出力
npm test          # 13フェイズ/35ページ/各ページ1コマ以上/著作権ブロックを検証
```

API キー不要(`AI_PROVIDER=mock` が既定)。OpenAI を使う場合は `AI_PROVIDER=openai OPENAI_API_KEY=...`。

### iOS / iPadOS アプリ(macOS + Xcode が必要)

```bash
cd ios
brew install xcodegen      # 未導入の場合
xcodegen generate          # project.yml から PlotNameAI.xcodeproj を生成
open PlotNameAI.xcodeproj  # Xcode で開いて実行
```

既定で `MockAIProvider` + 同梱サンプルデータにより、ネットワーク無しで全画面が動作します。

## FABLE パイプライン

```
Idea → StoryBrief → Save the Cat Type → 13 Phase Grid → Character Arc
     → Scene List → Page Plan → Panel Layout → Dialogue → Rough Image → Name Canvas → Export
```

入力は最初に SafetyAgent を通り、実在作家・作品の模倣要求を拒否します。各段階の出力はスキーマ検証されます。詳細は [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)。

## 1. 実装した内容

**仕様ドキュメント (`docs/`)**
- `PRODUCT_SPEC.md` / `ARCHITECTURE.md` / `AI_PROMPTS.md`(11エージェント)/ `DATABASE_SCHEMA.sql`(RLS例つき)

**TypeScript バックエンド (`backend/`) — この環境で検証済み**
- Zod スキーマ + 推論型、Mock + OpenAI provider(差し替え可能なアダプタ)
- 11エージェント、FABLE パイプライン、billing(free/plus/pro/studio)、usage 台帳
- **REST層 (`src/functions/`)**: フレームワーク非依存のルータ + projects CRUD・generate 各種・pages/panels PATCH・billing・usage・**ads/reward**・exports/project-json。全 generate 系は SafetyAgent を先頭で実行、Zod 検証(不正 400 / 抵触 422 / 未知 404)
- **非同期ジョブ (`src/jobs/`)**: `generate-name`(FABLE全工程)/ `generate-panel-image`(ラフのSVGプレースホルダ、画像1クレジット消費)、`GET /jobs/:id` でポーリング
- 任意の開発サーバ `src/server.ts`(`npm run serve`)、`npm run demo`、テスト **30件 pass**

**SwiftUI iOS/iPadOS アプリ (`ios/`)**
- 全データモデル / 全画面(Home/NewProject/StoryChat/PhaseGrid/PagePlan/NameCanvas/PanelInspector/Export/Paywall/Usage/SignIn)
- Mock provider + 同梱サンプルで**完全オフライン動作**。ネームキャンバスは 0..1 相対座標から描画、右開き導線、PDFKit 出力
- **Auth 抽象**(Sign in with Apple、`MockAuthProvider` 既定 / Apple・Supabase スタブ)
- **Reward 抽象**(リワード広告、`MockRewardProvider` 既定 / AdMob スタブ。無料ユーザー向け「広告を見て生成枠を増やす」)
- **1コマ画像ラフ生成**(`generatePanelRough`、`imageRoughGeneration` 機能＋クレジットでゲート、PanelInspector から非同期実行)
- **PencilKit 赤入れ**(`AnnotationCanvasView`、iPad のみ、ページ単位で PKDrawing を永続化)
- **SwiftData ローカルキャッシュ**(`ProjectPersistence` 抽象。端末は SwiftData、プレビュー/テストはファイル。失敗時フォールバック)
- 課金ゲーティング、AIクレジット台帳、無料プラン制限、構造診断(CriticAgent)

## 2. 未実装 / 次の段階

- OpenAI provider の実呼び出し(インターフェイス済み、`OPENAI_API_KEY` で有効化)
- Supabase の DB/Storage 同期、Sign in with Apple / AdMob の本番SDK配線(いずれもスタブ済み)
- StoreKit 2 / RevenueCat の実プロダクト設定(`BillingService` はローカル状態の抽象)
- バックエンドの永続化(現状インメモリ)・認証/マルチユーザー、実画像レンダリング、PDF/PNG-zip エクスポート、RevenueCat Webhook
- iPad 見開き編集 / Clip Studio 出力(Phase 3)

## 3. 起動方法

```bash
# バックエンド(この環境で実行・検証可能)
cd backend && npm install
npm run demo            # FABLE パイプラインで 35P プランを出力
npm run serve           # 任意: node:http 開発サーバ(REST)

# iOS / iPadOS(macOS + Xcode 16 が必要)
cd ios && xcodegen generate && open PlotNameAI.xcodeproj
```
iOS は既定で MockAIProvider + サンプルデータにより、サインインも含めオフラインで全画面動作します。

## 4. 環境変数

| 変数 | 対象 | 既定 | 用途 |
|---|---|---|---|
| `AI_PROVIDER` | backend | `mock` | `mock` / `openai` の切替 |
| `OPENAI_API_KEY` | backend | (なし) | OpenAI provider 使用時のみ |
| `OPENAI_API_KEY` | iOS | (なし) | `Info.plist` または `AppConfig.openAIKey`。未設定なら Mock |

Supabase / AdMob / Apple サインインの本番キーは各スタブ実装の TODO 箇所に配線します(未設定でも Mock で動作)。

## 5. テスト方法

```bash
cd backend
npm run typecheck       # tsc --noEmit(クリーン)
npm test                # node:test 30件(13フェーズ/35ページ/4〜12P/著作権ブロック/REST/ジョブ)
```
iOS はこの Linux 環境ではコンパイル不可。Xcode で `xcodegen generate` 後にビルド&プレビューで確認します。

## 6. 次に Codex へ渡すべきレビュー観点

- **iOS のビルド整合性**: `xcodegen generate` 後に新規ファイルがターゲットに含まれるか、`@MainActor` 化した `ProjectStore` と `ProjectPersistence` の並行性、`ModelContainer(for: ProjectRecord.self)` の構築/マイグレーション
- **PencilKit**: `PKCanvasView`/`PKDrawing(data:)` 配線、注釈オーバーレイのページ矩形整合
- **Sign in with Apple / AdMob / Supabase**: スタブ→本番SDKの差し替え、Capability/Entitlement、`Info.plist` 設定
- **StoreKit2**: `BillingService` を実 `Product`/`Transaction` に接続、復元購入、クレジット無期限の担保
- **バックエンド**: 永続化(DB)・認証・レート制限・コスト上限、実画像生成のコスト試算、未実装エンドポイント(PDF/PNG-zip、RevenueCat Webhook)
- **セキュリティ/著作権**: SafetyAgent のデニーリスト網羅性、編集後 `image_prompt` の再チェック、生成物の権利表示

---

各サブディレクトリの README にも、エンドポイント一覧・起動方法・環境変数・テスト方法・Xcode で人手確認が必要な項目を記載しています。

## 著作権・安全

本アプリは、既存作家・既存作品の絵柄・コマ割り・台詞・構図を模倣するためのものではありません。ユーザーは自身が権利を持つ素材、または許諾を得た素材のみを参照として使用できます。学習・保存するのは絵柄ではなく「ページ設計の統計(特徴量)」のみです。
