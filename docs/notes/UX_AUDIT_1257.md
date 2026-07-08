# 1.2.57 UX改善バッチ — 監査サマリと採否

5並列サブエージェントで全画面のUsabilityを監査した結果と、1.2.57で入れる/見送るの判断。
アプリは基礎（自己読み上げLabel・638/638ローカライズ同期・触覚・空状態）が既に高品質で、
指摘は「穴」ではなく「磨き込み」。ここは低リスク×高価値のみを採用する。

## 採用（1.2.57で実装）
- [P0] 共有: 「リンクで招待」は誰でも編集可の警告文を追加（ProjectShareSection）
- [P0] 活動ログ: 貸出行に借り手を表示（EventViews）
- [P0] 貸出: 「本日/まもなく期限」状態＋橙チップ（Loans.swift + LoansView）
- [P1] 共有: 参加者数は承諾済みのみカウント＋未参加を別表示（ProjectShareSection）
- [P1] 共有: リンク招待に進捗＋二度押し防止（ProjectShareSection）
- [P1] スキャン結果: 「閉じてスキャンに戻る」ボタン（ScanResultSheet）
- [P1] 製品作成: 管理方法は変更不可の説明フッター（ProductFormView）
- [P1] タブ: ホームのスキャンヒーローがタブ切替に（RootTabView選択バインド + HomeView）
- [P1] タブ: ホームにWeb借用の未処理バッジ（RootTabView）
- [P1] ホーム: ヒーロー見出しを状況で出し分け＋手順をタップ可能に＋空状態で「問題なし」を出さない
- [P1] a11y: アイコンのみツールバーボタンにVoiceOverラベル（各詳細画面）
- [P1] i18n: QRエラー文言をNSLocalizedString化（QREncoder/QRRasterRenderer/QRVectorPDFRenderer）
- [P1] 割り当て: 個体ピッカーからロット/既ラベル個体を除外（二重QR防止）＋検索可能に（AssignmentView）
- [P2小] 設定: JSON書き出しは復元不可の注記（SettingsView）＋名前欄textContentType
- [P2小] メール招待: 「別の人を招待」リセット＋email textContent
- [P2小] 参加: 貼り付け欄プレースホルダをt.l0l0.app/joinに（JoinShareSheet）
- [P2小] バックアップ: 行シェブロン記号を操作を示すものに（BackupListView）
- [P2小] 貸出既定期限の時刻を固定（CheckoutSheet/LoanEditSheet）
- [P2小] Web借用: 申請日時を表示（WebBorrowInboxView）
- [P2小] 棚卸し: 対象プロジェクト無しの空状態（StocktakeView）

## 見送り（次版以降・中リスク/大きめ）
- 参加者が共有から抜ける導線（CloudKit繊細） — S3
- バックアップ/復元のメインスレッドブロック解消（永続化タイミング） — S6
- 棚卸しで未スキャン製品の可視化（分母表示のみ簡易採用も検討） — L3
- Web借用リクエストに製品名解決表示 — L4
- 返却前リマインド（期限前通知） — L6
- 活動ログのテキスト検索 — L7
- 全リストのpull-to-refresh — X6
- スキャナ二度撮り抑制（先の再スキャン修正と相反） — C9

## 検証
Linuxコンテナのため**ローカルでSwiftコンパイル不可**。検証はCIのTestFlightビルド一択。
実装後にフレッシュ文脈の検証サブエージェントで差分をレビュー→ビルド1回で確認する。
