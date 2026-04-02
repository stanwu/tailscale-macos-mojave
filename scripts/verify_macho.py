#!/usr/bin/env python3
"""Verify Mach-O binaries against mach-o-header-symbols.json spec."""

import json
import subprocess
import sys
import os


def verify_binary(name, path, spec):
    errors = []
    print(f"\n=== Verifying {name} ===")

    with open(path, "rb") as f:
        h = f.read(32)

    ref = spec["reference_build"][name]

    for field, got, want in [
        ("magic", h[0:4].hex(), ref["magic"]),
        ("cputype", int.from_bytes(h[4:8], "little"), ref["cputype"]),
        ("cpusubtype", int.from_bytes(h[8:12], "little"), ref["cpusubtype"]),
        ("filetype", int.from_bytes(h[12:16], "little"), ref["filetype"]),
    ]:
        if got == want:
            print(f"  [OK] {field}: {got}")
        else:
            errors.append(f"{name}: {field}: got {got}, want {want}")
            print(f"  [FAIL] {field}: got {got}, want {want}")

    flags = int.from_bytes(h[24:28], "little")
    want_flags = ref["flags"]
    if (flags & want_flags) == want_flags:
        print(f"  [OK] flags: {flags:#x} (contains {want_flags:#x})")
    else:
        errors.append(f"{name}: flags {flags:#x} missing bits from {want_flags:#x}")
        print(f"  [FAIL] flags: {flags:#x}, want {want_flags:#x}")

    out = subprocess.check_output(["strings", path], text=True)
    syms = set(out.splitlines())

    for sym in spec["symbols"]["required"]:
        if sym in syms:
            print(f"  [OK] required: {sym}")
        else:
            errors.append(f"{name}: missing required symbol {sym}")
            print(f"  [FAIL] missing: {sym}")

    for sym in spec["symbols"]["forbidden"]:
        if sym not in syms:
            print(f"  [OK] absent: {sym}")
        else:
            errors.append(f"{name}: found forbidden symbol {sym}")
            print(f"  [FAIL] found: {sym} (would crash on Mojave)")

    return errors


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <spec.json> <binary> [binary...]")
        sys.exit(2)

    spec_path = sys.argv[1]
    with open(spec_path) as f:
        spec = json.load(f)

    all_errors = []
    for path in sys.argv[2:]:
        name = os.path.basename(path)
        all_errors.extend(verify_binary(name, path, spec))

    print(f"\n=== Summary ===")
    if all_errors:
        print(f"FAILED with {len(all_errors)} error(s):")
        for e in all_errors:
            print(f"  - {e}")
        sys.exit(1)
    else:
        print("All checks passed — binaries are Mojave-compatible")


if __name__ == "__main__":
    main()
