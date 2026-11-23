"""Use UniXNU's verified-root tooling to prepare the two iPadOS windows."""
import contextlib
from pathlib import Path
import subprocess
import sys
import tempfile


core = Path.cwd().resolve()
device = core.parent / 'UniXNU-sheng'
sys.path.insert(0, str(core / 'scripts'))

from unixnu.cli import parser, prepare
from unixnu.config import Context
from unixnu.ipsw import Ipsw
from unixnu.userdata import disk_blocks, image_size


def main():
    ctx = Context(parser().parse_args(['build', 'kernel', '-D', str(device), '--os', '27']))
    prepare(ctx, ['kernel'])
    source = Ipsw(ctx)
    profile = ctx.board['board']['os_profile']
    policies = device / 'scripts/policies' / profile
    with tempfile.TemporaryDirectory(prefix='ipados-root-', dir=ctx.work) as scratch:
        raw = Path(scratch) / 'root.raw'
        for window in ctx.board['userdata']['windows']:
            name = window['name']
            image = source.disk_image(window['component'])
            size = image_size(image)
            with raw.open('wb') as output, contextlib.closing(disk_blocks(image, size)) as blocks:
                for block in blocks:
                    output.write(block)
            if raw.stat().st_size != size:
                raise SystemExit(f'{name}: extracted disk size mismatch')
            volume = ctx.board['root'][name.lower() + '_volume_uuid']
            subprocess.run([sys.executable, str(core / 'scripts/make-root-policies.py'),
                            '--tree', str(ctx.tree), '--output', str(policies),
                            '--window', f'{name}={raw}:{volume}'], check=True)
            raw.unlink()


if __name__ == '__main__':
    main()
