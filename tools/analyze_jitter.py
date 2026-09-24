#!/usr/bin/env python3
"""
analyze_jitter.py — Investigate the camera-jitter patch site in FFXiMain.dll.

Goal: figure out exactly what the 0.125 scalar XICamera replaces with 1.0
actually does. Locates the jitter signature, identifies the enclosing
function, disassembles around the match, and enumerates every reader of
the 0.125 / -0.125 floats in .text.

Usage:
    python tools/analyze_jitter.py <path-to-FFXiMain.dll>

Default path is the unpacked decompile referenced in docs/.
"""
from __future__ import annotations

import struct
import sys
from pathlib import Path

import capstone  # type: ignore[import-not-found]
import pefile    # type: ignore[import-not-found]

DEFAULT_DLL = Path(r"C:\XI-decompiled\FFXiMain.dll_19042026004046.dll")

# 13-byte signature XICamera scans for. The two operand sites it patches
# are the FMUL m32fp at +0x0F and +0x1F into the match.
JITTER_SIG = bytes.fromhex("8D 54 24 2C 8D 44 24 2C D8 C9 52 55 50".replace(" ", ""))

# .rdata floats we care about (looked up at runtime via PE sections).
JITTER_VA   = 0x103293BC  # 0.125
N_JITTER_VA = 0x103293C0  # -0.125


def find_section(pe: pefile.PE, name: str) -> pefile.SectionStructure:
    target = name.encode().ljust(8, b"\x00")
    for s in pe.sections:
        if s.Name.rstrip(b"\x00") == name.encode():
            return s
    raise RuntimeError(f"section {name!r} not found")


def va_to_file_offset(pe: pefile.PE, va: int) -> int:
    rva = va - pe.OPTIONAL_HEADER.ImageBase
    for s in pe.sections:
        sec_rva = s.VirtualAddress
        sec_size = max(s.Misc_VirtualSize, s.SizeOfRawData)
        if sec_rva <= rva < sec_rva + sec_size:
            return s.PointerToRawData + (rva - sec_rva)
    raise RuntimeError(f"VA 0x{va:08X} not in any section")


def file_offset_to_va(pe: pefile.PE, off: int) -> int:
    for s in pe.sections:
        if s.PointerToRawData <= off < s.PointerToRawData + s.SizeOfRawData:
            return pe.OPTIONAL_HEADER.ImageBase + s.VirtualAddress + (off - s.PointerToRawData)
    raise RuntimeError(f"file offset 0x{off:X} not in any section")


def find_pattern(buf: bytes, pat: bytes, start: int = 0, end: int | None = None) -> list[int]:
    """All offsets in [start, end) where pat matches."""
    if end is None:
        end = len(buf)
    out = []
    i = start
    while True:
        i = buf.find(pat, i, end)
        if i < 0:
            break
        out.append(i)
        i += 1
    return out


def find_function_start(buf: bytes, text_start: int, match_off: int, max_lookback: int = 0x4000) -> int:
    """Walk back from match_off to find the nearest function boundary.

    Heuristic: a function ends with RET (C3 / C2 imm16) optionally followed
    by INT3 (CC) padding. The next instruction after that padding is the
    function start. We accept any RET whose successor (after padding) looks
    like a plausible prologue start.
    """
    i = match_off - 1
    floor = max(text_start, match_off - max_lookback)
    plausible_starts = (0x55, 0x53, 0x56, 0x57, 0x83, 0x81, 0x8B, 0xA1, 0xB8)
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
    return floor  # fallback


def find_function_end(buf: bytes, fn_start: int, scan_limit: int = 0x10000) -> int:
    """Best-effort scan forward looking for the next RET that's followed by
    function-boundary signals. Approximate: the function may have multiple
    RETs; we want the LAST one before the next prologue."""
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
    md.skipdata = True
    md.detail = False
    last_ret = fn_start + scan_limit
    for ins in md.disasm(buf[fn_start:fn_start + scan_limit], fn_start):
        if ins.mnemonic in ("ret", "retn"):
            j = ins.address + ins.size
            while j < fn_start + scan_limit and buf[j] in (0xCC, 0x90):
                j += 1
            if j < fn_start + scan_limit and buf[j] in (0x55, 0x53, 0x56, 0x57, 0x83, 0x81, 0x8B):
                return ins.address + ins.size
            last_ret = ins.address + ins.size
    return last_ret


def disassemble(buf: bytes, file_start: int, length: int, va_base_for_start: int) -> list[capstone.CsInsn]:
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
    md.skipdata = True
    md.detail = True
    return list(md.disasm(buf[file_start:file_start + length], va_base_for_start))


def find_xrefs_to_data(pe: pefile.PE, buf: bytes, target_va: int) -> list[tuple[int, str]]:
    """Find every FPU-load instruction (D8/D9 with mod=00 r/m=101) in .text
    whose absolute m32 operand equals target_va.
    """
    text = find_section(pe, ".text")
    text_start = text.PointerToRawData
    text_end = text_start + text.SizeOfRawData
    target_le = struct.pack("<I", target_va)

    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
    md.skipdata = True
    md.detail = True

    hits = []
    # Quick byte search for any 6-byte sequence that ENDS in target_le; use
    # capstone to confirm and report the actual mnemonic.
    i = text_start
    while True:
        idx = buf.find(target_le, i, text_end)
        if idx < 0:
            break
        # Try to disassemble the instruction starting at idx-2 (D8/D9 prefix)
        for back in (2,):
            if idx - back < text_start:
                continue
            try:
                insns = list(md.disasm(buf[idx - back:idx - back + 8], file_offset_to_va(pe, idx - back)))
            except Exception:
                insns = []
            if insns and insns[0].size == 6 and insns[0].address + 2 == file_offset_to_va(pe, idx):
                ins = insns[0]
                hits.append((idx - back, f"{ins.mnemonic} {ins.op_str}"))
                break
        i = idx + 1
    return hits


def main() -> int:
    dll_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_DLL
    if not dll_path.is_file():
        print(f"DLL not found: {dll_path}", file=sys.stderr)
        return 1

    pe = pefile.PE(str(dll_path), fast_load=True)
    buf = pe.__data__  # whole file as bytes

    rdata = find_section(pe, ".rdata")
    text = find_section(pe, ".text")
    text_start = text.PointerToRawData
    text_end = text_start + text.SizeOfRawData
    rdata_start = rdata.PointerToRawData

    # Sanity-check the jitter scalar.
    jitter_off = va_to_file_offset(pe, JITTER_VA)
    jitter_val = struct.unpack("<f", buf[jitter_off:jitter_off + 4])[0]
    n_jitter_off = va_to_file_offset(pe, N_JITTER_VA)
    n_jitter_val = struct.unpack("<f", buf[n_jitter_off:n_jitter_off + 4])[0]
    print(f"Jitter scalar  @ VA 0x{JITTER_VA:08X}  = {jitter_val}")
    print(f"-Jitter scalar @ VA 0x{N_JITTER_VA:08X}  = {n_jitter_val}")
    print()

    matches = find_pattern(buf, JITTER_SIG, text_start, text_end)
    if not matches:
        print("ERROR: jitter signature not found in .text")
        return 2
    if len(matches) > 1:
        print(f"WARNING: signature matches {len(matches)} sites; expected 1")
    match_off = matches[0]
    match_va = file_offset_to_va(pe, match_off)
    print(f"Jitter signature match: file=0x{match_off:X}  VA=0x{match_va:08X}")
    print()

    fn_start = find_function_start(buf, text_start, match_off)
    fn_va    = file_offset_to_va(pe, fn_start)
    fn_end   = find_function_end(buf, fn_start, scan_limit=0x4000)
    fn_end_va = file_offset_to_va(pe, min(fn_end, text_end - 1))
    print(f"Enclosing function start (heuristic): file=0x{fn_start:X}  VA=0x{fn_va:08X}")
    print(f"Enclosing function end   (heuristic): file=0x{fn_end:X}  VA=0x{fn_end_va:08X}")
    print(f"Match offset within function: +0x{match_off - fn_start:X}")
    print()

    # Disassemble the 0x100 bytes surrounding the match.
    print("=== Disassembly window around jitter match (±64 bytes) ===")
    win_start = max(fn_start, match_off - 0x40)
    win_va    = file_offset_to_va(pe, win_start)
    win_len   = min(0x100, text_end - win_start)
    for ins in disassemble(buf, win_start, win_len, win_va):
        marker = ""
        if ins.address == match_va:
            marker = "  <-- signature match start"
        elif ins.address == match_va + 0x0D:
            marker = "  <-- XICamera patches operand at +0x0F"
        elif ins.address == match_va + 0x1D:
            marker = "  <-- XICamera patches operand at +0x1F"
        bs = " ".join(f"{b:02X}" for b in ins.bytes)
        print(f"  0x{ins.address:08X}  {bs:<24}  {ins.mnemonic} {ins.op_str}{marker}")
    print()

    print(f"=== Every reader of 0x{JITTER_VA:08X} (=0.125) in .text ===")
    for off, txt in find_xrefs_to_data(pe, buf, JITTER_VA):
        va = file_offset_to_va(pe, off)
        print(f"  file=0x{off:06X}  VA=0x{va:08X}  {txt}")
    print()
    print(f"=== Every reader of 0x{N_JITTER_VA:08X} (=-0.125) in .text ===")
    for off, txt in find_xrefs_to_data(pe, buf, N_JITTER_VA):
        va = file_offset_to_va(pe, off)
        print(f"  file=0x{off:06X}  VA=0x{va:08X}  {txt}")
    print()

    # Also xref the threshold constant 0x10328D38 (= 3.0). Tells us whether
    # patching the threshold globally is safe (used only by this function)
    # vs. the per-site pointer-rewrite required if it's a shared constant.
    THRESHOLD_VA = 0x10328D38
    print(f"=== Every reader of 0x{THRESHOLD_VA:08X} (=3.0 threshold) in .text ===")
    for off, txt in find_xrefs_to_data(pe, buf, THRESHOLD_VA):
        va = file_offset_to_va(pe, off)
        in_fn = "  (inside sub_1001ED90)" if fn_start <= off < fn_end else ""
        print(f"  file=0x{off:06X}  VA=0x{va:08X}  {txt}{in_fn}")
    print()

    print("=== Readers within sub_1001ED90 (the enclosing function) ===")
    print(f"(approx function range: VA 0x{fn_va:08X}..0x{fn_end_va:08X})")
    in_fn_readers = []
    for off, txt in (find_xrefs_to_data(pe, buf, JITTER_VA)
                      + find_xrefs_to_data(pe, buf, N_JITTER_VA)):
        if fn_start <= off < fn_end:
            in_fn_readers.append((off, txt))
            va = file_offset_to_va(pe, off)
            offset_in_fn = off - fn_start
            print(f"  +0x{offset_in_fn:04X}  VA=0x{va:08X}  {txt}")
    print()

    # Resolve threshold constants referenced near the readers (the comparison
    # constants tell us what triggers the damping block in each case).
    print("=== Disassembly around each in-function reader (±48 bytes) ===")
    for off, _txt in sorted(in_fn_readers):
        va = file_offset_to_va(pe, off)
        win_start = max(fn_start, off - 0x30)
        win_va = file_offset_to_va(pe, win_start)
        win_len = min(0x70, text_end - win_start)
        print(f"\n--- reader @ +0x{off - fn_start:04X} (VA 0x{va:08X}) ---")
        for ins in disassemble(buf, win_start, win_len, win_va):
            marker = "  <-- this reader" if ins.address == va else ""
            bs = " ".join(f"{b:02X}" for b in ins.bytes)
            print(f"  0x{ins.address:08X}  {bs:<24}  {ins.mnemonic} {ins.op_str}{marker}")
    print()

    # Decode any comparison constants we saw in those windows. Specifically
    # collect every immediate float-address operand referenced in fcomp/fcom/
    # fsub/fld around the readers, and print its value.
    print("=== Constants referenced near these readers ===")
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
    md.detail = True
    md.skipdata = True
    seen = set()
    for off, _ in in_fn_readers:
        win_start = max(fn_start, off - 0x40)
        win_va = file_offset_to_va(pe, win_start)
        for ins in md.disasm(buf[win_start:win_start + 0x80], win_va):
            try:
                ops = ins.operands
            except capstone.CsError:
                continue
            for op in ops:
                if op.type == capstone.x86.X86_OP_MEM and op.mem.disp and not op.mem.base and not op.mem.index:
                    addr = op.mem.disp & 0xFFFFFFFF
                    if 0x10328000 <= addr < 0x10350000 and addr not in seen:
                        seen.add(addr)
                        try:
                            o = va_to_file_offset(pe, addr)
                            v = struct.unpack("<f", buf[o:o + 4])[0]
                            print(f"  {ins.mnemonic} @ 0x{ins.address:08X} -> [0x{addr:08X}] = {v}")
                        except Exception:
                            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
