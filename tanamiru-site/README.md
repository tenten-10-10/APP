# タナミル サイト（`tanamiru.l0l0.app`）

タナミルの公開サイト。現状は `/guide/`（使い方ガイド）が本体で、ルートはガイドへ転送。
将来ここをマーケティングサイト本体に育てる。

- `guide/index.html` … 使い方ガイド（正本は `docs/guide/`。更新時は両方へ反映）
- `guide/team.html` … タナミル チーム案内の器（1.3審査通過後に内容を実装）

## 初回セットアップ（Vercelダッシュボード・一回きり）
1. Add New → Project → GitHub `tenten-10-10/APP` を選択
2. **Root Directory: `tanamiru-site`** / Framework: Other（静的）
3. Settings → Git → Production Branch を `claude/confident-rubin-0np4rh` に変更（mainへマージ後は main に戻す）
4. Settings → Domains → **`tanamiru.l0l0.app`** を追加
   （`l0l0.app` が同一Vercelアカウント管理のため自動で検証・割り当てされる）

以後は git push だけで自動デプロイ。

## デザイン方針（必読）

- **絵文字はサイトに使用しない**（2026-07-06 ユーザー指示）。アイコンは
  各ページ内の `IC` マップ（20×20・線画SVG・currentColor）に統一。
  新しいアイコンが必要なときは同スタイルで `IC` に追加し、
  `<span class="icx" data-ic="name"></span>`（インライン）または
  `<div class="ico" data-ic="name"></div>`（カード）で使う。
