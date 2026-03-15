#!/usr/bin/env python3
import argparse
import json
import os
import re
import sys
import urllib.request
from pathlib import Path


def fetch_text(url: str) -> str:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "android-home-server/1.0",
            "Accept": "text/html,application/xhtml+xml,text/plain",
        },
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        charset = resp.headers.get_content_charset() or "utf-8"
        return resp.read().decode(charset, "replace")


def resolve_latest_grapheneos_version(releases_page_url: str) -> str:
    page = fetch_text(releases_page_url)

    for pattern in [
        r"href=#(\d{10})",
        r">(\d{10})</a>",
    ]:
        match = re.search(pattern, page)
        if match:
            return match.group(1)

    raise SystemExit("failed to resolve the latest GrapheneOS version from the official releases page")


def render_url(template_or_url: str, *, device: str, version: str) -> str:
    return template_or_url.format(device=device, version=version)


def resolve_grapheneos_release(args: argparse.Namespace) -> tuple[str, str, str]:
    version = args.grapheneos_version
    if version.lower() == "latest":
        version = resolve_latest_grapheneos_version(args.grapheneos_releases_page_url)

    release_source = args.grapheneos_release_url_template or args.grapheneos_release_url
    sig_source = args.grapheneos_release_sig_url_template or args.grapheneos_release_sig_url
    if not release_source or not sig_source:
        raise SystemExit("GrapheneOS release URL configuration is incomplete")

    return (
        version,
        render_url(release_source, device=args.device, version=version),
        render_url(sig_source, device=args.device, version=version),
    )


def build_manifest(args: argparse.Namespace) -> dict:
    grapheneos_version, grapheneos_release_url, grapheneos_release_sig_url = resolve_grapheneos_release(args)
    return {
        "device": args.device,
        "grapheneos": {
            "version": grapheneos_version,
            "release_url": grapheneos_release_url,
            "release_name": os.path.basename(grapheneos_release_url),
            "release_sig_url": grapheneos_release_sig_url,
            "release_sig_name": os.path.basename(grapheneos_release_sig_url),
            "allowed_signers_url": args.grapheneos_allowed_signers_url,
            "allowed_signers_name": os.path.basename(args.grapheneos_allowed_signers_url),
        },
        "platform_tools": {
            "version": args.platform_tools_version,
            "zip_url": args.platform_tools_url,
            "zip_name": os.path.basename(args.platform_tools_url),
            "sha256": args.platform_tools_sha256,
        },
        "termux": {
            "apk_url": args.termux_apk_url,
            "apk_name": os.path.basename(args.termux_apk_url),
        },
        "termux_boot": {
            "apk_url": args.termux_boot_apk_url,
            "apk_name": os.path.basename(args.termux_boot_apk_url),
        },
        "magisk": {
            "apk_url": args.magisk_apk_url,
            "apk_name": os.path.basename(args.magisk_apk_url),
            "host_patch_url": args.magisk_host_patch_url,
            "host_patch_name": os.path.basename(args.magisk_host_patch_url),
        },
    }


def download(url: str, target: Path) -> None:
    if target.exists() and target.stat().st_size > 0:
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    print(f"download -> {target.name}")
    req = urllib.request.Request(url, headers={"User-Agent": "android-home-server/1.0"})
    with urllib.request.urlopen(req, timeout=120) as resp, open(target, "wb") as out:
        while True:
            chunk = resp.read(1024 * 1024)
            if not chunk:
                break
            out.write(chunk)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", required=True)
    parser.add_argument("--grapheneos-version", required=True)
    parser.add_argument("--grapheneos-release-url")
    parser.add_argument("--grapheneos-release-sig-url")
    parser.add_argument("--grapheneos-release-url-template")
    parser.add_argument("--grapheneos-release-sig-url-template")
    parser.add_argument("--grapheneos-allowed-signers-url", required=True)
    parser.add_argument(
        "--grapheneos-releases-page-url",
        default="https://grapheneos.org/releases",
    )
    parser.add_argument("--platform-tools-version", required=True)
    parser.add_argument("--platform-tools-url", required=True)
    parser.add_argument("--platform-tools-sha256", required=True)
    parser.add_argument("--termux-apk-url", required=True)
    parser.add_argument("--termux-boot-apk-url", required=True)
    parser.add_argument("--magisk-apk-url", required=True)
    parser.add_argument("--magisk-host-patch-url", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--download-dir", required=True)
    parser.add_argument("--download", action="store_true")
    args = parser.parse_args()

    manifest = build_manifest(args)
    manifest_path = Path(args.manifest)
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"wrote manifest: {manifest_path}")

    if not args.download:
        return 0

    download_dir = Path(args.download_dir)
    download(manifest["grapheneos"]["allowed_signers_url"], download_dir / manifest["grapheneos"]["allowed_signers_name"])
    download(manifest["grapheneos"]["release_url"], download_dir / manifest["grapheneos"]["release_name"])
    download(manifest["grapheneos"]["release_sig_url"], download_dir / manifest["grapheneos"]["release_sig_name"])
    download(manifest["platform_tools"]["zip_url"], download_dir / manifest["platform_tools"]["zip_name"])
    download(manifest["termux"]["apk_url"], download_dir / manifest["termux"]["apk_name"])
    download(manifest["termux_boot"]["apk_url"], download_dir / manifest["termux_boot"]["apk_name"])
    download(manifest["magisk"]["apk_url"], download_dir / manifest["magisk"]["apk_name"])
    download(manifest["magisk"]["host_patch_url"], download_dir / manifest["magisk"]["host_patch_name"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
