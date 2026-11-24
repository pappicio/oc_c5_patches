#!/usr/bin/env python3

import sys
from pathlib import Path

BOT_DIR = Path.home() / "moonraker-telegram-bot" / "bot"
MAIN_FILE = BOT_DIR / "main.py"

OLD = 'mess += "Printer online on " + get_local_ip()'
NEW = 'mess += "Printer online on " + configWrap.bot_config.host'


def main():
    if not MAIN_FILE.is_file():
        raise SystemExit(f"ERROR: Bot source not found: {MAIN_FILE}")

    source = MAIN_FILE.read_text(encoding="utf-8")

    if source.count(OLD) != 1:
        raise SystemExit(
            "ERROR: Expected exactly one greeting line. "
            "Runtime patch was not applied."
        )

    patched_source = source.replace(OLD, NEW, 1)

    sys.path[0] = str(BOT_DIR)
    sys.argv[0] = str(MAIN_FILE)

    namespace = {
        "__name__": "__main__",
        "__file__": str(MAIN_FILE),
        "__package__": None,
        "__cached__": None,
        "__spec__": None,
    }

    print(
        "[OC Telegram] Runtime greeting patch applied. "
        "Source files remain unchanged.",
        flush=True,
    )

    code = compile(patched_source, str(MAIN_FILE), "exec")
    exec(code, namespace)


if __name__ == "__main__":
    main()
