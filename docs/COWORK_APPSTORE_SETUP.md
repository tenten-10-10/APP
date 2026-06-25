# Cowork への指示文 — ProjectStock を App Store Connect に登録する

Chrome で Apple のサイトを操作し、TestFlight にビルドを上げられる状態まで登録してください。
以下をそのまま Cowork に貼ってください。先頭の ★ だけ自分で埋めてから渡します。

---

## 【Cowork への依頼】Apple Developer / App Store Connect で iOS アプリ「ProjectStock」を新規登録して

### あなた(Cowork)への注意
- Chrome で私の Apple ID にログインして操作してください。**2要素認証(2FA)のコードは私の手元の端末に届く**ので、入力が必要なときは私に促してください。
- 削除・課金・既存アプリの変更などの破壊的操作はしないでください。新規作成だけ。
- 各手順の完了後に画面のスクショ、または指示された値を控えてください。
- 最後の「### 報告してほしい値」を**すべて**埋めて報告してください。特に **API キーの .p8 はこの Mac にダウンロード**してください(再ダウンロード不可)。

### 事前に決まっている値
- ★ **Bundle ID**: `__________________`  ← (例 `com.yourname.projectstock`。私が所有する逆ドメイン形式)
- App 名(App Store 表示・30字以内・全ストアで一意): `ProjectStock 在庫QR管理`
  - もし既に使われていて登録できない場合は、末尾に語を足して(例 `ProjectStock 在庫QR管理 Pro`)、使った名前を報告して。
- 主要言語: **日本語 (Japanese)**
- SKU: `projectstock-001`
- CloudKit コンテナ ID: `iCloud.` + 上の Bundle ID(例 `iCloud.com.yourname.projectstock`)
- カテゴリ: Primary = **Productivity(仕事効率化)**、Secondary = Utilities(任意)
- 価格: **無料 (Free)**

---

### 手順A. Apple Developer Portal(App ID と iCloud コンテナ)
1. `https://developer.apple.com/account` を開く。
2. 「Membership details」を開き、**Team ID(10桁の英数字)** を控える。
3. 「Certificates, Identifiers & Profiles」→ 左メニュー **Identifiers** → 右上「+」。
4. 「**App IDs**」を選び Continue → 「**App**」を選び Continue。
5. Description に `ProjectStock`、Bundle ID は「**Explicit**」を選び、★Bundle ID を入力。
6. **Capabilities** で次の2つにチェック:
   - **iCloud**(「Include CloudKit support」を選択)
   - **Push Notifications**
7. Continue → Register。
8. 続けて iCloud コンテナを作る: Identifiers 画面の右上プルダウンを「**iCloud Containers**」に切り替え → 「+」 → Description `ProjectStock`、Identifier に `iCloud.<上のBundle ID>` を入力 → Continue → Register。
9. 手順5で作った App ID を一覧から開き、**iCloud** capability の「Configure / Edit」から、手順8で作ったコンテナにチェックを入れて **Save**。

### 手順B. App Store Connect(アプリレコード作成)
10. `https://appstoreconnect.apple.com` → 「**My Apps / アプリ**」→ 「**+**」→ 「**New App / 新規アプリ**」。
11. 次を入力して作成:
    - Platforms: **iOS**
    - Name: 上記の App 名
    - Primary Language: **Japanese**
    - Bundle ID: ドロップダウンから ★Bundle ID を選択
    - SKU: `projectstock-001`
    - User Access: **Full Access**
    - 「Create」。
12. 作成後 **App Information** ページで:
    - **Category**: Primary = **Productivity**、Secondary = Utilities(任意)
    - **Privacy Policy URL**: 仮で `https://example.com/projectstock/privacy`(後で差し替え)
    - 「Save」。
13. **Pricing and Availability** → Price = **Free** → Save。

### 手順C. App Store Connect API キー(fastlane アップロード用)
14. 「**Users and Access**」→ タブ「**Integrations**」(古い UI では「Keys」)→ 「**App Store Connect API**」→ 「**Team Keys**」。
15. 初回で「Request Access / Enable」が出たら有効化する。
16. 「**+**(Generate API Key / キーを生成)」→ Name: `fastlane`、Access(Role): **App Manager** → Generate。
17. 生成された行の「**Download API Key**」を押し、**.p8 ファイルをこの Mac にダウンロード**(1回限り)。保存先パスを控える。
18. ページ上部の **Issuer ID**、キー行の **Key ID** を控える。

---

### 報告してほしい値(私=オーナーに渡す)
- [ ] Team ID:
- [ ] 確定した Bundle ID:
- [ ] CloudKit コンテナ ID:
- [ ] App の Apple ID(数字の App ID)/ SKU:
- [ ] API: **Issuer ID** / **Key ID** / **.p8 の保存パス**
- [ ] App 名を変更した場合は、その名前
- [ ] 途中で詰まった画面があれば、そのスクショ

---

## このあと(オーナー=Claude 側でやること)
Cowork から上記の値をもらったら、私(Claude)が以下を行います:
1. `Scripts/generate_pbxproj.py` の `DEVELOPMENT_TEAM` / `PRODUCT_BUNDLE_IDENTIFIER` /
   `CLOUDKIT_CONTAINER_IDENTIFIER`(+ tests/uitests の bundle id)を実値へ更新し、再生成。
2. `fastlane`(Fastfile/Appfile)を作成 — `fastlane beta` で archive→TestFlight upload。
   App Store Connect API キー(Issuer ID/Key ID/.p8)を使うので 2FA 不要・自動化可能。
3. 配布ビルド用に `aps-environment` を `production` にする対応(CloudKit 本番環境向け)。
4. Mac での実行手順を案内。

> ※ TestFlight 配布ビルドは **CloudKit の Production 環境**を使います。アプリを一度
> 実機/シミュレータで起動してスキーマを Development に作成 → CloudKit Console で
> 「Deploy Schema Changes to Production」を実行する必要があります(この手順も後で案内/
> Cowork に依頼可能)。
