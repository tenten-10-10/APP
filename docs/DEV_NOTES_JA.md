# 📱 iOSアプリ開発ナレッジ（タナミル/ProjectStock より）

タナミル（QR在庫管理アプリ）の開発を通じて得た、次回以降のiOSアプリ開発に
再利用できる知見のまとめ。個人開発〜小規模チームでの
「SwiftUI + Core Data + fastlane + GitHub Actions + 最小バックエンド」構成を
前提にしている。

## 0. 一行サマリ

個人開発でも「SwiftUI + Core Data(CloudKit 2ストア) + fastlane match +
GitHub Actions + 最小バックエンド(Supabase/Vercel)」の型を組めば、
**Macローカルでビルドせずにクラウド署名で App Store まで到達できる**。
詰まりの9割は「証明書」と「App Store Connect のバージョン制約」。

---

## 1. アーキテクチャの型（そのまま流用可）

- **SwiftUI + MVVM + Repository/Service**。`ServiceContainer`
  （合成ルート/composition root）を1つ作り、全サービスを生成・保持して
  `.environmentObject` で注入。配線が1か所に集約されて見通しが良い。
- **Core Data + `NSPersistentCloudKitContainer` の2ストア構成**
  （Private + Shared）。`StoreRouter` を挟んで「子オブジェクトを親と同じ
  ストアへ入れる」ことでゾーン跨ぎ参照を防ぐ。CloudKit共有をやるなら必須の型。
- **在庫や履歴は「追加のみの台帳（イベントソーシング）」**。現在値は台帳
  から再計算し、`cachedQuantity` は表示キャッシュに徹する。訂正は削除せず
  「逆仕訳イベント」で行う。競合が起きても両方残して決定的に解決できる。
- **書き込みは必ずバックグラウンドcontext**（`performAndWait`）で、
  viewContextオブジェクトは `objectID` で解決し直す。
- **iOS15最低ラインは今も有効**（iPhone SE 1st gen を拾える）。iOS16専用API
  （新しい`NavigationStack`等）を避ける方針を最初に決めておくと後で楽。

---

## 2. CI/CD・リリースパイプライン（最重要・再利用性◎）

- **fastlane 3レーン構成**：
  - `beta`：ビルド→TestFlightアップロード（`build_app` +
    `upload_to_testflight`、`skip_waiting_for_build_processing:true`）
  - `release`：`deliver` でメタデータ＋審査提出（`submit_for_review:true`,
    `automatic_release:true`, `skip_binary_upload:true`,
    `reject_if_possible:true`）
  - `certs`：`match` で証明書/プロファイルを用意（新capability追加時は
    `force:true` でプロファイル再生成）
- **GitHub Actions**：`workflow_dispatch`（手動）＋ `v*` タグpushでのみ
  ビルド。**毎push自動ビルドはやめる**（後述の証明書枯渇＆無駄upload回避）。
- **APIキー(.p8) / .env はSecretsからワークフロー内で書き出す**。
  リポジトリには置かない。

### fastlane match（証明書問題の根治）★

- **症状**：クラウド署名で毎ビルドが新しい配布証明書を発行 →
  「maximum number of certificates」で枯渇し全ビルド失敗。
- **対処**：`match`（storage_mode: git）で **証明書＋プロファイルを専用
  privateリポに共有**し、全ビルドで再利用。認証は
  `MATCH_GIT_BASIC_AUTHORIZATION`（`base64(user:PAT)`）、暗号化は
  `MATCH_PASSWORD`。
- **ハマり**：`MATCH_GIT_URL` を空文字でenv注入すると `Matchfile` の
  既定URLを上書きして `git clone ''` で落ちる。**空になり得るenvは
  渡さない**（Matchfile側に既定値を持たせる）。

---

## 3. App Store Connect の制約と実務パターン（最頻出ハマりどころ）★

- **【最重要・事故厳禁】「TestFlight」と「App Store審査（review）」は完全に
  別物。指示の対象がどちらか曖昧なまま、審査の取り下げ/提出をするな。**
  - 実際にやらかした事故（1.2.51）: ユーザーの「1.3.0をテストフライトから
    取り下げて1.2.51をあげて」を**審査操作と誤解**して `release.yml`
    (deliver + `reject_if_possible`) を実行。**審査中だった1.2.11を却下し**、
    1.2.51を新規提出してしまった。1.2.11が積み上げていた審査待ち時間は
    Appleの仕様上**復元不能**（キャンセル→再提出は必ず列の最後尾）。
  - ユーザーの本当の意図は **TestFlightベータ配信の操作**だった:
    「1.3.0ビルドをexpireして」「1.2.51ビルドをTestFlightに出して」。
    これは審査パイプラインに一切触れない。→ `fastlane expire_train
    version:X.Y.Z`（`expire-build.yml`）で該当trainのビルドだけexpireする。
  - **鉄則**: 「取り下げ」「あげて」「出して」は曖昧語。対象が
    ①TestFlight（ベータ配信・テスター向け）か ②App Store審査（一般公開）か
    を**必ず先に確認**してから、reject/submit のような取り返しのつかない
    操作を実行する。一度取り違えて実害を出している。
- **同時に審査へ出せる編集中バージョンは1つだけ**。`N` が審査中/未公開の
  まま `N+1` は作れない。次を出すには **①`N`を公開まで進める** か
  **②`N`を却下/取り下げて`N+1`に統合** のどちらか。
- **統合パターン**：`reject_if_possible:true` で審査中を自動却下 →
  新バージョンを作成・提出。今回は
  「1.0.2→(取り下げ)→1.0.3→(取り下げ)→1.0.4→1.0.5」と何度も上位番号へ
  巻き取った。**未公開バージョンは番号を上げて丸ごと巻き取れる**
  （下位の内容は上位に全部含める）。
- **ビルド処理待ちは必須**：アップロード直後に `release` を回すと
  `latest_testflight_build_number` が**古いビルドを掴み**、新バージョンに
  旧ビルド(=別バージョン文字列)を貼ろうとして失敗する。**アップロード後
  約20〜25分待ってから提出**する。
- **`automatic_release:true`** にしておくと「承認されたら自動公開」。
  都度の手動公開が不要。
- **ログの `conclusion:success` を鵜呑みにしない**。小規模アプリは
  `build_app` が1〜2分で終わるので「速すぎ＝失敗？」と疑い、**必ずログで
  `Archive Succeeded` / `Uploaded build N` /
  `Successfully submitted the app for review!` を確認**する。
- **プライバシーは三者一致**：①栄養ラベル ②公開プライバシーポリシー本文
  ③アプリの実挙動。バックエンドに個人情報を送るなら「データを収集して
  いません」は使えない。**ラベルはビルドと独立して審査中でも編集可**
  なので、挙動を変えたら即ラベルも更新（不一致は却下理由）。

---

## 4. 実装の落とし穴（Swift/並行処理）★

- **@Published の変更は必ずメインスレッドで**。CloudKit/CoreDataの
  完了ハンドラ（`persistUpdatedShare`・`CKFetchShareMetadataOperation`等）は
  **バックグラウンドキューで呼ばれる**。そこから @Published/@State を直接
  触ると SwiftUI の AttributeGraph 更新がバックグラウンドで走り
  EXC_BREAKPOINT で即死（1.2.51実機クラッシュ: CloudKitSyncMonitor.log が
  logShareEvent 経由でCoreDataキューから呼ばれた）。対策は**受け側で
  funnel**する: log() 等の入口で `Thread.isMainThread` を見て
  `DispatchQueue.main.async` へ。呼び出し側の1箇所を直すだけだと
  次の呼び出し元でまた死ぬ。
- **`@MainActor` な `ObservableObject` からバックグラウンドCore Data
  書き込みをする時**：書き込みクロージャが `@MainActor` に推論されると、
  background queue上で実行された瞬間に破綻する。
  - 解決：変換ロジックを **`nonisolated static func` にして依存
    (サービス群/値)を引数で渡す**。呼び出し側で
    `let 依存 = self.依存` と**ローカルに退避**してからクロージャに渡すと、
    クロージャが `self`(=main actor) を掴まず非分離になる。
  - `@MainActor` クラスでも `init` を `nonisolated` にすると、非分離な
    合成ルートから素直に生成できる。
- **`.create` イベントは数量に効く**。「ロット/個体を代表として仮生成
  して貸出だけ記録したい」等では、`registerUnit`(=+1 createイベント) を
  使わず、**ユニットを直接作って即checkout(delta 0)** すれば数量合計を
  汚さない（checkedOutはon-hand扱いでない前提を確認）。
- **URLSessionのasync API（`data(for:)`）はiOS15+で使える**。軽い外部
  連携なら第三者SDK不要、素の `URLSession` で十分。

---

## 5. 最小バックエンド連携（Layer A/B）

- **QRは「URL」にする**：ラベルに `https://<自前ドメイン>/<コード>` を
  焼くと、**アプリ未導入の人がカメラで読んでもApp Storeへ誘導**でき、
  導入済みなら Universal Links でアプリが該当画面を開く。旧来のベア
  コードも `extractCode()` で両対応に。
  - AASA(`/.well-known/apple-app-site-association`)はドメインroot直下・
    `Content-Type: application/json`・entitlementに `applinks:<domain>`。
    静的ホスティング(Vercel等)で十分。
- **「登録不要の外部フォーム」は Supabase が相性◎**：
  - **anon(公開)キーはpublic-by-design**。RLS＋`SECURITY DEFINER` RPC で
    権限を絞れば、クライアントにも公開Webフォームにも埋め込んでよい。
  - 書き込み専用フォーム→ `POST /rest/v1/<table>`、読み取り/更新は
    RPC(`/rest/v1/rpc/<fn>`)に限定。アプリ側は**自分が持つコードだけ**を
    渡して取得＝テナント越しの漏洩を防ぐ。
- **外部送信を1つでも足したらプライバシーポリシー＆ラベルを即更新**
  （§3参照）。

---

## 6. プロダクト/UXの学び

- **「自動でやってあげる」が逆に混乱を生む**ことがある。今回は「個体を
  追加すると勝手にQR発行」が分かりにくく、**「空QRを先刷り→現物に貼って
  スキャンで割り当て」に一本化**（自動/直接発行の導線を撤去）して腑に
  落ちた。**入手経路は1本に絞る**。
- **状態の可視化＋その場アクション**：一覧行に「QRあり/なし」を出し、
  無ければ**その行から直接スキャンして割り当て**（別画面で一覧から
  選ばせない）。「見えて」「その場で直せる」は強い。
- **主軸ユースケースにUI/文言を寄せる**（今回は「サンプル管理」）。
  ホーム/スキャン後の第一アクションを主軸に合わせる。

---

## 7. ローカライズ / プロジェクト生成

- **`Localizable.strings` は「キー＝日本語原文」方式**にすると、未翻訳
  でも日本語で表示されるフォールバックが効く。en側は「日本語キー＝
  英訳」。
  - 自動整形器は入れていない → **追加前に既存キーの有無をgrepで確認**
    （重複キーはビルド警告＆後勝ち）。ja/enの対応は手動で担保。
- **`project.pbxproj` はPythonでツリー走査生成**
  （`generate_pbxproj.py`）。**新規`.swift`は再生成で自動取り込み**
  （手動でproject編集不要）。ただし **`MARKETING_VERSION` はスクリプト内
  3辞書＋`Config.xcconfig.example` にハードコード**。バージョン上げは
  全箇所を漏れなく。
- **秘匿値は `Config.xcconfig`(gitignore) 経由**でInfo.plist/
  entitlementsへ `$(VAR)` 展開。exampleだけをコミット。

---

## 8. 進め方（プロセス）の学び

- **ローカルにSwiftコンパイラが無くてもCIが唯一の検証手段**。実装→push→
  `beta`ビルドを回して**コンパイル確認＝実質の型チェック**にする（失敗
  してもupload前に落ちるので低リスク）。
- **外部の非同期待ち（Apple処理・CI）は「タイマー(background sleep)で
  再入」**して進める。イベント通知が来ない待ちはポーリング前提で設計。
- **却下/取り下げのような外向き・不可逆操作はユーザー確認を挟む**
  （今回はどのバージョンに巻き取るかを都度確認）。ユーザーが自分で
  取り下げる運用もアリ。
- **リリースは番号戦略を先に決める**：「未公開のうちは番号を上げて
  統合」「公開済みなら次番号で追加」。

---

## 9. CloudKit同期・共有の実戦知見（1.1.3〜1.1.20で血を流して確定）★★

### 9.1 共有が本番だけ全滅する最大の罠：`cloudkit.share` 型
- **Productionは絶対に型を自動作成しない**。`CD_*` だけでなく、CKShareの
  システム型 **`cloudkit.share` もDevelopment→Productionのデプロイで運ぶ**
  必要がある。無いと共有リンク作成が
  `CKErrorDomain #12 / CKInternalErrorDomain 2006
  "Cannot create new type cloudkit.share in production schema"` で全滅。
- ゾーン保存はアトミックなので、同じバッチの他レコードは
  `#22 "Atomic failure"(2024)` で巻き添え失敗 →
  NSPersistentCloudKitContainerのイベントには**素のCKError#2
  (partialFailure)しか出ず、真の理由はイベントerrorから取れない**
  （コンソールにしか出ない）。
- Developmentに `cloudkit.share` を作る方法は2つ：
  ①Debug実行(=Development環境)で共有を1回実際に作る、
  ②.ckdbに **`RECORD TYPE "cloudkit.share" (…)` を引用符付きで**含めて
  Import Schema（**無引用だとドットで構文エラー**
  `Encountered "." … Was expecting "("`）。②は検証済みで動く。
  インポート後、サーバー側が本物のシステム型（cloudkit.title等9フィールド）
  に展開してくれる。

### 9.2 真因特定はアプリ内プローブが最強（TestFlightにコンソールは無い）
- 使い捨てゾーンに `CD_Project` + `CKShare` を**直接
  `CKModifyRecordsOperation` で保存**するボタンを診断画面に置く。
  直接APIのエラーには **`ServerErrorDescription`**（真の理由）が入る。
- **Result版APIの罠**：`modifyRecordsResultBlock` はレコードが全部
  拒否されても **`.success`** を返す（操作としては完了扱い）。判定は
  必ず `perRecordSaveBlock` の失敗を集約して行う。
- 診断ログにはエラーツリーを**全部**吐く：`partialErrorsByItemID` /
  `NSDetailedErrorsKey` / `NSUnderlyingError` / userInfoの全String値。
  自己参照ループがあるので訪問済み管理＋深さ上限は必須。

### 9.2.5 `cloudkit.share` の次に来る第2の罠：`CD_moveReceipt`
- 共有は「CKShare作成」→「対象グラフを共有ゾーンへ**移動**」の2段階。移動時に
  Core Dataは全レコードへ内部フィールド **`CD_moveReceipt BYTES`**
  （＋`CD_moveReceipt_ckAsset ASSET`）を書く。本番に無いと
  `Cannot create or modify field 'CD_moveReceipt' in record 'CD_…'` で
  移動が全滅し、**リンクは発行できるのに中身が空／参加者追加が失敗**という
  紛らわしい状態になる。
- 型の確証源：実プロジェクトのスキーマ書き出し複数
  （perfect-nap / simpleledger / mySpot）＋Apple技術者の回答
  （WWDC22 lounge:「中身は私的なアーカイブ」）＋シリアライザ実装解析。
  **本番のフィールド型は作成後に変更・削除不可**なので、推測で作るのは厳禁。
- **内部フィールドの完全リスト**（シリアライザのキー列挙で確定）：
  `CD_entityName` ／ 属性ごとの `CD_<attr>`（可変長は `_ckAsset` 併設）／
  to-one関係の `CD_<rel>` STRING ／ `CD_moveReceipt`(+`_ckAsset`) ／
  多対多がある場合のみ CDMR型。**これ以外は無い**ので、これで打ち止め。
- プローブの盲点：新規ゾーンに新規レコード＋CKShareを作るテストは
  **移動を発生させない**ため moveReceipt 欠落を検出できない。移動まで
  検証するには「既存ゾーンのレコードを共有する」実共有が必要。

### 9.3 .ckdb（CKMLインポート）の細則
- Import Schemaは**Developmentスキーマの置き換え**。差分ではなく
  **常に全型入りのフルファイル**を取り込む。
- **BYTESフィールドに QUERYABLE/SORTABLE を付けない**（Core Data純正の
  ミラーリングは付けない。デプロイ時に索引削除の差分が出たら消してよい）。
- Core Data→CD_マッピング：String/UUID→STRING+`_ckAsset ASSET`、
  Bool/Int→INT64、Date→TIMESTAMP、Binary→BYTES+`_ckAsset`、
  to-one→`CD_<rel>` STRING（REFERENCEではない）、to-many→フィールド無し、
  全型に `___`系6システムフィールド＋`CD_entityName`。
  生成スクリプト: `Scripts/generate_ckdb.py` → `docs/cloudkit/tanamiru-schema.ckdb`。

### 9.4 UICloudSharingController の正しい使い方
- **未共有レコードには `init(preparationHandler:)`**。ハンドラ内で
  `container.share([obj], to: nil)` してから completion。
  生成直後のCKShareを `init(share:container:)` に渡すと
  failedToSaveShareWithError（Apple明記の誤用）。既存共有の管理のみ
  `init(share:container:)`。
- 保存後は **`persistUpdatedShare(_:in: privateStore)`** 必須
  （Core Dataは自動で書き戻さない）。`Info.plist` に
  **`CKSharingSupported = true`**。
- **SwiftUIの `.sheet` でホストしない**。共有セクションが
  syncMonitor等の頻繁にpublishするオブジェクトを購読していると、
  再描画のたびに `.sheet` 内のrepresentableが破棄→「一瞬開いて閉じる」。
  **キーウィンドウ最前面VCから直接 `present`**（delegateは
  associated objectで保持）すれば再描画の影響を受けない。

### 9.5 その他のCloudKit地雷（このアプリで実際に踏んだもの）
- **`@FetchRequest(sortDescriptors:)` はCloudKit有効時に entity が
  nil になり得る**（複数モデルバージョン＋ミラーリングでクラス→entity
  対応が壊れる）→ 全部 `@FetchRequest(fetchRequest:)`＋
  `Type.fetchRequest()`（エンティティ名ベース）にする。
- **`storeDescription.configuration = "Default"` は誤り**。モデルに
  その名の構成が無ければ 134060 で全ストアロード失敗。**nil**にする
  （暗黙のデフォルト構成）。
- **同期エラーの表示は「次の成功イベントで自動解除」**を必ず実装する。
  「エラー保持のearly return」だけだと解除経路が存在せず、起動ごとに
  手動リセットが必要な最悪UXになる（保留アップロードが1回失敗→以降
  成功でも表示が残る）。

### 9.6 招待リンクの行き止まり（1.2.52で修正）★
- **症状**: 招待リンクを受け取った人がリンクを開くと「Appleアカウントに
  サインイン」だけ出て、参加が成立しない（所有者側にも参加者が現れない）。
- **真因は2つの合わせ技**:
  1. `UICloudSharingController.availablePermissions` に **`.allowPublic` が
     無く、共有が常に招待制（invite-only）**。それなのに独自の
     「招待リンクを送る」は `share.url` を生のままLINE/メールで配るため、
     受信者のApple IDは参加者に登録されておらず、サインインしても弾かれる。
     → 生リンクを配る運用なら **`share.publicPermission = .readWrite` に
     昇格して `persistUpdatedShare` してから送る**（ensureLinkJoinable）。
  2. **LINE等のアプリ内ブラウザは icloud.com 共有リンクをアプリに
     ハンドオフしない**（`userDidAcceptCloudKitShareWith` が呼ばれない）。
     → ブラウザ経由に依存しない回収動線として「**招待リンクから参加**」
     （リンク貼り付け → `CKFetchShareMetadataOperation` →
     `acceptShareInvitations`）をプロジェクト画面の「…」に用意する。
     招待文にも③としてこの手順を明記。
- 受諾処理の結果は必ずUIに出す（`acceptFeedback`）。握りつぶすと
  「リンクが何もしない」と区別がつかない。
- 貼り付け解釈は `CloudSharingService.extractShareURL`：メッセージ全文
  貼り付けOK・未エンコードの日本語フラグメントは#前のトークンに落とす。

## 10. 運用インフラ（1.2.11: リモート設定・バックアップ・ローカルストア）

### 10.1 リモート設定 (RemoteConfig)
- 置き場所: `tanamiru-site/app-config.json` → https://tanamiru.l0l0.app/app-config.json
  （Vercel Git連携なので **このリポジトリにpushすれば約1分で全端末に反映**。
  アプリのリリース不要）。vercel.json で no-cache ヘッダー付与済み。
- アプリ側: `RemoteConfig.shared`（起動時 + フォアグラウンド復帰で取得、
  15分スロットル、最後に成功したJSONを UserDefaults にキャッシュ、
  オフライン時はハードコードの既定値で完全動作）。
- キー（v1）:
  - `teamPlanEnabled` (既定 false): チーム課金UI。**1.3はASCで商品を
    作成したあと、このフラグをtrueにするだけで有効化できる**
    （EntitlementService.teamPlanEnabled が参照）。
  - `deleteEnabled` (既定 true): 製品・個体削除UIのキルスイッチ。
  - `sharingEnabled` (既定 true): 共有の**新規開始**のキルスイッチ
    （既存共有の管理は止めない）。
  - `notice` {title?, message, url?}: ホーム最上部のお知らせバナー。
    障害・メンテ告知用。null で非表示。
- 原則: リモートで変えられるのは「すでに審査を通った挙動のON/OFF」だけ。
  コード配信や価格変更に使わない（審査規約違反）。

### 10.2 端末内バックアップ (BackupService)
- 目的: 共有プロジェクトはメンバーの削除ミスや同期競合が**全員に伝播**
  する。iCloudから消えたレコードは戻せないため、各端末が毎日ローカルに
  スナップショットを持つのが最後の砦。
- 仕様: 起動時に1日1回（20h間隔）、全「実」プロジェクトをJSONで
  Application Support/Backups に保存、最新14件ローテーション。
  設定 > データ > バックアップ から手動バックアップ・書き出し・復元。
- 復元は**必ず新規プロジェクト「◯◯（復元）」として追加**（既存データに
  マージしない = 復元操作自体が事故を起こさない）。QRコードは元の文字列で
  再生成するので**印刷済みラベルがそのまま使える**。ただし同じコードが
  まだ生きている場合はスキップ（既存側が優先、コードの一意性を守る）。
- スナップショット対象: 構成（フォルダ/場所/製品）・在庫数・個体（貸出中
  の借り手/期限含む）・ロット（期限含む）・QRコード割り当て・空きQR。
  含まないもの: 写真・操作履歴（履歴は台帳イベントの責務）。

### 10.3 お試しデータはローカル専用ストア (local.sqlite)
- 3ストア構成に変更: private.sqlite (.private) / shared.sqlite (.shared) /
  **local.sqlite（CloudKitオプションなし＝絶対に同期されない）**。
- `StoreRouter.assignNewProject` が `project.isSample` で振り分け。
  お試しデータがiCloud容量を食わない・実データと衝突しない・削除後に
  他端末から復活しない。
- 既存ユーザーは起動時に一度だけ移行（ServiceContainer.
  migrateSampleDataToLocalStoreIfNeeded）: クラウド側のお試しを削除→
  ローカルに再生成。フラグは成功時のみ立てる。
- 注意: ローカルストアのオブジェクトは共有(CKShare)不可（お試しは
  そもそも共有対象外）。`initializeCloudKitSchema` はCloudKitストアにのみ
  作用するので影響なし。

### 10.4 QRの付け直し（紛失時）と譲渡の廃止
- 譲渡UIは1.2.11で廃止（ユーザー判断: 貸出と削除で十分）。retireUnit
  サービス自体は残置。
- 「貸出から戻ったらQRシールが無くなっていた」の救済:
  個体の長押しメニュー（イレギュラー操作なので奥に配置）→
  「QRを付け直す（紛失時）」→ 空QRをスキャンで再割り当て。
  このとき**旧ラベルは自動で無効化**（1個体=1QR。紛失したQRが後日
  出てきても退役済みなので誤読しない）。

### 10.5 サイトのアイコン方針
- **サイト（tanamiru-site/・docs/guide/）に絵文字は使用禁止**（ユーザー指示）。
  各ページ内の `IC` マップ（20×20 線画SVG・stroke=currentColor・タブバー
  アイコンと同スタイル）に集約。インラインは `.icx`、カード見出しは `.ico`。
  ガイドは docs/guide が原本 → tanamiru-site/guide へ cp+sed 同期。

### 10.6 1.2.51 動線総点検（7領域の並列監査より）
- 方針: 「作れるのに、変えられない・消せない・戻せない」を全廃する。
  リネームは共通 RenameSheet（iOS15はalert内TextFieldが出ないためシート式）。
- 追加した回復動線: 個体/ロットのリネーム、ロット編集・削除、貸出の
  期限延長・借り手修正（updateLoan: 成立checkoutイベントを直接更新して
  貸出日を保持）、QRのunassign（空に戻して使い回し）、誤割当のやり直し、
  スキャン直後の取り消し（直近イベントをreverse）、棚卸し行のsetCount/
  removeLine（除去時はseenUnitCodesから引く）、場所の編集配線＋
  deleteLocation（子はCascade・在庫はNullifyで残る・ラベルは空へ）、
  フォルダのリネーム/削除/並び替え/FolderDetailView、空きQR一覧
  (BlankLabelsView)、訂正の確認ダイアログ（EventListViewに集約）。
- 教訓: LocationFormViewの編集モードのように「実装済みだが未配線」の
  機能が残りやすい。画面を作ったら必ず呼び出し元まで通すこと。
