#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl jq nix-update sd gitMinimal prefetch-npm-deps coreutils

set -xeou pipefail

version=$(curl ${GITHUB_TOKEN:+ -H "Authorization: Bearer $GITHUB_TOKEN"} -sL https://api.github.com/repos/mrmn2/PdfDing/releases/latest | jq -r '.tag_name')

# source hashes
nix-update --version="$version" pdfding
nix-update --version="$version" pdfding.frontend

PACKAGE_DIR="$(realpath "$(dirname "$0")")"
ROOT_DIR=$(git rev-parse --show-toplevel)

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
cd "$TMPDIR"

src="$(nix-build --no-link "$ROOT_DIR" -A pdfding.src)"
cp "$src"/{package.json,package-lock.json} .

# npmDeps hash
prev_npm_hash="$(
  nix-instantiate "$ROOT_DIR" \
    --eval --json \
    -A pdfding.frontend.npmDeps.hash |
    jq -r .
)"
new_npm_hash="$(prefetch-npm-deps ./package-lock.json)"

sd --fixed-strings "$prev_npm_hash" "$new_npm_hash" "$PACKAGE_DIR/frontend.nix"

# pdfjs version
pdfjs_version="$(grep 'PDFJS_VERSION=' "$src/Dockerfile" | cut -d'=' -f2)"

sed -i "s|pdfjsVersion = .*;|pdfjsVersion = \"$pdfjs_version\";|" "$PACKAGE_DIR/frontend.nix"

# pdfjs hash
sed -i "s|pdfjsHash = .*;|pdfjsHash = lib.fakeHash;|" "$PACKAGE_DIR/frontend.nix"

set +e
new_pdfjs_hash="$(
  nix-build --no-out-link -A pdfding.frontend.pdfjs "$ROOT_DIR" 2>&1 >/dev/null | grep "got:" | cut -d':' -f2 | sed 's| ||g'
)"
set -e

sed -i "s|lib\.fakeHash|\"$new_pdfjs_hash\"|g" "$PACKAGE_DIR/frontend.nix"
