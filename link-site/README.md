# タナミル リンクサイト（`t.l0l0.app`）

スキャンしたQRのURL（`https://t.l0l0.app/<コード>`）を捌くための、ごく小さな静的サイト。

- `t.l0l0.app` に **タナミルがインストール済み** → iOS が Universal Link でアプリを直接開く（このサイトは表示されない）。
- **未インストール** → ブラウザがこのサイトを開き、App Store への導線を表示する。

## 中身
- `.well-known/apple-app-site-association` … Universal Links 設定。`appIDs` は `3FGX27GY77.com.tenten.tanamiru`。
- `index.html` … 未インストール時の案内ページ（App Store ボタン＋手順）。
- `vercel.json` … AASA の Content-Type を `application/json` にし、`/<コード>` を `index.html` に rewrite。

## デプロイ（Vercel CLI）
既存の `l0l0-portal` とは**別の新規プロジェクト**として上げ、`t.l0l0.app` を割り当てる。

```bash
cd link-site
vercel deploy --prod --yes --name tanamiru-link
# 初回はプロジェクト作成のプロンプトに従う（team は h0301m-7381's projects）
```

その後、Vercel ダッシュボード → tanamiru-link → Settings → Domains で **`t.l0l0.app`** を追加。
（`l0l0.app` が同じVercelアカウント管理なら、サブドメインは自動で検証・割り当てされる）

## 検証
```bash
curl -i https://t.l0l0.app/.well-known/apple-app-site-association
# → 200 / Content-Type: application/json / 上記JSONが返ればOK
```
Apple の CDN がAASAを取得するまで数時間かかる場合がある。
