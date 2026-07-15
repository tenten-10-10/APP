# Cowork 指示書（Phase 2）— タナミル を TestFlight に上げる

アプリレコードは作成済み。ここから **TestFlight にビルドを上げて確認できる状態**まで進めてください。
以下をそのまま Cowork に貼れます。確定値は本文に埋め込み済みです。

## 確定情報
- リポジトリ: `tenten-10-10/app`　ブランチ: `claude/confident-rubin-0np4rh`
- App 名: タナミル / Bundle ID: `com.tenten.tanamiru`
- CloudKit コンテナ: `iCloud.com.tenten.tanamiru`
- Xcode scheme: `ProjectStock`

---

## 【Cowork への依頼】タナミルを TestFlight へ

### 注意
- ブラウザ操作は私の Apple ID で。**2FA コードは私の端末に届く**ので必要時に促して。
- Terminal を使える場合は Part 2 も実行。使えない/エラー時は、出力（特にエラー全文）を貼って私に渡して。
- 破壊的操作はしない。最後の「報告」を全部埋める。**.p8 は安全に保管**（再DL不可）。

---

### Part 1 — ブラウザ作業（developer.apple.com / App Store Connect）

**1. App ID の Capability を確認・修正**
1. `developer.apple.com/account/resources/identifiers/list` → `com.tenten.tanamiru` を開く。
2. 次が有効か確認。無ければチェックして Save:
   - ☑ **iCloud**（「Include CloudKit support」）→ Configure/Edit で **`iCloud.com.tenten.tanamiru`** を割り当て（未作成なら右上プルダウン「iCloud Containers」→ + で作成してから割当）。
   - ☑ **Push Notifications**
3. 保存。

**2. Team ID を取得**
- `developer.apple.com/account` → **Membership details** → **Team ID**（10桁英数）を控える。

**3. App Store Connect API キーを作成**
1. `appstoreconnect.apple.com` → **Users and Access** → タブ **Integrations**（または Keys）→ **App Store Connect API** → **Team Keys**。
2. 初回は有効化（Request Access / Enable）。
3. **+ (Generate API Key)** → Name `fastlane`、Access(Role) **Admin** → Generate。
   - ※ クラウド署名(配布証明書/プロファイルの自動生成)には **Admin** が必要。App Manager だと「Cloud signing permission error」になります。
4. 生成行の **Download API Key** で **.p8 を Mac に保存**（1回限り）。保存先パスを控える（例 `~/private_keys/AuthKey_XXXXXXXXXX.p8`）。
5. **Issuer ID**（ページ上部）と **Key ID**（キー行）を控える。

---

### Part 2 — Mac で fastlane 実行（Terminal が使える場合）

> 前提: macOS に **Xcode 26** がインストール済みで、一度起動してライセンス同意済み
> （`sudo xcodebuild -license accept`）。`xcode-select --install` 済み。

**1. コードを取得**
```sh
# 未クローンなら
git clone https://github.com/tenten-10-10/app.git tanamiru && cd tanamiru
# 既にあるなら
# cd tanamiru && git fetch origin
git checkout claude/confident-rubin-0np4rh && git pull origin claude/confident-rubin-0np4rh
```

**2. fastlane を準備**
```sh
gem install bundler 2>/dev/null; bundle install   # うまくいかない場合は: brew install fastlane
```

**3. 認証情報を設定**（Part 1 で控えた値を入れる）
```sh
cp fastlane/.env.example fastlane/.env
# fastlane/.env を編集:
#   ASC_KEY_ID=（Key ID）
#   ASC_ISSUER_ID=（Issuer ID）
#   ASC_KEY_PATH=（.p8 の絶対パス）
#   TANAMIRU_TEAM_ID=（Team ID）
```

**4. ビルド＆アップロード**
```sh
bundle exec fastlane beta      # bundler を使わない場合: fastlane beta
```
- 成功すると「Uploaded build N to TestFlight 🚀」。
- 署名でコケる場合: 一度 Xcode で `ProjectStock.xcodeproj` を開き、Signing & Capabilities の Team を選んで Automatic のままプロファイルを作らせ、再実行。

---

### Part 3 — CloudKit を Production にデプロイ（ブラウザ: CloudKit Console）

> TestFlight ビルドは CloudKit の **Production** を使うため、スキーマを本番へ展開する必要あり。

1. まずスキーマを Development に作る: Mac で `ProjectStock` を**シミュレータ/実機(Debug)で一度起動**し、サンプルデータ生成などを実行（Coreデータ→CloudKit同期でスキーマ生成）。
2. `icloud.developer.apple.com/dashboard` → コンテナ `iCloud.com.tenten.tanamiru` を選択。
3. Schema → **Deploy Schema Changes…** → Development の変更を **Production** へ Deploy。

---

### Part 4 — TestFlight で確認

1. App Store Connect → アプリ「タナミル」→ **TestFlight** タブ。
2. アップロードしたビルドの処理完了（数分）を待つ。**輸出コンプライアンス**を聞かれたら「いいえ（非該当）」でOK（コードで `ITSAppUsesNonExemptEncryption=false` 設定済み）。
3. **内部テスター**に自分を追加 → iPhone の TestFlight アプリでインストール。
4. 動作確認: QRラベル発行/印刷・スキャン入出庫・サンプル/在庫/ロット・貸出の期限通知・iCloud同期。

---

### 報告してほしい
- [ ] Team ID / Issuer ID / Key ID / .p8 の保存パス
- [ ] `fastlane beta` の結果（成功なら build 番号、失敗ならエラー全文）
- [ ] CloudKit Production デプロイ完了の可否
- [ ] TestFlight にビルドが出たか / インストールできたか
- [ ] 途中のエラー画面はスクショで
