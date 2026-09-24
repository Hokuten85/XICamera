"""
gen_signatures.py - generate unique, tool-tolerant signatures for reader instructions.

For each target RVA (an x87 instruction with a disp32 memory operand) it disassembles a window of
instructions around it, wildcards every imm32/disp32/rel32, rejects windows whose fixed bytes
overlap anything TrueFPS writes, and keeps the shortest window that matches the image exactly
once. Output is XICamera's compact hex plus the operand offset, ready for Core.SITES.

Usage:
    python tools/gen_signatures.py            (edit DUMP and `targets` below first)

Needs an unpacked FFXiMain image (raw memory layout), capstone, and a TrueFPS checkout at
./TrueFPS for its site table (smooth.h). The jitter sites keep their hand-made signatures.
"""
import re, struct, sys
import capstone
from capstone import x86

DUMP = sys.argv[1] if len(sys.argv) > 1 else r"C:/Users/Hokuten/AppData/Local/Temp/FFXiMain_retail_20260528_unpacked.bin"
img = open(DUMP, "rb").read()
base = 0x10000000
md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
md.detail = True

# TrueFPS write ranges on this build (from xicam_overlap.py --raw output)
src = open("TrueFPS/src/smooth.h", encoding="utf-8", errors="replace").read()
kl = {}
for m in re.finditer(r'inline constexpr const char\* (k\w+)\s*=\s*((?:"[^"]*"\s*)+);', src):
    kl[m.group(1)] = " ".join(re.findall(r'"([^"]*)"', m.group(2)))

def parse(pat):
    toks = pat.split()
    if len(toks) == 1 and len(toks[0]) > 2:
        t = toks[0]; toks = [t[i:i+2] for i in range(0, len(t), 2)]
    return bytes(int(t, 16) if t != "??" else 0 for t in toks), bytes(0 if t == "??" else 0xFF for t in toks)

def findall(pat, limit=8):
    b, m = parse(pat); n = len(b); hits = []
    first = bytes([b[0]]); i = img.find(first)
    while i != -1 and i + n <= len(img):
        if all(not m[k] or img[i+k] == b[k] for k in range(n)):
            hits.append(i)
            if len(hits) >= limit: break
        i = img.find(first, i + 1)
    return hits

tf_writes = []
for m in re.finditer(r'\{"([^"]+)", (0x[0-9a-fA-F]+), (?:"([^"]*)"|(k\w+)), (-?\d+|0x[0-9a-fA-F]+), .*?SiteKind::(\w+), (\d+),', src):
    name, rva, lit, ident, loff, kind, ln = m.groups()
    loc = lit if lit is not None else kl.get(ident)
    hits = findall(loc, 3) if loc else []
    if len(hits) != 1: continue
    at = hits[0] + int(loff, 0); ln = int(ln)
    wo, wl = {"SwapImm": (2, 4), "CallToStub": (1, 4), "Byte": (0, 1), "Disp8": (1, 1)}.get(kind, (0, ln))
    tf_writes.append((name, at + wo, at + wo + wl))

def truefps_touches(lo, hi):
    return [n for n, a, b in tf_writes if lo < b and a < hi]

def wild_ranges(ins):
    """Byte ranges inside the instruction that hold imm32/disp32/rel32 (wildcard these)."""
    out = []
    if ins.imm_size == 4 and ins.imm_offset: out.append((ins.imm_offset, ins.imm_offset + 4))
    if ins.disp_size == 4 and ins.disp_offset: out.append((ins.disp_offset, ins.disp_offset + 4))
    if ins.group(x86.X86_GRP_JUMP) or ins.group(x86.X86_GRP_CALL) or ins.group(x86.X86_GRP_BRANCH_RELATIVE):
        if ins.size >= 5 and ins.imm_size == 4: pass  # covered above
    return out

def stream(lo, hi):
    """Linear disassembly from lo; x86 resyncs quickly, we verify the target lands on a boundary."""
    return list(md.disasm(img[lo:hi], base + lo))

def make(target, before=6, after=6, min_len=10, max_len=64):
    # find a stream that contains the target as an instruction start
    for back in range(48, 200, 8):
        ins = stream(target - back, target + 64)
        idx = next((i for i, x in enumerate(ins) if x.address - base == target), None)
        if idx is not None and idx >= before: break
    else:
        raise RuntimeError(f"no boundary for {target:#x}")
    best = None
    for b in range(0, before + 1):
        for a in range(0, after + 1):
            sel = ins[idx - b: idx + 1 + a]
            lo = sel[0].address - base; hi = sel[-1].address - base + sel[-1].size
            if hi - lo < min_len or hi - lo > max_len: continue
            if truefps_touches(lo, hi): continue
            mask = bytearray(b"\xff" * (hi - lo))
            for x in sel:
                for (o0, o1) in wild_ranges(x):
                    s = x.address - base - lo
                    for k in range(s + o0, s + o1): mask[k] = 0
            if any(mask[k] and truefps_touches(lo + k, lo + k + 1) for k in range(hi - lo)): continue
            pat = " ".join("??" if not mask[k] else f"{img[lo+k]:02X}" for k in range(hi - lo))
            hits = findall(pat, 3)
            if len(hits) == 1 and hits[0] == lo:
                cand = (hi - lo, b + a, pat, lo)
                if best is None or cand[:2] < best[:2]: best = cand
    if best is None: raise RuntimeError(f"no unique window for {target:#x}")
    _, _, pat, lo = best
    return pat, target - lo

targets = [
    # (name, rva of instruction, operand byte offset within instruction (always 2 for D8/D9 xx disp32))
    ("minDist_zoomCalc", 0x01C7C4), ("minDist_eyeA", 0x01F8F3), ("minDist_eyeB", 0x01FCB9), ("minDist_eyeC", 0x01FCC6),
    ("minDist_eyeD", 0x01FD34), ("minDist_eyeE", 0x01FD4B), ("minDist_battleCam", 0x02036E),
    ("maxDist_A", 0x01EFC0), ("maxDist_B", 0x01F128), ("maxDist_C", 0x01F764), ("maxDist_D", 0x01F7B4),
    ("maxDist_E", 0x01F80A), ("maxDist_F", 0x01F852), ("maxDist_G", 0x01FC62), ("maxDist_H", 0x01FC75),
    ("minBattle", 0x02031B), ("maxBattle", 0x020329), ("hPan", 0x01EF5C), ("vPan", 0x01F02F),
    ("jitterPush2_x", 0x01FD66), ("jitterPush2_z", 0x01FD76), ("jitterPush1", 0x01FCD5), ("battleRange", 0x020342),
]
for name, rva in targets:
    ins = next(md.disasm(img[rva:rva + 8], base + rva))
    assert ins.disp_size == 4 and ins.disp_offset == 2, (name, ins.mnemonic, ins.op_str)
    try:
        pat, off = make(rva)
        compact = pat.replace(" ", "")
        print(f"{name:20} rva {rva:#08x}  {ins.mnemonic} {ins.op_str:28}  sig '{compact}' operand +{off + 2:#04x}")
    except RuntimeError as e:
        print(f"{name:20} FAILED: {e}")
