-- Inkora gallery folders. Storage is separate from editable INKORA1 layers.
-- Mirrors observable ibisPaint My Gallery folders, including nesting.
local Folders={}
Folders.__index=Folders
local PATH="gallery-folders.txt"
local VERSION="INKORA_GALLERY_FOLDERS_1"

local function cleanName(s)
    return tostring(s or ""):gsub("[\r\n\t]"," "):gsub("^%s+",""):gsub("%s+$",""):sub(1,64)
end
local function validID(id)
    return type(id)=="string" and id:match("^f[%d]+%-%d+$")~=nil
end
local function validKey(key)
    return type(key)=="string" and key:match("^[%w%-]+$")~=nil
end
function Folders.new()
    local self=setmetatable({items={},order={},projects={},counter=0},Folders)
    local bytes=love.filesystem.read(PATH)
    if not bytes then return self end
    local lines={}
    for line in bytes:gmatch("[^\r\n]+") do lines[#lines+1]=line end
    if lines[1]~=VERSION then
        error("Formato de indice de galerias desconhecido")
    end
    for i=2,#lines do
        local a,b,c,d=lines[i]:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
        if a=="folder" and validID(b) and cleanName(d)~="" and
            not self.items[b] then
            self.items[b]={id=b,parent=c,name=cleanName(d)}
            self.order[#self.order+1]=b
        elseif a=="project" and validKey(b) and validID(c) then
            self.projects[b]=c
        end
    end
    for _,id in ipairs(self.order) do
        local folder=self.items[id]
        if folder.parent~="" and not self.items[folder.parent] then
            folder.parent=""
        end
    end
    return self
end
function Folders:write()
    local rows={VERSION}
    for _,id in ipairs(self.order) do
        local folder=self.items[id]
        if folder then
            rows[#rows+1]=table.concat({"folder",id,folder.parent,folder.name},"\t")
        end
    end
    local keys={}
    for key in pairs(self.projects) do keys[#keys+1]=key end
    table.sort(keys)
    for _,key in ipairs(keys) do
        local folder=self.projects[key]
        if self.items[folder] then
            rows[#rows+1]=table.concat({"project",key,folder,"-"},"\t")
        end
    end
    assert(love.filesystem.write(PATH,table.concat(rows,"\n").."\n"),
        "Nao foi possivel salvar as pastas da galeria")
end
function Folders:parent(id)
    return self.items[id] and self.items[id].parent or ""
end
function Folders:name(id)
    return self.items[id] and self.items[id].name or "Minha Galeria"
end
function Folders:children(id)
    id=id or ""
    local list={}
    for _,fid in ipairs(self.order) do
        if self.items[fid] and self.items[fid].parent==id then
            list[#list+1]=self.items[fid]
        end
    end
    return list
end
function Folders:location(key)
    local id=self.projects[key]
    return id and self.items[id] and id or ""
end
function Folders:contents(projects,id)
    id=id or ""
    local list={}
    for _,folder in ipairs(self:children(id)) do
        list[#list+1]={kind="folder",id=folder.id,name=folder.name}
    end
    for _,project in ipairs(projects) do
        if self:location(project.key)==id then
            list[#list+1]={kind="art",project=project,key=project.key,name=project.name}
        end
    end
    return list
end
function Folders:create(name,parent)
    local clean=cleanName(name)
    assert(clean~="","Digite um nome para a pasta")
    parent=parent or ""
    assert(parent=="" or self.items[parent],"Pasta de destino invalida")
    self.counter=self.counter+1
    local id
    repeat
        id="f"..tostring(os.time()).."-"..tostring(math.random(100000,999999))
    until not self.items[id]
    self.items[id]={id=id,name=clean,parent=parent}
    self.order[#self.order+1]=id
    local ok,err=pcall(function()self:write()end)
    if not ok then
        self.items[id]=nil
        table.remove(self.order)
        error(err)
    end
    return id
end
function Folders:rename(id,name)
    local folder=assert(self.items[id],"Pasta inexistente")
    local newName=cleanName(name)
    assert(newName~="","Digite um nome para a pasta")
    local before=folder.name
    folder.name=newName
    local ok,err=pcall(function()self:write()end)
    if not ok then folder.name=before;error(err) end
    return newName
end
function Folders:moveProjects(keys,destination)
    destination=destination or ""
    assert(destination=="" or self.items[destination],"Pasta de destino invalida")
    local before={}
    for _,key in ipairs(keys) do
        assert(validKey(key),"Projeto invalido")
        before[key]=self.projects[key] or ""
        self.projects[key]=destination~="" and destination or nil
    end
    local ok,err=pcall(function()self:write()end)
    if not ok then
        for key,value in pairs(before) do
            self.projects[key]=value~="" and value or nil
        end
        error(err)
    end
    return #keys
end
function Folders:moveFolder(id,destination)
    local folder=assert(self.items[id],"Pasta inexistente")
    destination=destination or ""
    assert(destination=="" or self.items[destination],"Destino invalido")
    local current=destination
    while current~="" do
        assert(current~=id,"Nao e permitido mover pasta para dentro dela mesma")
        current=self.items[current].parent
    end
    local before=folder.parent
    folder.parent=destination
    local ok,err=pcall(function()self:write()end)
    if not ok then folder.parent=before;error(err) end
end
function Folders:deleteEmpty(id)
    assert(self.items[id],"Pasta inexistente")
    assert(#self:children(id)==0,"Pasta possui subpastas")
    for _,fid in pairs(self.projects) do
        assert(fid~=id,"A pasta contem desenhos")
    end
    local removed=self.items[id]
    local index
    for i,fid in ipairs(self.order) do if fid==id then index=i;break end end
    self.items[id]=nil
    table.remove(self.order,index)
    local ok,err=pcall(function()self:write()end)
    if not ok then
        self.items[id]=removed
        table.insert(self.order,index,id)
        error(err)
    end
end
return Folders
