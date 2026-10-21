import gzip
import json
import tempfile
import unittest
from pathlib import Path

from app.ru_blocked import DOMAINS_URL, IPS_URL, fetch_ru_blocked


class _Response:
    def __init__(self, body: bytes, headers: dict[str, str]):
        self._body = body
        self.headers = headers

    def read(self) -> bytes:
        return self._body

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False


def _opener(lists: dict[str, tuple[str, bool]]):
    def open_url(request, timeout):
        text, compressed = lists[request.full_url]
        body = text.encode()
        headers = {"ETag": f'W/"{len(text)}"'}
        if compressed:
            body = gzip.compress(body)
            headers["Content-Encoding"] = "gzip"
        return _Response(body, headers)

    return open_url


class RuBlockedTest(unittest.TestCase):
    def test_writes_compressed_lists_and_their_etags(self):
        domains = "\n".join(f"domain:site{i}.example" for i in range(1200))
        ips = "\n".join(f"10.0.{i // 256}.{i % 256}/32" for i in range(1100))
        with tempfile.TemporaryDirectory() as root:
            fetch_ru_blocked(
                root,
                opener=_opener({DOMAINS_URL: (domains, True), IPS_URL: (ips, False)}),
            )
            path = Path(root)
            self.assertEqual(
                gzip.decompress((path / "domains.txt.gz").read_bytes()).decode(),
                domains,
            )
            self.assertEqual(
                gzip.decompress((path / "ips.txt.gz").read_bytes()).decode(), ips
            )
            manifest = json.loads((path / "manifest.json").read_text())
            self.assertEqual(manifest["domains"]["count"], 1200)
            self.assertEqual(manifest["domains"]["etag"], f'W/"{len(domains)}"')
            self.assertEqual(manifest["ips"]["count"], 1100)
            self.assertGreater(manifest["fetchedAt"], 0)

    def test_refuses_a_list_too_short_to_be_data(self):
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaises(ValueError):
                fetch_ru_blocked(
                    root,
                    opener=_opener(
                        {DOMAINS_URL: ("<html>", False), IPS_URL: ("", False)}
                    ),
                )
            self.assertFalse((Path(root) / "manifest.json").exists())


if __name__ == "__main__":
    unittest.main()
