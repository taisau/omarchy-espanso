#!/usr/bin/env python3
"""Manage the simple matches owned by the Omarchy Espanso widget.

JSON is valid YAML, so Espanso can read the generated .yml file directly.
Other Espanso match files are never written by this helper.
"""

import argparse
import fcntl
import hashlib
import json
import os
import sys
import tempfile
from pathlib import Path


MAX_MATCHES = 500
MAX_TRIGGER = 100
MAX_REPLACE = 5000


def match_path():
    config_home = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    return config_home / "espanso" / "match" / "omarchy-plugin.yml"


def load(path):
    if not path.exists():
        return []
    if path.is_symlink():
        raise ValueError("Managed match file must not be a symlink")
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or set(data) != {"matches"}:
        raise ValueError("Managed match file must contain only a matches list")
    matches = data["matches"]
    if not isinstance(matches, list) or len(matches) > MAX_MATCHES:
        raise ValueError("Invalid managed matches list")
    for item in matches:
        if not isinstance(item, dict) or not {"trigger", "replace"} <= set(item) \
                or set(item) - {"trigger", "replace", "word"}:
            raise ValueError("Managed matches must contain trigger, replace, and optional word")
        validate(item["trigger"], item["replace"])
        if "word" in item and not isinstance(item["word"], bool):
            raise ValueError("word must be a boolean")
    return matches


def validate(trigger, replacement):
    if not isinstance(trigger, str) or not trigger or len(trigger) > MAX_TRIGGER:
        raise ValueError("Trigger must contain 1–100 characters")
    if any(char in trigger for char in "\r\n\x00"):
        raise ValueError("Trigger must be on one line")
    if not isinstance(replacement, str) or not replacement or len(replacement) > MAX_REPLACE:
        raise ValueError("Replacement must contain 1–5000 characters")
    if "\x00" in replacement:
        raise ValueError("Replacement cannot contain a NUL character")


def identity(index, item):
    payload = json.dumps([index, item], ensure_ascii=False, sort_keys=True)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()[:20]


def resolve(matches, match_id):
    for index, item in enumerate(matches):
        if identity(index, item) == match_id:
            return index
    raise ValueError("Expansion changed since the panel loaded; refresh and try again")


def save(path, matches):
    path.parent.mkdir(parents=True, exist_ok=True)
    content = json.dumps({"matches": matches}, ensure_ascii=False, indent=2) + "\n"
    fd, name = tempfile.mkstemp(prefix=".omarchy-plugin-", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            os.fchmod(output.fileno(), 0o600)
            output.write(content)
            output.flush()
            os.fsync(output.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("list")
    create = sub.add_parser("create")
    create.add_argument("trigger")
    create.add_argument("replacement")
    create.add_argument("--word", action="store_true")
    update = sub.add_parser("update")
    update.add_argument("id")
    update.add_argument("trigger")
    update.add_argument("replacement")
    update.add_argument("--word", action="store_true")
    delete = sub.add_parser("delete")
    delete.add_argument("id")
    args = parser.parse_args()
    path = match_path()

    try:
        if args.action == "list":
            matches = load(path)
            print(json.dumps([
                {"id": identity(index, item), **item, "word": item.get("word", False)}
                for index, item in enumerate(matches)
            ], ensure_ascii=False))
            return 0

        path.parent.mkdir(parents=True, exist_ok=True)
        lock_path = path.with_suffix(".lock")
        with lock_path.open("a+") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            matches = load(path)
            if args.action in ("create", "update"):
                validate(args.trigger, args.replacement)
                target_index = resolve(matches, args.id) if args.action == "update" else -1
                if any(item["trigger"] == args.trigger for index, item in enumerate(matches)
                       if index != target_index):
                    raise ValueError("That trigger already exists in managed expansions")
                new_item = {"trigger": args.trigger, "replace": args.replacement, "word": args.word}
                if args.action == "create":
                    if len(matches) >= MAX_MATCHES:
                        raise ValueError("Managed expansion limit reached")
                    matches.append(new_item)
                else:
                    matches[target_index] = new_item
            else:
                del matches[resolve(matches, args.id)]
            save(path, matches)
        print("OK")
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
