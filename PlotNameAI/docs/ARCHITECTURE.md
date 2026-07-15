# PlotName AI — アーキテクチャ

## 1. 全体像

```
┌────────────────────────────┐         ┌──────────────────────────────┐
│  iOS / iPadOS App (SwiftUI) │         │  Backend (TypeScript / Edge)  │
│                            │  HTTPS   │                              │
│  ├ Features (画面)          │ ───────► │  ├ functions/ (REST handlers) │
│  ├ Services                │         │  ├ pipeline.ts (FABLE)        │
│  ├ Providers (AIProvider)   │         │  ├ agents/ (各AIエージェント)  │
│  │   ├ MockAIProvider       │         │  ├ providers/ (Mock/OpenAI)   │
│  │   └ OpenAIProvider       │         │  ├ schemas/ (Zod)             │
│  └ SwiftData (local cache)  │         │  ├ billing/  usage/           │
└────────────────────────────┘         └──────────────┬───────────────┘
        │ StoreKit2 / RevenueCat                       │
        │ PencilKit / PDFKit                           ▼
        ▼                              ┌──────────────────────────────┐
   App Store IAP                       │ Supabase: Postgres / Auth /   │
                                       │ Storage / Edge Functions      │
                                       └──────────────┬───────────────┘
                                                      ▼
                                          OpenAI Responses API / Image API
```

クライアントは **同じ AIProvider 抽象** をローカルにも持ち、`MockAIProvider` で完全オフライン動作する(プロトタイプ/プレビュー/審査用)。本番では Edge Functions 経由でサーバ側 provider を呼び、APIキーを端末に置かない。

## 2. FABLE パイプライン

```
Idea
 → Story Brief        (IntakeAgent)
 → Save the Cat Type  (GenreAgent)
 → 13 Phase Grid      (PhaseAgent)
 → Character Arc      (CharacterAgent)
 → Scene List         (SceneAgent)
 → Page Plan          (PagePlannerAgent)
 → Panel Layout       (LayoutAgent)
 → Dialogue + Balloon (DialogueAgent)
 → Rough Image Prompt (VisualPromptAgent)
 → iPad Name Canvas
 → Export / Revise / Upscale
```

入力は最初に **SafetyAgent** を通り、既存作家・作品の模倣要求を拒否する。各段階の出力は **Zod(backend)/ Codable + 検証(iOS)** でスキーマ検証され、不正なら例外。

## 3. エージェント一覧

| エージェント | 役割 |
|---|---|
| IntakeAgent | アイデアを整理し StoryBrief 雛形を作る |
| GenreAgent | Save the Cat タイプを判定(primary + secondary) |
| PhaseAgent | 13フェイズへ展開、ページ範囲を割当 |
| CharacterAgent | 欲求/欠落/変化/関係性を設計 |
| SceneAgent | シーン単位へ分解 |
| PagePlannerAgent | ページ数に合わせて配分(35P標準テンプレ) |
| LayoutAgent | ページごとのコマ割り(0..1相対座標)を生成 |
| DialogueAgent | セリフと吹き出し量を調整 |
| VisualPromptAgent | コマごとの画像生成プロンプト作成 |
| CriticAgent | 構造/テンポ/読者導線を診断、弱点アラート |
| SafetyAgent | 著作権・年齢制限・禁止表現をチェック |
| (MonetizationAgent) | 使用量・クレジット・プラン制御(billing/usage に内包) |

## 4. クライアント構成 (iOS)

- **Models/** — Project / StoryBrief / PhaseCard / PagePlan / PanelSpec / GenerationJob / UsageLedgerEntry / SubscriptionEntitlement と各 enum。すべて `Codable`。
- **Providers/** — `AIProvider` プロトコル / `MockAIProvider`(決定的・オフライン)/ `OpenAIProvider`(本番)。`AppConfig` で選択。
- **Services/** — `ProjectStore`(状態 + Codable 永続化)/ `GenerationService`(パイプライン実行・進捗発行)/ `BillingService`(エンタイトルメント・ペイウォール)/ `UsageService`(クレジット台帳)/ `SafetyService`。
- **Features/** — 画面群(下記)。
- **Resources/SampleData** — フル35Pサンプル。全画面がネットワーク無しで描画可能。

### 画面とサイズクラス適応

| 画面 | 役割 |
|---|---|
| HomeView | 最近のプロジェクト/新規/診断/クレジット残量 |
| NewProjectView | 形式・ページ数・ジャンル・アイデア入力 |
| StoryChatView | 会話で企画を詰める(SafetyService 経由) |
| PhaseGridView | 13カード表示 + 弱点アラート |
| PagePlanView | 35ページ一覧(各ページの目的/コマ数/感情/引き) |
| NameCanvasView | iPad: コマ枠編集(相対座標から描画、右開き導線) |
| PanelInspectorView | コマ内容(セリフ/構図/カメラ)編集 |
| PaywallView | free/plus/pro/studio |
| ExportView / PDFExporter | PDF出力 |
| UsageView | 使用量・クレジット |

- **iPhone:** `NavigationStack` 中心。
- **iPad(regular width):** `NavigationSplitView` の3カラム(左: チャット/フェイズ/ページ一覧、中央: ネームキャンバス、右: インスペクタ)。

## 5. バックエンド構成 (TypeScript)

- **schemas/** — Zod スキーマ + 推論型(クライアント Models と1:1)。
- **providers/** — `AIProvider` インターフェイス / `mockProvider`(決定的)/ `openaiProvider`(Responses API、`openai` は動的 import の任意依存)/ `index`(env `AI_PROVIDER` で選択、既定 mock)。
- **agents/** — 各エージェントは provider 呼び出し + Zod 検証をラップ。
- **billing/** — プラン定義・制限・クレジット原価表・エンタイトルメント解決。
- **usage/** — 使用台帳・残高・原価見積。
- **pipeline.ts** — FABLE オーケストレータ。
- **functions/** — REST ハンドラ(下記 API)。
- **demo.ts / test/** — オフライン実行・検証。

## 6. API エンドポイント

```
POST   /projects
GET    /projects
GET    /projects/:id
PATCH  /projects/:id
DELETE /projects/:id
POST   /projects/:id/story-brief
POST   /projects/:id/classify-genre
POST   /projects/:id/generate-phases
POST   /projects/:id/generate-scenes
POST   /projects/:id/generate-page-plan
POST   /projects/:id/generate-layout
POST   /projects/:id/generate-name
POST   /projects/:id/generate-panel-image
POST   /projects/:id/critique
GET    /projects/:id/pages
PATCH  /projects/:id/pages/:pageNumber
PATCH  /projects/:id/panels/:panelId
POST   /exports/pdf
POST   /exports/png-zip
POST   /exports/project-json
GET    /billing/entitlements
POST   /billing/webhook/revenuecat
POST   /ads/reward
GET    /usage
```

## 7. コスト制御 / ユニットエコノミクス

- テキスト生成は安価モデル優先、詳細な構造診断のみ高性能モデル。
- 画像は低品質ラフが標準、高品質はクレジット制。
- 35P一括は非同期ジョブ(即時生成にしない)。
- キャラ設定・世界観はキャッシュ(毎回長文を送らない)。
- ページ単位で差分再生成(全体再生成を避ける)。
- 無料ユーザーは画像なし → 広告/課金へ誘導。
- 目標粗利: Plus 80%↑ / Pro 65%↑ / Studio 70%↑。

## 8. 技術スタック

| 領域 | 技術 |
|---|---|
| iOS/iPadOS | SwiftUI |
| ローカル保存 | SwiftData / Codable |
| 同期 | Supabase |
| 認証 | Supabase Auth / Sign in with Apple |
| DB | PostgreSQL |
| ストレージ | Supabase Storage / S3互換 |
| AI API | OpenAI Responses API / Image API(provider interface で差し替え可) |
| 課金 | StoreKit 2 + RevenueCat 互換抽象 |
| 広告 | Google AdMob Rewarded |
| Analytics | PostHog / Amplitude |
| Crash | Sentry |
| Queue | Supabase Edge Functions + pgmq / Cloudflare Queues |
| Export | PDFKit |
| 描画 | SwiftUI Canvas / PencilKit |
| スキーマ検証 | Zod (backend) / Codable (iOS) |

## 9. 著作権・安全

入力は SafetyAgent / SafetyService を通る。実在作家名・作品名(例: ONE PIECE, 鬼滅, 「○○先生風」)を含む模倣要求は拒否し、言い換え(「少年漫画らしいテンポ」「バトル多め」「大ゴマを多く」等、作家名に寄せない)を促す。学習・保存するのは絵柄ではなく **ページ設計の統計(特徴量)** のみ。
