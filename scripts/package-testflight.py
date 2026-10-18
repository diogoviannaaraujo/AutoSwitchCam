#!/usr/bin/env python3
"""Sign a validated Xcode archive, including its camera system extension, for TestFlight."""
import argparse
from datetime import datetime, timezone
import fnmatch
import hashlib
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

APP_ID = 'com.diogoviannaaraujo.AutoSwitchCam'
TEAM = 'W76LFH4CZ4'


def run(*args, **kwargs):
    # Never include command arguments in failures: signing tools can take passwords.
    result = subprocess.run([str(arg) for arg in args], **kwargs)
    if result.returncode:
        raise RuntimeError(f'{args[0]} failed with exit code {result.returncode}')
    return result


def validate_profile(profile, identifier, identity):
    if profile.get('Platform') != ['OSX']:
        raise ValueError('Expected a macOS provisioning profile')
    if profile['ExpirationDate'].replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc):
        raise ValueError('Provisioning profile has expired')
    if 'ProvisionedDevices' in profile or profile.get('ProvisionsAllDevices'):
        raise ValueError('Expected a Mac App Store distribution profile')
    if profile.get('TeamIdentifier') != [TEAM]:
        raise ValueError('Provisioning profile belongs to the wrong team')
    entitlements = profile['Entitlements']
    if entitlements.get('com.apple.application-identifier') != TEAM + '.' + identifier:
        raise ValueError('Provisioning profile does not match ' + identifier)
    if entitlements.get('get-task-allow') or entitlements.get('com.apple.security.get-task-allow'):
        raise ValueError('Development profiles cannot be distributed through TestFlight')
    if identity.upper() not in [hashlib.sha1(cert).hexdigest().upper() for cert in profile['DeveloperCertificates']]:
        raise ValueError('Provisioning profile does not include the signing certificate')


def sign_bundle(bundle, target, options, temporary):
    info = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
    identifier = info['CFBundleIdentifier']
    source = options.profiles / (target + '.provisionprofile')
    profile = plistlib.loads(run('security', 'cms', '-D', '-i', source, capture_output=True).stdout)
    validate_profile(profile, identifier, options.identity)
    entitlements = plistlib.loads((options.archive / 'Entitlements' / (target + '.entitlements')).read_bytes())

    def expand(value):
        if isinstance(value, str):
            return value.replace('$(TeamIdentifierPrefix)', TEAM + '.').replace('$(PRODUCT_BUNDLE_IDENTIFIER)', identifier)
        if isinstance(value, list):
            return [expand(item) for item in value]
        return value

    entitlements = {name: expand(value) for name, value in entitlements.items()}
    if not entitlements.get('com.apple.security.app-sandbox'):
        raise ValueError(target + ' must enable App Sandbox')
    if target == 'AutoSwitchCam' and not profile['Entitlements'].get('com.apple.developer.system-extension.install'):
        raise ValueError('The app profile must enable System Extension installation')
    for group in entitlements.get('com.apple.security.application-groups', []):
        # Team-prefixed macOS groups are authorized by the signing identity.
        if group.startswith(TEAM + '.'):
            continue
        if not any(fnmatch.fnmatchcase(group, allowed) for allowed in
                   profile['Entitlements'].get('com.apple.security.application-groups', [])):
            raise ValueError('The extension profile does not authorize app group ' + group)
    for name in ('com.apple.application-identifier', 'com.apple.developer.team-identifier', 'beta-reports-active'):
        if name in profile['Entitlements']:
            entitlements[name] = profile['Entitlements'][name]
    path = temporary / (target + '.entitlements')
    path.write_bytes(plistlib.dumps(entitlements))
    shutil.copy2(source, bundle / 'Contents/embedded.provisionprofile')
    run('codesign', '--force', '--sign', options.identity, '--options', 'runtime',
        '--timestamp', '--entitlements', path, bundle)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--profiles', type=Path, required=True)
    parser.add_argument('--identity', required=True)
    parser.add_argument('--installer-identity', required=True)
    parser.add_argument('--installer-keychain', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    options = parser.parse_args()
    options.output.mkdir(parents=True, exist_ok=True)
    app = options.archive / 'Products/Applications/AutoSwitchCam.app'
    extension = app / 'Contents/Library/SystemExtensions' / (APP_ID + '.CameraExtension.systemextension')
    app_info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    extension_info = plistlib.loads((extension / 'Contents/Info.plist').read_bytes())
    for field in ('CFBundleVersion', 'CFBundleShortVersionString'):
        if app_info[field] != extension_info[field]:
            raise ValueError('The app and camera extension must have matching ' + field)
    if app_info['CFBundleIdentifier'] != APP_ID or extension_info['CFBundleIdentifier'] != APP_ID + '.CameraExtension':
        raise ValueError('The archive has unexpected bundle identifiers')
    with tempfile.TemporaryDirectory(prefix='autoswitchcam-signing-') as directory:
        temporary = Path(directory)
        for framework in sorted((app / 'Contents/Frameworks').glob('*.framework')):
            run('codesign', '--force', '--sign', options.identity, '--options', 'runtime', '--timestamp', framework)
        sign_bundle(extension, 'AutoSwitchCamExtension', options, temporary)
        sign_bundle(app, 'AutoSwitchCam', options, temporary)
    run('codesign', '--verify', '--deep', '--strict', app)
    package = options.output / 'AutoSwitchCam.pkg'
    run('productbuild', '--component', app, '/Applications', '--sign', options.installer_identity,
        '--keychain', options.installer_keychain, package, timeout=180)
    run('pkgutil', '--check-signature', package)
    digest = hashlib.sha256(package.read_bytes()).hexdigest()
    (options.output / 'SHA256SUMS.txt').write_text(digest + '  ' + package.name + '\n')
    print(f"TestFlight package: {package} — {app_info['CFBundleShortVersionString']} ({app_info['CFBundleVersion']})", flush=True)


if __name__ == '__main__':
    main()
