--[[
    test_core.lua - exercises xicamera_core.lua against an unpacked FFXiMain.dll image with a
    fake memory adapter (reads from the image, writes to an overlay, fake allocations).

    Usage:  lua tools/test_core.lua <unpacked FFXiMain image>
    Needs Lua 5.1 (the game's Lua). Exits non-zero on the first failing check.
]]

local imagePath = arg[1]
if not imagePath then io.stderr:write('usage: lua tools/test_core.lua <unpacked FFXiMain image>\n') os.exit(2) end

local script = arg[0]:gsub('[^/\\]+$', '')
package.path = script .. '../Ashita4/addons/xicamera/?.lua;' .. package.path
local Core = require('xicamera_core')

-- every port ships a verbatim copy of the core; the Ashita 4 one is the source of truth
do
    local function slurp(path) local h = io.open(path, 'rb') if not h then return nil end local s = h:read('*a') h:close() return s end
    local root = script .. '../'
    local master = slurp(root .. 'Ashita4/addons/xicamera/xicamera_core.lua')
    for _, copy in ipairs({ 'Ashita3/addons/xicamera/xicamera_core.lua', 'Windower4/addons/XICamera/lib/xicamera_core.lua', 'Windower5/addons/xicamera/xicamera_core.lua' }) do
        if slurp(root .. copy) ~= master then
            io.stderr:write('core copy differs from Ashita4/addons/xicamera/xicamera_core.lua: ' .. copy .. '\n')
            os.exit(1)
        end
    end
    print('core copies identical')
end

local f = assert(io.open(imagePath, 'rb'))
local img = f:read('*a')
f:close()

local BASE = 0x10000000
local ALLOC_BASE = 0x20000000

-- IEEE-754 single precision without string.pack (Lua 5.1)
local function floatToBytes(x)
    local sign = 0
    if x < 0 or (x == 0 and 1 / x < 0) then sign = 1; x = -x end
    local mant, exp
    if x == 0 then mant, exp = 0, 0
    else
        local m, e = math.frexp(x)      -- x = m * 2^e, 0.5 <= m < 1
        exp = e + 126
        mant = math.floor((m * 2 - 1) * 8388608 + 0.5)
        if mant == 8388608 then mant = 0; exp = exp + 1 end
    end
    local bits = sign * 2147483648 + exp * 8388608 + mant
    return bits
end
local function bytesToFloat(bits)
    local sign = bits >= 2147483648 and -1 or 1
    if sign < 0 then bits = bits - 2147483648 end
    local exp = math.floor(bits / 8388608)
    local mant = bits % 8388608
    if exp == 0 then return sign * mant * 2 ^ -149 end
    return sign * (1 + mant / 8388608) * 2 ^ (exp - 127)
end

local overlay = {}
local function byteAt(a)
    local o = overlay[a]
    if o then return o end
    local i = a - BASE
    if i >= 0 and i < #img then return img:byte(i + 1) end
    return 0
end
local function readN(a, n)
    local v = 0
    for k = n - 1, 0, -1 do v = v * 256 + byteAt(a + k) end
    return v
end
local function writeN(a, n, v)
    for k = 0, n - 1 do overlay[a + k] = v % 256; v = math.floor(v / 256) end
end

local nextAlloc = ALLOC_BASE
local log = {}
local mem = {
    find = function(sig)
        local pat = {}
        for i = 1, #sig, 2 do
            local t = sig:sub(i, i + 1)
            if t == '??' then pat[#pat + 1] = '.'
            else
                local c = string.char(tonumber(t, 16))
                if c == '\0' then pat[#pat + 1] = '%z'
                elseif c:match('%w') then pat[#pat + 1] = c
                else pat[#pat + 1] = '%' .. c end
            end
        end
        local s = img:find(table.concat(pat))
        return s and (BASE + s - 1) or 0
    end,
    read_u16 = function(a) return readN(a, 2) end,
    read_u32 = function(a) return readN(a, 4) end,
    read_float = function(a) return bytesToFloat(readN(a, 4)) end,
    write_u16 = function(a, v) writeN(a, 2, v) end,
    write_u32 = function(a, v) writeN(a, 4, v) end,
    write_float = function(a, v) writeN(a, 4, floatToBytes(v)) end,
    alloc = function(size) local a = nextAlloc; nextAlloc = nextAlloc + size; return a end,
    log = function(text) log[#log + 1] = text end,
}

local failures = 0
local function check(cond, what)
    if cond then print('  ok   ' .. what) else failures = failures + 1; print('  FAIL ' .. what) end
end
local function near(a, b) return a and b and math.abs(a - b) < 1e-5 end
local function siteByName(core, name)
    for _, s in ipairs(core.sites) do if s.name == name then return s end end
end

-- ---------------------------------------------------------------- clean install
print('clean install')
local core = Core.new(mem)
check(core:install(), 'install reports every required group in')
local rows = core:status()
local patched, other = 0, {}
for _, r in ipairs(rows) do if r.state == 'patched' then patched = patched + 1 else other[#other + 1] = r.name .. '=' .. r.state end end
check(patched == #Core.SITES, 'every site patched (' .. patched .. '/' .. #Core.SITES .. ') ' .. table.concat(other, ', '))
check(near(core:original('min'), 3.0) and near(core:original('max'), 6.0), 'stock min/max read from the literals')
check(core:original('minBattle') and core:original('maxBattle') and core:original('hPan') and core:original('vPan') and core:original('battleRange'), 'every slot has a stock value')
check(near(core:original('jitter'), 0.125) and near(core:original('jitterNeg'), -0.125), 'jitter originals are +/-0.125')
local minLiteral = 0x10328d38
check(near(mem.read_float(minLiteral), 3.0), 'the pooled 3.0 literal is untouched')

local eyeC = siteByName(core, 'min distance: eye follow C')
check(mem.read_u32(eyeC.at) == core:slotAddress('min'), 'eye follow C operand points at the min slot')
check(mem.read_u16(eyeC.at - 2) == 0x05D9, 'eye follow C opcode bytes untouched')

core:setCameraDistance(25)
check(near(mem.read_float(core:slotAddress('max')), 25) and near(mem.read_float(core:slotAddress('min')), 22), 'distance 25 -> max 25, min 22 in the slots')
check(near(mem.read_float(minLiteral), 3.0), 'the pooled 3.0 literal is still 3.0 after setting distance 25')

core:setSlot('jitter', 1.0) core:setSlot('jitterNeg', -1.0)
check(near(mem.read_float(core:slotAddress('jitter')), 1.0), 'jitter slot holds 1.0')

check(core:battleRangeLocked() == true, 'battle range starts locked')
check(core:setBattleRangeLock(false) and core:battleRangeLocked() == false, 'unlock writes the NOPs')
check(core:setBattleRangeLock(true) and core:battleRangeLocked() == true, 'lock restores fld1')

-- ---------------------------------------------------------------- other tools after load: XICamera lets them
print('after load')
for k in pairs(Core) do
    check(not tostring(k):lower():find('recheck'), 'no re-check entry point in the core (' .. tostring(k) .. ')')
end
mem.write_u32(eyeC.at, eyeC.original)                           -- another tool wrote the client's operand back
check(mem.read_u32(eyeC.at) == eyeC.original, 'nothing puts the patch back on its own')
local rows = core:status(true)
check(eyeC.state == 'reverted', 'a status refresh reports the revert (' .. tostring(eyeC.state) .. ')')
check(mem.read_u32(eyeC.at) == eyeC.original, 'the refresh wrote nothing')

local jx = siteByName(core, 'jitter push x')
local foreignOne = mem.alloc(4) mem.write_float(foreignOne, 1.0)
mem.write_u32(jx.at, foreignOne)                                -- another tool pointed it at its own 1.0
core:refresh()
check(jx.state == 'neutral' and mem.read_u32(jx.at) == foreignOne, 'a takeover at our value is neutral and left alone')
mem.write_u32(jx.at, jx.original)                               -- the other tool unloaded
core:refresh()
check(jx.state == 'neutral' and mem.read_u32(jx.at) == jx.original, 'a handed-back site is not retaken')

local jz = siteByName(core, 'jitter push z')
mem.write_u32(jz.at, jz.original)                               -- reverted, then an unloading tool restores our pointer
core:refresh()
mem.write_u32(jz.at, core:slotAddress('jitter'))
core:refresh()
check(jz.state == 'patched', 'a site holding our pointer again counts as ours, so unload restores it')

-- ---------------------------------------------------------------- uninstall
print('uninstall')
local eyeA = siteByName(core, 'min distance: eye follow A')
local stranger = mem.alloc(4)
mem.write_u32(eyeA.at, stranger)                                -- someone else took eye follow A meanwhile
core:refresh()
check(eyeA.state == 'foreign', 'a takeover at another value is reported as foreign')
local eyeB = siteByName(core, 'min distance: eye follow B')
mem.write_u32(eyeB.at, stranger)                                -- taken over after the last status refresh
check(not core:uninstall(), 'uninstall reports the restore it had to refuse')
check(eyeB.state == 'refused' and mem.read_u32(eyeB.at) == stranger, 'a site that changed since the last refresh is refused, not overwritten')
check(eyeA.state == 'foreign' and mem.read_u32(eyeA.at) == stranger, 'a known-foreign site is left alone without counting as refused')
check(mem.read_u32(eyeC.at) == eyeC.original, 'a reverted site is left as the other tool set it')
check(mem.read_u32(jz.at) == jz.original, 'a patched jitter site is restored')
local eyeE = siteByName(core, 'min distance: eye follow E')
check(eyeE.state == 'restored' and mem.read_u32(eyeE.at) == eyeE.original, 'an untouched site is restored')
local refused = 0
for _, r in ipairs(core:status()) do if r.state == 'refused' then refused = refused + 1 end end
check(refused == 1, 'exactly one refused site')
check(nextAlloc == ALLOC_BASE + 4 * #Core.SLOTS + 8, 'slots were allocated once and never freed')

-- ---------------------------------------------------------------- TrueFPS loaded first
print('TrueFPS-first scenarios')
overlay = {}
local push = siteByName(Core.new(mem), 'jitter push vertical')
local pushAt = mem.find(push.spec.sig) + push.spec.off
-- TrueFPS's ReplaceCall: E8 rel32 90 over the fmul
mem.write_u16(pushAt - 2, 0x11E8) mem.write_u32(pushAt, 0x90223344)
-- TrueFPS's swap on the horizontal pushes: operands to its own 0.125 cell
local cell = mem.alloc(4) mem.write_float(cell, 0.125)
local jxAt = mem.find('8D54242C8D44242CD8C9525550') + 0x0F
mem.write_u32(jxAt, cell) mem.write_u32(jxAt + 0x10, cell)
core = Core.new(mem)
check(core:install(), 'required groups still install with TrueFPS loaded first')
check(siteByName(core, 'jitter push vertical').state == 'owned', 'the replaced instruction is reported as owned, not missing')
local jx2 = siteByName(core, 'jitter push x')
check(jx2.state == 'foreign' and mem.read_u32(jxAt) == cell, 'TrueFPS\'s 0.125 cell is foreign and not overwritten')
check(core:uninstall(), 'uninstall is clean when nothing foreign was touched')
check(mem.read_u32(jxAt) == cell and mem.read_u32(pushAt) == 0x90223344, 'TrueFPS\'s bytes survive XICamera\'s unload')

-- ---------------------------------------------------------------- a missing required site
print('missing signature')
overlay = {}
local saved = Core.SITES[3].sig
Core.SITES[3].sig = 'DEADBEEFDEADBEEFDEADBEEF'
core = Core.new(mem)
check(not core:install(), 'install reports failure when a min reader is missing')
check(not core:groupOn('min') and core:groupOn('max'), 'only the min group is off')
local written = 0
for _, s in ipairs(core.sites) do if s.slot == 'min' and s.state == 'patched' then written = written + 1 end end
check(written == 0, 'no min site was patched (all-or-none)')
Core.SITES[3].sig = saved

-- ---------------------------------------------------------------- atomic adapter (Windower DLL)
print('compare-exchange adapter')
overlay = {}
local casCalls = 0
mem.cas_u32 = function(a, expected, v)
    casCalls = casCalls + 1
    local prev = readN(a, 4)
    if prev == expected then writeN(a, 4, v) end
    return prev
end
core = Core.new(mem)
check(core:install() and casCalls == #Core.SITES, 'every patch goes through compare-exchange (' .. casCalls .. ')')
local eyeD = siteByName(core, 'min distance: eye follow D')
mem.write_u32(eyeD.at, stranger)
check(not core:uninstall() and eyeD.state == 'refused' and mem.read_u32(eyeD.at) == stranger, 'compare-exchange refuses a changed operand')
mem.cas_u32 = nil

print(failures == 0 and 'ALL PASSED' or (failures .. ' FAILED'))
os.exit(failures == 0 and 0 or 1)
