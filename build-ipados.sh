#!/usr/bin/env bash
set -euo pipefail

bundle=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
workspace=${1:?Usage: bash build-ipados.sh BUILD_WORKSPACE}
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode_26.6.app/Contents/Developer}
xcodebuild -version
bash "$bundle/prepare-sources.sh" "$workspace"
cd "$workspace/UniXNU"
for patch in ipados-metal-bridge.patch ipados-link-drivers.patch; do
    if ! git apply --reverse --check "$bundle/patches/$patch" 2>/dev/null; then
        git apply "$bundle/patches/$patch"
    fi
done
cp "$bundle/patches/metal2vulkan-ios-mach-vm.patch" scripts/data/
device=../UniXNU-sheng
for patch in ipados-startup-log.patch ipados-keyboard-log.patch ipados-sleep-log.patch ipados-link-board.patch; do
    if ! git -C "$device" apply --reverse --check "$bundle/patches/$patch" 2>/dev/null; then
        git -C "$device" apply "$bundle/patches/$patch"
    fi
done
target=out/sheng/ipados-27.0.1-24A446/sheng_ipados27
python3 - "$device/board.toml" "$bundle/ipados-linux.toml" <<'PY'
from pathlib import Path
import sys
import tomllib

board, override = map(Path, sys.argv[1:])
text = board.read_text()
overlay = override.read_text().strip()
if overlay not in text:
    text = text.rstrip() + '\n\n' + overlay + '\n'
    tomllib.loads(text)
    board.write_text(text)
PY

llvm=$(brew --prefix llvm@22)
lld=$(brew --prefix lld@22)
mkdir -p .cache/edk2-llvm22
for tool in clang llvm-lib llvm-rc; do
    ln -sfn "$llvm/bin/$tool" ".cache/edk2-llvm22/$tool"
done
ln -sfn "$lld/bin/lld-link" .cache/edk2-llvm22/lld-link
export CLANG_BIN="$PWD/.cache/edk2-llvm22/"

./unixnu defconfig sheng_ipados27_defconfig -D "$device" --os 27
python3 "$device/scripts/extract-files.py"
python3 "$bundle/pin-wifi-freebsd.py" "$device/drivers/Ath12kWifi"
python3 "$device/drivers/Ath12kWifi/tools/fetch-sources.py"
python3 "$bundle/prepare-ipados-root.py"
"$device/scripts/package.sh" --os 27 --uefi ../uefi-sheng --init-data
./unixnu build userdata -D "$device" --os 27 \
    --object "OS.vroot=$target/tree/build/verified-root-OS/hashes.bin" \
    --object "SystemOS.vroot=$target/tree/build/verified-root-SystemOS/hashes.bin"

python3 - "$target" <<'PY'
import json
from pathlib import Path
import struct
import sys

target = Path(sys.argv[1])
command = json.loads((target / 'tree/build/sheng-source-storage/NativeUfs.command.json').read_text())
if '-DUNIXNU_SHENG_ROOT_PARTITION="linux"' not in command:
    raise SystemExit('The UFS driver was not compiled for the linux partition')
boot = target / 'boot/boot.img'
if not 0 < boot.stat().st_size <= 201326592:
    raise SystemExit('The boot image exceeds the measured boot_b slot')
root = json.loads((target / 'userdata/unixnu-root.json').read_text())
if (root['target_partition'] != 'linux'
        or root['userdata_bytes'] != 124748038144
        or not 0 < root['storage_required_bytes'] <= root['userdata_bytes']
        or [item['name'] for item in root['objects']] != ['OS.vroot', 'SystemOS.vroot']):
    raise SystemExit('The root image does not match the linux partition or expected root policies')
with (target / 'runtime/data.dbr').open('rb') as seed:
    magic, version, page_bytes, logical_bytes, _ = struct.unpack('<8sIIQQ', seed.read(32))
if (magic, version, page_bytes, logical_bytes) != (b'DBRDISK1', 1, 4096, 90 << 30):
    raise SystemExit('The packed iPadOS Data seed does not describe the 90 GiB volume')
PY
