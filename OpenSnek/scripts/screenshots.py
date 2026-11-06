#!/usr/bin/env python3
"""Refresh native UI screenshots or verify their source/image provenance."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
NAMES = ('desktop',)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sources():
    paths = list((ROOT / 'OpenSnek/Sources/OpenSnek/UI').glob('*.swift'))
    paths += list((ROOT / 'OpenSnek/Sources/OpenSnek/Services').glob('*.swift'))
    paths += list((ROOT / 'OpenSnek/Sources/OpenSnek').glob('*.swift'))
    paths += list((ROOT / 'OpenSnek/Sources/OpenSnekCore').glob('*.swift'))
    paths += list((ROOT / 'OpenSnek/Sources/OpenSnekAppSupport').glob('*.swift'))
    paths += list((ROOT / 'OpenSnek/App/Resources').rglob('*.png'))
    paths += [ROOT / 'OpenSnek/project.yml', ROOT / 'OpenSnek/Package.swift',
              ROOT / 'OpenSnek/App/Info.plist', ROOT / 'OpenSnek/scripts/build_macos_app.sh',
              ROOT / 'run.sh', Path(__file__).resolve()]
    return {str(p.relative_to(ROOT)): digest(p) for p in sorted(paths)}


def verify(output):
    manifest = output / 'screenshots.json'
    if not manifest.is_file():
        raise SystemExit('Missing screenshots. Run ./run.sh --screenshots, then commit the updated images.')
    saved = json.loads(manifest.read_text())
    if saved.get('sources') != sources():
        raise SystemExit('Screenshots are stale. Run ./run.sh --screenshots, then commit the updated images.')
    expected = {name + '.png' for name in NAMES}
    if set(saved.get('images', {})) != expected:
        raise SystemExit('Screenshot set is incomplete.')
    for name, sha in saved['images'].items():
        path = output / name
        if not path.is_file() or digest(path) != sha:
            raise SystemExit(f'Screenshot changed without regeneration: {name}')
    print('Screenshots match the current UI source and image checksums.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'docs/media/screenshots')
    parser.add_argument('--check', action='store_true')
    build = parser.add_mutually_exclusive_group()
    build.add_argument('--skip-build', action='store_true', help='Intentionally reuse the staged app built from the current source')
    build.add_argument('--app', type=Path, help='Render from an already-built .app, such as the notarized release export')
    args = parser.parse_args()
    output = args.output.resolve()
    if args.check:
        verify(output)
        return
    before = sources()
    if not args.skip_build and args.app is None:
        subprocess.run([str(ROOT / 'OpenSnek/scripts/build_macos_app.sh'), '--configuration', 'debug', '--build-channel', 'release'], check=True)
    app = args.app.resolve() if args.app else ROOT / 'OpenSnek/.dist/OpenSnek.app'
    command = [str(app / 'Contents/MacOS/OpenSnek'), '--render-screenshots', str(output)]
    with subprocess.Popen(command) as renderer:
        try:
            status = renderer.wait(timeout=90)
        except subprocess.TimeoutExpired:
            sample = ROOT / 'OpenSnek/.release/screenshot-render.sample.txt'
            sample.parent.mkdir(parents=True, exist_ok=True)
            try:
                subprocess.run(['sample', str(renderer.pid), '2', '-file', str(sample)], timeout=15)
            finally:
                renderer.kill()
                renderer.wait()
            raise SystemExit(f'Screenshot renderer timed out; process sample: {sample}')
        if status:
            raise SystemExit(f'Screenshot renderer exited with status {status}')
    if sources() != before:
        raise SystemExit('Sources changed while rendering. Run ./run.sh --screenshots again.')
    record = {'sources': before, 'images': {name + '.png': digest(output / (name + '.png')) for name in NAMES}}
    (output / 'screenshots.json').write_text(json.dumps(record, indent=2) + '\n')
    verify(output)


if __name__ == '__main__':
    main()
