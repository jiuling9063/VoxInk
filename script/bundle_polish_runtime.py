"""Build-time only: copy a relocatable interpreter, audit, sign and smoke-test it."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from setup_polish_runtime import verify_internal_links

MACHO = {b'\xfe\xed\xfa\xce', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xcf\xfa\xed\xfe',
         b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca'}


def native_files(root):
    for path in sorted(root.rglob('*')):
        if path.is_file() and not path.is_symlink():
            with path.open('rb') as stream:
                if stream.read(4) in MACHO:
                    yield path


def audit_dependencies(paths):
    for path in paths:
        libraries = subprocess.check_output(['/usr/bin/otool', '-L', str(path)], text=True)
        for line in libraries.splitlines()[1:]:
            if not line.startswith('\t'):
                continue  # Universal binaries have a separate header for each architecture.
            name = line.strip().split(' (')[0]
            if name.startswith('/') and not name.startswith(('/usr/lib/', '/System/Library/')):
                raise ValueError('Non-system absolute native dependency: ' + name)


def bundle(python, destination, identity, requirements):
    info = json.loads(subprocess.check_output([str(python), '-I', '-c',
        'import sys,sysconfig,json; print(json.dumps(dict(base=sys.base_prefix,site=sysconfig.get_path("purelib"))))'], text=True))
    base, site = Path(info['base']).resolve(), Path(info['site']).resolve()
    if destination.exists():
        raise ValueError('Runtime destination already exists')
    shutil.copytree(base, destination, symlinks=True, ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
    shutil.copytree(site, destination / 'lib/python3.12/site-packages', symlinks=True, dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
    verify_internal_links(destination)
    # uv records the managed install location as the dylib ID; replace it before signing.
    subprocess.run(['/usr/bin/install_name_tool', '-id', '@rpath/libpython3.12.dylib',
                    str(destination / 'lib/libpython3.12.dylib')], check=True)
    binaries = list(native_files(destination))
    audit_dependencies(binaries)
    for binary in binaries:
        command = ['/usr/bin/codesign', '--force', '--sign', identity]
        if identity != '-':
            command += ['--options', 'runtime', '--timestamp']
        subprocess.run(command + [str(binary)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    executable = destination / 'bin/python3.12'
    with tempfile.TemporaryDirectory(prefix='voxink-runtime-probe-') as probe_root:
        environment = {'PATH': '/usr/bin:/bin', 'TMPDIR': probe_root}
        probe = subprocess.run([str(executable), '-I', '-B', '-c',
            'import sys,json,ssl,sqlite3,mlx.core as mx,mlx_lm,tokenizers,huggingface_hub; '
            'assert mx.metal.is_available(); assert (mx.array([1,2])+1).tolist()==[2,3]; '
            'print(json.dumps(dict(base=sys.base_prefix,paths=sys.path)))'],
            check=True, capture_output=True, text=True, timeout=90, cwd=probe_root, env=environment)
    loaded = json.loads(probe.stdout)
    if Path(loaded['base']).resolve() != destination.resolve() or any(
        not Path(p).resolve().is_relative_to(destination.resolve()) for p in loaded['paths']
    ):
        raise ValueError('Runtime still references an external interpreter or site-packages')
    metadata = {'python': '3.12.13', 'platform': 'macOS-arm64', 'minimum_macos': '15.0',
                'requirements_sha256': hashlib.sha256(requirements.read_bytes()).hexdigest(),
                'native_file_count': len(binaries)}
    (destination / 'voxink-runtime.json').write_text(json.dumps(metadata, indent=2))
    shutil.copyfile(requirements, destination / 'requirements.lock')
    print('Bundled runtime: isolated Python and Metal smoke test passed; signed', len(binaries), 'native files.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--python', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--identity', default='-')
    parser.add_argument('--requirements', type=Path, required=True)
    args = parser.parse_args()
    bundle(args.python, args.destination, args.identity, args.requirements)
