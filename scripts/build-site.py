#!/usr/bin/env python3
"""Build the static Pages site using a verified GitHub latest-release response."""
import argparse
import html
import json
import re
import shutil
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent.parent
REPO = "Capyhw/winway"
SCREENSHOTS = ROOT / "docs/screenshots/2026-10-28"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release-json", type=Path, required=True)
    args = parser.parse_args()
    release = json.loads(args.release_json.read_text())
    if release.get("draft") or release.get("prerelease"):
        raise ValueError("Pages downloads must use a published stable release")
    version = release["tag_name"]
    if not re.fullmatch(r"v\d+\.\d+\.\d+", version):
        raise ValueError(f"Unexpected release version: {version}")
    replacements = {"@@VERSION@@": version}
    for arch, token in [("arm64", "@@ARM64_URL@@"), ("x86_64", "@@INTEL_URL@@")]:
        name = f"Winway-{version[1:]}-macos-{arch}.dmg"
        matches = [a for a in release["assets"] if a["name"] == name and a.get("state") == "uploaded"]
        if len(matches) != 1:
            raise ValueError(f"Missing or ambiguous release asset: {name}")
        url = matches[0]["browser_download_url"]
        parsed = urlparse(url)
        if parsed.scheme != "https" or parsed.netloc != "github.com" or not parsed.path.startswith(f"/{REPO}/releases/download/{version}/"):
            raise ValueError(f"Unexpected download URL: {url}")
        replacements[token] = url

    source = ROOT / "website"
    destination = ROOT / ".build/site"
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source, destination)
    for name in ["overview", "move-between-tabs", "search", "context-menu", "keyboard"]:
        shutil.copy2(SCREENSHOTS / f"{name}.png", destination / "assets" / f"{name}.png")
    document = (source / "index.html").read_text()
    for token, value in replacements.items():
        if token not in document:
            raise ValueError(f"Missing HTML token: {token}")
        document = document.replace(token, html.escape(value, quote=True))
    if re.search(r"@@[A-Z_0-9]+@@", document):
        raise ValueError("Unresolved HTML token")
    (destination / "index.html").write_text(document)
    (destination / ".nojekyll").touch()
    (destination / "robots.txt").write_text("User-agent: *\nAllow: /\nSitemap: https://capyhw.github.io/winway/sitemap.xml\n")
    (destination / "sitemap.xml").write_text('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>https://capyhw.github.io/winway/</loc></url></urlset>\n')
    print(f"Built {destination} with {version} downloads")


if __name__ == "__main__":
    main()
