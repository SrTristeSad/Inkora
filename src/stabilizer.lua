-- Inkora adaptive stroke stabilizer (One-Euro style filtering).
-- Smoothing depends on elapsed time rather than on how many pointer events
-- happen to be delivered by the operating system.
-- Faster intentional movement raises the cutoff to reduce lag.
local Stabilizer={}
Stabilizer.__index=Stabilizer
local pi=math.pi

local function finite(v)
    return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge
end
local function clamp(v,a,b)
    return math.max(a,math.min(b,v))
end
local function alpha(cutoff,dt)
    -- Exact first-order response under a constant signal, stable with dt.
    return 1-math.exp(-2*pi*cutoff*dt)
end

function Stabilizer.new(x,y,strength)
    assert(finite(x) and finite(y),"Invalid starting point")
    local s=clamp(strength or 0,0,1)
    return setmetatable({
        x=x,y=y,rawX=x,rawY=y,
        vx=0,vy=0,prevX=x,prevY=y,
        strength=s,
        -- High strength damps low velocity jitter, but follows fast strokes.
        minCutoff=14*math.pow(0.10,s),
        beta=0.045*(1-s)+0.020,
        derivativeCutoff=2.5,
        samples=0,
    },Stabilizer)
end

function Stabilizer:push(x,y,dt)
    assert(finite(x) and finite(y),"Invalid pointer position")
    dt=finite(dt) and clamp(dt,1/240,1/15) or 1/60
    if self.strength==0 then
        self.prevX,self.prevY=self.x,self.y
        self.x,self.y=x,y
        self.rawX,self.rawY=x,y
        self.samples=self.samples+1
        return x,y
    end
    local dx=(x-self.rawX)/dt
    local dy=(y-self.rawY)/dt
    local dv=alpha(self.derivativeCutoff,dt)
    self.vx=self.vx+(dx-self.vx)*dv
    self.vy=self.vy+(dy-self.vy)*dv
    local speed=math.sqrt(self.vx*self.vx+self.vy*self.vy)
    local cutoff=self.minCutoff+self.beta*speed
    local amount=alpha(cutoff,dt)
    self.prevX,self.prevY=self.x,self.y
    self.x=self.x+(x-self.x)*amount
    self.y=self.y+(y-self.y)*amount
    self.rawX,self.rawY=x,y
    self.samples=self.samples+1
    return self.x,self.y
end

-- Complete the residual line with intermediate samples rather than
-- teleporting a single huge segment on release. The C++ spacing phase is
-- shared across these segments, so no holes appear between dabs.
function Stabilizer:finishPath(x,y,diameter)
    assert(finite(x) and finite(y),"Invalid ending point")
    local dx,dy=x-self.x,y-self.y
    local distance=math.sqrt(dx*dx+dy*dy)
    if distance<0.001 then
        self:finish(x,y)
        return {}
    end
    local step=math.max(1,math.min(7,(diameter or 12)*0.35))
    local count=math.max(1,math.min(64,math.ceil(distance/step)))
    local points={}
    local ox,oy=self.x,self.y
    for i=1,count do
        local t=i/count
        points[#points+1]={ox+dx*t,oy+dy*t}
    end
    self:finish(x,y)
    return points
end

function Stabilizer:finish(x,y)
    assert(finite(x) and finite(y),"Invalid end point")
    self.prevX,self.prevY=self.x,self.y
    self.x,self.y=x,y
    self.rawX,self.rawY=x,y
    return x,y
end

return Stabilizer
