"""Regression coverage for Xcode's compiled iOS icon metadata."""
import importlib.util
import plistlib
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('check_release', Path(__file__).with_name('check_release.py'))
check_release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check_release)


class ArchiveIconTests(unittest.TestCase):
    def validate_icon(self, icon):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / 'Products/Applications/Voyage.app'
            extension = app / 'PlugIns/VoyageWidgets.appex'
            extension.mkdir(parents=True)
            base = {'CFBundleShortVersionString': '1.0', 'CFBundleVersion': '4'}
            plist = dict(base, CFBundleIdentifier='com.patrickliu.voyage',
                         ITSAppUsesNonExemptEncryption=False,
                         NSSupportsLiveActivities=True)
            plist.update(icon)
            (app / 'Info.plist').write_bytes(plistlib.dumps(plist))
            # The rest of what check_archive expects of a shippable bundle: the
            # privacy manifest and every PA clip from Voyage/Resources/PA.
            (app / 'PrivacyInfo.xcprivacy').write_bytes(plistlib.dumps({}))
            pa = Path(__file__).resolve().parents[1] / 'Voyage' / 'Resources' / 'PA'
            for clip in pa.glob('*.m4a') if pa.is_dir() else []:
                (app / clip.name).write_bytes(b'')
            (extension / 'Info.plist').write_bytes(plistlib.dumps(dict(
                base, CFBundleIdentifier='com.patrickliu.voyage.widgets')))
            check_release.problems.clear()
            check_release.check_archive(directory)
            return [message for level, message in check_release.problems if level == 'BLOCKER']

    def test_accepts_actool_primary_icon_dictionary(self):
        self.assertEqual(self.validate_icon({'CFBundleIcons': {'CFBundlePrimaryIcon': {
            'CFBundleIconName': 'AppIcon', 'CFBundleIconFiles': ['AppIcon60x60']}}}), [])

    def test_missing_icon_still_blocks_submission(self):
        self.assertTrue(any('CFBundleIconName' in message for message in self.validate_icon({})))

    def test_missing_live_activity_key_blocks_submission(self):
        # Activity.request throws without NSSupportsLiveActivities and the
        # controller swallows it, so the check has to catch it before upload.
        icon = {'CFBundleIcons': {'CFBundlePrimaryIcon': {
            'CFBundleIconName': 'AppIcon', 'CFBundleIconFiles': ['AppIcon60x60']}},
            'NSSupportsLiveActivities': False}
        self.assertTrue(any('NSSupportsLiveActivities' in m for m in self.validate_icon(icon)))

    def test_empty_icon_name_still_blocks_submission(self):
        self.assertTrue(self.validate_icon({'CFBundleIcons': {'CFBundlePrimaryIcon': {
            'CFBundleIconName': ''}}}))


if __name__ == '__main__':
    unittest.main()
