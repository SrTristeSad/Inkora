-- Inkora brush library: independent presets backed by the existing
-- C++ brush engine. Each entry must change the actual stroke parameters.
local Presets={
    {id="ink",name="Nanquim",family="Tinta",size=10,hardness=1,
     spacing=0.09,opacity=1,flow=1,stabilization=0.40,tip=0,
     pressureOpacity=0.65,preview="solid"},
    {id="pencil",name="Lapis",family="Esboco",size=5,hardness=0.75,
     spacing=0.13,opacity=0.62,flow=0.74,stabilization=0.18,tip=2,
     pressureOpacity=0.8,texture=0.35,scatter=0.08,sizeJitter=0.20,
     preview="pencil"},
    {id="marker",name="Marcador",family="Tinta",size=28,hardness=1,
     spacing=0.10,opacity=0.65,flow=0.8,stabilization=0.10,tip=1,
     pressureOpacity=0.25,angle=0,followPath=true,preview="flat"},
    {id="soft",name="Aerografo",family="Pintura",size=55,hardness=0.08,
     spacing=0.07,opacity=0.42,flow=0.18,stabilization=0.24,tip=0,
     pressureOpacity=0.6,preview="soft"},
    {id="chalk",name="Giz",family="Textura",size=29,hardness=0.8,
     spacing=0.12,opacity=0.85,flow=0.75,stabilization=0.15,tip=2,
     pressureOpacity=0.5,texture=0.65,scatter=0.42,sizeJitter=0.45,
     preview="grain"},
    {id="paint",name="Pincel macio",family="Pintura",size=21,hardness=0.3,
     spacing=0.09,opacity=0.75,flow=0.55,stabilization=0.30,tip=0,
     pressureOpacity=0.6,preview="paint"},
    {id="watercolor",name="Aquarela",family="Pintura",size=36,
     hardness=0.35,spacing=0.08,opacity=0.68,flow=0.40,
     stabilization=0.22,tip=0,pressureOpacity=0.72,
     wetness=0.78,pigmentLoad=0.38,
     pigmentPickup=0.70,pigmentRetention=0.78,
     preview="paint"},
    {id="pixel",name="Pixel",family="Precisao",size=3,hardness=1,
     spacing=0.1,opacity=1,flow=1,stabilization=0,tip=0,
     pressureOpacity=0,preview="pixel"},
    {id="custom",name="Ponta PNG",family="Sua biblioteca",size=24,
     hardness=1,spacing=0.12,opacity=1,flow=0.8,stabilization=0.2,
     tip=3,pressureOpacity=0.5,preview="custom"},
}
-- Fixed-angle brushes preserve the original behavior. The marker uses
-- direction-following by default so the improvement is visible immediately.
for _,preset in ipairs(Presets) do
    if preset.angle==nil then preset.angle=0 end
    if preset.followPath==nil then preset.followPath=false end
    if preset.texture==nil then preset.texture=0 end
    if preset.scatter==nil then preset.scatter=0 end
    if preset.sizeJitter==nil then preset.sizeJitter=0 end
    if preset.wetness==nil then preset.wetness=0 end
    if preset.pigmentLoad==nil then preset.pigmentLoad=1 end
    if preset.pigmentPickup==nil then preset.pigmentPickup=0 end
    if preset.pigmentRetention==nil then preset.pigmentRetention=0 end
end

function Presets.find(id)
    for _,p in ipairs(Presets) do if p.id==id then return p end end
    return nil
end
return Presets
