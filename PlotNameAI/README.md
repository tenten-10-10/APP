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

## このリポジトリで実装した範囲

- ✅ 仕様ドキュメント一式(`docs/`)
- ✅ TypeScript バックエンド: Zod スキーマ / Mock + OpenAI provider / 11エージェント / FABLE パイプライン / billing / usage / 実行可能な demo + テスト
- ✅ SwiftUI アプリ: 全モデル / Mock provider / サービス / 全画面 / ネームキャンバス(相対座標描画・右開き導線)/ PDF出力 / ペイウォール / XcodeGen 構成 / フル35Pサンプルデータ

## 未実装 / 次の段階

- OpenAI provider の実呼び出し配線(インターフェイスは用意済み、キー設定で有効化)
- Supabase 同期 / Sign in with Apple の本番配線
- StoreKit 2 / RevenueCat の実プロダクト設定
- 画像ラフ生成の非同期ジョブ実体
- PencilKit 赤入れ / 見開き編集 / Clip Studio 出力(Phase 3)

各サブディレクトリの README に、起動方法・環境変数・テスト方法・Xcode で人手確認が必要な項目を記載しています。

## 著作権・安全

本アプリは、既存作家・既存作品の絵柄・コマ割り・台詞・構図を模倣するためのものではありません。ユーザーは自身が権利を持つ素材、または許諾を得た素材のみを参照として使用できます。学習・保存するのは絵柄ではなく「ページ設計の統計(特徴量)」のみです。
