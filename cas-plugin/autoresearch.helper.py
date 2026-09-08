"""Use the installed skill helper without its worktree-wide discard operation.

Discard edits explicitly with apply_patch before logging. Never reset/clean the
shared worktree. Inspect all changes before keep, which commits through the skill.
"""
import importlib.util
from pathlib import Path
import sys

path = Path.home() / ".codex/skills/autoresearch/scripts/autoresearch.py"
spec = importlib.util.spec_from_file_location("tuist_autoresearch_helper", path)
helper = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = helper
spec.loader.exec_module(helper)
helper.revert_non_kept = lambda paths: "Automatic reset disabled; discard experimental edits explicitly."
helper.main()
