from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_app_store_bundle import metadata_checks, version_tuple


class AppStoreBundleTests(unittest.TestCase):
    def setUp(self):
        self.info = dict(CFBundleIdentifier="example.voxink", CFBundleShortVersionString="1.0",
                         CFBundleVersion="1", LSMinimumSystemVersion="15.0",
                         NSMicrophoneUsageDescription="Record speech locally.",
                         CFBundleLocalizations=["zh-Hans", "zh-Hant", "en", "ja", "ko"])
        self.entitlements = {"com.apple.security.app-sandbox": True}
        self.signing = "Authority=Apple Distribution: Example\n"

    def statuses(self):
        return {item["check"]: item["status"] for item in metadata_checks(self.info, self.entitlements, self.signing)}

    def test_valid_metadata_is_not_a_substitute_for_runtime_and_upload_tests(self):
        self.assertEqual(set(self.statuses().values()), {"PASS"})

    def test_developer_id_and_ad_hoc_are_not_store_signatures(self):
        for signature in ["Authority=Developer ID Application: Example", "Signature=adhoc", ""]:
            self.signing = signature
            self.assertEqual(self.statuses()["distribution-signature"], "FAIL")

    def test_legacy_store_application_certificate_is_recognized(self):
        self.signing = "Authority=3rd Party Mac Developer Application: Example"
        self.assertEqual(self.statuses()["distribution-signature"], "PASS")

    def test_missing_sandbox_fails(self):
        self.entitlements.clear()
        self.assertEqual(self.statuses()["app-sandbox"], "FAIL")

    def test_debug_entitlement_fails(self):
        for key in ["get-task-allow", "com.apple.security.get-task-allow"]:
            self.entitlements = {key: True}
            self.assertEqual(self.statuses()["debug-entitlement"], "FAIL")

    def test_missing_purpose_version_or_language_fails(self):
        for value in [None, " ", 123]:
            self.info["NSMicrophoneUsageDescription"] = value
            self.assertEqual(self.statuses()["microphone-description"], "FAIL")
        self.info.pop("CFBundleVersion")
        self.info["CFBundleLocalizations"] = ["en"]
        for check in ["microphone-description", "version", "interface-languages"]:
            self.assertEqual(self.statuses()[check], "FAIL")

    def test_os_versions_are_compared_numerically_with_padding(self):
        self.assertEqual(version_tuple("15"), version_tuple("15.0.0"))
        self.assertGreater(version_tuple("15.10"), version_tuple("15.9"))
