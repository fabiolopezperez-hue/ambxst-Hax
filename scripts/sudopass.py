#!/usr/bin/env python3
"""Guarda la contraseña sudo de Hax de forma local.

La contraseña se cifra con XOR + machine-id (igual que keystore.py) y se
guarda en un archivo con permisos 0600. Solo la usa Hax internamente para
los comandos de paquetes (install, update, remove...).

Uso:
    sudopass.py <db_path> get          -> imprime {"password": "..."}
    sudopass.py <db_path> set <pass>   -> guarda la contraseña
    sudopass.py <db_path> clear        -> borra la contraseña
"""
import sys
import os
import json
from pathlib import Path


def get_machine_id():
    try:
        with open("/etc/machine-id", "r") as f:
            return f.read().strip().encode("utf-8")
    except Exception:
        return b"ambxst-fallback-salt-82741"


def xor_crypt(data, key):
    return bytes([b ^ key[i % len(key)] for i, b in enumerate(data)])


def main():
    if len(sys.argv) < 3:
        print(json.dumps({"error": "usage: <db_path> get|set <pass>|clear"}), flush=True)
        sys.exit(1)

    db_path = Path(os.path.expanduser(sys.argv[1]))
    cmd = sys.argv[2]
    key = get_machine_id()

    if cmd == "get":
        if db_path.exists():
            try:
                raw = bytes.fromhex(db_path.read_text().strip())
                print(json.dumps({"password": xor_crypt(raw, key).decode("utf-8")}), flush=True)
            except Exception:
                print(json.dumps({"password": ""}), flush=True)
        else:
            print(json.dumps({"password": ""}), flush=True)

    elif cmd == "set":
        if len(sys.argv) < 4:
            print(json.dumps({"error": "set requires a password"}), flush=True)
            sys.exit(1)
        db_path.parent.mkdir(parents=True, exist_ok=True)
        enc = xor_crypt(sys.argv[3].encode("utf-8"), key)
        db_path.write_text(enc.hex())
        os.chmod(str(db_path), 0o600)
        print(json.dumps({"status": "ok"}), flush=True)

    elif cmd == "clear":
        if db_path.exists():
            db_path.unlink()
        print(json.dumps({"status": "ok"}), flush=True)

    else:
        print(json.dumps({"error": f"unknown command: {cmd}"}), flush=True)
        sys.exit(1)


if __name__ == "__main__":
    main()
