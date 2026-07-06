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


## /guide/ — 使い方ガイド（2026-07 追加）
- `guide/index.html` … 使い方ガイド本体（`https://t.l0l0.app/guide/`）。`docs/guide/` と同内容（サポート/プライバシーへのリンクのみ絶対URL化）。
- `guide/team.html` … タナミル チーム案内の器（近日公開・noindex）。
- `/:code` の rewrite はファイル実体が優先されるため、`/guide/` 配下と干渉しない。

### 更新の運用（推奨: Git連携）
Vercel ダッシュボード → tanamiru-link → Settings → Git で
GitHub `tenten-10-10/APP` に接続し、Root Directory を `link-site`、
Production Branch を作業ブランチ（例: `claude/confident-rubin-0np4rh`）にすると、
push だけで自動デプロイされる。未接続の間は従来どおり `vercel deploy --prod`。
