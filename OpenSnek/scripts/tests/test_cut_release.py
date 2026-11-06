"""Release preparation refreshes images; tagging cannot bypass stale-image checks."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'cut_release.sh'


class ReleaseScreenshotTests(unittest.TestCase):
    def run_release(self, *args, stale=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            log = root / 'commands'
            stubs = {
                'git': '''#!/bin/sh
printf 'git %s\n' "$*" >> "$RELEASE_TEST_LOG"
case "$*" in
  *'rev-parse -q --verify'*) exit 1 ;;
esac
''',
                'python3': '''#!/bin/sh
printf 'python3 %s\n' "$*" >> "$RELEASE_TEST_LOG"
if [ "$RELEASE_TEST_STALE" = 1 ] && [ "$2" = --check ]; then
  echo 'Screenshots are stale' >&2
  exit 1
fi
''',
                'swift': '''#!/bin/sh
printf 'swift %s\n' "$*" >> "$RELEASE_TEST_LOG"
''',
            }
            for name, body in stubs.items():
                path = root / name
                path.write_text(body)
                path.chmod(0o755)
            env = dict(os.environ, PATH=f'{root}:{os.environ["PATH"]}',
                       RELEASE_TEST_LOG=str(log), RELEASE_TEST_STALE='1' if stale else '0')
            result = subprocess.run(['/bin/bash', str(SCRIPT), *args], env=env,
                                    text=True, capture_output=True)
            commands = log.read_text().splitlines() if log.exists() else []
            return result, commands

    def test_prepare_refreshes_without_git_or_tagging(self):
        result, commands = self.run_release('--prepare')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(commands, [f'python3 {SCRIPT.parent / "screenshots.py"}'])

    def test_prepare_rejects_publish_options(self):
        for options in [('--version', '1.2.3'), ('--skip-tests',)]:
            with self.subTest(options=options):
                result, commands = self.run_release('--prepare', *options)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(commands, [])

    def test_stale_images_prevent_tag_and_push_even_when_tests_skipped(self):
        for options in [(), ('--skip-tests',)]:
            with self.subTest(options=options):
                result, commands = self.run_release('--version', '1.2.3', *options, stale=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Screenshots are stale', result.stderr)
                self.assertFalse(any(' tag -a ' in command or ' push ' in command for command in commands))

    def test_current_images_are_checked_after_pull_before_tests_and_tag(self):
        result, commands = self.run_release('--version', '1.2.3')
        self.assertEqual(result.returncode, 0, result.stderr)
        pull = next(i for i, cmd in enumerate(commands) if ' pull --ff-only ' in cmd)
        check = next(i for i, cmd in enumerate(commands) if 'screenshots.py --check' in cmd)
        tests = next(i for i, cmd in enumerate(commands) if cmd.startswith('swift test '))
        tag = next(i for i, cmd in enumerate(commands) if ' tag -a ' in cmd)
        self.assertLess(pull, check)
        self.assertLess(check, tests)
        self.assertLess(tests, tag)
