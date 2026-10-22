local palette = require("src.palette")
local Document = require("src.document")
local Presets = require("src.presets")
local BrushPreview = require("src.brush_preview")
local UI = {}
UI.__index = UI

local C = {
    top={0.067,0.076,0.105}, side={0.089,0.100,0.137},
    panel={0.100,0.109,0.149}, surface={0.151,0.166,0.215},
    surface2={0.204,0.222,0.279}, accent={0.44,0.82,0.91},
    white={0.954,0.960,0.974}, muted={0.63,0.68,0.75},
    divider={0.226,0.247,0.31}, red={0.95,0.45,0.50},
    peach={0.99,0.74,0.56}, green={0.64,0.86,0.68},
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
        layerScroll=0, favoriteOnly=false, inspectorWidth=316,
        brushCategory=1, draggingPanel=false,
        hue=0.55, saturation=0.75, brightness=0.9,
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
            elseif hit.kind=="panel-resize" then
                self.draggingPanel=true
            end
            if hit.action then hit.action(x,y) end
            return true
        end
    end
    return self.modal~=nil
end

function UI:mousemoved(x,y)
    if self.draggingPanel then
        local w=love.graphics.getWidth()
        local maximum=math.max(316,math.min(490,w-620))
        local oldWidth=self.inspectorWidth
        local width=clamp(w-x,316,maximum)
        self.inspectorWidth=width
        if self.currentApp and oldWidth~=width then
            -- Keep the document anchored to the centre of the workspace.
            self.currentApp.offsetX=self.currentApp.offsetX+(oldWidth-width)/2
        end
        return true
    end
    if self.draggingSlider then
        self.draggingSlider.action(x,y)
        return true
    end
    return false
end

function UI:mousereleased()
    self.draggingSlider=nil
    self.draggingPanel=false
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


-- App-specific workspace sizing is shared with main.lua.
function UI:workspaceBounds()
    local w,h=love.graphics.getDimensions()
    return 88,73,w-self.inspectorWidth-16,h-44
end

local TOOLS={
    {"Pincel","brush","B"},{"Borracha","eraser","E"},
    {"Mover tela","hand","H"},{"Balde","fill","G"},
    {"Conta-gotas","picker","I"},{"Linha","line","L"},
    {"Retangulo","rectangle","R"},{"Elipse","ellipse","O"},
    {"Selecao","select","M"}
}

local function hsvRgb(h,s,v)
    local i=math.floor(h*6)
    local f=h*6-i
    local p=v*(1-s)
    local q=v*(1-f*s)
    local t=v*(1-(1-f)*s)
    i=i%6
    if i==0 then return {v,t,p}
    elseif i==1 then return {q,v,p}
    elseif i==2 then return {p,v,t}
    elseif i==3 then return {p,q,v}
    elseif i==4 then return {t,p,v}
    else return {v,p,q} end
end

local function rgbHsv(rgb)
    local r,g,b=rgb[1],rgb[2],rgb[3]
    local hi=math.max(r,g,b)
    local lo=math.min(r,g,b)
    local delta=hi-lo
    local h=0
    if delta>0 then
        if hi==r then h=((g-b)/delta)%6
        elseif hi==g then h=(b-r)/delta+2
        else h=(r-g)/delta+4 end
        h=h/6
    end
    return h,hi==0 and 0 or delta/hi,hi
end

local function applyColor(app,rgb)
    app.color=rgb
    app.colorIndex=nil
    if app.tool=="eraser" then app.tool="brush" end
end

function UI:toolIcon(kind,x,y)
    color(C.white)
    love.graphics.setLineWidth(2.4)
    if kind=="brush" then
        love.graphics.line(x-8,y+7,x+5,y-8,x+9,y-4,x-4,y+10,x-9,y+11,x-8,y+7)
    elseif kind=="eraser" then
        love.graphics.polygon("line",x-10,y+3,x+1,y-9,x+10,y,x-1,y+11)
    elseif kind=="hand" then
        love.graphics.rectangle("line",x-7,y-1,14,13,3)
        for dx=-5,5,5 do love.graphics.line(x+dx,y-1,x+dx,y-10) end
    elseif kind=="fill" then
        love.graphics.polygon("line",x-10,y-4,x,y-13,x+10,y-3,x,y+8)
        love.graphics.circle("fill",x+9,y+11,3)
    elseif kind=="picker" then
        love.graphics.line(x-9,y+9,x+9,y-9)
        love.graphics.circle("line",x+7,y-8,4)
    elseif kind=="line" then love.graphics.line(x-10,y+9,x+10,y-9)
    elseif kind=="rectangle" then love.graphics.rectangle("line",x-10,y-8,20,16,2)
    elseif kind=="ellipse" then love.graphics.ellipse("line",x,y,11,8)
    elseif kind=="select" then
        love.graphics.setLineStyle("rough")
        love.graphics.rectangle("line",x-10,y-9,20,18)
        love.graphics.setLineStyle("smooth")
    end
    love.graphics.setLineWidth(1)
end

function UI:drawToolbar(app,w,h,right)
    self:rect(0,0,w,64,C.top)
    self:rect(0,64,80,h-100,C.side)
    self:rect(right,64,w-right,h-100,C.panel)
    self:rect(0,h-36,w,36,C.top)
    self:rect(79,64,1,h-100,C.divider)
    self:rect(right,64,1,h-100,C.divider)

    self:rect(15,13,36,36,C.accent,11)
    love.graphics.setColor(0.08,0.13,0.18,1)
    love.graphics.setLineWidth(3)
    love.graphics.line(25,38,39,25)
    love.graphics.line(30,42,44,30)
    love.graphics.setLineWidth(1)
    self:print("inkora",60,16,C.white,self.large)
    if right>=870 then
        self:print(app.doc.name or "Sem titulo",212,17,C.muted,self.font,right-725)
    end

    local actions={
        {"Novo",function() self:askNew(app) end},
        {"Abrir",function() self:askOpen(app) end},
        {"Salvar",function() if app.doc.projectKey then
            app:saveProject(app.doc.name) else self:askSave(app) end end},
        {"PNG",function() app:exportPNG() end},
        {"Desf.",function() app.doc:undo() end},
        {"Ref.",function() app.doc:redo() end}
    }
    local start=right-466
    for i,a in ipairs(actions) do
        self:button(start+(i-1)*77,13,71,37,a[1],a[2],i==3 and "primary" or "ghost")
    end

    for i,t in ipairs(TOOLS) do
        local top=86+(i-1)*math.min(64,(h-173)/#TOOLS)
        if top+51<h-52 then
            local selected=app.tool==t[2]
            if selected then self:rect(6,top,68,53,C.surface2,12)
                self:rect(6,top+8,3,35,C.accent,2)
            end
            self:toolIcon(t[2],40,top+18)
            self:print(t[3],8,top+36,selected and C.accent or C.muted,
                self.small,64,"center")
            self:register(6,top,68,53,function()
                app.tool=t[2]
                if t[2]=="brush" or t[2]=="eraser" then
                    self.tab="brush"
                end
            end)
        end
    end
end

function UI:drawStrokePreview(kind,x,y,width)
    -- Procedural visual preview: rendered by the UI, never copied assets.
    local innerX=x+9
    local innerY=y+11
    local steps=19
    if kind=="pixel" then
        color(C.accent)
        for i=0,steps do
            local a=i/steps
            love.graphics.rectangle("fill",innerX+a*width,
                innerY+9+math.sin(a*5)*4,3,3)
        end
    elseif kind=="soft" then
        for radius=10,2,-2 do
            love.graphics.setColor(0.43,0.83,0.92,0.12)
            for i=0,steps do
                local a=i/steps
                love.graphics.circle("fill",innerX+a*width,
                    innerY+11+math.sin(a*4.3)*5,radius)
            end
        end
    elseif kind=="grain" or kind=="pencil" then
        for i=0,steps*3 do
            local a=i/(steps*3)
            local jitter=math.sin(i*9.71)*3
            love.graphics.setColor(0.66,0.86,0.94,
                kind=="grain" and 0.65 or 0.54)
            love.graphics.circle("fill",innerX+a*width,
                innerY+12+math.sin(a*4.3)*5+jitter,
                kind=="grain" and 2 or 1.1)
        end
    elseif kind=="flat" then
        for i=0,steps do
            local a=i/steps
            love.graphics.setColor(0.63,0.86,0.91,0.84)
            love.graphics.rectangle("fill",innerX+a*width,
                innerY+7+math.sin(a*4.3)*3,4,12)
        end
    else
        love.graphics.setLineWidth(kind=="paint" and 6 or 3.8)
        love.graphics.setColor(0.64,0.87,0.95,kind=="paint" and 0.60 or 1)
        local points={}
        for i=0,steps do
            local a=i/steps
            points[#points+1]=innerX+a*width
            points[#points+1]=innerY+13+math.sin(a*4.3)*5
        end
        love.graphics.line(points)
        love.graphics.setLineWidth(1)
    end
end

local CATEGORIES={"Todos","Tinta","Esboco","Pintura","Textura","Precisao","Sua biblioteca"}

function UI:visibleBrushes(app)
    local category=CATEGORIES[self.brushCategory] or "Todos"
    local shown={}
    for _,preset in ipairs(Presets) do
        if (category=="Todos" or preset.family==category) and
           (not self.favoriteOnly or app.favorites[preset.id]) then
            shown[#shown+1]=preset
        end
    end
    return shown
end

function UI:drawBrushPanel(app,x,w,h)
    self:print("BIBLIOTECA DE PINCEIS",x,155,C.white)
    self:print("Previa renderizada pelo C++",x,181,C.muted,self.small)
    self:button(x,205,29,30,"<",function()
        self.brushCategory=(self.brushCategory-2)%#CATEGORIES+1
    end,"ghost")
    self:rect(x+34,205,w-155,30,C.surface,7)
    self:print(CATEGORIES[self.brushCategory],x+39,213,C.white,
        self.small,w-165,"center")
    self:button(x+w-117,205,29,30,">",function()
        self.brushCategory=self.brushCategory%#CATEGORIES+1
    end,"ghost")
    self:button(x+w-83,205,83,30,
        self.favoriteOnly and "Todos" or "Favoritos",function()
            self.favoriteOnly=not self.favoriteOnly
        end,self.favoriteOnly and "primary" or "ghost")
    local shown=self:visibleBrushes(app)
    local itemWidth=(w-9)/2
    if #shown==0 then
        self:print("Sem pinceis nesta categoria.",x+9,290,C.muted,self.small,w-18)
    end
    for i,preset in ipairs(shown) do
        local col=(i-1)%2
        local row=math.floor((i-1)/2)
        local px=x+col*(itemWidth+9)
        local py=245+row*63
        local active=app.presetId==preset.id
        self:rect(px,py,itemWidth,58,active and C.surface2 or C.surface,10)
        if active then
            color(C.accent)
            love.graphics.setLineWidth(1.5)
            love.graphics.rectangle("line",px+0.5,py+0.5,itemWidth-1,57,10)
            love.graphics.setLineWidth(1)
        end
        local preview=BrushPreview.get(app:presetStyle(preset.id),app.tipMask)
        if preview then
            local sw,sh=preview:getDimensions()
            local pw=itemWidth-21
            love.graphics.push("all")
            love.graphics.setScissor(px+5,py+3,pw,33)
            love.graphics.setColor(1,1,1,1)
            love.graphics.draw(preview,px+5,py+1,0,pw/sw,34/sh)
            love.graphics.pop()
        else
            self:drawStrokePreview(preset.preview,px+4,py+2,itemWidth-27)
        end
        local name=preset.name
        if app.profiles[preset.id] then name=name.." •" end
        self:print(name,px+7,py+37,C.white,self.small,itemWidth-13)
        self:register(px,py,itemWidth,58,function()
            if app:choosePreset(preset.id) then
                app:statusMessage("Pincel: "..preset.name)
            else
                app:statusMessage("Ponta PNG: Shift + arraste uma imagem")
            end
        end)
        self:button(px+itemWidth-29,py+4,25,23,
            app.favorites[preset.id] and "*" or "+",function()
                app:toggleFavorite(preset.id)
            end,app.favorites[preset.id] and "primary" or "ghost")
    end
    self:print("CONTROLE RAPIDO",x,513,C.muted,self.small)
    self:slider(x+9,550,w-20,(app.brushSize-1)/119,"Tamanho",function(v)
        app.brushSize=math.max(1,math.floor(1+v*119+0.5))
    end,tostring(app.brushSize).." px")
    self:slider(x+9,601,w-20,app.brushOpacity,"Opacidade",function(v)
        app.brushOpacity=math.max(0.03,v)
    end,tostring(math.floor(app.brushOpacity*100+0.5)).."%")
    self:print("PALETA",x,h-139,C.muted,self.small)
    self:drawSwatches(app,x,h-113,w)
end

function UI:drawSwatches(app,x,y,w)
    local cell=(w-6)/#palette
    if cell<14 then cell=14 end
    for i,swatch in ipairs(palette) do
        local col=(i-1)%8
        local row=math.floor((i-1)/8)
        local xx=x+col*math.min(34,(w-2)/8)
        local yy=y+row*29
        self:rect(xx,yy,23,23,swatch,6)
        if app.colorIndex==i then
            color(C.accent)
            love.graphics.rectangle("line",xx-2,yy-2,27,27,7)
        end
        self:register(xx-1,yy-1,26,26,function()
            applyColor(app,swatch)
            app.colorIndex=i
            self.hue,self.saturation,self.brightness=rgbHsv(swatch)
        end)
    end
end

function UI:drawSettings(app,x,w,h)
    self:print("AJUSTES DO PINCEL",x,155,C.white)
    self:print("Parametros aplicados ao motor C++",x,181,C.muted,self.small)
    local controls={
        {"Espessura",(app.brushSize-1)/119,function(v)
            app.brushSize=math.max(1,math.floor(1+v*119+0.5))
        end,tostring(app.brushSize).." px"},
        {"Opacidade",app.brushOpacity,function(v)
            app.brushOpacity=math.max(0.03,v)
        end,tostring(math.floor(app.brushOpacity*100+0.5)).."%"},
        {"Fluxo",app.brushFlow,function(v)
            app.brushFlow=math.max(0.01,v)
        end,tostring(math.floor(app.brushFlow*100+0.5)).."%"},
        {"Dureza",app.brushHardness,function(v) app.brushHardness=v end,
            tostring(math.floor(app.brushHardness*100+0.5)).."%"},
        {"Espacamento",(app.brushSpacing-0.03)/0.47,function(v)
            app.brushSpacing=0.03+v*0.47
        end,tostring(math.floor(app.brushSpacing*100+0.5)).."%"},
        {"Estabilizacao",app.stabilization,function(v)
            app.stabilization=v
        end,tostring(math.floor(app.stabilization*100+0.5)).."%"},
        {"Pressao na opacidade",app.pressureOpacity,function(v)
            app.pressureOpacity=v
        end,tostring(math.floor(app.pressureOpacity*100+0.5)).."%"},
        {"Angulo da ponta",app.brushAngle/180,function(v)
            app.brushAngle=math.floor(180*v+0.5)
        end,tostring(app.brushAngle).."°"},
    }
    for i,c in ipairs(controls) do
        self:slider(x+10,220+(i-1)*33,w-22,c[2],c[1],c[3],c[4])
    end
    self:button(x+4,483,w-8,31,
        app.brushFollowPath and "Ponta acompanha o traco: SIM"
            or "Ponta acompanha o traco: NAO",function()
        app.brushFollowPath=not app.brushFollowPath
    end,app.brushFollowPath and "primary" or nil)
    self:print("FORMATO DA PONTA",x,522,C.muted,self.small)
    for i,item in ipairs({{"Red.",0},{"Chata",1},{"Grao",2},{"PNG",3}}) do
        local bx=x+(i-1)*(w/4)
        self:button(bx,540,w/4-7,30,item[1],function()
            if item[2]==3 and not app.tipMask then
                app:statusMessage("Shift + arraste PNG para criar a ponta")
            else app.brushTip=item[2];app.tool="brush" end
        end,app.brushTip==item[2] and "primary" or nil)
    end
    self:print("PREVIA DIRECIONAL - MOTOR C++",x,582,C.white,self.small)
    self:rect(x+5,600,w-10,48,C.surface,8)
    local preview=BrushPreview.getLive(app)
    if preview then
        local iw,ih=preview:getDimensions()
        love.graphics.setColor(1,1,1,1)
        love.graphics.draw(preview,x+12,602,0,(w-24)/iw,43/ih)
    else
        self:print("Motor C++ indisponivel",x+17,615,C.muted,self.small,w-34)
    end
    self:button(x+4,657,(w-14)/2,31,"Salvar preset",function()
        app:saveBrushProfile()
    end,"primary")
    self:button(x+10+(w-14)/2,657,(w-14)/2,31,"Restaurar",function()
        app:resetBrushProfile()
    end)
end

function UI:drawColorPanel(app,x,w,h)
    self:print("ESTUDIO DE CORES",x,155,C.white)
    self:print("Toque no anel ou no quadrado",x,180,C.muted,self.small)
    local cx,cy=x+w/2,340
    local outer,inner=109,90
    local steps=72
    for i=0,steps-1 do
        local t=i/steps
        local nextT=(i+1)/steps
        local a=t*2*math.pi
        local b=nextT*2*math.pi
        local rgb=hsvRgb(t,1,1)
        love.graphics.setColor(rgb[1],rgb[2],rgb[3],1)
        love.graphics.polygon("fill",
            cx+math.cos(a)*inner,cy+math.sin(a)*inner,
            cx+math.cos(a)*outer,cy+math.sin(a)*outer,
            cx+math.cos(b)*outer,cy+math.sin(b)*outer,
            cx+math.cos(b)*inner,cy+math.sin(b)*inner)
    end
    local sq=130
    local px,py=cx-sq/2,cy-sq/2
    local grid=17
    for gy=0,grid-1 do
        for gx=0,grid-1 do
            local rgb=hsvRgb(self.hue,gx/(grid-1),1-gy/(grid-1))
            love.graphics.setColor(rgb[1],rgb[2],rgb[3],1)
            love.graphics.rectangle("fill",px+gx*sq/grid,py+gy*sq/grid,
                sq/grid+0.5,sq/grid+0.5)
        end
    end
    color(C.white)
    love.graphics.rectangle("line",px-1,py-1,sq+2,sq+2,4)
    local markX=px+self.saturation*sq
    local markY=py+(1-self.brightness)*sq
    love.graphics.setColor(0,0,0,1)
    love.graphics.circle("line",markX,markY,6)
    love.graphics.setColor(1,1,1,1)
    love.graphics.circle("line",markX,markY,5)
    self:register(cx-outer,cy-outer,outer*2,outer*2,function(xx,yy)
        local dx,dy=xx-cx,yy-cy
        local distance=math.sqrt(dx*dx+dy*dy)
        if distance>inner-5 then
            local atan2=math.atan2
            local angle
            if atan2 then angle=atan2(dy,dx)
            else
                angle=math.atan(dy/(math.abs(dx)<0.0001 and 0.0001 or dx))
                if dx<0 then angle=angle+math.pi end
            end
            self.hue=(angle/(2*math.pi))%1
        else
            self.saturation=clamp((xx-px)/sq,0,1)
            self.brightness=clamp(1-(yy-py)/sq,0,1)
        end
        applyColor(app,hsvRgb(self.hue,self.saturation,self.brightness))
    end)
    self:print("COR ATUAL",x,485,C.muted,self.small)
    self:rect(x,510,w,68,C.surface,11)
    self:rect(x+9,520,48,48,app.color,9)
    local r,g,b=app.color[1],app.color[2],app.color[3]
    self:print(("R %03d   G %03d   B %03d"):format(
        math.floor(r*255+0.5),math.floor(g*255+0.5),math.floor(b*255+0.5)),
        x+70,535,C.white,self.small,w-77)
    self:print("PALETA",x,609,C.muted,self.small)
    self:drawSwatches(app,x,639,w)
end

local function thumbnail(canvas,x,y,w,h)
    color({0.84,0.84,0.86})
    love.graphics.rectangle("fill",x,y,w,h,5)
    color({0.67,0.67,0.72})
    for row=0,2 do for col=0,3 do
        if (row+col)%2==0 then
            love.graphics.rectangle("fill",x+col*w/4,y+row*h/3,w/4,h/3)
        end
    end end
    local bw,bh=canvas:getDimensions()
    local factor=math.min(w/bw,h/bh)
    local dx=x+(w-bw*factor)/2
    local dy=y+(h-bh*factor)/2
    love.graphics.push("all")
    love.graphics.setScissor(x,y,w,h)
    love.graphics.setBlendMode("alpha","premultiplied")
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(canvas,dx,dy,0,factor,factor)
    love.graphics.pop()
    color(C.divider)
    love.graphics.rectangle("line",x,y,w,h,5)
end

function UI:drawLayersPanel(app,x,w,h)
    local doc=app.doc
    self:print("PILHA DE CAMADAS",x,155,C.white)
    self:print(("%d / 16  |  edicao nao destrutiva"):format(#doc.layers),
        x,181,C.muted,self.small)
    self:button(x,207,63,32,"+ Nova",function()
        if doc:addLayer() then self.layerScroll=0
        else app:statusMessage("Maximo de 16 camadas") end
    end,"primary")
    self:button(x+70,207,56,32,"Excluir",function()
        if not doc:removeLayer() then
            app:statusMessage("Deixe ao menos uma camada")
        end
    end)
    self:button(x+133,207,57,32,"Subir",function() doc:moveLayer(1) end)
    self:button(x+197,207,78,32,"Descer",function() doc:moveLayer(-1) end)
    local y0=253
    local endY=h-327
    self:rect(x,y0,w,math.max(72,endY-y0),C.top,8)
    local visible=math.max(1,math.floor((endY-y0-4)/65))
    local offset=clamp(self.layerScroll,0,math.max(0,#doc.layers-visible))
    self.layerScroll=offset
    for row=1,math.min(visible,#doc.layers) do
        local index=#doc.layers-offset-row+1
        local layer=doc.layers[index]
        local yy=y0+4+(row-1)*65
        local active=doc.selected==index
        self:rect(x+4,yy,w-8,60,active and C.surface2 or C.surface,8)
        if active then self:rect(x+4,yy+6,3,48,C.accent,2) end
        thumbnail(layer.canvas,x+13,yy+9,52,42)
        self:print(layer.name,x+76,yy+8,active and C.white or C.muted,
            self.small,w-118)
        local flags={}
        if layer.alphaLock then flags[#flags+1]="Alpha" end
        if layer.mask then flags[#flags+1]="Mascara" end
        if layer.clipping then flags[#flags+1]="Clip" end
        self:print(("%d%%  %s"):format(math.floor(layer.opacity*100+0.5),
            table.concat(flags," / ")),x+76,yy+32,C.muted,self.small,w-116)
        self:button(x+w-38,yy+16,30,29,layer.visible and "V" or "-",function()
            doc:toggleLayer(index)
        end,layer.visible and "ghost" or nil)
        self:register(x+10,yy+5,w-54,52,function()
            doc.selected=index
        end)
    end
    if #doc.layers>visible then
        self:button(x,endY+3,105,25,"Mais acima",function()
            self.layerScroll=clamp(self.layerScroll+1,0,#doc.layers-visible)
        end)
        self:button(x+170,endY+3,105,25,"Mais abaixo",function()
            self.layerScroll=clamp(self.layerScroll-1,0,#doc.layers-visible)
        end)
    end
    local active=doc.layers[doc.selected]
    if not active then return end
    local base=h-289
    self:print("PROPRIEDADES",x,base,C.muted,self.small)
    self:button(x,base+23,134,31,
        active.alphaLock and "Alpha Lock ON" or "Alpha Lock",
        function() doc:setLayerAlphaLock(doc.selected,not active.alphaLock) end,
        active.alphaLock and "primary" or nil)
    self:button(x+142,base+23,134,31,
        active.clipping and "Clipping ON" or "Clipping",
        function()
            if not doc:setClipping(doc.selected,not active.clipping) then
                app:statusMessage("Clipping exige camada abaixo e C++")
            end
        end,active.clipping and "primary" or nil)
    self:print("Mascara da camada",x,base+67,C.muted,self.small)
    self:button(x,base+85,85,30,active.mask and "Recriar" or "Criar",function()
        doc:createLayerMask(doc.selected)
    end)
    self:button(x+95,base+85,85,30,"Inverter",function()
        if not doc:invertLayerMask(doc.selected) then
            app:statusMessage("Crie a mascara antes")
        end
    end)
    self:button(x+190,base+85,85,30,"Remover",function()
        doc:removeLayerMask(doc.selected)
    end)
    self:print("Mesclagem",x,base+140,C.muted,self.small)
    local mode=(active.blendMode or 0)+1
    self:button(x,base+163,35,32,"<",function()
        doc:setLayerBlend(doc.selected,(mode-2)%#doc.BLEND_MODES)
    end)
    self:rect(x+40,base+163,w-80,32,C.surface,6)
    self:print(doc.BLEND_MODES[mode],x+42,base+172,C.white,
        self.small,w-84,"center")
    self:button(x+w-35,base+163,35,32,">",function()
        doc:setLayerBlend(doc.selected,mode%#doc.BLEND_MODES)
    end)
    self:slider(x+10,base+232,w-20,active.opacity,"Opacidade da camada",function(v)
        doc:setLayerOpacity(doc.selected,v,true)
    end,tostring(math.floor(active.opacity*100+0.5)).."%",function()
        doc:checkpoint()
    end)
end

function UI:drawWorkspaceHeader(app)
    local x,y,r= self:workspaceBounds()
    local z=app.zoom
    self:rect(x+13,y+12,242,38,C.top,10)
    self:print(app.doc.name or "Sem titulo",x+25,y+23,C.white,
        self.small,213)
    local bx=r-225
    self:rect(bx,y+12,213,38,C.top,10)
    self:button(bx+6,y+16,33,29,"-",function()
        local mx,my=love.graphics.getDimensions()
        app:zoomAt(1/1.2,(x+r)/2,y+(my-y-44)/2)
    end,"ghost")
    self:print(("%d%%"):format(math.floor(z*100+0.5)),bx+47,y+25,C.white,
        self.small,66,"center")
    self:button(bx+119,y+16,33,29,"+",function()
        local mx,my=love.graphics.getDimensions()
        app:zoomAt(1.2,(x+r)/2,y+(my-y-44)/2)
    end,"ghost")
    self:button(bx+159,y+16,48,29,"Tela",function() app:fitView() end,"ghost")
    self:rect(bx-5,y+55,218,35,C.top,9)
    local left,top,right,bottom=self:workspaceBounds()
    local centerX,centerY=(left+right)/2,(top+bottom)/2
    self:button(bx+1,y+58,35,28,"<",function()
        app:rotateAt(-15,centerX,centerY)
    end,"ghost")
    local angle=math.deg(app.rotation)
    if angle>180 then angle=angle-360 end
    self:print(("%d deg"):format(math.floor(angle+0.5)),
        bx+42,y+66,C.white,self.small,83,"center")
    self:button(bx+129,y+58,35,28,">",function()
        app:rotateAt(15,centerX,centerY)
    end,"ghost")
    self:button(bx+168,y+58,44,28,"0",function()
        app:resetRotation()
    end,"ghost")
end

function UI:draw(app)
    self.hits={}
    local w,h=love.graphics.getDimensions()
    local maximum=math.max(316,math.min(490,w-620))
    self.inspectorWidth=clamp(self.inspectorWidth,316,maximum)
    local right=w-self.inspectorWidth
    self.currentApp=app
    love.graphics.push("all")
    self:drawToolbar(app,w,h,right)
    local px=right+18
    local panelWidth=self.inspectorWidth-36
    self:rect(px,78,panelWidth,43,C.top,10)
    local tabs={{"Pinceis","brush"},{"Ajustes","settings"},
        {"Camadas","layers"},{"Cor","color"}}
    for i,t in ipairs(tabs) do
        local tw=(panelWidth-8)/4
        local xx=px+4+(i-1)*tw
        if self.tab==t[2] then self:rect(xx,82,tw,35,C.surface2,8) end
        self:print(t[1],xx+1,93,self.tab==t[2] and C.accent or C.muted,
            self.small,tw-2,"center")
        self:register(xx,82,tw,35,function() self.tab=t[2] end)
    end
    self.currentDoc=app.doc
    if self.tab=="brush" then self:drawBrushPanel(app,px,panelWidth,h)
    elseif self.tab=="settings" then self:drawSettings(app,px,panelWidth,h)
    elseif self.tab=="layers" then self:drawLayersPanel(app,px,panelWidth,h)
    else self:drawColorPanel(app,px,panelWidth,h) end
    -- Splitter is intentionally above the panels in hit priority.
    self:rect(right-2,64,4,h-100,C.divider)
    self:register(right-7,64,14,h-100,function() end,"panel-resize")
    self:drawWorkspaceHeader(app)

    self:print(app.message or "Pronto para criar",18,h-25,C.white,
        self.small,math.max(100,w-545))
    local mode=app.tool=="brush" and (Presets.find(app.presetId) or {}).name or app.tool
    self:print(("%d x %d  |  %s  |  zoom %d%%  |  giro %d"):format(
        app.doc.width,app.doc.height,mode or "",math.floor(app.zoom*100+0.5),
        math.floor(math.deg(app.rotation)+0.5)),
        w-505,h-25,C.muted,self.small,486,"right")
    if self.modal then self:drawModal(app) end
    love.graphics.pop()
end

function UI:mousewheel(x,y)
    local w=love.graphics.getWidth()
    if self.tab~="layers" or x<w-self.inspectorWidth then return false end
    local count=#(self.currentDoc and self.currentDoc.layers or {})
    self.layerScroll=clamp(self.layerScroll-(y>0 and 1 or -1),0,math.max(0,count-1))
    return true
end

return UI
