"""Renders pages with tobrod and with Firefox and writes a side-by-side report.

    python tools/compare.py tools/pages.txt
    python tools/compare.py http://127.0.0.1:8765/floats.html odin-lang.org

Firefox runs headless with JavaScript turned off (tobrod has no JavaScript yet,
so that is what we should look like) and the size of tobrod's page view. The
report (screenshots/compare/index.html) shows Firefox, tobrod and a picture of
where they differ. Fonts are rasterized differently, so the numbers are only a
rough guide; the pictures show what is missing.

Real pages are frozen in a snapshot (snapshots/ by default, not in git: it is
the pages' content): the first run records every response tobrod gets
(tobrod --record) and keeps Firefox's picture; later runs replay them
(tobrod --replay) and reuse the picture, without the network and without
Firefox. So runs are fast and before/after pictures show only what changed
in tobrod. Local addresses (the fixtures in testdata/) are always loaded live.

    --refresh         record the pages again (they changed, or tobrod loads more)
    --live            no snapshot: load everything, render Firefox every time
    --snapshot DIR    another snapshot directory
    --tobrod PATH     another tobrod binary (e.g. one built from main)

Needs Pillow (pip install pillow) and Firefox; set FIREFOX if it is not in the
default place. Build tobrod first (odin build .). Run from the repository root.
"""

import argparse
import html
import re
import shutil
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageChops

PAGE_VIEW = (1024, 732)  # tobrod's default window (1024 x 800) minus tabs and address bar
CHROME = 68  # tab bar (32) + address bar (36) above the page
OUT = Path("screenshots/compare")

FIREFOX_PATHS = [
    os.environ.get("FIREFOX", ""),
    r"C:\Program Files\Mozilla Firefox\firefox.exe",
    "/Applications/Firefox.app/Contents/MacOS/firefox",
    "/usr/bin/firefox",
]


def firefox_path():
    for path in FIREFOX_PATHS:
        if path and Path(path).exists():
            return path
    sys.exit("Firefox not found, set FIREFOX to its path")


def tobrod_path():
    for name in ("tobrod.exe", "tobrod"):
        if Path(name).exists():
            return str(Path(name).resolve())
    sys.exit("tobrod not found: build it first (odin build .)")


def complete(url):
    # like tobrod's address bar: no scheme -> https, local addresses -> http
    if "://" in url:
        return url
    host = url.split("/")[0].split(":")[0]
    local = host == "localhost" or host.replace(".", "").isdigit()
    return ("http://" if local else "https://") + url


def firefox_profile():
    profile = Path(tempfile.gettempdir()) / "tobrod-compare-firefox"
    profile.mkdir(exist_ok=True)
    (profile / "user.js").write_text(
        'user_pref("javascript.enabled", false);\n'
        # tobrod only has a light theme; don't follow a dark system theme
        'user_pref("layout.css.prefers-color-scheme.content-override", 1);\n'
        'user_pref("ui.systemUsesDarkTheme", 0);\n'
        # no "what's new" pages, no telemetry on the first start
        'user_pref("browser.startup.homepage_override.mstone", "ignore");\n'
        'user_pref("datareporting.policy.dataSubmissionEnabled", false);\n'
        'user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);\n'
    )
    return profile


def run_firefox(firefox, profile, url, out):
    args = [
        firefox, "--headless", "--no-remote", "-wait-for-browser",
        "--profile", str(profile),
        f"--window-size={PAGE_VIEW[0]},{PAGE_VIEW[1]}",
        "--screenshot", str(out.resolve()), url,
    ]
    subprocess.run(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
    return out.exists()


def is_local(url):
    host = url.split("://", 1)[-1].split("/")[0].rsplit(":", 1)[0].strip("[]")
    return host in ("localhost", "::1") or host.endswith(".localhost") or host.replace(".", "").isdigit()


def slug(url):
    """A file name for a URL: https://en.wikipedia.org/wiki/X -> en.wikipedia.org_wiki_X"""
    return re.sub(r"[^A-Za-z0-9.-]+", "_", url.split("://", 1)[-1]).strip("_")[:120]


def run_tobrod(tobrod, url, out, recording=()):
    window = out.with_suffix(".window.png")
    args = [tobrod, "--url", url, "--screenshot", str(window), *recording]
    result = subprocess.run(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
    if result.returncode != 0 or not window.exists():
        return False
    # only the page view, without the address bar
    with Image.open(window) as im:
        im.crop((0, CHROME, PAGE_VIEW[0], CHROME + PAGE_VIEW[1])).save(out)
    window.unlink()
    return True


def diff(a_path, b_path, out):
    """Red where the pictures differ, on a faded tobrod picture. Returns the
    share of pixels that are (more than slightly) different."""
    a = Image.open(a_path).convert("RGB").resize(PAGE_VIEW)
    b = Image.open(b_path).convert("RGB").resize(PAGE_VIEW)
    mask = ImageChops.difference(a, b).convert("L").point(lambda v: 255 if v > 40 else 0)
    faded = Image.blend(b, Image.new("RGB", PAGE_VIEW, "white"), 0.7)
    faded.paste(Image.new("RGB", PAGE_VIEW, (230, 30, 30)), mask=mask)
    faded.save(out)
    histogram = mask.histogram()
    return histogram[255] / (PAGE_VIEW[0] * PAGE_VIEW[1])


def read_urls(args):
    urls = []
    for arg in args:
        path = Path(arg)
        if path.suffix == ".txt" and path.exists():
            for line in path.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if line and not line.startswith("#"):
                    urls.append(line)
        else:
            urls.append(arg)
    return urls


def main():
    parser = argparse.ArgumentParser(usage=__doc__)
    parser.add_argument("urls", nargs="*")
    parser.add_argument("--snapshot", default="snapshots")
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--refresh", action="store_true")
    parser.add_argument("--tobrod")
    opts = parser.parse_args()
    urls = read_urls(opts.urls)
    if not urls:
        sys.exit(__doc__)
    tobrod = str(Path(opts.tobrod).resolve()) if opts.tobrod else tobrod_path()
    snapshot = Path(opts.snapshot)
    firefox = profile = None  # only started when a page has to be rendered by it
    OUT.mkdir(parents=True, exist_ok=True)

    rows = []
    for i, url in enumerate(urls):
        url = complete(url)
        ff, tb, df = (OUT / f"{i:02}-{kind}.png" for kind in ("firefox", "tobrod", "diff"))
        for old in (ff, tb, df):
            old.unlink(missing_ok=True)

        frozen = snapshot / "firefox" / f"{slug(url)}.png"
        replay = not opts.live and not is_local(url) and frozen.exists() and not opts.refresh
        record = not opts.live and not is_local(url) and not replay
        print(f"[{i + 1}/{len(urls)}] {url}" + (" (replay)" if replay else " (recording)" if record else ""), flush=True)
        if replay:
            shutil.copy(frozen, ff)
            ok_ff = True
            ok_tb = run_tobrod(tobrod, url, tb, ["--replay", str(snapshot)])
        else:
            if firefox is None:
                firefox, profile = firefox_path(), firefox_profile()
            ok_ff = run_firefox(firefox, profile, url, ff)
            ok_tb = run_tobrod(tobrod, url, tb, ["--record", str(snapshot)] if record else [])
            if record and ok_ff:
                frozen.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy(ff, frozen)
        share = diff(ff, tb, df) if ok_ff and ok_tb else None
        rows.append((url, ff.name if ok_ff else None, tb.name if ok_tb else None, df.name if share is not None else None, share))

    write_report(rows)
    print(f"report: {OUT / 'index.html'}")


def write_report(rows):
    cells = []
    for url, ff, tb, df, share in rows:
        def img(name, label):
            if name is None:
                return f"<figure><div class=missing>{label}: failed</div></figure>"
            return f'<figure><a href="{name}"><img src="{name}" alt="{label}"></a><figcaption>{label}</figcaption></figure>'
        score = "" if share is None else f"{share:.0%} of the pixels differ"
        cells.append(
            f'<section><h2><a href="{html.escape(url)}">{html.escape(url)}</a> <small>{score}</small></h2>'
            f'<div class=row>{img(ff, "Firefox (no JavaScript)")}{img(tb, "tobrod")}{img(df, "difference (red)")}</div></section>'
        )
    page = f"""<!doctype html>
<meta charset=utf-8>
<title>tobrod vs. Firefox</title>
<style>
  body {{ font-family: system-ui, sans-serif; margin: 16px; background: #f5f5f5 }}
  section {{ background: white; padding: 8px 16px 16px; margin-bottom: 16px }}
  h2 {{ font-size: 16px }} small {{ color: #666; font-weight: normal; margin-left: 8px }}
  .row {{ display: flex; gap: 8px }}
  figure {{ margin: 0; flex: 1 }} img {{ width: 100%; border: 1px solid #ccc }}
  figcaption {{ font-size: 13px; color: #555 }}
  .missing {{ padding: 40px; background: #fee; text-align: center }}
</style>
<h1>tobrod vs. Firefox</h1>
{''.join(cells)}
"""
    (OUT / "index.html").write_text(page, encoding="utf-8")


if __name__ == "__main__":
    main()
