#!/usr/bin/env python3
"""
Discord desktop cache -> Markdown notes for Sentient OS.

Reads the Discord app's HTTP cache (Chromium "simple cache"), pulls out the
message lists Discord fetched for chats you opened, merges them into a local
archive, and writes one Markdown file per DM into an output folder that
Sentient's Files source reads.

Read-only on Discord's files. No network, no Discord token, no API calls.

Usage:
  python3 discord_cache_to_md.py                 # DMs only (default)
  python3 discord_cache_to_md.py --all           # also server channels
  python3 discord_cache_to_md.py --out ~/X --cache ~/Y --days 365
"""
import argparse, datetime as dt, gzip, json, os, re, struct, sys, zlib
from pathlib import Path

HOME = Path.home()
DEFAULT_CACHES = [
    HOME / "Library/Application Support/discord/Cache/Cache_Data",
    HOME / "Library/Application Support/discordptb/Cache/Cache_Data",
    HOME / "Library/Application Support/discordcanary/Cache/Cache_Data",
]
DEFAULT_OUT = HOME / "Sentient Sources/Discord"
STATE = HOME / ".sentient/discord-archive.json"

HEADER_MAGIC = 0xFCFB6D1BA7725C30
EOF_MAGIC = struct.pack("<Q", 0xF4FA6F45970D41D8)

MSG_RE = re.compile(r"/api/v\d+/channels/(\d+)/messages(?:\?|$)")
DM_LIST_RE = re.compile(r"/api/v\d+/users/@me/channels(?:\?|$)")
ME_RE = re.compile(r"/api/v\d+/users/@me(?:\?|$)")
CHANNEL_RE = re.compile(r"/api/v\d+/channels/(\d+)(?:\?|$)")


# ---------- cache parsing ----------

def read_entry(path):
    """Return (key, body_bytes, header_bytes) for a simple-cache *_0 file, or None."""
    data = path.read_bytes()
    if len(data) < 24:
        return None
    magic, _ver, key_len, _hash = struct.unpack_from("<QIII", data, 0)
    if magic != HEADER_MAGIC:
        return None
    key = data[24:24 + key_len].decode("utf-8", "replace")
    body_start = 24 + key_len
    eof1 = data.find(EOF_MAGIC, body_start)
    if eof1 < 0:
        return None
    # Stream 1 (the body) runs from the key to its EOF record. That record's stream_size
    # field is only filled in for stream 0, so it can't be used to find the body.
    body = data[body_start:eof1]
    # Stream 0 (HTTP response info) sits after EOF1; we only need it for content-encoding.
    headers = data[eof1 + 24:]
    return key, body, headers


def decode_body(body, headers):
    enc = b""
    m = re.search(rb"content-encoding:\s*([a-z0-9-]+)", headers, re.I)
    if m:
        enc = m.group(1).lower()
    attempts = []
    if enc == b"br":
        attempts.append("br")
    elif enc in (b"gzip", b"deflate"):
        attempts.append("gzip")
    elif enc == b"zstd":
        attempts.append("zstd")
    attempts += ["raw", "gzip", "br", "zstd"]
    for how in attempts:
        try:
            if how == "raw":
                out = body
            elif how == "gzip":
                out = zlib.decompress(body, 47)  # gzip or zlib
            elif how == "br":
                import brotli
                out = brotli.decompress(body)
            elif how == "zstd":
                import zstandard
                out = zstandard.ZstdDecompressor().decompress(body, max_output_size=64 << 20)
            return json.loads(out.decode("utf-8"))
        except Exception:
            continue
    return None


def scan_cache(cache_dir):
    found = {"messages": [], "dm_channels": [], "channels": [], "me": None, "undecoded": 0}
    for p in cache_dir.glob("*_0"):
        try:
            entry = read_entry(p)
        except OSError:
            continue  # file being written; next run gets it
        if not entry:
            continue
        key, body, headers = entry
        url = key.split(" ")[-1]
        kind = None
        if MSG_RE.search(url):
            kind = "messages"
        elif DM_LIST_RE.search(url):
            kind = "dm_channels"
        elif ME_RE.search(url):
            kind = "me"
        elif CHANNEL_RE.search(url):
            kind = "channels"
        if not kind:
            continue
        obj = decode_body(body, headers)
        if obj is None:
            found["undecoded"] += 1
            continue
        if kind == "me":
            if isinstance(obj, dict) and "id" in obj:
                found["me"] = obj
        elif kind == "channels":
            if isinstance(obj, dict):
                found["channels"].append(obj)
        elif isinstance(obj, list):
            found[kind].extend(o for o in obj if isinstance(o, dict))
    return found


# ---------- archive ----------

def load_state():
    try:
        return json.loads(STATE.read_text())
    except Exception:
        return {"me": None, "channels": {}, "messages": {}}


def save_state(state):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE.with_suffix(".tmp")
    tmp.write_text(json.dumps(state))
    os.replace(tmp, STATE)


def slim(msg):
    a = msg.get("author") or {}
    ref = msg.get("referenced_message") or {}
    return {
        "id": msg["id"],
        "ts": msg.get("timestamp"),
        "edited": msg.get("edited_timestamp"),
        "author_id": a.get("id"),
        "author": a.get("global_name") or a.get("username") or "unknown",
        "content": msg.get("content") or "",
        "attachments": [x.get("filename") for x in msg.get("attachments") or [] if isinstance(x, dict)],
        "embeds": [e.get("title") or e.get("url") for e in msg.get("embeds") or [] if isinstance(e, dict) and (e.get("title") or e.get("url"))],
        "reply_to": [(ref.get("author") or {}).get("global_name") or (ref.get("author") or {}).get("username"),
                     (ref.get("content") or "")[:120]] if ref else None,
        "type": msg.get("type", 0),
    }


def channel_info(ch):
    recips = [r.get("global_name") or r.get("username") for r in ch.get("recipients") or [] if isinstance(r, dict)]
    return {"type": ch.get("type"), "name": ch.get("name"), "recipients": [r for r in recips if r],
            "guild_id": ch.get("guild_id")}


# The DM list (/users/@me/channels) is rarely cached, so tell DMs from servers by the messages.
# Types 1/2/4 also occur in server threads, so only calls count as DM-only.
DM_ONLY_TYPES = {3}  # call
GUILD_ONLY_TYPES = {7, 8, 9, 10, 11, 12, 18, 21, 24}  # joins, boosts, follows, threads, automod


def evidence(msg):
    if msg.get("type") in DM_ONLY_TYPES or msg.get("call"):
        return "dm_seen"
    if (msg.get("type") in GUILD_ONLY_TYPES or msg.get("mention_roles") or msg.get("webhook_id")
            or "member" in msg or (msg.get("message_reference") or {}).get("guild_id")):
        return "guild_seen"
    return None


def infer_me(state):
    """Without a cached /users/@me, you're the author present in most of your chats."""
    seen = {}
    for bucket in state["messages"].values():
        for aid in {m["author_id"] for m in bucket.values()}:
            seen[aid] = seen.get(aid, 0) + 1
    if not seen:
        return
    aid, n = max(seen.items(), key=lambda kv: kv[1])
    if n >= 2 and n > len(state["messages"]) / 2:
        name = next(m["author"] for b in state["messages"].values() for m in b.values() if m["author_id"] == aid)
        state["me"] = {"id": aid, "name": name, "inferred": True}


def merge(state, found):
    if found["me"]:
        me = found["me"]
        state["me"] = {"id": me.get("id"), "name": me.get("global_name") or me.get("username")}
    for ch in found["dm_channels"] + found["channels"]:
        if "id" in ch:
            prev = state["channels"].get(ch["id"], {})
            info = channel_info(ch)
            state["channels"][ch["id"]] = {**prev, **{k: v for k, v in info.items() if v}}
    changed = set()
    for m in found["messages"]:
        if "id" not in m or "channel_id" not in m:
            continue
        bucket = state["messages"].setdefault(m["channel_id"], {})
        s = slim(m)
        if bucket.get(m["id"]) != s:
            bucket[m["id"]] = s
            changed.add(m["channel_id"])
        ev = evidence(m)
        if ev:
            state["channels"].setdefault(m["channel_id"], {})[ev] = True
    if not state.get("me") or state["me"].get("inferred"):
        infer_me(state)
    return changed


# ---------- markdown ----------

def is_dm(info):
    return info.get("type") in (1, 3) or (info.get("dm_seen") and not info.get("guild_seen"))


def is_guild(info):
    return bool(info.get("guild_id") or info.get("guild_seen"))


def title_for(cid, info, msgs, me_id):
    if info.get("name"):
        return info["name"]
    if info.get("recipients"):
        r = info["recipients"]
        return r[0] if len(r) == 1 else ", ".join(r[:3]) + (f" & {len(r) - 3} others" if len(r) > 3 else "")
    others = sorted({m["author"] for m in msgs if m["author_id"] != me_id})
    return ", ".join(others[:3]) or "chat"


def safe_name(s):
    s = re.sub(r'[\\/:*?"<>|\n\r\t]+', " ", s).strip().strip(".")
    return (s or "untitled")[:80]


def fmt_time(ts):
    try:
        t = dt.datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone()
        return t.strftime("%Y-%m-%d %H:%M")
    except Exception:
        return ts or ""


SYSTEM_TEXT = {1: "(added someone to the chat)", 2: "(removed someone from the chat)", 3: "(started a call)",
               4: "(renamed the chat)", 5: "(changed the chat icon)", 6: "(pinned a message)"}


def render(cid, info, msgs, me_id, kind):
    title = title_for(cid, info, msgs, me_id)
    lines = [f"# Discord {kind}: {title}", "",
             f"Source: Discord desktop cache. {len(msgs)} messages, newest day first. \"Me\" = the Mac's owner.", ""]
    # Newest day first: Sentient's analysis reads only the first 8,000 characters of a note.
    days = {}
    for m in msgs:
        stamp = fmt_time(m["ts"])
        who = "Me" if me_id and m["author_id"] == me_id else m["author"]
        text = m["content"].replace("\n", "\n  ") or SYSTEM_TEXT.get(m.get("type"), "")
        extras = []
        if m.get("reply_to") and m["reply_to"][0]:
            extras.append(f"(replying to {m['reply_to'][0]}: \"{m['reply_to'][1]}\")")
        if m["attachments"]:
            extras.append("[attachments: " + ", ".join(a for a in m["attachments"] if a) + "]")
        if m["embeds"]:
            extras.append("[links: " + ", ".join(m["embeds"]) + "]")
        if m.get("edited"):
            extras.append("(edited)")
        body = " ".join(x for x in [text] + extras if x)
        if not body:
            continue
        days.setdefault(stamp[:10], []).append(f"- **{stamp[11:]} {who}:** {body}")
    for day in reversed(days):
        lines += ["", f"## {day}", ""] + days[day]
    return title, "\n".join(lines) + "\n"


def write_notes(state, out_dir, include_all, days):
    out_dir.mkdir(parents=True, exist_ok=True)
    me_id = (state.get("me") or {}).get("id")
    known_dm = any(c.get("type") in (1, 3) for c in state["channels"].values())  # real DM list cached
    cutoff = None
    if days:
        cutoff = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=days)).isoformat()
    written = skipped = 0
    for cid, bucket in state["messages"].items():
        info = state["channels"].get(cid, {})
        authors = {m["author_id"] for m in bucket.values()}
        if is_dm(info):
            kind = "DM"
        elif not is_guild(info) and not known_dm and me_id in authors and len(authors) == 2:
            kind = "DM"  # just you and one other person, nothing server-like
        elif include_all:
            kind = "channel" if is_guild(info) else "chat"
        else:
            skipped += 1  # a server channel, or can't tell
            continue
        msgs = sorted(bucket.values(), key=lambda m: (m["ts"] or "", int(m["id"])))
        if cutoff:
            msgs = [m for m in msgs if (m["ts"] or "") >= cutoff]
        if not msgs:
            continue
        title, md = render(cid, info, msgs, me_id, kind)
        path = out_dir / f"{safe_name(title)} ({cid[-4:]}).md"
        if not path.exists() or path.read_text() != md:
            # Replace rather than rewrite in place: Sentient re-analyzes a file only when its
            # "date added" moves, and only a new directory entry moves it.
            tmp = path.with_name(f".{path.name}.tmp")
            tmp.write_text(md)
            os.replace(tmp, path)
            written += 1
    return written, skipped


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--cache", type=Path, action="append")
    ap.add_argument("--all", action="store_true", help="include server channels, not just DMs")
    ap.add_argument("--days", type=int, default=0, help="only write the last N days (0 = everything)")
    a = ap.parse_args()

    caches = [c.expanduser() for c in (a.cache or DEFAULT_CACHES) if c.expanduser().is_dir()]
    if not caches:
        sys.exit("No Discord cache found. Is the Discord desktop app installed?")
    for c in caches:
        try:
            os.listdir(c)  # glob() swallows this and silently finds nothing
        except PermissionError:
            # Under the nightly job, the launcher app holds the grant. Run by hand, it's python:
            # sys.executable names bin/python3.x, but framework Pythons re-exec into
            # Resources/Python.app, and that bundle is what Full Disk Access must name.
            app = os.environ.get("DISCORD_READER_APP")
            if not app:
                exe = os.popen(f"ps -o comm= -p {os.getpid()}").read().strip() or sys.executable
                app = exe.split("/Contents/MacOS/")[0] if "/Contents/MacOS/" in exe else exe
            sys.exit(f"Permission denied reading {c}. macOS protects other apps' data: give "
                     f"{app} (and your terminal) Full Disk Access in "
                     "System Settings > Privacy & Security.")
    state = load_state()
    changed, total, undecoded = set(), 0, 0
    for c in caches:
        found = scan_cache(c)
        total += len(found["messages"])
        undecoded += found["undecoded"]
        changed |= merge(state, found)
    save_state(state)
    written, skipped = write_notes(state, a.out.expanduser(), a.all, a.days)
    print(f"cache messages seen: {total}  chats updated: {len(changed)}  notes written: {written}"
          f"  archive chats: {len(state['messages'])}  skipped (server or unsure): {skipped}"
          f"  out: {a.out.expanduser()}")
    if undecoded:
        print(f"note: {undecoded} cache entries couldn't be decoded"
              + ("" if _has_brotli() else " (install brotli: python3 -m pip install --user brotli)"))


def _has_brotli():
    try:
        import brotli  # noqa
        return True
    except ImportError:
        return False


if __name__ == "__main__":
    main()
