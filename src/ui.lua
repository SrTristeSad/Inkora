local palette = require("src.palette")
local Document = require("src.document")
local UI = {}
UI.__index = UI

local C = {
    top={0.080,0.106,0.155}, side={0.100,0.133,0.190},
    panel={0.090,0.118,0.172}, surface={0.145,0.187,0.256},
    surface2={0.175,0.219,0.299}, accent={0.260,0.800,0.789},
    white={0.937,0.963,0.980}, muted={0.625,0.692,0.756},
    divider={0.223,0.280,0.350}, red={0.910,0.370,0.397},
}

local function color(c,alpha)
    love.graphics.setColor(c[1],c[2],c[3],alpha or 1)
end

local function inside(x,y,b)
    return x>=b.x and x<=b.x+b.w and y>=b.y and y<=b.y+b.h
end

local function clamp(v,a,b) return math.max(a,math.min(b,v)) end

function UI.new()
    return setmetatable({
        hits={}, modal=nil, draggingSlider=nil, tab="brush",
        font=love.graphics.newFont(14),
        small=love.graphics.newFont(12),
        large=love.graphics.newFont(21),
    }, UI)
end

function UI:rect(x,y,w,h,c,r)
    color(c)
    love.graphics.rectangle("fill",x,y,w,h,r or 0,r or 0)
end

function UI:print(value,x,y,c,font,width,align)
    love.graphics.setFont(font or self.font)
    color(c or C.white)
    if width then
        love.graphics.printf(tostring(value),x,y,width,align or "left")
    else love.graphics.print(tostring(value),x,y) end
end

function UI:register(x,y,w,h,action,kind,onStart)
    self.hits[#self.hits+1]={x=x,y=y,w=w,h=h,action=action,kind=kind,onStart=onStart}
end

function UI:button(x,y,w,h,label,action,style)
    local mx,my=love.mouse.getPosition()
    local hover=inside(mx,my,{x=x,y=y,w=w,h=h})
    local bg=style=="primary" and C.accent or style=="danger" and C.red or
        style=="ghost" and C.side or C.surface
    self:rect(x,y,w,h,hover and C.surface2 or bg,7)
    self:print(label,x+2,y+(h-self.font:getHeight())/2,
        style=="primary" and C.top or C.white,self.font,w-4,"center")
    if action then self:register(x,y,w,h,action) end
end

function UI:slider(x,y,w,value,label,action,suffix,onStart)
    self:print(label,x,y-19,C.muted,self.small)
    self:print(suffix or "",x,y-19,C.white,self.small,w,"right")
    self:rect(x,y+5,w,5,C.surface2,3)
    self:rect(x,y+5,w*clamp(value,0,1),5,C.accent,3)
    color(C.white)
    love.graphics.circle("fill",x+w*clamp(value,0,1),y+7.5,7)
    self:register(x-8,y-6,w+16,29,function(px)
        action(clamp((px-x)/w,0,1))
    end,"slider",onStart)
end

function UI:click(x,y)
    for i=#self.hits,1,-1 do
        local hit=self.hits[i]
        if inside(x,y,hit) then
            if hit.kind=="slider" then
                self.draggingSlider=hit
                if hit.onStart then hit.onStart() end
            end
            if hit.action then hit.action(x,y) end
            return true
        end
    end
    return self.modal~=nil
end

function UI:mousemoved(x,y)
    if self.draggingSlider then
        self.draggingSlider.action(x,y)
        return true
    end
    return false
end

function UI:mousereleased()
    self.draggingSlider=nil
end

function UI:confirm(message,action)
    self.modal={kind="confirm",message=message,action=action}
end

function UI:askSave(app)
    self.modal={kind="save",value=app.doc.name}
end

function UI:askOpen(app)
    local open=function()
        self.modal={kind="open",projects=Document.listProjects()}
    end
    if app.doc.dirty then
        self:confirm("Alteracoes nao salvas serao perdidas.",open)
    else open() end
end

function UI:askNew(app)
    local show=function()
        self.modal={kind="new",width="1280",height="800",field="width"}
    end
    if app.doc.dirty then
        self:confirm("Alteracoes nao salvas serao perdidas.",show)
    else show() end
end

function UI:keypressed(app,key)
    if not self.modal then return false end
    local m=self.modal
    if key=="escape" then self.modal=nil; return true end
    if m.kind=="save" then
        if key=="return" or key=="kpenter" then
            self.modal=nil; app:saveProject(m.value)
        elseif key=="backspace" then
            local utf8=require("utf8")
            local at=utf8.offset(m.value,-1)
            if at then m.value=m.value:sub(1,at-1) end
        end
    elseif m.kind=="new" then
        if key=="tab" then m.field=m.field=="width" and "height" or "width"
        elseif key=="backspace" then m[m.field]=m[m.field]:sub(1,-2)
        elseif key=="return" or key=="kpenter" then
            local w,h=tonumber(m.width),tonumber(m.height)
            if w and h and w%1==0 and h%1==0 and w>=64 and h>=64 and w<=4096 and h<=4096 then
                self.modal=nil
                app:newDocument(w,h)
            else
                m.error="Use valores inteiros entre 64 e 4096."
            end
        end
    elseif m.kind=="confirm" and (key=="return" or key=="kpenter") then
        self.modal=nil; m.action()
    end
    return true
end

function UI:textinput(value)
    if not self.modal then return end
    local m=self.modal
    if m.kind=="save" then
        m.value=(m.value..value:gsub("[\r\n\t]","")):sub(1,64)
    elseif m.kind=="new" then
        m[m.field]=(m[m.field]..value:gsub("%D","")):sub(1,4)
    end
end

function UI:drawModal(app)
    if not self.modal then return end
    local m=self.modal
    local w,h=love.graphics.getDimensions()
    color(C.top,0.84)
    love.graphics.rectangle("fill",0,0,w,h)
    self.hits={}
    local bw,bh=460,m.kind=="open" and 400 or 246
    local x,y=(w-bw)/2,(h-bh)/2
    self:rect(x,y,bw,bh,C.side,14)
    self:print("Inkora",x+25,y+19,C.accent,self.large)
    if m.kind=="confirm" then
        self:print("Descartar alteracoes?",x+24,y+72,C.white)
        self:print(m.message,x+24,y+102,C.muted,self.small)
        self:button(x+24,y+bh-63,194,38,"Cancelar",function() self.modal=nil end)
        self:button(x+240,y+bh-63,194,38,"Descartar",function()
            self.modal=nil; m.action()
        end,"danger")
    elseif m.kind=="save" then
        self:print("Nome do projeto",x+25,y+70,C.muted)
        self:rect(x+24,y+104,412,38,C.panel,7)
        self:print(m.value.."_",x+35,y+114,C.white)
        self:button(x+24,y+bh-63,194,38,"Cancelar",function() self.modal=nil end)
        self:button(x+240,y+bh-63,194,38,"Salvar",function()
            self.modal=nil; app:saveProject(m.value)
        end,"primary")
    elseif m.kind=="new" then
        self:print("Novo documento (64 a 4096 px)",x+24,y+62,C.white)
        self:print("Largura",x+24,y+98,C.muted,self.small)
        self:print("Altura",x+239,y+98,C.muted,self.small)
        for i,entry in ipairs({{"width",x+24},{"height",x+239}}) do
            local field,xx=entry[1],entry[2]
            self:rect(xx,y+118,192,34,m.field==field and C.surface2 or C.panel,6)
            self:print(m[field]..(m.field==field and "_" or ""),xx+13,y+128,C.white)
            self:register(xx,y+118,192,34,function() m.field=field end)
        end
        if m.error then self:print(m.error,x+24,y+161,C.red,self.small) end
        self:button(x+24,y+bh-58,194,36,"Cancelar",function() self.modal=nil end)
        self:button(x+240,y+bh-58,194,36,"Criar",function()
            local ww,hh=tonumber(m.width),tonumber(m.height)
            if ww and hh and ww%1==0 and hh%1==0 and ww>=64 and hh>=64 and ww<=4096 and hh<=4096 then
                self.modal=nil; app:newDocument(ww,hh)
            else m.error="Use valores inteiros entre 64 e 4096." end
        end,"primary")
    elseif m.kind=="open" then
        self:print("Projetos salvos",x+24,y+61,C.white)
        if #m.projects==0 then
            self:print("Nenhum projeto encontrado.",x+24,y+110,C.muted)
        end
        for i=1,math.min(6,#m.projects) do
            local project=m.projects[i]
            self:button(x+24,y+93+(i-1)*40,412,34,project.name,function()
                self.modal=nil; app:openProject(project.key)
            end,"ghost")
        end
        self:button(x+282,y+bh-49,154,32,"Fechar",function()
            self.modal=nil
        end)
    end
end

function UI:drawToolbar(app,w,h,right)
    self:rect(0,0,w,58,C.top)
    self:rect(0,58,74,h-92,C.side)
    self:rect(right,58,280,h-92,C.panel)
    self:rect(0,h-34,w,34,C.top)
    self:rect(74,58,1,h-92,C.divider)
    self:rect(right,58,1,h-92,C.divider)
    self:print("INKORA",18,16,C.accent,self.large)
    self:button(173,10,75,37,"Novo",function() self:askNew(app) end)
    self:button(258,10,78,37,"Salvar",function()
        if app.doc.projectKey then app:saveProject(app.doc.name)
        else self:askSave(app) end
    end)
    self:button(346,10,75,37,"Abrir",function() self:askOpen(app) end)
    self:button(431,10,91,37,"PNG",function() app:exportPNG() end)
    self:button(540,10,69,37,"Voltar",function() app.doc:undo() end)
    self:button(618,10,77,37,"Refazer",function() app.doc:redo() end)
    self:button(707,10,95,37,"Ajustar",function() app:fitView() end)

    self:print("FERRAMENTAS",5,77,C.muted,self.small,65,"center")
    local tools={
        {"Pincel","brush","B"}, {"Apagar","eraser","E"},
        {"Mover","hand","H"}, {"Balde","fill","G"},
        {"Amostra","picker","I"}, {"Linha","line","L"},
        {"Retangulo","rectangle","R"}, {"Elipse","ellipse","O"},
    }
    for i,t in ipairs(tools) do
        local yy=103+(i-1)*56
        self:button(8,yy,58,30,t[3],function()
            app.tool=t[2]
        end,app.tool==t[2] and "primary" or nil)
        self:print(t[1],4,yy+33,C.muted,self.small,66,"center")
    end
end

function UI:drawBrushPanel(app,x,w,h)
    self:print("PINCEL / FERRAMENTA",x,139,C.white)
    local brushName=({
        brush="Pincel redondo",eraser="Borracha solida",hand="Navegacao",
        fill="Balde (camada atual)",picker="Conta-gotas (visivel)",
        line="Linha reta",rectangle="Retangulo",ellipse="Elipse",
    })[app.tool] or app.tool
    self:print(brushName,x,163,C.muted,self.small)
    self:slider(x+6,208,w-12,(app.brushSize-1)/119,"Espessura",function(v)
        app.brushSize=math.max(1,math.floor(1+v*119+0.5))
    end,tostring(app.brushSize).." px")
    self:slider(x+6,268,w-12,app.brushOpacity,"Opacidade",function(v)
        app.brushOpacity=math.max(0.05,v)
    end,tostring(math.floor(app.brushOpacity*100+0.5)).."%")
    self:slider(x+6,328,w-12,app.stabilization,"Estabilizacao",function(v)
        app.stabilization=v
    end,tostring(math.floor(app.stabilization*100+0.5)).."%")
    self:slider(x+6,385,w-12,app.brushHardness,"Dureza da ponta",function(v)
        app.brushHardness=v
    end,tostring(math.floor(app.brushHardness*100+0.5)).."%")
    self:slider(x+6,442,w-12,(app.brushSpacing-0.03)/0.47,"Espacamento",function(v)
        app.brushSpacing=0.03+v*0.47
    end,tostring(math.floor(app.brushSpacing*100+0.5)).."%")
    self:print("CORES",x,481,C.white)
    self:rect(x+188,478,50,20,app.color,5)
    for i,swatch in ipairs(palette) do
        local col,row=(i-1)%6,math.floor((i-1)/6)
        local bx,by=x+col*40,506+row*39
        if app.colorIndex==i then
            color(C.accent)
            love.graphics.rectangle("line",bx-3,by-3,34,34,6,6)
        end
        self:rect(bx,by,28,28,swatch,5)
        self:register(bx-3,by-3,34,34,function()
            app.colorIndex=i;app.color=swatch
            if app.tool=="eraser" then app.tool="brush" end
        end)
    end
    self:slider(x+6,660,w-12,app.fillTolerance/0.3,"Tolerancia do balde",function(v)
        app.fillTolerance=v*0.3
    end,tostring(math.floor(app.fillTolerance*100+0.5)).."%")
    self:print("PONTA C++",x,679,C.white,self.small)
    local tips={{"Redonda",0},{"Chata",1},{"Granulada",2}}
    for i,t in ipairs(tips) do
        local bx=x+(i-1)*81
        self:button(bx,697,77,28,t[1],function()
            app.brushTip=t[2]
            app:statusMessage("Ponta nativa: "..t[1])
        end,app.brushTip==t[2] and "primary" or nil)
    end
end

function UI:drawLayersPanel(app,x,w,h)
    local doc=app.doc
    self:print("CAMADAS",x,143,C.white)
    self:print(tostring(#doc.layers).." / 16 camadas",x,170,C.muted,self.small)
    self:button(x,204,51,32,"+",function()
        if not doc:addLayer() then app:statusMessage("Limite de 16 camadas") end
    end)
    self:button(x+61,204,51,32,"-",function()
        if not doc:removeLayer() then app:statusMessage("Nao e possivel excluir a ultima camada") end
    end)
    self:button(x+122,204,51,32,"Cima",function() doc:moveLayer(1) end)
    self:button(x+183,204,57,32,"Baixo",function() doc:moveLayer(-1) end)
    self:print("Toque em uma camada para editar",x,251,C.muted,self.small)
    local rows=math.max(1,math.floor((h-416)/46))
    local top=math.min(#doc.layers,math.max(rows,doc.selected+rows-1))
    for r=1,math.min(rows,#doc.layers) do
        local index=top-r+1
        if index>=1 then
            local layer=doc.layers[index]
            local yy=278+(r-1)*46
            self:rect(x,yy,w,41,index==doc.selected and C.surface2 or C.surface,6)
            self:button(x+5,yy+5,47,31,layer.visible and "Ver" or "Off",function()
                doc:toggleLayer(index)
            end,"ghost")
            self:print(layer.name,x+61,yy+7,index==doc.selected and C.accent or C.white,self.small)
            self:print(tostring(math.floor(layer.opacity*100+0.5)).."%",x+61,yy+23,C.muted,self.small)
            self:register(x+57,yy,w-57,41,function()
                doc.selected=index
            end)
        end
    end
    local layer=doc.layers[doc.selected]
    if layer then
        self:slider(x+6,h-90,w-12,layer.opacity,"Opacidade da camada",function(v)
            doc:setLayerOpacity(doc.selected,v,true)
        end,tostring(math.floor(layer.opacity*100+0.5)).."%",function()
            doc:checkpoint()
        end)
    end
end

function UI:draw(app)
    self.hits={}
    love.graphics.push("all")
    local w,h=love.graphics.getDimensions()
    local right=w-280
    self:drawToolbar(app,w,h,right)
    local x=right+20
    self:button(x,75,113,40,"Pincel",function() self.tab="brush" end,
        self.tab=="brush" and "primary" or nil)
    self:button(x+124,75,116,40,"Camadas",function() self.tab="layers" end,
        self.tab=="layers" and "primary" or nil)
    if self.tab=="brush" then self:drawBrushPanel(app,x,240,h)
    else self:drawLayersPanel(app,x,240,h) end
    self:print(app.message or "Pronto",14,h-26,C.white,self.small,math.max(100,w-620))
    self:print(("%dx%d  |  %d camadas  |  zoom %d%%"):format(
        app.doc.width,app.doc.height,#app.doc.layers,math.floor(app.zoom*100+0.5)),
        w-600,h-26,C.muted,self.small,585,"right")
    if self.modal then self:drawModal(app) end
    love.graphics.pop()
end

return UI
