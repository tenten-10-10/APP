#!/usr/bin/env python3
"""Amazon Vine レビュー下書き自動生成ツール。

流れ:
  1. fetch    : Vineの「レビューを書く」ページからレビュー待ち商品を取得して data/queue.json に貯める
  2. memo     : 商品ごとに使用メモと星評価を登録する（メモがないとレビューは生成しない）
  3. generate : prompt.md のプロンプトで Claude API にレビューを書かせ、data/reviews/ に蓄積する

生成されるのはあくまで下書き。Amazonへの投稿は自分でコピペして行う（自動投稿はしない）。
"""

import argparse
import datetime
import json
import os
import re
import sys
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"
QUEUE_FILE = DATA_DIR / "queue.json"
REVIEWS_DIR = DATA_DIR / "reviews"
PROFILE_DIR = DATA_DIR / "browser-profile"
PROMPT_FILE = BASE_DIR / "prompt.md"

VINE_REVIEWS_URL = "https://www.amazon.co.jp/vine/vine-reviews"
MODEL = os.environ.get("VINE_MODEL", "claude-opus-4-8")
LOGIN_TIMEOUT_SEC = 300
MAX_PAGES = 30


# ---------------------------------------------------------------- queue I/O

def load_queue() -> dict:
    if QUEUE_FILE.exists():
        return json.loads(QUEUE_FILE.read_text(encoding="utf-8"))
    return {"items": {}}


def save_queue(queue: dict) -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    QUEUE_FILE.write_text(
        json.dumps(queue, ensure_ascii=False, indent=2), encoding="utf-8"
    )


def now_iso() -> str:
    return datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")


# ------------------------------------------------------------------- fetch

def cmd_fetch(args: argparse.Namespace) -> None:
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        sys.exit(
            "playwright がありません。以下でインストールしてください:\n"
            "  pip install -r requirements.txt && playwright install chromium"
        )

    PROFILE_DIR.mkdir(parents=True, exist_ok=True)
    scraped: list[dict] = []

    with sync_playwright() as p:
        # 永続プロファイル: 初回に手動ログインすれば次回以降は保持される
        ctx = p.chromium.launch_persistent_context(
            str(PROFILE_DIR),
            headless=False,
            locale="ja-JP",
            viewport={"width": 1280, "height": 900},
        )
        page = ctx.pages[0] if ctx.pages else ctx.new_page()
        page.goto(VINE_REVIEWS_URL, wait_until="domcontentloaded")

        if not _wait_for_vine_page(page):
            ctx.close()
            sys.exit("ログインが確認できませんでした。もう一度 fetch を実行してください。")

        for page_no in range(1, MAX_PAGES + 1):
            page.wait_for_timeout(1500)
            items = _extract_items(page)
            print(f"  ページ{page_no}: {len(items)}件")
            scraped.extend(items)
            if not _goto_next_page(page):
                break

        if not scraped:
            debug = DATA_DIR / "debug_page.html"
            debug.write_text(page.content(), encoding="utf-8")
            print(f"商品が見つかりませんでした。ページ構造確認用に {debug} を保存しました。")

        ctx.close()

    queue = load_queue()
    added = 0
    for item in scraped:
        asin = item["asin"]
        if asin in queue["items"]:
            queue["items"][asin]["name"] = item["name"]  # 商品名は最新に更新
        else:
            queue["items"][asin] = {
                "asin": asin,
                "name": item["name"],
                "url": f"https://www.amazon.co.jp/dp/{asin}",
                "memo": "",
                "stars": None,
                "status": "pending",  # pending -> generated
                "fetched_at": now_iso(),
            }
            added += 1
    save_queue(queue)
    print(f"\n取得 {len(scraped)}件 / 新規 {added}件 を {QUEUE_FILE} に保存しました。")
    if added:
        print("次: python vine_review.py memo <ASIN> --stars 4 \"使ってみた感想メモ\"")


def _wait_for_vine_page(page) -> bool:
    """ログイン済みでVineページが表示されるまで待つ。未ログインなら手動ログインを促す。"""
    import time

    deadline = time.time() + LOGIN_TIMEOUT_SEC
    prompted = False
    while time.time() < deadline:
        url = page.url
        if "/vine/" in url and page.query_selector("a[href*='/dp/']"):
            return True
        if ("signin" in url or "/ap/" in url) and not prompted:
            print("Amazonへのログインが必要です。開いたブラウザでログインしてください（最大5分待ちます）...")
            prompted = True
        if "/vine/" in url and not prompted:
            # ページはVineだが商品リンクがまだ無い → 読み込み待ちか0件
            if page.query_selector("#vvp-reviews-table--body-container, .vvp-reviews-table--row"):
                return True
        page.wait_for_timeout(2000)
        if "/vine/" not in page.url and "signin" not in page.url and "/ap/" not in page.url:
            page.goto(VINE_REVIEWS_URL, wait_until="domcontentloaded")
    return "/vine/" in page.url


def _extract_items(page) -> list[dict]:
    """レビュー待ち商品の (asin, name) をページから抽出する。

    Vineのページ構造は変わることがあるので、複数のセレクタを順に試し、
    最終手段として /dp/ リンクを含む行を総なめする。
    """
    row_selectors = [
        "#vvp-reviews-table--body-container tr",
        ".vvp-reviews-table--row",
        "table tr",
    ]
    rows = []
    for sel in row_selectors:
        rows = page.query_selector_all(sel)
        if rows:
            break

    items: list[dict] = []
    seen: set[str] = set()
    for row in rows:
        link = row.query_selector("a[href*='/dp/']")
        if not link:
            continue
        href = link.get_attribute("href") or ""
        m = re.search(r"/dp/([A-Z0-9]{10})", href)
        if not m:
            continue
        asin = m.group(1)
        if asin in seen:
            continue

        name = (link.inner_text() or "").strip()
        if not name:
            img = row.query_selector("img[alt]")
            name = (img.get_attribute("alt") or "").strip() if img else ""
        if not name:
            name = asin

        # 既にレビュー済み（承認済み/審査中）の行はスキップする。
        # 「レビューを書く」リンク/ボタンがある行だけ対象にし、
        # 判定材料が何も無いページ構造なら安全側で全件拾う。
        row_text = row.inner_text() or ""
        has_write_button = bool(
            row.query_selector("a[href*='create-review'], a[href*='review/create']")
        ) or ("レビューを書く" in row_text)
        looks_done = any(w in row_text for w in ("承認済み", "審査中", "却下"))
        if looks_done and not has_write_button:
            continue

        seen.add(asin)
        items.append({"asin": asin, "name": name})
    return items


def _goto_next_page(page) -> bool:
    nxt = page.query_selector("ul.a-pagination li.a-last:not(.a-disabled) a")
    if not nxt:
        return False
    nxt.click()
    page.wait_for_load_state("domcontentloaded")
    return True


# -------------------------------------------------------------------- memo

def cmd_memo(args: argparse.Namespace) -> None:
    queue = load_queue()
    item = queue["items"].get(args.asin)
    if not item:
        sys.exit(f"ASIN {args.asin} はキューにありません。先に fetch を実行してください。")
    item["memo"] = args.text
    if args.stars is not None:
        item["stars"] = args.stars
    save_queue(queue)
    print(f"メモを保存しました: {item['name'][:40]}")
    print("次: python vine_review.py generate")


# -------------------------------------------------------------------- list

def cmd_list(args: argparse.Namespace) -> None:
    queue = load_queue()
    items = list(queue["items"].values())
    if not items:
        print("キューは空です。まず fetch を実行してください。")
        return
    for it in items:
        memo_state = "メモあり" if it["memo"] else "メモ未入力"
        stars = f"星{it['stars']}" if it["stars"] else "星未設定"
        print(f"[{it['status']:9}] {it['asin']}  {stars} / {memo_state}  {it['name'][:50]}")
    pending = sum(1 for i in items if i["status"] == "pending" and i["memo"])
    print(f"\n合計 {len(items)}件（生成可能: {pending}件）")


# ---------------------------------------------------------------- generate

def cmd_generate(args: argparse.Namespace) -> None:
    try:
        from anthropic import Anthropic
    except ImportError:
        sys.exit("anthropic がありません: pip install -r requirements.txt")
    if not os.environ.get("ANTHROPIC_API_KEY"):
        sys.exit("環境変数 ANTHROPIC_API_KEY を設定してください。")

    system_prompt = PROMPT_FILE.read_text(encoding="utf-8")
    queue = load_queue()

    targets = []
    for it in queue["items"].values():
        if args.asin and it["asin"] != args.asin:
            continue
        if it["status"] == "generated" and not args.force:
            continue
        if not it["memo"]:
            if args.asin:
                sys.exit(
                    f"{it['asin']} にはメモがありません。プロンプトの方針上、実際の感想メモなしでは生成しません。\n"
                    f"先に: python vine_review.py memo {it['asin']} --stars 4 \"感想メモ\""
                )
            continue
        targets.append(it)

    if not targets:
        print("生成対象がありません（メモ入力済み・未生成の商品がない）。list で状態を確認してください。")
        return

    client = Anthropic()
    REVIEWS_DIR.mkdir(parents=True, exist_ok=True)

    for it in targets:
        print(f"生成中: {it['name'][:50]} ...")
        stars_line = f"星評価: {it['stars']}" if it["stars"] else "星評価: 未指定（メモの温度感から推定してください）"
        user_content = (
            f"商品名: {it['name']}\n"
            f"商品URL: {it['url']}\n"
            f"{stars_line}\n"
            f"使用メモ:\n{it['memo']}"
        )
        response = client.messages.create(
            model=MODEL,
            max_tokens=4096,
            thinking={"type": "adaptive"},
            # プロンプトが大きいのでキャッシュして連続生成時のコストを下げる
            system=[{
                "type": "text",
                "text": system_prompt,
                "cache_control": {"type": "ephemeral"},
            }],
            messages=[{"role": "user", "content": user_content}],
        )
        review_text = "".join(
            block.text for block in response.content if block.type == "text"
        )

        date = datetime.datetime.now().strftime("%Y%m%d")
        out_file = REVIEWS_DIR / f"{date}_{it['asin']}.md"
        out_file.write_text(
            f"# {it['name']}\n\n"
            f"- ASIN: {it['asin']}\n"
            f"- URL: {it['url']}\n"
            f"- 星評価: {it['stars'] or '未指定'}\n"
            f"- 生成日時: {now_iso()}\n\n"
            f"## 入力メモ\n\n{it['memo']}\n\n"
            f"## 生成されたレビュー\n\n{review_text}\n",
            encoding="utf-8",
        )
        it["status"] = "generated"
        it["generated_at"] = now_iso()
        it["output_file"] = str(out_file.relative_to(BASE_DIR))
        save_queue(queue)
        print(f"  -> {out_file}")

    print(f"\n完了。レビュー下書きは {REVIEWS_DIR} に溜まっていきます。")


# --------------------------------------------------------------------- cli

def main() -> None:
    parser = argparse.ArgumentParser(description="Amazon Vine レビュー下書き自動生成")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("fetch", help="Vineページからレビュー待ち商品を取得する").set_defaults(func=cmd_fetch)

    p_memo = sub.add_parser("memo", help="商品に使用メモと星評価を登録する")
    p_memo.add_argument("asin", help="対象商品のASIN（listで確認）")
    p_memo.add_argument("text", help="使用メモ（実際に使った感想）")
    p_memo.add_argument("--stars", type=int, choices=[1, 2, 3, 4, 5], help="星評価")
    p_memo.set_defaults(func=cmd_memo)

    sub.add_parser("list", help="キューの状態を表示する").set_defaults(func=cmd_list)

    p_gen = sub.add_parser("generate", help="メモ入力済みの商品のレビューを生成する")
    p_gen.add_argument("--asin", help="特定のASINだけ生成する")
    p_gen.add_argument("--force", action="store_true", help="生成済みでも再生成する")
    p_gen.set_defaults(func=cmd_generate)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
