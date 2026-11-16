#!/usr/bin/env python3
"""Package and sign the built app. Private signing material stays in Keychain."""
import hashlib
import pathlib
import plistlib
import subprocess
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from email.utils import format_datetime

ROOT = pathlib.Path(__file__).resolve().parents[1]
APP = ROOT / 'dist/BMusic.app'
TOOLS = ROOT / '.build/artifacts/sparkle/Sparkle/bin'
ACCOUNT = 'io.github.kcxain.BMusic'
SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'

def run(*args):
    return subprocess.check_output([str(a) for a in args], text=True).strip()

info = plistlib.loads((APP / 'Contents/Info.plist').read_bytes())
public_key = run(TOOLS / 'generate_keys', '--account', ACCOUNT, '-p')
if public_key != info['SUPublicEDKey']:
    raise SystemExit('Signing key does not match the public key embedded in BMusic')
run('codesign', '--verify', '--deep', '--strict', APP)
version = info['CFBundleShortVersionString']
archive = ROOT / f'dist/BMusic-{version}-macOS-arm64.zip'
run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', APP, archive)
signature = run(TOOLS / 'sign_update', '--account', ACCOUNT, '-p', archive)
run(TOOLS / 'sign_update', '--account', ACCOUNT, '--verify', archive, signature)
ET.register_namespace('sparkle', SPARKLE)
rss = ET.Element('rss', version='2.0')
channel = ET.SubElement(rss, 'channel')
ET.SubElement(channel, 'title').text = 'BMusic'
ET.SubElement(channel, 'link').text = 'https://github.com/kcxain/bMusic'
ET.SubElement(channel, 'description').text = 'BMusic macOS updates'
item = ET.SubElement(channel, 'item')
ET.SubElement(item, 'title').text = f'BMusic {version}'
ET.SubElement(item, 'pubDate').text = format_datetime(datetime.now(timezone.utc))
for name, value in [('version', info['CFBundleVersion']), ('shortVersionString', version), ('minimumSystemVersion', info['LSMinimumSystemVersion'])]:
    ET.SubElement(item, f'{{{SPARKLE}}}{name}').text = value
ET.SubElement(item, 'enclosure', {
    'url': f'https://github.com/kcxain/bMusic/releases/download/v{version}/{archive.name}',
    'length': str(archive.stat().st_size), 'type': 'application/octet-stream',
    f'{{{SPARKLE}}}edSignature': signature,
})
ET.indent(rss)
feed = ROOT / 'dist/appcast.xml'
ET.ElementTree(rss).write(feed, encoding='utf-8', xml_declaration=True)
(ROOT / 'dist/SHA256SUMS.txt').write_text(''.join(
    f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in [archive, feed]))
print(f'Verified archive: {archive}\nAppcast: {feed}')
