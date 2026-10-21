"""Bundles runetfreedom's "blocked in Russia" lists for the ru-blocked profile.

Only the ru-blocked category is fetched (about 0.8 MB compressed), not the
complete geosite/geoip files. The App encodes the lists into Geodata files
on first use and later asks for changes with these ETags
(lib/service/connect/routing/profiles/ru_blocked.dart).
"""

import gzip
import json
import os
import time
import urllib.request

DOMAINS_URL = (
    "https://raw.githubusercontent.com/runetfreedom/"
    "russia-blocked-geosite/release/ru-blocked.txt"
)
IPS_URL = (
    "https://raw.githubusercontent.com/runetfreedom/"
    "russia-blocked-geoip/release/text/ru-blocked.txt"
)
# A list this short is an error page or a broken release, not data.
MINIMUM_ENTRIES = 1000


def _entries(text: str) -> int:
    return sum(
        1 for line in text.splitlines() if line.split("#")[0].strip()
    )


def _fetch(url: str, opener) -> tuple[bytes, str | None, int]:
    request = urllib.request.Request(
        url,
        headers={"Accept-Encoding": "gzip", "User-Agent": "HyperClient-build"},
    )
    with opener(request, timeout=60) as response:
        body = response.read()
        compressed = response.headers.get("Content-Encoding") == "gzip"
        etag = response.headers.get("ETag")
    data = body if compressed else gzip.compress(body, mtime=0)
    count = _entries(gzip.decompress(data).decode("utf-8", errors="replace"))
    if count < MINIMUM_ENTRIES:
        raise ValueError(f"{url} returned {count} entries")
    return data, etag, count


def fetch_ru_blocked(destination: str, opener=urllib.request.urlopen) -> None:
    os.makedirs(destination, exist_ok=True)
    manifest = {"fetchedAt": int(time.time())}
    for key, url, name in (
        ("domains", DOMAINS_URL, "domains.txt.gz"),
        ("ips", IPS_URL, "ips.txt.gz"),
    ):
        data, etag, count = _fetch(url, opener)
        with open(os.path.join(destination, name), "wb") as file:
            file.write(data)
        manifest[key] = {"url": url, "etag": etag, "count": count}
    with open(
        os.path.join(destination, "manifest.json"), "w", encoding="utf-8"
    ) as file:
        json.dump(manifest, file, indent=2)
        file.write("\n")
