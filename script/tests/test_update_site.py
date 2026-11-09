import hashlib
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from stage_update_site import SITE, recent_tags, verify_download


class UpdateSiteTests(unittest.TestCase):
    def test_old_reruns_drafts_and_prereleases_do_not_replace_current_feed(self):
        releases = [dict(tagName=tag, isDraft=draft, isPrerelease=preview) for tag, draft, preview in [
            ("v0.1.27", False, False), ("v0.1.99", False, True), ("v0.1.28", False, False),
            ("v0.1.30", True, False), ("v0.1.26", False, False), ("v0.1.29", False, False)]]
        self.assertEqual(recent_tags(releases), ["v0.1.29", "v0.1.28"])

    def test_rejects_misdirected_feed_and_corrupted_asset_of_same_length(self):
        tag = "v0.1.27"
        name = "VoxInk-0.1.27-macOS-arm64.dmg"
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            image = root / name
            image.write_bytes(b"original")
            digest = hashlib.sha256(image.read_bytes()).hexdigest()
            (root / "SHA256SUMS.txt").write_text(f"{digest}  {name}\n")
            feed = root / "appcast.xml"
            xml = f'''<rss xmlns:s="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
                <s:shortVersionString>0.1.27</s:shortVersionString>
                <enclosure url="{SITE}/{tag}/{name}" length="8" s:edSignature="fixture"/>
                </item></channel></rss>'''
            feed.write_text(xml.replace(SITE, "https://example.invalid"))
            with self.assertRaisesRegex(ValueError, "Feed does not match"):
                verify_download(root, tag)
            feed.write_text(xml)
            verify_download(root, tag)
            image.write_bytes(b"modified")
            with self.assertRaisesRegex(ValueError, "checksum"):
                verify_download(root, tag)
