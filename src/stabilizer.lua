-- Stabilizador de traços independente do motor gráfico.
-- 0 = acompanha o cursor; 1 = alta suavização.
local Stabilizer = {}
Stabilizer.__index = Stabilizer

function Stabilizer.new(x, y, strength)
    assert(type(x) == "number" and type(y) == "number")
    return setmetatable({
        x = x, y = y,
        strength = math.max(0, math.min(1, strength or 0)),
    }, Stabilizer)
end

function Stabilizer:push(x, y)
    local factor = 1 / (1 + self.strength * 14)
    self.x = self.x + (x - self.x) * factor
    self.y = self.y + (y - self.y) * factor
    return self.x, self.y
end

function Stabilizer:finish(x, y)
    self.x, self.y = x, y
    return x, y
end

return Stabilizer
