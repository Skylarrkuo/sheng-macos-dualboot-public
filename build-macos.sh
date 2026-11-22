#!/usr/bin/env bash
set -euo pipefail

if [[ $(uname -s) != Darwin ]]; then
    printf 'The macOS build requires Xcode, hdiutil, diskutil and aea on macOS.\n' >&2
    exit 1
fi
bundle=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
workspace=${1:?Usage: bash build-macos.sh BUILD_WORKSPACE}
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode_26.6.app/Contents/Developer}
python3 -c 'import sys; sys.exit(sys.version_info < (3, 11))'
xcodebuild -version
for tool in aea hdiutil diskutil dtc fdtget fdtput mformat mcopy ipsw; do
    command -v "$tool" >/dev/null || { printf 'Missing build tool: %s\n' "$tool" >&2; exit 1; }
done

if [[ -z ${UNIXNU_UNIQUE_CHIP_ID:-} ]]; then
    read -rsp 'Platform seed (16 hex digits from fastboot getvar cpuid): ' UNIXNU_UNIQUE_CHIP_ID
    printf '\n'
fi
if [[ ! $UNIXNU_UNIQUE_CHIP_ID =~ ^[a-fA-F0-9]{16}$ || $UNIXNU_UNIQUE_CHIP_ID == 0000000000000000 ]]; then
    printf 'Platform seed must contain the complete nonzero 16-digit CPUID.\n' >&2
    exit 1
fi
export UNIXNU_UNIQUE_CHIP_ID

bash "$bundle/prepare-sources.sh" "$workspace"
cd "$workspace/UniXNU"
target=out/sheng/macos-27.3-26C5035r/sheng_macos
if [[ ! -f $target/runtime/data.dbr && -z ${UNIXNU_LAB_PASSWORD:-} ]]; then
    read -rsp 'Initial macOS administrator password: ' UNIXNU_LAB_PASSWORD
    printf '\n'
    export UNIXNU_LAB_PASSWORD
fi

if [[ -z ${CLANG_BIN:-} ]]; then
    llvm=$(brew --prefix llvm@22)
    lld=$(brew --prefix lld@22)
    mkdir -p .cache/edk2-llvm22
    for tool in clang llvm-lib llvm-rc; do
        ln -sfn "$llvm/bin/$tool" ".cache/edk2-llvm22/$tool"
    done
    ln -sfn "$lld/bin/lld-link" .cache/edk2-llvm22/lld-link
    export CLANG_BIN="$PWD/.cache/edk2-llvm22/"
fi

./unixnu defconfig sheng_macos_defconfig -D ../UniXNU-sheng --os macos-27
./unixnu fetch --os macos-27
wifi=../UniXNU-sheng/drivers/Ath12kWifi
# A fresh upstream checkout follows the FreeBSD branch before checking its pin.
# Fetch the locked revision first so the branch moving cannot change the inputs.
if [[ ! -e $wifi/deps/freebsd ]]; then
    python3 - "$wifi" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

wifi = Path(sys.argv[1]).resolve()
source = json.loads((wifi / 'tools/source-lock.json').read_text())['freebsd']
directory = wifi / 'deps/freebsd'
directory.mkdir(parents=True)
commands = [
    ['init', '-q'],
    ['remote', 'add', 'origin', source['url']],
    ['config', 'remote.origin.promisor', 'true'],
    ['config', 'remote.origin.partialclonefilter', 'blob:none'],
    ['sparse-checkout', 'init', '--cone'],
    ['fetch', '--depth', '1', '--filter=blob:none', 'origin', source['commit']],
    ['switch', '--detach', 'FETCH_HEAD'],
]
for command in commands:
    subprocess.run(['git', '-C', str(directory), *command], check=True)
PY
fi
python3 ../UniXNU-sheng/scripts/prepare-macos-install.py
../UniXNU-sheng/scripts/package.sh --os macos-27 --uefi ../uefi-sheng
python3 - "$target" <<'PY'
import json
import sys
from pathlib import Path

target = Path(sys.argv[1])
record = target / 'tree/build/sheng-source-storage/NativeUfs.command.json'
command = json.loads(record.read_text())
if '-DUNIXNU_SHENG_ROOT_PARTITION="linux"' not in command:
    raise SystemExit('Refusing to package a boot image without the linux GPT target')
if not 0 < (target / 'boot/boot.img').stat().st_size <= 201326592:
    raise SystemExit('The boot image exceeds the 192 MiB boot_b partition')
PY
objects=()
for window in OS SystemOS App; do
    objects+=(--object "$window.vroot=$target/tree/build/verified-root-$window/hashes.bin")
done
./unixnu build userdata -D ../UniXNU-sheng --os macos-27 "${objects[@]}"
printf 'Boot image: %s/%s/boot/boot.img\n' "$PWD" "$target"
printf 'Root image: %s/%s/userdata/unixnu-root.img\n' "$PWD" "$target"
