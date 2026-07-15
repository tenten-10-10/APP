# APP_STORE_CHECKLIST — プロットネームAI 提出準備チェックリスト

対象: `PlotNameAI/ios`（bundle id `com.plotname.ai`、XcodeGen 生成プロジェクト）。
自動化は `PlotNameAI/ios/fastlane/`（beta / release / screenshots / produce_app）と
`.github/workflows/plotname-testflight.yml` で行います。

## 1. App Store Connect レコード作成（初回のみ）

- [ ] **`produce_app` レーンを実行**して bundle ID とアプリレコードを作成
  - Actions → "PlotName AI TestFlight" → Run workflow → lane = `produce_app`。
  - app_name「プロットネームAI」/ primary language `ja` / SKU `plotname-ai-001`。
  - 冪等（既に存在する場合はスキップ）。API キーは既存の Admin キー
    （`ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_P8_BASE64`）を再利用します。
- [ ] ASC 上でアプリ名「プロットネームAI」が取得できたことを確認
  （名前が衝突した場合は produce がエラーになるので別名を検討）。

## 2. IAP 商品（10点）の作成と審査ノート

ASC → 対象アプリ → 「App内課金」/「サブスクリプション」で以下を作成します。
Product ID・価格は `PlotNameAI/ios/PlotNameAI/Resources/Products.storekit` と
一致させてください（ローカルテストと本番で同じ ID を使うため）。

- [ ] サブスクリプショングループ「PlotName AI Plans」を作成（レベル: Studio > Pro > Plus）
- [ ] `com.plotname.ai.plus.monthly` — Plus（月額）¥980
- [ ] `com.plotname.ai.plus.yearly` — Plus（年額）¥7,800
- [ ] `com.plotname.ai.pro.monthly` — Pro（月額）¥2,980
- [ ] `com.plotname.ai.pro.yearly` — Pro（年額）¥24,800
- [ ] `com.plotname.ai.studio.monthly` — Studio（月額）¥6,800
- [ ] `com.plotname.ai.studio.yearly` — Studio（年額）¥59,800
- [ ] 消耗型 `com.plotname.ai.credits.small` — クレジット100 ¥480
- [ ] 消耗型 `com.plotname.ai.credits.medium` — クレジット300 ¥1,200
- [ ] 消耗型 `com.plotname.ai.credits.large` — クレジット900 ¥3,000
- [ ] 消耗型 `com.plotname.ai.credits.studio` — スタジオパック3500 ¥9,800
- [ ] 各商品に日本語のローカライズ（表示名・説明）と**審査用スクリーンショット**を添付
  （課金画面のスクショで可。IAP は初回、アプリ本体の審査と同時提出が必要）
- [ ] 審査ノートに「課金は StoreKit サンドボックスで確認可能。クレジットは無期限」と記載
  （テキストは `ios/fastlane/metadata/review_information/notes.txt` を参照）

> 補足: クレジット（消耗型）は**無期限**である旨をアプリ内・説明文の双方に明記済み。
> 有効期限を後から付ける変更は App Store 規約上トラブルになりやすいので変えないこと。

## 3. 年齢レーティング

- [ ] ASC の年齢レーティング質問票に回答（**4+ 想定**）
  - 暴力・ギャンブル・医療情報などは「なし」。
  - 「ユーザー生成コンテンツ / 無制限のWebアクセス」は**なし**（投稿・共有機能なし、
    ブラウザなし）。
  - AI生成コンテンツに関する質問（2025年以降の新設問）には「あり」で回答し、
    フィルタリング（著作権セーフティ・模倣拒否）を説明。
- [ ] 質問票は fastlane では送信しない（`release` レーンは rating をスキップ）。
  ASC 上で一度だけ回答すればよい。

## 4. AI生成コンテンツの開示

- [x] App Store 説明文に「プロット・ページ割り・ラフ画像はAIによって生成される」旨を明記
  （`ios/fastlane/metadata/ja/description.txt`）
- [x] 審査ノートに AI 生成である旨と著作権セーフティ（実在作品名の拒否）を記載
  （`review_information/notes.txt`）
- [ ] アプリ内の生成結果画面に「AIによる生成物」の表示があることを実機で確認
- [ ] 実在の作品名・作家名を入力した際に生成が拒否されることを実機で確認
  （例:「ワンピース風で」→ お断りメッセージ）

## 5. App Privacy（Nutrition Label）質問票

ASC → App Privacy で以下を回答します（`PlotNameAI/PRIVACY_POLICY.md` と一致させること）。

- [ ] **収集するデータ**:
  - 連絡先情報 > メールアドレス（Sign in with Apple、非公開リレー可）— アプリ機能
  - ユーザーコンテンツ > その他のユーザーコンテンツ（アイデア・プロット・ネーム）— アプリ機能
  - 識別子 > ユーザーID — アプリ機能
  - 購入 > 購入履歴（サブスク状態・クレジット残高）— アプリ機能
  - 使用状況データ > 製品の操作（生成回数など）— 分析・アプリ機能
  - 診断 > クラッシュデータ — 分析
- [ ] **トラッキング**: リワード広告で IDFA を使用する場合のみ「あり」+ ATT 実装。
  初期リリースでコンテキスト広告のみ（または広告未実装）なら「なし」で回答。
- [ ] AI プロバイダ（OpenAI 等）への入力送信は「アプリ機能のための第三者への処理委託」
  として整理（学習利用なしの設定である旨をプライバシーポリシーに記載済み）。

## 6. スクリーンショット要件

ユニバーサルアプリ（iPhone + iPad）のため **2サイズ必須**です。

- [ ] **iPhone 6.9"**（iPhone 16 Pro Max / 1320×2868）— プロット設計・13フェイズ・35P割り
- [ ] **iPad 13"**（iPad Pro 13-inch M4 / 2064×2752）— ネームキャンバス・Apple Pencil編集
- [ ] 撮影は `ios/fastlane/Snapfile` + `screenshots` レーン
  （PlotNameAIUITests の ScreenshotUITests 追加後に `only_testing` を有効化）
- [ ] 撮影 → フレーム/キャプション加工 → `release` レーンでアップロード
  （タナミルと同じフロー。加工済み PNG を `fastlane/screenshots/ja` に配置）

## 7. 審査提出前チェック（ガイドライン対応）

- [ ] **購入の復元**導線がある（「設定 > 購入の復元」等。3.1.1）
- [ ] **アカウント削除**導線がある（「設定 > アカウント > アカウントを削除」。5.1.1(v)）
- [ ] **プライバシーポリシーURL** を実URLに差し替え
  （現状 `https://github.com/tenten-10-10/APP` のプレースホルダ。
  `ios/fastlane/metadata/TODO_URLS.md` 参照。GitHub Pages 公開を推奨）
- [ ] **利用規約（EULA）**へのリンクをアプリ内の課金画面と App Store 説明文に記載
  （標準EULAを使う場合もリンクは必要。3.1.2）
- [ ] **サブスク説明文言（3.1.2）**: 課金画面に「価格・期間・自動更新される旨・
  解約方法」を明記。説明文にも記載済み（`description.txt` の料金プラン節）
- [ ] Mock モードのままでも審査員が全機能を確認できることを確認
  （`review_information/notes.txt` に手順記載済み）
- [ ] `ITSAppUsesNonExemptEncryption = false` を Info.plist に設定（輸出コンプライアンス）
- [ ] App Icon 1024×1024（透過なし）/ Launch Screen / Accent Color を同梱
- [ ] 提出ビルドで Debug メニュー・開発用ログを無効化

## 8. TestFlight / リリース手順

1. - [ ] （初回のみ）`produce_app` レーン実行 → §1
2. - [ ] Actions → **"PlotName AI TestFlight"** → Run workflow → **lane = `beta`**
   - `workflow_dispatch` のみ（タグ/push自動ビルドなし）。クラウド署名はビルドごとに
     配布証明書を発行するため、証明書上限（cert cap）に達すると失敗します。
     不要な証明書は Developer Portal で失効させてから実行してください。
   - ビルド番号は TestFlight の最新 +1 が自動採番されます（`latest_testflight_build_number`）。
3. - [ ] TestFlight で内部テスター配布 → 実機確認
   - 判定 → 13フェイズ → 35P割り → ネームキャンバス → PDF出力の一連フロー
   - サンドボックスでのサブスク購入・アップグレード/ダウングレード・復元
   - クレジット購入と残高反映、リワード広告（実装済みの場合）
4. - [ ] メタデータ最終確認（`ios/fastlane/metadata/`、URL差し替え含む）
5. - [ ] Run workflow → **lane = `release`**（メタデータ+スクショを上げて審査提出。
     バイナリは直近の `beta` ビルドを使用、承認後は手動リリース設定）

> 補足: ルートの `fastlane/`（タナミル用）とは完全に独立しています。
> `PlotNameAI/ios` で `bundle exec fastlane <lane>` を実行するとこのアプリ用の
> `PlotNameAI/ios/fastlane/` 設定が使われます（環境変数はローカルでは
> `ios/fastlane/.env.example` をコピーして設定）。
