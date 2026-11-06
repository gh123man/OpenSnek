"""Screenshot verification must reject stale, missing, or changed screenshots."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import sys
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('screenshots', Path(__file__).parents[1] / 'screenshots.py')
screenshots = importlib.util.module_from_spec(spec)
spec.loader.exec_module(screenshots)


class ScreenshotGateTests(unittest.TestCase):
    def test_release_app_is_used_without_rebuilding(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / 'Release App.app'
            binary = app / 'Contents/MacOS/OpenSnek'
            binary.parent.mkdir(parents=True)
            binary.write_text('#!/bin/sh\nmkdir -p "$2"\nprintf release-render > "$2/desktop.png"\n')
            binary.chmod(0o755)
            output = root / 'screenshots'
            with patch.object(sys, 'argv', ['screenshots.py', '--app', str(app), '--output', str(output)]), \
                    patch.object(screenshots, 'sources', return_value={}), \
                    patch.object(screenshots.subprocess, 'run') as build:
                screenshots.main()
                build.assert_not_called()
                screenshots.verify(output)
            self.assertEqual((output / 'desktop.png').read_text(), 'release-render')

    def test_source_change_and_image_tampering_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            for name in screenshots.NAMES:
                (output / (name + '.png')).write_bytes(b'test-image')
            images = {p.name: screenshots.digest(p) for p in output.glob('*.png')}
            (output / 'screenshots.json').write_text(json.dumps({'sources': {'View.swift': 'current'}, 'images': images}))
            with patch.object(screenshots, 'sources', return_value={'View.swift': 'current'}):
                screenshots.verify(output)
                (output / 'desktop.png').write_bytes(b'changed')
                with self.assertRaises(SystemExit):
                    screenshots.verify(output)
                (output / 'desktop.png').unlink()
                with self.assertRaises(SystemExit):
                    screenshots.verify(output)
            with patch.object(screenshots, 'sources', return_value={'View.swift': 'changed'}):
                with self.assertRaises(SystemExit):
                    screenshots.verify(output)

    def test_missing_manifest_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(SystemExit):
                screenshots.verify(Path(directory))

    def test_incomplete_image_set_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            (output / 'screenshots.json').write_text(json.dumps({'sources': {}, 'images': {}}))
            with patch.object(screenshots, 'sources', return_value={}):
                with self.assertRaisesRegex(SystemExit, 'incomplete'):
                    screenshots.verify(output)
