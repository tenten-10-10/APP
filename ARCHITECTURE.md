# ARCHITECTURE — ProjectStock

MVVM + Repository/Service。過剰な Clean Architecture を避け、SwiftUI / Core Data /
CloudKit の素直な組み合わせで構成しています。

```
┌────────────────────────────────────────────────────────────────┐
│ SwiftUI Views (Views/)                                          │
│  RootTabView → Projects / Scan / Activity / Settings            │
│   ・@FetchRequest で Core Data を直接購読                        │
│   ・複雑なフローのみ ViewModel(ObservableObject) を併用          │
└───────────────▲──────────────────────────────┬─────────────────┘
                │ EnvironmentObject             │ 書き込みは background context
                │                               ▼
┌───────────────┴──────────────────────────────────────────────┐
│ ServiceContainer (composition root)                           │
│  router / inventory / projects / folders / locations /        │
│  aliases / qrExport / scanRouter / stocktake / sharing /      │
│  syncMonitor / sampleData                                     │
└───────────────▲──────────────────────────────┬───────────────┘
                │                               ▼
┌───────────────┴───────────────┐  ┌───────────────────────────┐
│ Services (純ロジック)          │  │ Persistence                │
│  InventoryService 台帳         │  │  PersistenceController     │
│  PublicCodeGenerator           │  │   ・Private + Shared 2store │
│  CodeAliasService              │  │  StoreRouter               │
│  Folder/LocationService 階層    │  │  CloudKitSyncMonitor       │
│  ProjectService / Stocktake    │  │  CloudKitErrorMapper       │
│  QR* レンダラ群                 │  └───────────────────────────┘
└───────────────▲───────────────┘
                │
        ┌───────┴───────┐
        │ Core Data Model│  Project / Folder / Product / StockUnit /
        │  (.xcdatamodeld)│  Location / InventoryEvent / CodeAlias
        └────────────────┘
```

## レイヤの責務

- **Views**: 表示と入力のみ。データ取得は `@FetchRequest`、書き込みは
  `ServiceContainer.performWrite { ctx in … }`（background context）。
- **ViewModels**: 状態を持つ画面（`QRStudioViewModel`、`StocktakeCoordinator`）のみ。
- **Services**: ビジネスロジック。Core Data の `NSManagedObjectContext` とオブジェクトを
  引数に取り、その context 上で処理します（context を内部生成しないので、background でも
  viewContext でもテストでも同じコードが動く）。
- **Persistence**: Core Data / CloudKit のセットアップと状態監視。

## Core Data 永続化と 2 ストア戦略（CloudKit 共有）

`PersistenceController` は **1 つの `NSPersistentCloudKitContainer`** に
**2 つの SQLite ストア** を設定します。

| ストア | データベーススコープ | 用途 |
|---|---|---|
| `private.sqlite` | `.private` | 自分が所有するプロジェクト |
| `shared.sqlite`  | `.shared`  | 他人から共有されたプロジェクト |

両ストアは同じ Default Configuration（=同じエンティティ集合）を使い、双方向に
同期します。必須設定:

- `NSPersistentHistoryTrackingKey = true`
- `NSPersistentStoreRemoteChangeNotificationPostOptionKey = true`
- `viewContext.automaticallyMergesChangesFromParent = true`
- 明示的 merge policy（`mergeByPropertyObjectTrump`）
- 書き込みは background context（`transactionAuthor` 設定）

### StoreRouter（ゾーン跨ぎの防止）

新規オブジェクトは必ず **Project と同じストア** に `context.assign(_:to:)` で割り当てます。

- 新規 Project（所有）→ Private Store
- 子オブジェクト（Folder/Product/Location/StockUnit/InventoryEvent/CodeAlias）→ その Project と同じストア

これにより「所有者は private、参加者は shared」が保たれ、**ストア（CloudKit ゾーン）を
跨ぐリレーションを作らない**という制約を守れます。プロジェクト間の移動は MVP では
直接行わず、「別プロジェクトへ複製」+「元をアーカイブ」を提供します
（`ProjectService.duplicate`）。

## Core Data モデルの CloudKit 互換ルール

`ProjectStock.xcdatamodeld` は以下を厳守しています（`usedWithCloudKit=true`）。

- Unique Constraint を使わない（一意性はアプリ層で検証）
- Ordered Relationship を使わない（並びは `sortIndex` / `createdAt` で表現）
- すべての Relationship に Inverse を設定し、optional にする
- Deny の Delete Rule を使わない（Cascade / Nullify のみ）
- 必須属性に安全なデフォルト値（空文字 / 0 / false）
- プロジェクトを跨ぐリレーションを作らない
- すべての配下エンティティから Project へ到達できる（`StockUnit` を含め `project` を保持。
  そのため Project には仕様の列挙に加えて `units` を inverse として追加）

## 在庫イベント台帳（原本）

`InventoryService` がすべての在庫変更を **追加のみ可能な `InventoryEvent`** として記録します。

- 数量モード: `cachedQuantity = Σ(quantityDelta)`（`affectsQuantityTotal` な種別のみ）。
  起動時・Remote Change 後に `recomputeAll(in:)` で再構築。
- 個体モード: `StockUnit.status` を更新しつつイベントを追加。現在状態は
  `resolvedStatus(for:)` がイベント時刻 + 安定タイブレーカー（occurredAt → createdAt → id）で
  決定。競合は履歴を残したまま `hasUnresolvedConflict(for:)` でバッジ表示。
- 訂正は履歴を消さず **逆仕訳 / correction イベント**（`correctsEvent` リンク）で行います。
- 同時編集は両方のイベントを加算（上書き解決をしない）。

## QR パイプライン（分離された段）

仕様 §7.2 に従い、各段を厳密に分離しています。

```
PublicCodeGenerator → QREncoding(CoreImage) → QRCodeMatrix
        → paddedGrid(QuietZone) → { Raster(PNG) | Vector(PDF) | EPS | SVG }
        → QRExportService（ファイル名・一時ディレクトリ・共有）
QRScanabilityEvaluator が Matrix+Spec から読取評価を算出。
```

- **QR ペイロード**: `IQ` + Crockford Base32 16文字 = 18文字。80bit を
  `SecRandomCopyBytes` で生成。名称・数量・CloudKit Record ID を**含めない**。
- **PNG**: 物理 mm→px を整数モジュールに微調整、アンチエイリアスなし、sRGB、透過対応。
- **PDF/EPS**: 完全ベクター。横方向の連続黒モジュールを 1 矩形にまとめてデータ量削減。
  EPS は ASCII を自前生成（`%!PS-Adobe-3.0 EPSF-3.0` / 正しい `%%BoundingBox` / `rectfill`）。
- **Quiet Zone**: 既定 4 モジュール。透過 PNG でも既定では Quiet Zone を白で保持。

## CloudKit 共有

- 共有単位は **Project のみ**。`NSPersistentCloudKitContainer.share([project], to:)` で
  Project と全配下を 1 つの CKShare に関連付け。
- `UICloudSharingController` を SwiftUI でラップ（read-only / read-write）。
- 招待受諾は AppDelegate / Scene の `userDidAcceptCloudKitShareWith` →
  NotificationCenter → `CloudSharingService.acceptShare(... into: sharedStore)`。
- 権限は `CloudSharingService.permission(for:)` が判定し、read-only なら UI の編集を無効化。

## スキャナと結果ルーティング

`ScanResultRouter` がスキャン文字列を分類:

1. 有効な既知コード → 対象詳細 / クイック操作
2. 無効化済みコード → 理由表示 + 再発行
3. 未割当コード → 割当フロー
4. 形式は合うが未検出 → 未同期の可能性を案内
5. アプリ形式でない → コピー / 閉じる

## エラー処理 / 状態

- `CloudKitErrorMapper` が CKError を日本語の短文へ変換（詳細は診断画面で原文確認）。
- `CloudKitSyncMonitor` が import/export イベントと iCloud アカウント状態を監視し、
  `SyncState`（ローカルのみ / 同期中 / オフライン / エラー…）を提供。
- Store ロード失敗は `fatalError` せず `StoreLoadFailure` に記録して復旧 UI を出します。
