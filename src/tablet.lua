-- Windows WinTab pressure reader. Uses driver packet polling instead of
-- hooking SDL's window procedure. All FFI calls are optional; mouse and
-- touch inputs continue to work if the driver or tablet is unavailable.
local Tablet={}
local Pressure={}
local curves={["Leve"]=0.65,["Linear"]=1.0,["Firme"]=1.6}
local function clamp(v) return math.max(0,math.min(1,v)) end

function Pressure.normalize(raw,minValue,maxValue)
    if type(raw)~="number" or type(minValue)~="number" or
        type(maxValue)~="number" or raw~=raw or
        maxValue<=minValue then return nil end
    return clamp((raw-minValue)/(maxValue-minValue))
end
function Pressure.curve(v,name)
    if type(v)~="number" or v~=v then return nil end
    return clamp(v)^(curves[name] or curves.Linear)
end
Tablet.normalize=Pressure.normalize
Tablet.applyCurve=Pressure.curve
Tablet.curves={"Leve","Linear","Firme"}

local driver
local context
local window
local lastPressure=nil
local lastSample=-100
local state="Mouse / toque"
local nextRetry=0
local ffiOK,ffi=pcall(require,"ffi")
local isWin=ffiOK and love and love.system and love.system.getOS()=="Windows"

if isWin then
    ffi.cdef[[
    typedef void *INKORA_HWND;
    typedef struct {
        char lcName[40];
        unsigned int lcOptions,lcStatus,lcLocks,lcMsgBase,lcDevice,
            lcPktRate,lcPktData,lcPktMode,lcMoveMask,lcBtnDnMask,lcBtnUpMask;
        int lcInOrgX,lcInOrgY,lcInOrgZ,lcInExtX,lcInExtY,lcInExtZ;
        int lcOutOrgX,lcOutOrgY,lcOutOrgZ,lcOutExtX,lcOutExtY,lcOutExtZ;
        unsigned int lcSensX,lcSensY,lcSensZ;
        int lcSysMode,lcSysOrgX,lcSysOrgY,lcSysExtX,lcSysExtY;
        unsigned int lcSysSensX,lcSysSensY;
    } INKORA_LOGCONTEXTA;
    typedef struct { int min,max; unsigned int units,resolution; } INKORA_AXIS;
    typedef struct { int x,y; unsigned int pressure; } INKORA_PACKET;
    void *GetForegroundWindow(void);
    unsigned long GetWindowThreadProcessId(void *hWnd, unsigned long *pid);
    unsigned long GetCurrentProcessId(void);
    unsigned int __stdcall WTInfoA(unsigned int category,unsigned int index,void *out);
    void *__stdcall WTOpenA(void *hwnd,void *context,int enable);
    int __stdcall WTClose(void *context);
    int __stdcall WTPacketsGet(void *context,int maximum,void *packets);
    int __stdcall WTOverlap(void *context,int top);
    ]]
end

local axisMin,axisMax=0,1023
local function activeWindow()
    local user=ffi.load("user32")
    local hwnd=user.GetForegroundWindow()
    if hwnd==nil or hwnd==ffi.NULL then return nil end
    local pid=ffi.new("unsigned long[1]",0)
    user.GetWindowThreadProcessId(hwnd,pid)
    local kernel=ffi.load("kernel32")
    if pid[0]~=kernel.GetCurrentProcessId() then return nil end
    return hwnd
end

local function initialize()
    if not isWin then return false end
    local ok,err=pcall(function()
        local hwnd=activeWindow()
        if not hwnd then return end
        local wintab=ffi.load("wintab32")
        -- Never pass a smaller LOGCONTEXT than the driver reports.
        local bytes=tonumber(wintab.WTInfoA(4,0,nil))
        if bytes~=ffi.sizeof("INKORA_LOGCONTEXTA") then return end
        local lc=ffi.new("INKORA_LOGCONTEXTA[1]")
        if wintab.WTInfoA(4,0,lc)~=bytes then return end
        local dev=tonumber(lc[0].lcDevice)
        if dev==4294967295 then return end
        local axis=ffi.new("INKORA_AXIS[1]")
        if wintab.WTInfoA(100+dev,15,axis)<ffi.sizeof("INKORA_AXIS")
            or axis[0].max<=axis[0].min then return end
        -- PACKETDATA: X, Y, normal pressure. Wintab defines this layout
        -- without padding: two signed LONG followed by one UINT.
        lc[0].lcPktData=0x80+0x100+0x400
        lc[0].lcPktMode=0
        lc[0].lcMoveMask=lc[0].lcPktData
        -- Polling, no WT_PACKET window procedure or callback required.
        local ctx=wintab.WTOpenA(hwnd,lc,1)
        if ctx==nil or ctx==ffi.NULL then return end
        driver=wintab
        context=ctx
        window=hwnd
        axisMin,axisMax=tonumber(axis[0].min),tonumber(axis[0].max)
        state="WinTab - aguardando caneta"
        if pcall(function() driver.WTOverlap(context,1) end) then end
    end)
    if not ok then
        state="Mouse / toque (WinTab indisponivel)"
        return false
    end
    return context~=nil
end

function Tablet.poll(now)
    now=now or (love and love.timer and love.timer.getTime() or 0)
    if not isWin then return nil end
    if not context and now>=nextRetry then
        nextRetry=now+4
        initialize()
    end
    if not context then return nil end
    local ok,n=pcall(function()
        local packet=ffi.new("INKORA_PACKET[32]")
        local received=tonumber(driver.WTPacketsGet(context,32,packet))
        if received<0 or received>32 then error("Invalid WinTab packet count") end
        if received>0 then
            local newest=packet[received-1]
            lastPressure=Pressure.normalize(tonumber(newest.pressure),axisMin,axisMax)
            lastSample=now
            state="WinTab - caneta detectada"
        end
        return received
    end)
    if not ok then
        Tablet.shutdown()
        nextRetry=now+5
        state="Mouse / toque (falha WinTab)"
        return nil
    end
    return n
end

function Tablet.pressure(now)
    now=now or (love and love.timer and love.timer.getTime() or 0)
    -- Never treat an old hover packet as active pressure.
    if lastSample<0 or now-lastSample>0.10 or
       not lastPressure or lastPressure<=0 then return nil end
    return lastPressure
end

function Tablet.status() return state end
function Tablet.active() return context~=nil end
function Tablet.lastPressure() return lastPressure end
function Tablet.shutdown()
    if context and driver then pcall(function() driver.WTClose(context) end) end
    context=nil
    driver=nil
    lastPressure=nil
    lastSample=-100
end

-- Optional internal mock for CI. No hardware is required to test normalized
-- pressure, staleness protection and fallback behavior.
function Tablet._injectForTest(pressure,at)
    lastPressure=pressure
    lastSample=at
end
return Tablet
