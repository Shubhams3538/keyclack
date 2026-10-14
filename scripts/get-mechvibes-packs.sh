#!/usr/bin/env bash
# Downloads the sound packs bundled with Mechvibes (https://github.com/hainguyents13/mechvibes)
# into KeyClack's Packs folder, so they show up in the Sound menu. Real recordings of Cherry MX
# Blue/Brown/Red/Black, Holy Pandas, NK Creams, Topre and more.
#
# The packs are community-made; they're downloaded to your Mac for personal use and are not
# part of this repository.
set -euo pipefail

DEST="${KEYCLACK_PACKS_DIR:-$HOME/Library/Application Support/KeyClack/Packs}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading Mechvibes sound packs…"
git clone --quiet --depth 1 --filter=blob:none --sparse \
  https://github.com/hainguyents13/mechvibes.git "$TMP/mechvibes"
git -C "$TMP/mechvibes" sparse-checkout set src/audio

mkdir -p "$DEST"
count=0
for pack in "$TMP/mechvibes/src/audio"/*/; do
  name="$(basename "$pack")"
  [[ -f "$pack/config.json" ]] || continue
  if [[ -e "$DEST/$name" ]]; then
    echo "  skip  $name (already installed)"
    continue
  fi
  cp -R "$pack" "$DEST/$name"
  echo "  added $name"
  count=$((count + 1))
done

echo "Installed $count new pack(s) into: $DEST"
echo "Pick one from the KeyClack menu (Sound). If it isn't listed, choose + › Reload Packs."
