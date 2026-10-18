from copy import deepcopy
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
from pathlib import Path
import plistlib
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('package_testflight', Path(__file__).parents[1] / 'package-testflight.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class ProvisioningProfileTests(unittest.TestCase):
    def setUp(self):
        certificate = b'test certificate'
        self.identity = hashlib.sha1(certificate).hexdigest().upper()
        self.profile = {
            'Platform': ['OSX'],
            'ExpirationDate': datetime.now(timezone.utc) + timedelta(days=30),
            'TeamIdentifier': [package.TEAM],
            'DeveloperCertificates': [certificate],
            'Entitlements': {'com.apple.application-identifier': package.TEAM + '.' + package.APP_ID},
        }

    def validate(self, **changes):
        profile = deepcopy(self.profile)
        profile.update(changes)
        package.validate_profile(profile, package.APP_ID, self.identity)

    def test_accepts_matching_mac_app_store_profile(self):
        self.validate()

    def test_embedded_profile_is_readable_by_all_users(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            contents = root / 'AutoSwitchCam.app/Contents'
            contents.mkdir(parents=True)
            (contents / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': package.APP_ID}))
            entitlements = root / 'archive/Entitlements'
            entitlements.mkdir(parents=True)
            (entitlements / 'AutoSwitchCam.entitlements').write_bytes(plistlib.dumps({
                'com.apple.security.app-sandbox': True,
                'com.apple.developer.system-extension.install': True,
            }))
            profiles = root / 'profiles'
            profiles.mkdir()
            source = profiles / 'AutoSwitchCam.provisionprofile'
            source.write_bytes(b'public profile data')
            source.chmod(0o600)
            profile = deepcopy(self.profile)
            profile['ExpirationDate'] = profile['ExpirationDate'].replace(tzinfo=None)
            profile['Entitlements']['com.apple.developer.system-extension.install'] = True
            options = SimpleNamespace(profiles=profiles, archive=root / 'archive', identity=self.identity)
            with patch.object(package, 'run', return_value=SimpleNamespace(stdout=plistlib.dumps(profile))):
                package.sign_bundle(contents.parent, 'AutoSwitchCam', options, root)
            embedded = contents / 'embedded.provisionprofile'
            self.assertEqual(embedded.read_bytes(), source.read_bytes())
            self.assertEqual(embedded.stat().st_mode & 0o777, 0o644)
            self.assertEqual(source.stat().st_mode & 0o777, 0o600)

    def test_rejects_wrong_platform(self):
        with self.assertRaisesRegex(ValueError, 'macOS'):
            self.validate(Platform=['iOS'])

    def test_rejects_expired_profile(self):
        with self.assertRaisesRegex(ValueError, 'expired'):
            self.validate(ExpirationDate=datetime.now(timezone.utc) - timedelta(seconds=1))

    def test_rejects_development_and_developer_id_profiles(self):
        for changes in ({'ProvisionedDevices': ['mac']}, {'ProvisionsAllDevices': True},
                        {'Entitlements': dict(self.profile['Entitlements'], **{'get-task-allow': True})}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.validate(**changes)

    def test_rejects_other_bundle_id(self):
        with self.assertRaisesRegex(ValueError, 'does not match'):
            self.validate(Entitlements={'com.apple.application-identifier': package.TEAM + '.com.getlightray.client'})

    def test_rejects_other_team(self):
        with self.assertRaisesRegex(ValueError, 'wrong team'):
            self.validate(TeamIdentifier=['OTHERTEAM'])

    def test_rejects_mismatched_certificate(self):
        with self.assertRaisesRegex(ValueError, 'signing certificate'):
            self.validate(DeveloperCertificates=[b'other certificate'])


if __name__ == '__main__':
    unittest.main()
