from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from bundle_polish_runtime import audit_dependencies


class BundledRuntimeTests(unittest.TestCase):
    def test_rejects_developer_library_dependency(self):
        with patch('bundle_polish_runtime.subprocess.check_output', return_value=
                   'module.so:\n\t/opt/homebrew/lib/libpython.dylib (compatibility version 1.0)\n'):
            with self.assertRaises(ValueError):
                audit_dependencies([Path('/bundle/module.so')])

    def test_accepts_relocatable_universal_library(self):
        output = ''.join(f'/bundle/module.so (architecture {arch}):\n'
                         '\t@rpath/libpython3.12.dylib (compatibility version 1.0)\n'
                         '\t/usr/lib/libSystem.B.dylib (compatibility version 1.0)\n'
                         for arch in ['x86_64', 'arm64'])
        with patch('bundle_polish_runtime.subprocess.check_output', return_value=output):
            audit_dependencies([Path('/bundle/module.so')])
