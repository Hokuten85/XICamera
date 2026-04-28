#!/usr/bin/env python3
"""
analyze_camera_features.py — survey sub_1001ED90 (the camera task) for
candidate patch sites for proposed XICamera features:

 - battle camera pitch
 - battle camera vertical offset
 - vertical camera position lock
 - snap-to-offset for vertical position

Produces a human-readable report of every memory access against the
camera-position struct (`[edi+0x..]`) and every reference to
.rdata / .data globals nearby. The output is the input to manual
selection of patch sites — XICamera doesn't auto-pick anything.

Usage:
    python tools/analyze_camera_features.py [path-to-FFXiMain.dll]
"""
from __future__ import annotations

import struct
import sys
from collections import defaultdict
from pathlib import Path

import capstone  # type: ignore[import-not-found]
import pefile    # type: ignore[import-not-found]
from capstone import x86 as cx86  # type: ignore[import-not-found]

DEFAULT_DLL = Path(r"C:\XI-decompiled\FFXiMain.dll_19042026004046.dll")
JITTER_SIG = bytes.fromhex("8D54242C8D44242CD8C9525550")


def find_section(pe: pefile.PE, name: str):
    for s in pe.sections:
        if s.Name.rstrip(b"\x00") == name.encode():
            return s
    raise RuntimeError(f"section {name!r} not found")


def va_to_file_offset(pe: pefile.PE, va: int) -> int:
    rva = va - pe.OPTIONAL_HEADER.ImageBase
    for s in pe.sections:
        size = max(s.Misc_VirtualSize, s.SizeOfRawData)
        if s.VirtualAddress <= rva < s.VirtualAddress + size:
            return s.PointerToRawData + (rva - s.VirtualAddress)
    raise RuntimeError(f"VA 0x{va:08X} not in any section")


def file_offset_to_va(pe: pefile.PE, off: int) -> int:
    for s in pe.sections:
        if s.PointerToRawData <= off < s.PointerToRawData + s.SizeOfRawData:
            return pe.OPTIONAL_HEADER.ImageBase + s.VirtualAddress + (off - s.PointerToRawData)
    raise RuntimeError(f"file offset 0x{off:X} not in any section")


def find_function_start(buf: bytes, text_start: int, match_off: int, max_lookback: int = 0x4000) -> int:
    plausible_starts = (0x55, 0x53, 0x56, 0x57, 0x83, 0x81, 0x8B, 0xA1, 0xB8)
    i = match_off - 1
    floor = max(text_start, match_off - max_lookback)
    while i > floor:
        b = buf[i]
        if b == 0xC3 or b == 0xC2:
            j = i + 1
            if b == 0xC2:
                j += 2
            while j < match_off and buf[j] in (0xCC, 0x90):
                j += 1
            if j < match_off and buf[j] in plausible_starts:
                return j
        i -= 1
    return floor


def find_function_end(buf: bytes, fn_start: int, scan_limit: int = 0x10000) -> int:
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
    md.skipdata = True
    last = fn_start + scan_limit
    for ins in md.disasm(buf[fn_start:fn_start + scan_limit], fn_start):
        if ins.mnemonic in ("ret", "retn"):
            j = ins.address + ins.size
            while j < fn_start + scan_limit and buf[j] in (0xCC, 0x90):
                j += 1
            if j < fn_start + scan_limit and buf[j] in (0x55, 0x53, 0x56, 0x57, 0x83, 0x81, 0x8B):
                return ins.address + ins.size
            last = ins.address + ins.size
    return last


def get_constant_value(pe: pefile.PE, buf: bytes, va: int) -> tuple[float, int] | None:
    try:
        off = va_to_file_offset(pe, va)
    except Exception:
        return None
    if off + 4 > len(buf):
        return None
    f = struct.unpack("<f", buf[off:off + 4])[0]
    u = struct.unpack("<I", buf[off:off + 4])[0]
    return (f, u)


def main() -> int:
    dll = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_DLL
    if not dll.is_file():
        print(f"DLL not found: {dll}", file=sys.stderr)
        return 1

    pe = pefile.PE(str(dll), fast_load=True)
    buf = pe.__data__
    text = find_section(pe, ".text")

    # Locate sub_1001ED90 via the jitter signature -> walk back to fn start.
    matches = []
    i = text.PointerToRawData
    end = i + text.SizeOfRawData
    while True:
        idx = buf.find(JITTER_SIG, i, end)
        if idx < 0:
            break
        matches.append(idx)
        i = idx + 1
    if not matches:
        print("ERROR: jitter signature not found")
        return 2
    match_off = matches[0]
    fn_start = find_function_start(buf, text.PointerToRawData, match_off)
    fn_end   = find_function_end(buf, fn_start, 0x4000)
    fn_va    = file_offset_to_va(pe, fn_start)
    fn_end_va = file_offset_to_va(pe, min(fn_end, end - 1))
    print(f"Camera task: VA 0x{fn_va:08X}..0x{fn_end_va:08X}  ({fn_end - fn_start} bytes)")
    print()

    # Disassemble the whole function and gather instructions that touch
    # [edi + disp8] / [edi + disp32] (the camera-struct field accesses)
    # and instructions that reference globals in .rdata / .data.
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
    md.skipdata = True
    md.detail = True

    # accesses[offset] -> [(va, mnemonic_str)]
    accesses: dict[int, list[tuple[int, str]]] = defaultdict(list)
    # globals[va] -> [(va, mnemonic_str, value_if_float, value_if_uint)]
    globals_ref: dict[int, list[tuple[int, str]]] = defaultdict(list)

    for ins in md.disasm(buf[fn_start:fn_end], fn_va):
        try:
            ops = ins.operands
        except capstone.CsError:
            continue
        for op in ops:
            if op.type != cx86.X86_OP_MEM:
                continue
            mem = op.mem
            # [edi + disp]: camera struct field access
            if mem.base == cx86.X86_REG_EDI and mem.index == 0:
                accesses[mem.disp].append((ins.address, f"{ins.mnemonic} {ins.op_str}"))
            # absolute m32 address (no base/index): global ref
            elif mem.base == 0 and mem.index == 0 and mem.disp:
                addr = mem.disp & 0xFFFFFFFF
                if 0x10328000 <= addr < 0x10500000:
                    globals_ref[addr].append((ins.address, f"{ins.mnemonic} {ins.op_str}"))

    # ---- camera-struct accesses ----
    print("=== Camera-struct field accesses ([edi + disp]) ===")
    print("Disp is the offset into the CMoCameraTask 'this' instance.")
    print("FLD/FCOM = read; FSTP = write; FSUB[R]/FADD/FMUL = read+arith.")
    print()
    for disp in sorted(accesses.keys()):
        print(f"  +0x{disp:04X}  ({len(accesses[disp])} accesses)")
        for va, txt in accesses[disp]:
            print(f"      0x{va:08X}  {txt}")
        print()

    # ---- global refs ----
    print("=== Globals referenced inside this function ===")
    print("These are .rdata / .data float constants the camera math reads.")
    print()
    for addr in sorted(globals_ref.keys()):
        readings = get_constant_value(pe, buf, addr)
        val_str = ""
        if readings:
            f, u = readings
            val_str = f"  -> float={f:g}  uint=0x{u:08X}"
        print(f"  0x{addr:08X}  ({len(globals_ref[addr])} refs){val_str}")
        for va, txt in globals_ref[addr][:4]:
            print(f"      0x{va:08X}  {txt}")
        if len(globals_ref[addr]) > 4:
            print(f"      ... +{len(globals_ref[addr]) - 4} more")
        print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
