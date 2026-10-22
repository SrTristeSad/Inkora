-- Balde de tinta: flood-fill por spans horizontais, sem recursao.
-- Opera sobre ImageData da camada selecionada (nao a imagem composta).
local Fill = {}

local function same(r, g, b, a, tr, tg, tb, ta, tol)
    return math.abs(r-tr) <= tol and math.abs(g-tg) <= tol
       and math.abs(b-tb) <= tol and math.abs(a-ta) <= tol
end

-- Retorna true apenas quando ao menos um pixel foi modificado.
-- x/y inteiros em coordenadas da imagem; tol em [0, 1].
function Fill.apply(data, x, y, rgb, tol)
    local w, h = data:getDimensions()
    x, y = math.floor(x), math.floor(y)
    if x < 0 or y < 0 or x >= w or y >= h then return false end
    tol = math.max(0, math.min(1, tol or 0))
    local tr,tg,tb,ta = data:getPixel(x, y)
    local fr,fg,fb,fa = rgb[1],rgb[2],rgb[3],1

    -- Evita um loop infinito se a nova cor corresponde ao alvo.
    if same(fr,fg,fb,fa,tr,tg,tb,ta,tol) then return false end

    local function matches(px,py)
        if px < 0 or py < 0 or px >= w or py >= h then return false end
        local r,g,b,a = data:getPixel(px,py)
        return same(r,g,b,a,tr,tg,tb,ta,tol)
    end

    local stack = {y * w + x}
    local changed = false

    while #stack > 0 do
        local offset = stack[#stack]
        stack[#stack] = nil
        local sy = math.floor(offset / w)
        local sx = offset % w

        if matches(sx, sy) then
            local left, right = sx, sx
            while left > 0 and matches(left-1,sy) do left = left-1 end
            while right+1 < w and matches(right+1,sy) do right = right+1 end

            for px = left, right do
                data:setPixel(px,sy,fr,fg,fb,fa)
            end
            changed = true

            for _, ny in ipairs({sy-1, sy+1}) do
                if ny >= 0 and ny < h then
                    local px = left
                    while px <= right do
                        if matches(px,ny) then
                            stack[#stack+1] = ny*w+px
                            repeat px = px+1 until px > right or not matches(px,ny)
                        else
                            px = px+1
                        end
                    end
                end
            end
        end
    end
    return changed
end

return Fill
