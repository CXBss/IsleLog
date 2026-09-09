#!/usr/bin/env python3
"""解析 2020日记.txt（纯文本手写日记），按「日期头 + || + ‖ + 子时间行」拆成多条
memo，通过服务端接口上传到 IsleLog，每条打 #2020手写日记 标签。

日期头格式：  MM.dd<空白{2,}>HH.mm[  天气  正文…]      （. 号分隔，同行可跟正文）
子时间行  ：  行首  HH.mm 或 HH:mm （单个时间，可带“左右”），归属所在日期头的日期
分段符    ：  ||  或  ‖ (U+2016)
规则：首段 createTime = 日期头的日期+时间；子时间段 = 该日期 + 子时间；
      || / ‖ 切出的段若段首带时间用之，否则上一段 +1 分钟（跨天则不加）。
      日期永远取所属日期头的日期，只改时间。

用法：
  python3 tool/upload_2020_diary.py                    # 预演：出报告，不上传
  python3 tool/upload_2020_diary.py --upload           # 上传，记录到 tool/2020-uploaded.json
  python3 tool/upload_2020_diary.py --rollback FILE     # 删除 FILE 里记录的所有 memo
"""
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta

SRC = "/Users/cxb/SyncFiles/记录/生活/回忆/日记/2020日记.txt"
BASE = "http://10.0.9.2:5232/api/v1"
TAG = "2020手写日记"
YEAR = 2020
LOCAL_TO_UTC = timedelta(hours=-8)  # 本地 UTC+8 → UTC
OUT_JSON = "tool/2020-uploaded.json"
REPORT = "tool/2020-split-report.txt"

DATE_HDR = re.compile(r'^(\d{1,2})\.(\d{1,2})[ \t]{2,}(\d{1,2})\.(\d{2})(?![.\d])(.*)$')
# 子时间行：行首一个 HH.mm / HH:mm，其后可选“左右/许”和逗号，再是正文
SUBTIME = re.compile(r'^[ \t]*(\d{1,2})[.:](\d{2})(?![.:\d])[ \t]*(?:左右|许)?[，,]?[ \t]*(.*)$')
SEP = re.compile(r'\|\||‖')


def valid_hm(h, m):
    return 0 <= h <= 23 and 0 <= m <= 59


def valid_md(mo, d):
    return 1 <= mo <= 12 and 1 <= d <= 31


def token():
    return subprocess.check_output(
        ["defaults", "read", "dyc.dev.isleLog", "flutter.memos_access_token"],
        text=True,
    ).strip()


def api(method, path, body=None, tok=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(
        BASE + path, data=data, method=method,
        headers={"Authorization": "Bearer " + tok, "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(r, timeout=30) as f:
        raw = f.read()
        return json.loads(raw) if raw else None


def parse_entries(path):
    lines = open(path, encoding="utf-8").read().replace("\r\n", "\n").split("\n")
    entries, cur = [], None
    for raw in lines:
        mh = DATE_HDR.match(raw)
        if mh:
            mo, d, h, m = map(int, mh.groups()[:4])
            if valid_md(mo, d) and valid_hm(h, m):
                cur = dict(mo=mo, d=d, h=h, m=m, rest=mh.group(5).strip(), body=[])
                entries.append(cur)
                continue
        if cur is not None:
            cur["body"].append(raw)
    return entries


def _split_sep_into(segments, text):
    """把一行按 || / ‖ 切：第一片接到当前段，其余片各起新段（段首带时间则用之）。"""
    parts = SEP.split(text)
    segments[-1]["lines"].append(parts[0])
    for p in parts[1:]:
        mt = SUBTIME.match(p)
        if mt and valid_hm(int(mt.group(1)), int(mt.group(2))):
            segments.append(dict(time=(int(mt.group(1)), int(mt.group(2))),
                                 lines=[mt.group(3)]))
        else:
            segments.append(dict(time=None, lines=[p]))


def segment_entry(e):
    segments = [dict(time=(e["h"], e["m"]), lines=[])]
    if e["rest"]:
        if SEP.search(e["rest"]):
            _split_sep_into(segments, e["rest"])
        else:
            segments[0]["lines"].append(e["rest"])
    for ln in e["body"]:
        mt = SUBTIME.match(ln)
        if mt and valid_hm(int(mt.group(1)), int(mt.group(2))) and not DATE_HDR.match(ln):
            segments.append(dict(time=(int(mt.group(1)), int(mt.group(2))),
                                 lines=[mt.group(3)]))
            continue
        if SEP.search(ln):
            _split_sep_into(segments, ln)
            continue
        segments[-1]["lines"].append(ln)

    # 去掉正文为空的段
    kept = [s for s in segments if "\n".join(s["lines"]).strip()]
    out, prev = [], None
    for s in kept:
        if s["time"] is not None:
            dt = datetime(YEAR, e["mo"], e["d"], s["time"][0], s["time"][1])
        else:
            cand = prev + timedelta(minutes=1)
            dt = cand if cand.date() == prev.date() else prev
        prev = dt
        out.append((dt, "\n".join(s["lines"]).strip()))
    return out


def build(entries):
    memos = []  # (dt_local, content)
    for e in entries:
        for dt, text in segment_entry(e):
            memos.append((dt, f"{text}\n\n#{TAG}"))
    return memos


def write_report(entries, memos):
    b = []
    b.append(f"2020日记 拆分报告  日期头 {len(entries)} 个 → memo {len(memos)} 条")
    b.append("=" * 78)
    idx = 0
    for e in entries:
        segs = segment_entry(e)
        b.append(f"\n[{e['mo']}.{e['d']} {e['h']:02d}.{e['m']:02d}]  → {len(segs)} 段")
        b.append("-" * 78)
        for dt, text in segs:
            b.append(f"  createTime(本地) = {dt:%Y-%m-%d %H:%M:%S}")
            b.append("  " + text.replace("\n", "\n  "))
            b.append("  " + "·" * 38)
        idx += len(segs)
    open(REPORT, "w", encoding="utf-8").write("\n".join(b))


def cmd_dryrun():
    entries = parse_entries(SRC)
    memos = build(entries)
    write_report(entries, memos)
    seg_counts = {}
    for e in entries:
        n = len(segment_entry(e))
        seg_counts[n] = seg_counts.get(n, 0) + 1
    dmin = min(m[0] for m in memos)
    dmax = max(m[0] for m in memos)
    print(f"日期头(entry): {len(entries)}")
    print(f"拆出 memo    : {len(memos)}")
    print(f"每 entry 段数分布: {dict(sorted(seg_counts.items()))}")
    print(f"createTime 范围(本地): {dmin:%Y-%m-%d %H:%M} ~ {dmax:%Y-%m-%d %H:%M}")
    print(f"报告: {REPORT}")
    print("\n前 3 个 entry 的拆分：")
    for e in entries[:3]:
        segs = segment_entry(e)
        print(f"  [{e['mo']}.{e['d']} {e['h']:02d}.{e['m']:02d}] → {len(segs)} 段")
        for dt, text in segs:
            head = text.replace("\n", "⏎")
            print(f"    {dt:%Y-%m-%d %H:%M:%S}  {head[:80]}")


def cmd_upload():
    tok = token()
    entries = parse_entries(SRC)
    memos = build(entries)
    print(f"准备上传 {len(memos)} 条…（Ctrl-C 可中断，已传的记录在 {OUT_JSON}）")
    done = []
    try:
        for i, (dt, content) in enumerate(memos, 1):
            ct = (dt + LOCAL_TO_UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
            res = api("POST", "/memos",
                      {"content": content, "visibility": "PRIVATE", "createTime": ct},
                      tok=tok)
            done.append({"name": res["name"], "createTime": ct,
                         "preview": content[:40].replace("\n", " ")})
            if i % 25 == 0 or i == len(memos):
                print(f"  {i}/{len(memos)}  最新 {res['name']}")
            time.sleep(0.05)
    finally:
        json.dump(done, open(OUT_JSON, "w"), ensure_ascii=False, indent=1)
    print(f"完成，共 {len(done)} 条，清单写入 {OUT_JSON}")


def cmd_rollback(path):
    tok = token()
    items = json.load(open(path))
    print(f"将删除 {len(items)} 条 memo …")
    ok = 0
    for it in items:
        try:
            api("DELETE", "/" + it["name"], tok=tok)
            ok += 1
        except urllib.error.HTTPError as ex:
            print(f"  {it['name']} 删除失败: {ex}")
    print(f"已删除 {ok}/{len(items)}")


if __name__ == "__main__":
    if len(sys.argv) == 1:
        cmd_dryrun()
    elif sys.argv[1] == "--upload":
        cmd_upload()
    elif sys.argv[1] == "--rollback" and len(sys.argv) == 3:
        cmd_rollback(sys.argv[2])
    else:
        print(__doc__)
        sys.exit(1)
