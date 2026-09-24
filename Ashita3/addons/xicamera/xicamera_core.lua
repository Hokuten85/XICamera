--[[
    xicamera_core.lua - platform-independent camera patching for XICamera.

    Shared verbatim by the Ashita 3, Ashita 4 and Windower addons. The host supplies a small
    memory adapter (see Core.new) and owns settings, commands and UI; everything that touches
    the client lives here.

    Model
    -----
    The client's camera constants are compiler-pooled literals: the 3.0 "min distance" is the
    same float that 30-odd unrelated functions use, and 6.0 likewise. XICamera therefore never
    writes the client's constants. It allocates its own floats ("slots", one block for the life
    of the process, never freed) and re-points only the camera code's reads at them. Every
    site is a `D8/D9 xx <disp32>` x87 instruction; XICamera swaps the disp32.

    Rules borrowed from TrueFPS so several tools can share the same bytes:
      * A site is patched only while its opcode bytes and its operand still hold what was found
        at resolve time, and restored only while it still holds XICamera's slot. Anything else is
        left alone and reported, never overwritten.
      * An operand that already points outside the client image belongs to another tool. When
        the float there is the value XICamera would write (the jitter sites' 1.0) the site is
        "neutral": the other tool already did the job, and XICamera neither writes nor restores it.
      * Slots are never freed: another tool may have saved a slot address as "original" and will
        write it back after XICamera unloads.
      * A group of sites that must agree (every reader of one constant) installs all-or-none.
      * recheck() re-applies a patch another tool reverted, retakes a neutral site whose owner
        unloaded, and reports a takeover once. It runs once a second, and only inside a window:
        the first minute after install, the first minute after the character first enters the
        world following install (onEnterWorld; later zones open nothing), and a few seconds
        after the host sees another addon or plugin load or unload (beginRecheckWindow). Outside
        a window XICamera lives with whatever other tools do until it unloads.
]]

local Core = {}
Core.__index = Core

Core.VERSION = 1

-- Slot names. Each is one float XICamera owns.
Core.SLOTS = { 'min', 'max', 'minBattle', 'maxBattle', 'hPan', 'vPan', 'jitter', 'jitterNeg', 'battleRange' }

-- Groups install all-or-none. Jitter sites are individually optional.
Core.REQUIRED_GROUPS = { min = true, max = true, minBattle = true, maxBattle = true, hPan = true, vPan = true, battleRange = true }

--[[
    Site table. `sig` is XICamera's compact hex with ?? wildcards, `off` the operand's offset
    from the match, `slot` the float it is re-pointed at, `head` the two opcode bytes expected
    in front of the operand when the signature does not cover them, `want` the value another
    tool may already have pointed the operand at (neutral).

    Verified on the May 2026 retail client; see docs/TOOL_COMPAT_REVIEW.md for the reader map.
    None of the fixed bytes overlap anything TrueFPS writes.
]]
Core.SITES = {
    -- readers of the pooled 3.0 literal inside camera code
    { name = 'min distance: zoom calc',     sig = 'D8C9D9C0D8C1D9C2D80D????????D9C3DCC0D8EB',      off = 0x0A, slot = 'min' },
    { name = 'min distance: zoom setup',    sig = '85C0741AD9442404D80D????????D80D????????D87C',   off = 0x10, slot = 'min' },
    { name = 'min distance: eye follow A',  sig = 'D815????????DFE0F6C4057A62',                     off = 0x02, slot = 'min' },
    { name = 'min distance: eye follow B',  sig = 'D9442410D81D????????DFE0F6C4057A3E',             off = 0x06, slot = 'min' },
    { name = 'min distance: eye follow C',  sig = 'D905????????D864241051',                         off = 0x02, slot = 'min' },
    { name = 'min distance: eye follow D',  sig = 'D9FA83C414D9542410D81D????????',                 off = 0x0B, slot = 'min' },
    { name = 'min distance: eye follow E',  sig = 'D905????????D8642414D944242C',                   off = 0x02, slot = 'min' },
    { name = 'min distance: battle camera', sig = 'D9442424D80D????????EB1F',                       off = 0x06, slot = 'min' },
    -- readers of the pooled 6.0 literal inside camera code
    { name = 'max distance: orbit A',       sig = 'D905????????D8F1D84C2410D95C2410DDD88B16',       off = 0x02, slot = 'max' },
    { name = 'max distance: orbit B',       sig = 'D905????????D8F1D84C2410D95C2410DDD88B06',       off = 0x02, slot = 'max' },
    { name = 'max distance: zoom C',        sig = '743CE8????????D95C2410E8????????D80D????????',   off = 0x12, slot = 'max' },
    { name = 'max distance: zoom D',        sig = '7440E8????????D95C2410E8????????D80D????????',   off = 0x12, slot = 'max' },
    { name = 'max distance: zoom E',        sig = '7E3FE8????????D95C2410E8????????D80D????????',   off = 0x12, slot = 'max' },
    { name = 'max distance: zoom F',        sig = '7D54E8????????D95C2410E8????????D80D????????',   off = 0x12, slot = 'max' },
    { name = 'max distance: eye follow G',  sig = 'EB24D9442410D81D????????',                       off = 0x08, slot = 'max' },
    { name = 'max distance: eye follow H',  sig = 'D9442410D825????????51D80D',                     off = 0x06, slot = 'max' },
    -- single-reader constants
    { name = 'battle min distance',         sig = '5152D8442424D905????????D8C1',                   off = 0x08, slot = 'minBattle' },
    { name = 'battle max distance',         sig = 'D8C1D8CAD95C2450D805????????D8C9',               off = 0x0A, slot = 'maxBattle' },
    { name = 'horizontal pan speed',        sig = 'D84C24208B068BCED80D',                           off = 0x0A, slot = 'hPan', head = 'D80D' },
    { name = 'vertical pan speed',          sig = 'D84C24248B168BCED80D',                           off = 0x0A, slot = 'vPan', head = 'D80D' },
    -- proximity-push damping (the "jitter"): 0.125 -> 1.0 snaps in one frame
    { name = 'jitter push x',               sig = '8D54242C8D44242CD8C9525550',                     off = 0x0F, slot = 'jitter',    head = 'D80D', want = 1.0 },
    { name = 'jitter push z',               sig = '8D54242C8D44242CD8C9525550',                     off = 0x1F, slot = 'jitter',    head = 'D80D', want = 1.0 },
    -- the vertical arm: TrueFPS replaces this whole instruction with a call, so the signature
    -- stops before it and the opcode check reports the takeover instead of "not found"
    { name = 'jitter push vertical',        sig = 'D8642410518D44242C',                             off = 0x0B, slot = 'jitterNeg', head = 'D80D', want = -1.0 },
    -- battle camera range; the 2-byte clamp that follows it is the lock site
    { name = 'battle camera range',         sig = 'D8C9D99C24DC000000DDD8D9442450D8442428D83D',     off = 0x15, slot = 'battleRange', lockOff = 0x19 },
}

Core.CAMERA_MANAGER_SIG = 'A1????????0594020000C39090909090A1????????8B4050C3'
Core.CAMERA_MANAGER_OFF = 0x11

Core.LOCK_NOPS = 0x9090
Core.RECHECK_WINDOW = 60          -- seconds of once-a-second re-checks after install and after the first world entry
Core.RECHECK_AFTER_TOOL_CHANGE = 15   -- seconds after the host sees another addon or plugin load or unload

local function hexbyte(s, i) return tonumber(s:sub(i, i + 1), 16) end

-- The two opcode bytes in front of the operand, from the signature when it covers them.
local function headFromSig(site)
    local i = site.off - 2   -- 0-based byte index of the first head byte
    if i < 0 or (i + 2) * 2 > #site.sig then return nil end
    local a, b = site.sig:sub(i * 2 + 1, i * 2 + 2), site.sig:sub(i * 2 + 3, i * 2 + 4)
    if a == '??' or b == '??' then return nil end
    return tonumber(a .. b, 16)
end

--[[
    Core.new(mem) - mem is the host's memory adapter:
      mem.find(sig)                 -> address of the first match in FFXiMain.dll, or nil / 0
      mem.read_u16 / read_u32 / read_float(address)
      mem.write_u16 / write_u32 / write_float(address, value)
      mem.alloc(size)               -> address, never freed by XICamera
      mem.log(text)                 -> one line to the chat log
      mem.image_base, mem.image_size (optional; derived from the PE header when absent)
      mem.now()                     -> seconds (optional; os.time when absent)
]]
function Core.new(mem)
    local self = setmetatable({}, Core)
    self.mem = mem
    self.sites = {}
    for i, spec in ipairs(Core.SITES) do
        local head = spec.head and tonumber(spec.head, 16) or headFromSig(spec)
        assert(head, 'site ' .. spec.name .. ' needs a head')
        self.sites[i] = { spec = spec, name = spec.name, slot = spec.slot, head = head, state = 'unresolved', note = nil, at = nil, original = nil, logged = false }
    end
    self.slots = {}
    self.groups = {}       -- slot -> { enabled = bool, why = text }
    self.installed = false
    self.recheckUntil = 0  -- seconds; recheck() does nothing past this
    self.lastRecheck = nil -- the second of the last pass
    self.enteredWorld = false   -- onEnterWorld opens a window once
    self.lock = nil        -- { at, original }
    self.cameraManager = nil
    return self
end

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------

function Core:log(text)
    if self.mem.log then self.mem.log(text) end
end

function Core:imageBounds()
    if self.imageBase then return self.imageBase, self.imageSize end
    local mem = self.mem
    if mem.image_base and mem.image_size then
        self.imageBase, self.imageSize = mem.image_base, mem.image_size
        return self.imageBase, self.imageSize
    end
    -- the DOS header is the first thing in the module, so the first 'MZ' is the base
    local base = mem.find('4D5A')
    if base and base ~= 0 then
        local lfanew = mem.read_u32(base + 0x3C)
        local size = mem.read_u32(base + lfanew + 0x50)   -- IMAGE_OPTIONAL_HEADER.SizeOfImage
        if lfanew and lfanew > 0 and lfanew < 0x1000 and size and size > 0 then
            self.imageBase, self.imageSize = base, size
        end
    end
    return self.imageBase, self.imageSize
end

function Core:inImage(address)
    local base, size = self:imageBounds()
    if not base then return false end
    return address >= base and address < base + size
end

-- A float behind a pointer another tool placed. Below 64 KiB nothing is ever mapped; anything
-- else is assumed readable (the Windower reader is exception-guarded; Ashita's is not).
function Core:peekFloat(address)
    if not address or address < 0x10000 then return nil end
    return self.mem.read_float(address)
end

function Core:readHead(site)
    local b = self.mem.read_u16(site.at - 2)
    return b
end

function Core:headOk(site)
    -- read_u16 is little-endian: 'D8 0D' reads as 0x0DD8
    local want = site.head
    local le = ((want % 256) * 256) + math.floor(want / 256)
    return self:readHead(site) == le
end

function Core:slotAddress(name)
    local s = self.slots[name]
    return s and s.addr or nil
end

-- Replace a 4-byte operand only while it still holds `expected`. Uses the adapter's atomic
-- compare-exchange when the host has one (the Windower DLL); otherwise read, write, read back.
function Core:swap32(address, expected, value)
    local mem = self.mem
    if mem.cas_u32 then
        return mem.cas_u32(address, expected, value) == expected and mem.read_u32(address) == value
    end
    if mem.read_u32(address) ~= expected then return false end
    mem.write_u32(address, value)
    return mem.read_u32(address) == value
end

function Core:setState(site, state, note)
    site.state, site.note = state, note
end

function Core:logOnce(site, text)
    if site.logged == text then return end
    site.logged = text
    self:log(site.name .. ': ' .. text)
end

-- ---------------------------------------------------------------------------
-- install / uninstall
-- ---------------------------------------------------------------------------

function Core:allocSlots()
    local block = self.mem.alloc(4 * #Core.SLOTS)
    if not block or block == 0 then return false end
    for i, name in ipairs(Core.SLOTS) do
        self.slots[name] = { addr = block + 4 * (i - 1), original = nil, value = nil }
    end
    return true
end

-- Locate every site and classify it without writing anything.
function Core:resolve()
    local mem = self.mem
    self.matches = {}
    for _, site in ipairs(self.sites) do
        local spec = site.spec
        local match = self.matches[spec.sig]
        if match == nil then
            match = mem.find(spec.sig)
            if not match or match == 0 then match = false end
            self.matches[spec.sig] = match
        end
        if not match then
            self:setState(site, 'missing', 'signature not found on this client build')
        else
            site.at = match + spec.off
            if spec.lockOff then
                self.lock = { at = match + spec.lockOff, original = mem.read_u16(match + spec.lockOff) }
            end
            if not self:headOk(site) then
                self:setState(site, 'owned', 'another tool replaced this instruction')
            else
                local operand = mem.read_u32(site.at)
                local slot = self.slots[site.slot]
                if self:inImage(operand) then
                    site.original = operand
                    if slot.original == nil then slot.original = mem.read_float(operand) end
                    self:setState(site, 'original', nil)
                elseif slot and operand == slot.addr then
                    self:setState(site, 'patched', nil)   -- already ours (a second install)
                else
                    site.original = operand
                    local held = self:peekFloat(operand)
                    if spec.want ~= nil and held == spec.want then
                        self:setState(site, 'neutral', 'another tool already holds this at the value XICamera uses')
                    else
                        self:setState(site, 'foreign', 'another tool points this operand elsewhere')
                    end
                end
            end
        end
    end
    local match = mem.find(Core.CAMERA_MANAGER_SIG)
    if match and match ~= 0 then self.cameraManager = mem.read_u32(match + Core.CAMERA_MANAGER_OFF) end
end

-- Decide which groups may install: every site original or neutral, and a known stock value.
function Core:planGroups()
    for _, name in ipairs(Core.SLOTS) do
        self.groups[name] = { enabled = true, why = nil }
    end
    for _, site in ipairs(self.sites) do
        local g = self.groups[site.slot]
        if Core.REQUIRED_GROUPS[site.slot] and site.state ~= 'original' and site.state ~= 'neutral' and site.state ~= 'patched' and g.enabled then
            g.enabled = false
            g.why = site.name .. ': ' .. (site.note or site.state)
        end
    end
    for _, name in ipairs(Core.SLOTS) do
        local g, slot = self.groups[name], self.slots[name]
        if g.enabled and Core.REQUIRED_GROUPS[name] and slot.original == nil then
            g.enabled = false
            g.why = 'no site holds the client\'s own value'
        end
        if not g.enabled then
            for _, site in ipairs(self.sites) do
                if site.slot == name and (site.state == 'original' or site.state == 'neutral') then
                    self:setState(site, 'skipped', 'group off: ' .. g.why)
                end
            end
            self:log('camera ' .. name .. ' patch group is off: ' .. g.why)
        end
    end
end

-- Write XICamera's slot address into one site, only over the bytes found at resolve.
function Core:patchSite(site)
    local mem = self.mem
    local slot = self.slots[site.slot]
    if not self:headOk(site) then
        self:setState(site, 'owned', 'another tool replaced this instruction')
        return false
    end
    local now = mem.read_u32(site.at)
    if now == slot.addr then self:setState(site, 'patched', nil) return true end
    if now ~= site.original then
        self:setState(site, 'foreign', 'operand changed since it was found')
        return false
    end
    if self:swap32(site.at, site.original, slot.addr) then
        self:setState(site, 'patched', nil)
        return true
    end
    if mem.read_u32(site.at) == site.original then
        self:setState(site, 'failed', 'the write did not take')
    else
        self:setState(site, 'foreign', 'another tool wrote the operand first')
    end
    return false
end

-- Put the client's operand back, only while the site still holds XICamera's slot.
function Core:restoreSite(site)
    local mem = self.mem
    local slot = self.slots[site.slot]
    if site.state ~= 'patched' then return true end
    if not self:headOk(site) then
        self:setState(site, 'refused', 'another tool replaced this instruction; left as it is')
        return false
    end
    local now = mem.read_u32(site.at)
    if now == site.original then self:setState(site, 'restored', nil) return true end
    if now ~= slot.addr then
        self:setState(site, 'refused', 'another tool owns the operand now; left as it is')
        return false
    end
    if self:swap32(site.at, slot.addr, site.original) then
        self:setState(site, 'restored', nil)
        return true
    end
    self:setState(site, 'refused', mem.read_u32(site.at) == slot.addr and 'the restore did not take' or 'another tool wrote the operand first; left as it is')
    return false
end

-- Returns true when every required group is in. Optional groups report through status().
function Core:install()
    if self.installed then return self:active() end
    if not self:allocSlots() then
        self:log('could not allocate the float block; nothing patched')
        return false
    end
    self:resolve()
    self:planGroups()
    for _, name in ipairs(Core.SLOTS) do
        local slot = self.slots[name]
        if slot.original ~= nil then self.mem.write_float(slot.addr, slot.original) end
    end
    for _, site in ipairs(self.sites) do
        if site.state == 'original' and self.groups[site.slot].enabled then self:patchSite(site) end
        if site.state == 'neutral' then self:logOnce(site, 'left as another tool set it') end
        if site.state == 'owned' or site.state == 'foreign' or site.state == 'missing' then self:logOnce(site, site.note) end
    end
    self.installed = true
    self:beginRecheckWindow()
    return self:active()
end

function Core:uninstall()
    if not self.installed then return true end
    local ok = true
    for _, site in ipairs(self.sites) do
        if site.state == 'neutral' or site.state == 'foreign' or site.state == 'owned' then
            self:log(site.name .. ': left as another tool set it')
        elseif not self:restoreSite(site) then
            ok = false
            self:log(site.name .. ': ' .. site.note)
        end
    end
    if not self:setBattleRangeLock(true) then ok = false end
    self.installed = false
    return ok
end

-- True while every required group is patched.
function Core:active()
    for name in pairs(Core.REQUIRED_GROUPS) do
        local g = self.groups[name]
        if not g or not g.enabled then return false end
    end
    return true
end

function Core:groupOn(name)
    local g = self.groups[name]
    return g ~= nil and g.enabled
end

-- ---------------------------------------------------------------------------
-- re-check: once a second, for RECHECK_WINDOW seconds after install and after each zone-in
-- ---------------------------------------------------------------------------

function Core:now()
    if self.mem.now then return self.mem.now() end
    return os.time()
end

-- Opens a window. install() does this, and the host does it with RECHECK_AFTER_TOOL_CHANGE
-- when it sees another addon or plugin load or unload. A shorter request never cuts a window
-- that is already open longer.
function Core:beginRecheckWindow(seconds)
    local until_ = self:now() + (seconds or Core.RECHECK_WINDOW)
    if until_ > self.recheckUntil then self.recheckUntil = until_ end
    self.lastRecheck = nil
end

-- The host calls this every time the character enters the world (zone-in packet / login).
-- Only the first time after install opens a window: later zones are not re-checked.
function Core:onEnterWorld()
    if self.enteredWorld then return false end
    self.enteredWorld = true
    self:beginRecheckWindow()
    return true
end

function Core:recheckActive()
    return self.installed and self:now() <= self.recheckUntil
end

-- Call every frame; it does nothing outside the window and at most one pass per second inside it.
function Core:recheck()
    if not self.installed then return end
    local now = self:now()
    if now > self.recheckUntil or now == self.lastRecheck then return end
    self.lastRecheck = now
    self:recheckNow()
end

-- One pass, unconditionally (Windower 5 runs this from its status command).
function Core:recheckNow()
    if not self.installed then return end
    local mem = self.mem
    for _, site in ipairs(self.sites) do
        local slot = self.slots[site.slot]
        if site.state == 'patched' then
            if not self:headOk(site) then
                self:setState(site, 'owned', 'another tool replaced this instruction after XICamera patched it')
                self:logOnce(site, site.note)
            else
                local now = mem.read_u32(site.at)
                if now ~= slot.addr then
                    if now == site.original then
                        if self:swap32(site.at, site.original, slot.addr) then
                            self:logOnce(site, 'another tool wrote the client\'s value back; patch re-applied')
                        end
                    else
                        local held = self:peekFloat(now)
                        if site.spec.want ~= nil and held == site.spec.want then
                            self:setState(site, 'neutral', 'another tool took this over at the value XICamera uses')
                        else
                            self:setState(site, 'foreign', 'another tool took this operand over')
                        end
                        self:logOnce(site, site.note)
                    end
                end
            end
        elseif site.state == 'neutral' or site.state == 'foreign' then
            -- the other tool wrote the client's own operand back: it unloaded, so take the site
            if self:headOk(site) then
                local now = mem.read_u32(site.at)
                if self:inImage(now) and (not Core.REQUIRED_GROUPS[site.slot] or self:groupOn(site.slot)) then
                    site.original = now
                    if slot.original == nil then slot.original = mem.read_float(now) end
                    if self:patchSite(site) then self:logOnce(site, 'the other tool handed it back; patched') end
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- values
-- ---------------------------------------------------------------------------

function Core:original(name)
    local s = self.slots[name]
    return s and s.original or nil
end

function Core:setSlot(name, value)
    local s = self.slots[name]
    if not s then return false end
    s.value = value
    self.mem.write_float(s.addr, value)
    return self:groupOn(name)
end

-- The user's distance is the max; the min slides with it so the wheel-zoom travel stays stock.
function Core:setCameraDistance(distance)
    local minO, maxO = self:original('min'), self:original('max')
    if minO and maxO then self:setSlot('min', distance - (maxO - minO)) end
    return self:setSlot('max', distance)
end

function Core:setBattleDistance(distance)
    local minO, maxO = self:original('minBattle'), self:original('maxBattle')
    if minO and maxO then self:setSlot('minBattle', distance - (maxO - minO)) end
    return self:setSlot('maxBattle', distance)
end

-- Speeds take the user's friendly number (3 = stock horizontal); the client's factor is /100.
function Core:setHorizontalPanSpeed(speed) return self:setSlot('hPan', speed / 100.0) end
function Core:setVerticalPanSpeed(speed)   return self:setSlot('vPan', speed / 100.0) end

function Core:setBattleRange(range)
    range = math.min(math.max(0, tonumber(range) or 0), 100)
    return self:setSlot('battleRange', range)
end

-- The clamp after the range read is `fld1` (D9 E8); two NOPs let the camera go all the way round.
function Core:setBattleRangeLock(locked)
    local lock = self.lock
    if not lock then return false end
    local mem = self.mem
    local now = mem.read_u16(lock.at)
    local want = locked and lock.original or Core.LOCK_NOPS
    if now == want then return true end
    local expect = locked and Core.LOCK_NOPS or lock.original
    if now ~= expect then
        self:log('battle range lock: the clamp holds bytes XICamera did not write; left as it is')
        return false
    end
    mem.write_u16(lock.at, want)
    return mem.read_u16(lock.at) == want
end

function Core:battleRangeLocked()
    if not self.lock then return nil end
    return self.mem.read_u16(self.lock.at) ~= Core.LOCK_NOPS
end

-- ---------------------------------------------------------------------------
-- camera task (height snap)
-- ---------------------------------------------------------------------------

function Core:cameraTask()
    if not self.cameraManager or self.cameraManager == 0 then return nil end
    local manager = self.mem.read_u32(self.cameraManager)
    if not manager or manager == 0 then return nil end
    local task = self.mem.read_u32(manager + 0x50)
    if not task or task == 0 then return nil end
    return task
end

function Core:cameraHeights()
    local task = self:cameraTask()
    if not task then return nil end
    return self.mem.read_float(task + 0x48), self.mem.read_float(task + 0x54)
end

function Core:snapHeight(offset)
    local task = self:cameraTask()
    if not task then return nil end
    local referenceY = self.mem.read_float(task + 0x54)
    local cameraY = referenceY + offset
    self.mem.write_float(task + 0x48, cameraY)
    return cameraY, referenceY
end

-- ---------------------------------------------------------------------------
-- status
-- ---------------------------------------------------------------------------

-- One row per site: { name, state, note }. States: patched, neutral, restored, missing, owned,
-- foreign, skipped, failed, refused, unresolved.
function Core:status()
    local rows = {}
    for i, site in ipairs(self.sites) do
        rows[i] = { name = site.name, state = site.state, note = site.note, group = site.slot }
    end
    return rows
end

function Core:groupStatus()
    local rows = {}
    for _, name in ipairs(Core.SLOTS) do
        local g = self.groups[name] or {}
        rows[#rows + 1] = { name = name, enabled = g.enabled == true, why = g.why, required = Core.REQUIRED_GROUPS[name] == true }
    end
    return rows
end

return Core
