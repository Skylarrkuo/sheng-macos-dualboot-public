#!/usr/bin/env bash
set -euo pipefail

bundle=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mkdir -p "${1:?Usage: bash prepare-sources.sh BUILD_WORKSPACE}"
workspace=$(cd "$1" && pwd)
core="$workspace/UniXNU"
device="$workspace/UniXNU-sheng"
uefi="$workspace/uefi-sheng"

checkout() {
    local path=$1 name=$2 revision=$3
    if [[ ! -e "$path/.git" ]]; then
        if [[ -e "$path" ]]; then
            printf 'Expected a dedicated Git checkout at %s\n' "$path" >&2
            exit 1
        fi
        git init -q "$path"
        git -C "$path" remote add origin "https://github.com/UniXNU/$name.git"
        git -C "$path" fetch --depth 1 origin "$revision"
        git -C "$path" switch --detach FETCH_HEAD
    fi
    if [[ $(git -C "$path" rev-parse HEAD) != "$revision" ]]; then
        printf 'Expected %s at %s\n' "$revision" "$path" >&2
        exit 1
    fi
}

queue_patch() {
    local repo=$1 patch="$bundle/patches/$2"
    if git -C "$repo" apply -R --check "$patch" 2>/dev/null; then
        printf 'Already applied %s\n' "$2"
    else
        git -C "$repo" apply --check "$patch"
        patch_repos[patch_count]="$repo"
        patches[patch_count]="$patch"
        patch_count=$((patch_count + 1))
    fi
}

checkout "$core" UniXNU 8542980d02b4d2cc5c32ee3542de1760b2562aac
checkout "$device" UniXNU-sheng c8f92b208068eeaa4cd2b0f592671f04ee70076e
checkout "$uefi" uefi-sheng 8156d2e54a9f57818dc8b415a1a7dc28ad9ba4be
git -C "$core" submodule update --init --recursive --depth 1
if [[ ! -e "$device/drivers/ShengUfs/.git" ]]; then
    git -C "$device" submodule update --init --recursive --depth 1
fi
ufs="$device/drivers/ShengUfs"
if [[ $(git -C "$ufs" rev-parse HEAD) != 9d527ae1a8d36a7ff210f9f4c9b429549c34c991 ]]; then
    printf 'Unexpected ShengUfs revision\n' >&2
    exit 1
fi

patch_repos=()
patches=()
patch_count=0
queue_patch "$core" core.patch
queue_patch "$device" device.patch
queue_patch "$ufs" sheng-ufs.patch
for ((index = 0; index < patch_count; index++)); do
    git -C "${patch_repos[index]}" apply "${patches[index]}"
done
