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
