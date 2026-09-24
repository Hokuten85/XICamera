"""
analyze_tool_overlap.py - Map XICamera's signatures onto an unpacked FFXiMain.dll image,
list every .text reader of each constant XICamera edits in place, and intersect XICamera's
write and signature ranges with TrueFPS's patch sites (located by TrueFPS's own locators).

Usage:
    python tools/analyze_tool_overlap.py <FFXiMain image> [--raw]

--raw treats the file as a flat memory image (file offset == RVA), which is what a memory
dump is. Without it the file is parsed as a PE and its sections are mapped by pefile.
Requires a TrueFPS checkout at ./TrueFPS (or edit the path below). Needs pefile; capstone
is optional and adds disassembly of each reader.

See docs/TOOL_COMPAT_REVIEW.md for the findings this produced.
"""
import re, struct, sys
import pefile
try:
    import capstone
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
except Exception:
    md = None

DLL = sys.argv[1] if len(sys.argv) > 1 else r"C:\Program Files (x86)\PlayOnline\SquareEnix\FINAL FANTASY XI\FFXiMain.dll"
pe = pefile.PE(DLL)
img = open(DLL, "rb").read() if "--raw" in sys.argv else pe.get_memory_mapped_image()
base = pe.OPTIONAL_HEADER.ImageBase
def sname(s): return s.Name.rstrip(b"\x00").decode()
def sect(rva):
    for s in pe.sections:
        if s.VirtualAddress <= rva < s.VirtualAddress + max(s.Misc_VirtualSize, s.SizeOfRawData):
            return sname(s)
    return '?'
def u32(rva): return struct.unpack_from('<I', img, rva)[0]
def f32(rva): return struct.unpack_from('<f', img, rva)[0]

def parse(pat):
    toks = pat.replace('\n',' ').split()
    if len(toks) == 1 and len(toks[0]) > 2:  # xicamera compact hex
        t = toks[0]; toks = [t[i:i+2] for i in range(0, len(t), 2)]
    b = bytes(int(t,16) if t != '??' else 0 for t in toks)
    m = bytes(0 if t == '??' else 0xFF for t in toks)
    return b, m
def findall(pat, limit=64):
    b, m = parse(pat)
    n = len(b); hits = []
    first = bytes([b[0]])
    i = img.find(first) if m[0] == 0xFF else 0
    while i != -1 and i + n <= len(img):
        ok = True
        for k in range(n):
            if m[k] and img[i+k] != b[k]: ok = False; break
        if ok:
            hits.append(i)
            if len(hits) >= limit: break
        i = img.find(first, i+1) if m[0] == 0xFF else i+1
    return hits

print(f"DLL {DLL}\nImageBase {base:#x} size {len(img):#x}")
for s in pe.sections:
    print(f"  {sname(s):8} rva {s.VirtualAddress:#08x} vsize {s.Misc_VirtualSize:#08x} chars {s.Characteristics:#010x}")

XI = [
 ("minDistance",      'D8C9D9C0D8C1D9C2D80D????????D9C3DCC0D8EB', 0x0A, 'value'),
 ("maxDistance",      'D9442410D825????????51D80D', 0x06, 'value'),
 ("minBattle",        '5152D8442424D905????????D8C1', 0x08, 'value'),
 ("maxBattle",        'D8C1D8CAD95C2450D805????????D8C9', 0x0A, 'value'),
 ("hPanSpeed",        'D84C24208B068BCED80D', 0x0A, 'value'),
 ("vPanSpeed",        'D84C24248B168BCED80D', 0x0A, 'value'),
 ("zoomSetup",        '85C0741AD9442404D80D????????D80D????????D87C', 0x10, 'operand'),
 ("walkAnim",         '0F85????????D80D????????D913D81D', 0x08, 'operand'),
 ("npcWalkAnim",      '7514D9442410D80D????????D91B8B8E', 0x08, 'operand'),
 ("battleSound",      'D95C2414741B487410D9442410D80D', 0x0F, 'operand'),
 ("jitterPush2_x",    '8D54242C8D44242CD8C9525550', 0x0F, 'operand'),
 ("jitterPush2_z",    '8D54242C8D44242CD8C9525550', 0x1F, 'operand'),
 ("jitterPush1",      'D8642410518D44242CD80D????????D91C24', 0x0B, 'operand'),
 ("battleCamRange",   'D8C9D99C24DC000000DDD8D9442450D8442428D83D', 0x15, 'operand'),
 ("battleRangeLock",  'D8C9D99C24DC000000DDD8D9442450D8442428D83D', 0x19, 'code2'),
 ("cameraManager",    'A1????????0594020000C39090909090A1????????8B4050C3', 0x11, 'readonly'),
]
xi_writes = []
xi_sigs = []
consts = {}
print("\n=== XICamera signatures on this build ===")
for name, pat, off, kind in XI:
    hits = findall(pat)
    b,_ = parse(pat)
    if len(hits) != 1:
        print(f"  {name:16} matches={len(hits)}  <-- {'NOT FOUND' if not hits else 'AMBIGUOUS'}"); continue
    m = hits[0]
    xi_sigs.append((name, m, len(b)))
    if kind == 'value':
        va = u32(m+off); rva = va - base
        consts[name] = rva
        print(f"  {name:16} sig@{m:#08x}  const va {va:#x} rva {rva:#08x} [{sect(rva)}] = {f32(rva):.6g}")
    elif kind == 'operand':
        va = u32(m+off); rva = va - base
        xi_writes.append((name, m+off, 4))
        print(f"  {name:16} sig@{m:#08x}  operand@{m+off:#08x} -> va {va:#x} rva {rva:#08x} [{sect(rva)}] = {f32(rva):.6g}  ({img[m+off-2]:02X} {img[m+off-1]:02X})")
    elif kind == 'code2':
        xi_writes.append((name, m+off, 2))
        print(f"  {name:16} sig@{m:#08x}  code@{m+off:#08x} bytes {img[m+off]:02X} {img[m+off+1]:02X}")
    else:
        va = u32(m+off); print(f"  {name:16} sig@{m:#08x}  global va {va:#x}")

def readers(rva):
    va = struct.pack('<I', base + rva)
    out = []; i = img.find(va)
    while i != -1:
        if sect(i) == '.text':
            out.append(i)
        i = img.find(va, i+1)
    return out
print("\n=== Readers of each in-place-overwritten constant (shared-constant check) ===")
for name, crva in consts.items():
    rs = readers(crva)
    print(f"  {name:16} const rva {crva:#08x} = {f32(crva):.6g}: {len(rs)} reference(s)")
    for r in rs:
        desc = ''
        if md:
            for back in (2, 3, 4, 1, 6, 7):
                for ins in md.disasm(bytes(img[r-back:r+4]), base + r - back):
                    if ins.address == base + r - back and ins.size == back + 4:
                        desc = f"{ins.mnemonic} {ins.op_str}"; break
                if desc: break
        print(f"      @{r-2:#08x}  {img[r-2]:02X} {img[r-1]:02X} <imm>   {desc}")

src = open('TrueFPS/src/smooth.h', encoding='utf-8', errors='replace').read()
kl = {}
for m in re.finditer(r'inline constexpr const char\* (k\w+)\s*=\s*((?:"[^"]*"\s*)+);', src):
    kl[m.group(1)] = ' '.join(re.findall(r'"([^"]*)"', m.group(2)))
sites = []
for m in re.finditer(r'\{"([^"]+)", (0x[0-9a-fA-F]+), (?:"([^"]*)"|(k\w+)), (-?\d+|0x[0-9a-fA-F]+), .*?SiteKind::(\w+), (\d+),', src):
    name, rva, lit, ident, loff, kind, ln = m.groups()
    loc = lit if lit is not None else kl.get(ident)
    sites.append((name, int(rva,16), loc, int(loff,0), kind, int(ln)))
print(f"\n=== TrueFPS: {len(sites)} sites parsed; locating on this build ===")
tf = []
for name, rva, loc, loff, kind, ln in sites:
    hits = findall(loc, 3) if loc else []
    at = hits[0] + loff if len(hits) == 1 else None
    if kind == 'SwapImm': w = (2, 4)
    elif kind == 'CallToStub': w = (1, 4)
    elif kind in ('ReplaceCall','ReplaceFld'): w = (0, ln)
    elif kind == 'Byte': w = (0, 1)
    elif kind == 'Disp8': w = (1, 1)
    else: w = (0, ln)
    tf.append((name, at, rva, kind, ln, w, len(hits)))
    note = '' if at is not None and at == rva else (f' (doc rva {rva:#x}, hits={len(hits)})')
    print(f"  {name:34} {kind:12} at {at if at is None else format(at,'#08x')}{note}")

def overlap(a0, a1, b0, b1): return a0 < b1 and b0 < a1
print("\n=== Overlaps: XICamera WRITE ranges vs TrueFPS WRITE ranges ===")
for xn, xr, xl in xi_writes:
    for tn, at, rva, kind, ln, (wo, wl), nh in tf:
        if at is None: continue
        if overlap(xr, xr+xl, at+wo, at+wo+wl):
            print(f"  XICamera {xn} [{xr:#x}+{xl}]  <->  TrueFPS '{tn}' {kind} writes [{at+wo:#x}+{wl}] (instruction [{at:#x}+{ln}])")
print("\n=== Overlaps: XICamera SIGNATURE spans vs TrueFPS WRITE ranges (sig fails if TrueFPS loads first) ===")
for xn, xr, xl in xi_sigs:
    for tn, at, rva, kind, ln, (wo, wl), nh in tf:
        if at is None: continue
        if overlap(xr, xr+xl, at+wo, at+wo+wl):
            print(f"  XICamera sig {xn} [{xr:#x}+{xl}]  <->  TrueFPS '{tn}' {kind} writes [{at+wo:#x}+{wl}]")
print("\n=== TrueFPS sites whose float operand names a constant XICamera overwrites in place ===")
for tn, at, rva, kind, ln, w, nh in tf:
    if at is None or kind not in ('SwapImm','ReplaceCall'): continue
    if img[at] in (0xD8,0xD9) and ln >= 6:
        va = u32(at+2); r = va - base
        for cn, crva in consts.items():
            if r == crva: print(f"  TrueFPS '{tn}' at {at:#x} reads {cn} const {crva:#x}")
