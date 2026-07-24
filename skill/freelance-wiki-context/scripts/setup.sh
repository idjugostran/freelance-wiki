#!/usr/bin/env bash
# Standalone installer for the freelance-wiki-context Hermes skill.
#
# Designed to be run as a one-liner straight from GitHub, with nothing
# pre-cloned on the machine:
#
#   curl -fsSL https://raw.githubusercontent.com/idjugostran/freelance-wiki/main/skill/freelance-wiki-context/scripts/setup.sh | bash
#
# Everything is self-contained: it does a SPARSE clone of just the data the
# skill actually reads (wiki/, bin/, skill/ — NOT raw/, which is ~7.6MB of
# archival video transcripts the skill never opens), regenerates the wiki
# index, and registers the skill with Hermes (skills.external_dirs). No cron
# job — unlike tokovinin-video-flow, this skill is pure read-only context
# grounding triggered by chat mentions, nothing to run on a schedule.
#
# Idempotent — safe to re-run any time (same link again later, a cron job,
# whatever): re-running just fast-forwards to the latest wiki content (so
# newly ingested videos show up) and never re-registers a path that's
# already in skills.external_dirs. A run with nothing new upstream is a
# no-op past the git fetch.
#
# Override defaults via env vars (useful for the curl|bash form, where
# there's no way to pass CLI flags before the script exists locally):
#   FREELANCE_REPO_URL     git remote to clone (default: see REPO_URL below)
#   FREELANCE_INSTALL_DIR  where to clone it (default: ~/Freelance)
# CLI flags (only usable once you have a local copy, e.g. `./setup.sh --no-register`):
#   --dir PATH          same as FREELANCE_INSTALL_DIR
#   --repo URL          same as FREELANCE_REPO_URL
#   --no-register       skip the Hermes registration step (clone/update only)
#
# What it does, in order:
#   0. Sparse-clones (or fast-forward pulls, if already cloned) just
#      wiki/, bin/, and skill/ from the repo — cone-mode sparse-checkout,
#      so raw/, config/, assets/ never hit disk. Root-level loose files
#      (SCHEMA.md, PLAN.md, .gitignore) come along for free either way —
#      cone mode always includes files that sit directly at the repo root,
#      only directories need to be listed explicitly; harmless, a few KB.
#   1. Regenerates wiki/index.md (bin/generate-index.py) so the skill has a
#      fresh index the moment install/update finishes, not just on first
#      chat mention.
#   2. Checks the `hermes` CLI is on PATH (can't install Hermes itself here
#      - see hermes.nousresearch.com).
#   3. Registers the skill with Hermes by adding this checkout's `skill/`
#      directory to `skills.external_dirs` in ~/.hermes/config.yaml (best-
#      effort text patch, skipped with a manual instruction if the config's
#      current shape isn't one of the forms this script knows how to patch
#      safely - never guesses past that). Skipped entirely with --no-register.

set -euo pipefail

REPO_URL="${FREELANCE_REPO_URL:-https://github.com/idjugostran/freelance-wiki.git}"
INSTALL_DIR="${FREELANCE_INSTALL_DIR:-$HOME/Freelance}"
DO_REGISTER=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) INSTALL_DIR="$2"; shift 2 ;;
    --repo) REPO_URL="$2"; shift 2 ;;
    --no-register) DO_REGISTER=0; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

echo "== 0. Sparse clone/update (wiki/, bin/, skill/ only — no raw/) =="
if [[ -d "$INSTALL_DIR/.git" ]]; then
  echo "  Existing checkout found at $INSTALL_DIR - fetching updates..."
  BEFORE="$(git -C "$INSTALL_DIR" rev-parse HEAD)"
  git -C "$INSTALL_DIR" pull --ff-only
  AFTER="$(git -C "$INSTALL_DIR" rev-parse HEAD)"
  if [[ "$BEFORE" == "$AFTER" ]]; then
    echo "  OK: already up to date ($AFTER)"
  else
    N=$(git -C "$INSTALL_DIR" rev-list --count "$BEFORE..$AFTER")
    echo "  Updated: $N new commit(s), $BEFORE -> $AFTER"
    echo "  Changed files:"
    git -C "$INSTALL_DIR" diff --name-status "$BEFORE" "$AFTER" | sed 's/^/    /'
  fi
elif [[ -e "$INSTALL_DIR" ]]; then
  echo "  ERROR: $INSTALL_DIR exists and is not a git checkout of this repo." >&2
  echo "         Refusing to touch it - move it aside or pick a different --dir." >&2
  exit 1
else
  echo "  Cloning (sparse) $REPO_URL -> $INSTALL_DIR"
  git clone --filter=blob:none --no-checkout --depth 1 "$REPO_URL" "$INSTALL_DIR"
  git -C "$INSTALL_DIR" sparse-checkout init --cone
  git -C "$INSTALL_DIR" sparse-checkout set wiki bin skill
  DEFAULT_BRANCH="$(git -C "$INSTALL_DIR" remote show origin | sed -n '/HEAD branch/s/.*: //p')"
  git -C "$INSTALL_DIR" checkout "$DEFAULT_BRANCH"
  echo "  OK: cloned at $(git -C "$INSTALL_DIR" rev-parse HEAD)"
fi
INSTALLED_SIZE="$(du -sh "$INSTALL_DIR" 2>/dev/null | cut -f1)"
echo "  On-disk size: $INSTALLED_SIZE (raw/ excluded)"

echo "== 1. Regenerate wiki index =="
python3 "$INSTALL_DIR/bin/generate-index.py"

echo "== 2. hermes CLI =="
if command -v hermes >/dev/null 2>&1; then
  echo "  OK: $(hermes --version 2>&1 | head -1)"
else
  echo "  ERROR: 'hermes' not found on PATH. Install Hermes first:"
  echo "         https://hermes.nousresearch.com"
  exit 1
fi

if [[ "$DO_REGISTER" -eq 0 ]]; then
  echo "== Skipping Hermes registration (--no-register) =="
  echo "Done. Installed/updated at: $INSTALL_DIR"
  exit 0
fi

echo "== 3. Register skill with Hermes (skills.external_dirs) =="
python3 - "$INSTALL_DIR/skill" <<'PYEOF'
import re
import sys
from pathlib import Path

skill_parent_dir = sys.argv[1]
config_path = Path.home() / ".hermes" / "config.yaml"

if not config_path.exists():
    print(f"  WARNING: {config_path} not found - skipping (run 'hermes' once to create it, then re-run this script)")
    sys.exit(0)

text = config_path.read_text(encoding="utf-8")

if skill_parent_dir in text:
    print(f"  OK: {skill_parent_dir} already registered in skills.external_dirs")
    sys.exit(0)

# Case 1: empty flow-style list -> "external_dirs: []"
flow_empty = re.search(r"^(\s*)external_dirs:\s*\[\]\s*$", text, re.MULTILINE)
if flow_empty:
    indent = flow_empty.group(1)
    new_line = f'{indent}external_dirs: ["{skill_parent_dir}"]'
    text = text[:flow_empty.start()] + new_line + text[flow_empty.end():]
    config_path.write_text(text, encoding="utf-8")
    print(f"  Added {skill_parent_dir} to skills.external_dirs (was empty)")
    sys.exit(0)

# Case 2: non-empty flow-style list -> "external_dirs: [a, b]"
flow_nonempty = re.search(r"^(\s*)external_dirs:\s*\[(.*)\]\s*$", text, re.MULTILINE)
if flow_nonempty:
    indent, inner = flow_nonempty.group(1), flow_nonempty.group(2).strip()
    new_inner = f'{inner}, "{skill_parent_dir}"' if inner else f'"{skill_parent_dir}"'
    new_line = f"{indent}external_dirs: [{new_inner}]"
    text = text[:flow_nonempty.start()] + new_line + text[flow_nonempty.end():]
    config_path.write_text(text, encoding="utf-8")
    print(f"  Added {skill_parent_dir} to skills.external_dirs (existing flow list)")
    sys.exit(0)

# Case 3: block-style list -> "external_dirs:\n  - foo\n  - bar"
block = re.search(r"^(\s*)external_dirs:\s*\n((?:\1\s+- .*\n?)*)", text, re.MULTILINE)
if block:
    indent = block.group(1)
    item_indent = indent + "  "
    insert_at = block.end()
    new_item = f'{item_indent}- "{skill_parent_dir}"\n'
    text = text[:insert_at] + new_item + text[insert_at:]
    config_path.write_text(text, encoding="utf-8")
    print(f"  Added {skill_parent_dir} to skills.external_dirs (existing block list)")
    sys.exit(0)

# Case 4: a "skills:" block exists but has no "external_dirs:" key at all.
# Hermes' config.yaml only persists keys the user has explicitly touched, so
# a config that's never had its skill dirs configured commonly looks like:
#   skills:
#     creation_nudge_interval: 15
# with no external_dirs line to patch at all. Insert one as the first
# child of the skills: block, matching the indentation of its siblings.
skills_block = re.search(r"^skills:[ \t]*\n((?:[ \t]+\S.*\n?)*)", text, re.MULTILINE)
if skills_block and "external_dirs" not in skills_block.group(0):
    body = skills_block.group(1)
    first_line_indent_match = re.match(r"[ \t]+", body) if body else None
    item_indent = first_line_indent_match.group(0) if first_line_indent_match else "  "
    insert_at = skills_block.start(1)
    new_line = f'{item_indent}external_dirs: ["{skill_parent_dir}"]\n'
    text = text[:insert_at] + new_line + text[insert_at:]
    config_path.write_text(text, encoding="utf-8")
    print(f"  Added {skill_parent_dir} to skills.external_dirs (key didn't exist yet)")
    sys.exit(0)

# Case 5: no "skills:" top-level key at all - append a fresh block.
if not re.search(r"^skills:[ \t]*$", text, re.MULTILINE):
    sep = "" if text.endswith("\n") else "\n"
    text = text + sep + f'skills:\n  external_dirs: ["{skill_parent_dir}"]\n'
    config_path.write_text(text, encoding="utf-8")
    print(f"  Added {skill_parent_dir} to skills.external_dirs (created skills: block)")
    sys.exit(0)

print("  WARNING: could not find a recognizable 'external_dirs:' shape in")
print(f"           {config_path} - add it manually under skills.external_dirs:")
print(f'             - "{skill_parent_dir}"')
PYEOF

echo "== Done =="
echo "Installed/updated at: $INSTALL_DIR ($INSTALLED_SIZE on disk)"
echo "Re-run this script (same command) any time to pull newly ingested videos."
