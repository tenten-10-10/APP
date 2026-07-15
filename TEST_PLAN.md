# TEST_PLAN — ProjectStock

## 1. 自動テストの実行

```bash
xcodebuild -project ProjectStock.xcodeproj -scheme ProjectStock \
  -destination 'platform=iOS Simulator,name=iPhone 15' test
```

- Unit / UI ともに in-memory ストア・CloudKit 無効・モックスキャナで動くため、
  iCloud アカウントや実機カメラは不要です（`-uiTesting` 起動引数）。

## 2. Unit Tests（`ProjectStockTests/`）

| テスト | 検証内容（仕様 §17） |
|---|---|
| `PublicCodeGeneratorTests.testCodeFormatIs18AllowedCharacters` | 18文字・許可文字のみ |
| `…testCrockfordAlphabetExcludesAmbiguousLetters` | I/L/O/U 除外・32文字 |
| `…testRegeneratesOnCollision` | モック乱数で衝突時の再生成ロジック |
| `…testBatchProducesUniqueCodesDespiteDuplicateRandomness` | 一括生成の一意性 |
| `…testEightyBitsProduceSixteenSymbols` | 80bit → 16シンボル |
| `QRRenderingTests.testMatrixIsWellFormedSquare` | QR行列が正方形・正しいバージョン |
| `…testQuietZoneIsFourModules` | Quiet Zone 4モジュール確保 |
| `…testPNGIntegerScalingAndDimensions` | PNGピクセル寸法・整数スケーリング |
| `…testPNGHasAlphaChannel` | 透過（アルファ）対応 |
| `…testPDFPageSizeMatchesRequestedMillimeters` | PDFページサイズ = 指定mm |
| `…testEPSHeaderAndBoundingBox` | EPS ヘッダ・BoundingBox・rectfill |
| `…testEPSTransparentBackgroundOmitsWhiteFill` | 透過指定で白背景を描かない |
| `InventoryServiceTests.testLedgerTotalSumsDeltas` | 在庫イベント合計 |
| `…testTransferDoesNotChangeTotal` | 移動は総数を変えない |
| `…testCorrectionReversesEvent` | 訂正（逆仕訳）イベント |
| `…testCachedQuantityRebuild` | cachedQuantity 再構築 |
| `…testIndividualUnitStatusFlow` | 個体の貸出/返却と在庫反映 |
| `PersistenceAndRoutingTests.testNewProjectAndChildrenShareSameStore` | StoreRouter が同一ストアへ割当 |
| `…testCrossProjectAliasAssignmentRejected` | プロジェクト境界違反の拒否 |
| `…testShareReadinessPassesForCleanProject` | 共有前検証 |
| `…testReadOnlyPermissionBlocksEditing` | 読み取り専用で編集不可 |
| `HierarchyAndScanTests.testFolderCycleDetection` | Folder 循環検出 |
| `…testLocationCycleDetection` | Location 循環検出 |
| `…testBulkMoveContainerContents` | コンテナ一括移動 |
| `…testScanRoutingClassifications` | 既知/未割当/無効/対象外/未知のルーティング |
| `…testScanabilityWarnsOnTinyModules` | 極小サイズの読取評価警告 |

## 3. UI Tests（`ProjectStockUITests/`）

| テスト | フロー |
|---|---|
| `testLaunchShowsProjectsTab` | 初回起動 |
| `testCreateProject` | Project 作成 |
| `testCreateProjectAndProductWithStock` | Product 作成 + 初期在庫（入庫） |
| `testScanTabShowsMockScanner` | モックスキャンUI表示 |
| `testSettingsTabReachable` | 設定タブ到達 |

> UI テストはアクセシビリティ識別子（`createProjectButton`, `projectNameField`,
> `addProductButton`, `productNameField`, `initialQuantityField`, `saveProductButton`,
> `mockScanField`, `operatorNameField` など）で操作します。

## 4. 手動実機テスト（Apple Developer / 実機が必要）

### 端末カバレッジ
- [ ] iPhone SE 第1世代 または同等の iOS 15 端末
- [ ] iPhone SE 第2/3世代
- [ ] 小型画面（iPhone mini）
- [ ] 最新世代 iPhone / iOS 26

### 共有・同期
- [ ] 2 つの異なる Apple ID で共有（Owner / read-write / read-only）
- [ ] read-only 参加者で編集 UI が無効化される
- [ ] 機内モードで操作 → 復帰後に同期、両端末のイベントが加算される

### 画面 / アクセシビリティ
- [ ] iPhone SE 320pt 幅で主要画面が横スクロール・文字切れしない
- [ ] Dynamic Type 拡大で破綻しない
- [ ] VoiceOver で数量増減ボタンに label/hint
- [ ] Dark Mode / Reduce Motion
- [ ] Landscape でスキャナのボタンへ到達できる

### 印刷・読取（QR Fit 検証の本丸）
- [ ] 8 / 16 / 28 mm を実際に印刷して読み取り
- [ ] 300 / 600 / 1200 DPI を比較
- [ ] レーザー / インクジェット / ラベルプリンタを各1種以上
- [ ] 印刷校正シートのチェック欄で端末別の読取可否を記録
- [ ] 透過 PNG（Quiet Zone 白保持）を濃色用紙へ印刷して読み取り

### エラー処理
- [ ] カメラ権限拒否 → 設定導線が出る / 他機能は使える
- [ ] iCloud 未ログイン / 容量不足 / ネット不通の各メッセージ
- [ ] 重複コード検出・無効フォルダ階層・読み取り専用編集の拒否
