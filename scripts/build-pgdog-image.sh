#!/usr/bin/env bash
#
# Builds the pgdog:move-keys docker image the compose file expects,
# from the move-keys branch of the pgdog fork (the stack of PRs adding
# ADD SHARD and MOVE KEYS). See docs/pgdog.md and docs/resharding.md.
#
# Usage:
#   scripts/build-pgdog-image.sh
#
# Overridable via environment:
#   PGDOG_REPO    git URL of the fork    (default: rlittlefield/pgdog)
#   PGDOG_BRANCH  branch to build        (default: move-keys)
#   PGDOG_DIR     checkout location      (default: ~/.cache/shard_hound/pgdog)
#   PGDOG_IMAGE   image tag              (default: pgdog:move-keys)
#
# Point PGDOG_DIR at an existing checkout to build local, unpushed work.
set -euo pipefail

PGDOG_REPO="${PGDOG_REPO:-https://github.com/rlittlefield/pgdog.git}"
PGDOG_BRANCH="${PGDOG_BRANCH:-move-keys}"
DEFAULT_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/shard_hound/pgdog"
PGDOG_DIR="${PGDOG_DIR:-$DEFAULT_DIR}"
PGDOG_IMAGE="${PGDOG_IMAGE:-pgdog:move-keys}"

# The MOVE KEYS predicate fix; without it every move of a bigint key
# fails validation with "operator does not exist: bigint = text".
PREDICATE_FIX="cast key-move predicate arrays"

if [ "$PGDOG_DIR" != "$DEFAULT_DIR" ]; then
  # A caller-provided checkout is built exactly as it stands, so
  # local, unpushed work is never touched.
  echo "==> Using existing checkout $PGDOG_DIR as-is"
elif [ -d "$PGDOG_DIR/.git" ]; then
  echo "==> Updating $PGDOG_BRANCH in $PGDOG_DIR"
  git -C "$PGDOG_DIR" fetch origin "$PGDOG_BRANCH"
  git -C "$PGDOG_DIR" checkout "$PGDOG_BRANCH"
  git -C "$PGDOG_DIR" reset --hard "origin/$PGDOG_BRANCH"
else
  echo "==> Cloning $PGDOG_REPO ($PGDOG_BRANCH) into $PGDOG_DIR"
  mkdir -p "$(dirname "$PGDOG_DIR")"
  git clone --branch "$PGDOG_BRANCH" "$PGDOG_REPO" "$PGDOG_DIR"
fi

echo "==> Building $PGDOG_IMAGE from $(git -C "$PGDOG_DIR" rev-parse --short HEAD)"

if ! git -C "$PGDOG_DIR" log --oneline --grep "$PREDICATE_FIX" | grep -q .; then
  echo "WARNING: this checkout is missing the '$PREDICATE_FIX' fix;" >&2
  echo "         MOVE KEYS with bigint keys will fail validation." >&2
fi

docker build -t "$PGDOG_IMAGE" "$PGDOG_DIR"

echo "==> Done: $PGDOG_IMAGE"
