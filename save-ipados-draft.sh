#!/usr/bin/env bash
set -euo pipefail

tag=${1:?Missing Release tag}
title=${2:?Missing Release title}
notes=${3:?Missing Release notes}
shift 3

arguments=("$tag" --repo "$GITHUB_REPOSITORY" --draft --title "$title"
    --notes "$notes Built from commit $GITHUB_SHA.")
error_log=$(mktemp)
trap 'rm -f "$error_log"' EXIT

if ! gh release create "${arguments[@]}" --target "$GITHUB_SHA" 2>"$error_log"; then
    if ! grep -Fq 'Resource not accessible by integration' "$error_log"; then
        cat "$error_log" >&2
        exit 1
    fi
    # The job token cannot create a Release targeting an older workflow revision.
    gh release create "${arguments[@]}"
fi
gh release upload "$tag" --repo "$GITHUB_REPOSITORY" "$@"
