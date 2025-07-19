#!/bin/bash
set -euo pipefail

MC_VERSION="$1"
BRANCH="$MC_VERSION"
REPO="MediumCraft/Minecraft"  # 🔧 Replace with your private repo
AUTH_URL="https://${SECRET_PAT}@github.com/${REPO}.git"
WORK="$GITHUB_WORKSPACE/work"

rm -rf "$WORK"
mkdir -p "$WORK/decompile" "$WORK/private"

echo "::group::Clone private repo"
git clone --depth 1 "$AUTH_URL" "$WORK/private"
cd "$WORK/private"
if git rev-parse --verify "origin/$BRANCH" >/dev/null 2>&1; then
  echo "Branch exists (already decompiled). Exiting."
  exit 0
fi
echo "::endgroup::"

cd "$WORK/decompile"

# --- Mojang mappings with DecompilerMC ---
echo "::group::Check & Decompile Mojang mappings"
git clone https://github.com/hube12/DecompilerMC.git dmc
cd dmc
pip install -r requirements.txt || true

if ! python3 main.py --mcversion "$MC_VERSION" --check-mappings; then
  echo "❌ Mojang mappings not found for $MC_VERSION — aborting."
  exit 1
fi

python3 main.py --mcversion "$MC_VERSION" --decompiler fernflower -q
mkdir -p ../mojang
cp -r src/* ../mojang/
cd "$WORK/decompile"
echo "::endgroup::"

# --- Verify Yarn mappings via Gradle Loom ---
echo "::group::Check & Decompile Yarn mappings"
git clone https://github.com/FabricMC/fabric-example-mod.git yarn-tool
cd yarn-tool
echo "fabric_version=latest" > gradle.properties

if ! ./gradlew mapNamedJar --dry-run --quiet; then
  echo "❌ Yarn mapping resolution failed for $MC_VERSION — aborting."
  exit 1
fi

./gradlew genSources mapNamedJar --quiet
mkdir -p ../yarn
cp -r build/generated/sources/java/main ../yarn/
cd "$WORK/decompile"
echo "::endgroup::"

# --- Push results to private repo ---
echo "::group::Push branch $BRANCH"
cd "$WORK/private"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git checkout -b "$BRANCH"
mkdir -p "$BRANCH"/{mojang,yarn}
cp -r "$WORK/decompile/mojang/"* "$BRANCH/mojang/"
cp -r "$WORK/decompile/yarn/"* "$BRANCH/yarn/"
git add "$BRANCH"
git commit -m "Decompiled Minecraft $MC_VERSION with Mojang+Yarn mappings"
git push "$AUTH_URL" "$BRANCH"
echo "::endgroup::"
