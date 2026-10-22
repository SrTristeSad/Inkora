-- Flood fill by horizontal spans, no recursion; applied to the active layer.
-- Rectangle selection and alpha lock share the same semantics as C++ brush.
local Fill={}

local function near(r,g,b,a,tr,tg,tb,ta,tol)
    return math.abs(r-tr)<=tol and math.abs(g-tg)<=tol
       and math.abs(b-tb)<=tol and math.abs(a-ta)<=tol
end

-- opts.selection: document rectangle {x0,y0,x1,y1}, right/bottom exclusive.
-- opts.alphaLock: preserve per-pixel alpha; ignore fully transparent pixels.
function Fill.apply(data,x,y,rgb,tol,opts)
    local w,h=data:getDimensions()
    x,y=math.floor(x),math.floor(y)
    opts=opts or {}
    local area=opts.selection
    local locked=opts.alphaLock==true
    local function allowed(px,py)
        if px<0 or py<0 or px>=w or py>=h then return false end
        if area and (px<area.x0 or px>=area.x1 or
                     py<area.y0 or py>=area.y1) then return false end
        return true
    end
    if not allowed(x,y) then return false end
    tol=math.max(0,math.min(1,tol or 0))
    local tr,tg,tb,ta=data:getPixel(x,y)
    if locked and ta==0 then return false end
    local fr,fg,fb=rgb[1],rgb[2],rgb[3]
    local fa=locked and ta or 1
    if near(fr,fg,fb,fa,tr,tg,tb,ta,tol) then return false end

    local function matches(px,py)
        if not allowed(px,py) then return false end
        local r,g,b,a=data:getPixel(px,py)
        return (not locked or a>0) and near(r,g,b,a,tr,tg,tb,ta,tol)
    end

    local stack={y*w+x}
    local changed=false
    while #stack>0 do
        local offset=stack[#stack]
        stack[#stack]=nil
        local sy=math.floor(offset/w)
        local sx=offset%w
        if matches(sx,sy) then
            local left,right=sx,sx
            while left>0 and matches(left-1,sy) do left=left-1 end
            while right<w-1 and matches(right+1,sy) do right=right+1 end
            for px=left,right do
                if locked then
                    local _,_,_,a=data:getPixel(px,sy)
                    data:setPixel(px,sy,fr,fg,fb,a)
                else
                    data:setPixel(px,sy,fr,fg,fb,1)
                end
            end
            changed=true
            for _,ny in ipairs({sy-1,sy+1}) do
                if ny>=0 and ny<h then
                    local px=left
                    while px<=right do
                        if matches(px,ny) then
                            stack[#stack+1]=ny*w+px
                            repeat px=px+1 until px>right or not matches(px,ny)
                        else px=px+1 end
                    end
                end
            end
        end
    end
    return changed
end
return Fill
