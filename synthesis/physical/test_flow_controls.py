#!/usr/bin/env python3
"""Host-runner failure tests; fake Docker never synthesizes or reports a pass."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class FlowControls(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for name in ['synthesis/physical/run_reference.py',
                     'synthesis/physical/toolchain.json',
                     'synthesis/scripts/make_flat_top.py',
                     'synthesis/scripts/axi_ports.py']:
            dest = self.root/name
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT/name, dest)
        shutil.copytree(ROOT/'src', self.root/'src')
        bin_dir = self.root/'bin'
        bin_dir.mkdir()
        fake = bin_dir/'docker'
        fake.write_text('''#!/usr/bin/env python3
import json, os, pathlib, signal
manifest = next(pathlib.Path('build/physical').glob('*/manifest.json'))
record = json.loads(manifest.read_text())['commands'][-1]
assert record['exit_code'] is None and record['status'] == 'running'
pathlib.Path('invoked').write_text('yes')
if os.environ.get('KILL_RUNNER'):
    os.kill(os.getppid(), signal.SIGKILL)
raise SystemExit(42)
''')
        fake.chmod(0o755)
        self.env = dict(os.environ, PATH=str(bin_dir)+os.pathsep+os.environ['PATH'])

    def run_flow(self, *args):
        return subprocess.run(['python3', 'synthesis/physical/run_reference.py',
                               '--variant', 'test', *args], cwd=self.root,
                              env=self.env, capture_output=True, text=True)

    def manifest(self):
        return next((self.root/'build/physical').glob('*/manifest.json'))

    def test_failure_is_recorded_before_and_after_launch(self):
        result = self.run_flow('--stage', 'generic')
        self.assertEqual(result.returncode, 42, result.stderr)
        record = json.loads(self.manifest().read_text())['commands'][-1]
        self.assertEqual(record['exit_code'], 42)
        self.assertEqual(record['status'], 'completed')

    def test_hard_interruption_cannot_leave_success(self):
        self.env['KILL_RUNNER'] = '1'
        result = self.run_flow('--stage', 'generic')
        self.assertEqual(result.returncode, -9, result.stderr)
        record = json.loads(self.manifest().read_text())['commands'][-1]
        self.assertIsNone(record['exit_code'])
        self.assertEqual(record['status'], 'running')

    def test_changed_experiment_rejected_without_touching_inputs(self):
        self.assertEqual(self.run_flow('--stage', 'generic').returncode, 42)
        folder = self.manifest().parent
        before = {p.name: p.read_bytes() for p in folder.iterdir() if p.is_file()}
        (self.root/'invoked').unlink()
        for args in [('--period', '8'), ('--hold-margin', '.1'),
                     ('--cap-margin', '15'), ('--max-repair-passes', '100000'),
                     ('--closure-rounds', '2')]:
            result = self.run_flow(*args)
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertIn('choose a new --variant', result.stderr)
            self.assertFalse((self.root/'invoked').exists())
            self.assertEqual(before, {p.name: p.read_bytes() for p in folder.iterdir()
                                      if p.is_file()})


if __name__ == '__main__':
    unittest.main()
