#include "../inkora_core.h"
#ifdef NDEBUG
#undef NDEBUG // Keep all brush regression assertions in Release builds.
#endif
#include <cassert>
#include <cstdint>
#include <cmath>
#include <cstring>
#include <vector>
#include <iostream>
static constexpr int W=256,H=128;
static InkoraStroke sample(std::vector<uint8_t> &bytes) {
    InkoraStroke s{};
    s.pixels=bytes.data();s.width=W;s.height=H;s.stride=W*4;s.buffer_bytes=bytes.size();
    s.x0=12.5f;s.y0=20.5f;s.x1=92.5f;s.y1=20.5f;
    s.diameter=12;s.hardness=0.8f;s.opacity=1;s.spacing=0.18f;
    s.r=1;s.g=0;s.b=0;s.pressure0=1;s.pressure1=1;
    return s;
}
static uint8_t px(const std::vector<uint8_t>& image,int x,int y,int c) {
    return image[(y*W+x)*4+c];
}
int main() {
    assert(inkora_core_api_version()==12);
    std::vector<uint8_t> data(W*H*4,0);
    auto s=sample(data);
    InkoraStrokeState state{0,0};
    InkoraRect dirty{0,0,0,0};
    assert(inkora_core_stroke_v2(&s,&state,&dirty)==1);
    assert(dirty.width>0 && dirty.width<150 && dirty.height>0 && dirty.height<30);
    assert(dirty.x<=13 && dirty.y<=21);
    assert(px(data,40,20,0)>220 && px(data,40,20,3)>220);
    assert(px(data,40,80,3)==0);
    auto copy=data;
    s.eraser=1;
    assert(inkora_core_stroke(&s)==1);
    assert(px(data,40,20,3)<px(copy,40,20,3));
    s.buffer_bytes=3;assert(!inkora_core_stroke(&s));
    s.buffer_bytes=data.size();s.pixels=nullptr;assert(!inkora_core_stroke(&s));

    // Invariance: the same path split at an arbitrary event boundary
    // must paint the same pixels as an unsplit input.
    std::vector<uint8_t> whole(W*H*4,0), split(W*H*4,0);
    auto a=sample(whole);
    a.opacity=0.45f;a.spacing=0.23f;
    assert(inkora_core_stroke(&a));
    auto b=sample(split);
    b.opacity=0.45f;b.spacing=0.23f;
    const float end=b.x1;
    b.x1=47.5f;
    InkoraStrokeState st{0,0};
    InkoraRect r{0,0,0,0};
    assert(inkora_core_stroke_v2(&b,&st,&r));
    b.x0=b.x1;b.x1=end;
    assert(inkora_core_stroke_v2(&b,&st,&r));
    assert(whole==split && "Event splitting changed brush coverage");

    // Off-screen stamps need no GPU upload.
    b.x0=-1000;b.y0=-1000;b.x1=-900;b.y1=-900;
    st={0,0};
    assert(inkora_core_stroke_v2(&b,&st,&r));
    assert(r.width==0 && r.height==0);

    // Local small dab dirties only a small rectangle.
    st={0,0};b.x0=b.x1=128.5f;b.y0=b.y1=80.5f;
    assert(inkora_core_stroke_v2(&b,&st,&r));
    assert(r.width>0 && r.width<25 && r.height>0 && r.height<25);
    // Pressure changes brush radius.
    std::vector<uint8_t> pressure(W*H*4,0);
    auto p=sample(pressure);p.x0=p.x1=180.5f;p.y0=p.y1=80.5f;
    p.pressure0=0;p.pressure1=0;assert(inkora_core_stroke(&p));
    assert(px(pressure,180,85,3)==0);
    p.pressure0=p.pressure1=1;assert(inkora_core_stroke(&p));
    assert(px(pressure,180,85,3)>0);
    // ABI v3: brush tips must alter coverage while keeping legacy v2.
    std::vector<uint8_t> round(W*H*4,0),flat(W*H*4,0),grained(W*H*4,0);
    auto sr=sample(round);
    sr.x0=sr.x1=150.5f;sr.y0=sr.y1=65.5f;sr.diameter=24;
    InkoraStrokeState baseline{0,0};
    InkoraRect region{};
    assert(inkora_core_stroke_v2(&sr,&baseline,&region)==1);
    auto sf=sample(flat);
    sf.x0=sf.x1=150.5f;sf.y0=sf.y1=65.5f;sf.diameter=24;
    InkoraTip nib{1,0.2f,0.0f,0.0f,42u};
    InkoraStrokeState nibState{0,0};
    assert(inkora_core_stroke_v3(&sf,&nibState,&region,&nib)==1);
    assert(px(round,150,73,3)>80 && px(flat,150,73,3)==0);
    assert(px(flat,159,65,3)>150);
    auto sg=sample(grained);
    sg.x0=sg.x1=150.5f;sg.y0=sg.y1=65.5f;sg.diameter=24;
    InkoraTip chalk{2,1.0f,0.0f,0.95f,29u};
    InkoraStrokeState chalkState{0,0};
    assert(inkora_core_stroke_v3(&sg,&chalkState,&region,&chalk)==1);
    assert(grained!=round);
    chalk.grain=2.0f;
    assert(inkora_core_stroke_v3(&sg,&chalkState,&region,&chalk)==0);
    chalk.grain=0.95f;
    chalk.tip=9;
    assert(inkora_core_stroke_v3(&sg,&chalkState,&region,&chalk)==0);
    // Texture is deterministic even when stroke input is segmented.
    std::vector<uint8_t> one(W*H*4,0),parts(W*H*4,0);
    auto so=sample(one), sp=sample(parts);
    so.opacity=sp.opacity=0.6f;
    InkoraTip grain{2,1.0f,0.0f,0.8f,32u};
    InkoraStrokeState stateOne{0,0},stateParts{0,0};
    assert(inkora_core_stroke_v3(&so,&stateOne,&region,&grain)==1);
    float last=sp.x1;sp.x1=41.5f;
    assert(inkora_core_stroke_v3(&sp,&stateParts,&region,&grain)==1);
    sp.x0=sp.x1;sp.x1=last;
    assert(inkora_core_stroke_v3(&sp,&stateParts,&region,&grain)==1);
    assert(one==parts);
    // ABI v4: imported alpha bitmap, per-dab flow and pressure-opacity.
    std::vector<uint8_t> maskPixels(4*4,0);
    for(int y=0;y<4;++y)for(int x=0;x<2;++x) maskPixels[y*4+x]=255;
    InkoraMask mask{maskPixels.data(),4,4,4,maskPixels.size()};
    std::vector<uint8_t> imported(W*H*4,0);
    auto custom=sample(imported);
    custom.x0=custom.x1=100.5f;custom.y0=custom.y1=70.5f;
    custom.diameter=20;custom.pressure0=custom.pressure1=1;
    InkoraTip customTip{0,1.0f,0.0f,0.0f,19u,0,0};
    InkoraStrokeState cs{0,0};
    assert(inkora_core_stroke_v4(&custom,&cs,&region,&customTip,
        &mask,0.5f,0.0f)==1);
    assert(px(imported,96,70,3)>110 && px(imported,96,70,3)<145);
    assert(px(imported,105,70,3)==0);
    assert(region.width>0 && region.height>0);

    // Invalid mask is rejected before C++ reads caller memory.
    cs={0,0};mask.buffer_bytes=3;
    assert(!inkora_core_stroke_v4(&custom,&cs,&region,&customTip,&mask,1,0));
    mask.buffer_bytes=maskPixels.size();mask.stride=1;
    assert(!inkora_core_stroke_v4(&custom,&cs,&region,&customTip,&mask,1,0));
    mask.stride=4;
    assert(!inkora_core_stroke_v4(&custom,&cs,&region,&customTip,&mask,2,0));
    assert(!inkora_core_stroke_v4(&custom,&cs,&region,&customTip,&mask,1,-0.1f));

    // Pressure 0 deposits no paint when opacity is driven entirely by pressure.
    std::vector<uint8_t> zeroPressure(W*H*4,0);
    auto zp=sample(zeroPressure);
    zp.x0=zp.x1=100.5f;zp.y0=zp.y1=70.5f;
    zp.diameter=20;zp.pressure0=zp.pressure1=0;
    cs={0,0};
    assert(inkora_core_stroke_v4(&zp,&cs,&region,&customTip,nullptr,1,1));
    assert(px(zeroPressure,100,70,3)==0 && region.width==0);
    zp.pressure0=zp.pressure1=1;cs={0,0};
    assert(inkora_core_stroke_v4(&zp,&cs,&region,&customTip,nullptr,1,1));
    assert(px(zeroPressure,100,70,3)>220);
    // ABI v8: flat nib follows the stroke tangent across mouse events.
    std::vector<uint8_t> orientedX(W*H*4,0),orientedY(W*H*4,0);
    auto tangentX=sample(orientedX),tangentY=sample(orientedY);
    tangentX.x0=120.5f;tangentX.y0=65.5f;
    tangentX.x1=121.5f;tangentX.y1=65.5f;
    tangentY.x0=120.5f;tangentY.y0=65.5f;
    tangentY.x1=120.5f;tangentY.y1=66.5f;
    tangentX.diameter=tangentY.diameter=24;
    tangentX.spacing=tangentY.spacing=1;
    InkoraTip calligraphy{1,0.18f,0.0f,0.0f,1u,0,0};
    InkoraStrokeState orientationStateX{0,0},orientationStateY{0,0};
    InkoraBrushDirection directionX{1,0,0},directionY{1,0,0};
    assert(inkora_core_stroke_v8(&tangentX,&orientationStateX,&region,
        &calligraphy,nullptr,1,0,nullptr,&directionX)==1);
    assert(inkora_core_stroke_v8(&tangentY,&orientationStateY,&region,
        &calligraphy,nullptr,1,0,nullptr,&directionY)==1);
    assert(px(orientedX,128,65,3)>200 && px(orientedX,120,73,3)==0);
    assert(px(orientedY,128,65,3)==0 && px(orientedY,120,73,3)>200);
    assert(directionX.initialized==1 && directionY.initialized==1);
    assert(std::abs(directionY.angle_degrees-90.0f)<0.1f);
    tangentY.x0=tangentY.x1;tangentY.y0=tangentY.y1;
    assert(inkora_core_stroke_v8(&tangentY,&orientationStateY,&region,
        &calligraphy,nullptr,1,0,nullptr,&directionY)==1);
    assert(std::abs(directionY.angle_degrees-90.0f)<0.1f);

    // Original C++ v6 preserves fixed nib angle with the same segment.
    std::vector<uint8_t> legacy(W*H*4,0);
    auto fixed=sample(legacy);fixed.x0=fixed.x1=120.5f;
    fixed.y0=fixed.y1=65.5f;fixed.diameter=24;
    InkoraStrokeState fixedState{0,0};
    assert(inkora_core_stroke_v6(&fixed,&fixedState,&region,&calligraphy,
        nullptr,1,0,nullptr)==1);
    assert(px(legacy,128,65,3)>200 && px(legacy,120,73,3)==0);

    // Path orientation also rotates asymmetric user-owned bitmap masks.
    std::vector<uint8_t> asymmetric{255,255,0,0};
    InkoraMask customNib{asymmetric.data(),2,2,2,4};
    std::vector<uint8_t> orientedMask(W*H*4,0);
    auto maskStroke=sample(orientedMask);
    maskStroke.x0=120.5f;maskStroke.y0=65.5f;
    maskStroke.x1=120.5f;maskStroke.y1=66.5f;
    maskStroke.diameter=24;maskStroke.spacing=1;
    InkoraBrushDirection directionMask{1,0,0};
    InkoraStrokeState maskState{0,0};
    assert(inkora_core_stroke_v8(&maskStroke,&maskState,&region,&calligraphy,
        &customNib,1,0,nullptr,&directionMask)==1);
    assert(px(orientedMask,128,65,3)>200 && px(orientedMask,112,65,3)==0);

    // Invalid rotation metadata is rejected, with no buffer access.
    directionMask.follow_path=2;
    assert(!inkora_core_stroke_v8(&maskStroke,&maskState,&region,&calligraphy,
        nullptr,1,0,nullptr,&directionMask));
    directionMask.follow_path=1;directionMask.initialized=2;
    assert(!inkora_core_stroke_v8(&maskStroke,&maskState,&region,&calligraphy,
        nullptr,1,0,nullptr,&directionMask));
    directionMask.initialized=1;directionMask.angle_degrees=NAN;
    assert(!inkora_core_stroke_v8(&maskStroke,&maskState,&region,&calligraphy,
        nullptr,1,0,nullptr,&directionMask));
    std::cout<<"INKORA_CPP_DIRECTIONAL_BRUSH_OK\n";
    std::cout<<"INKORA_CPP_MASK_FLOW_PRESSURE_OK\n";
    std::cout<<"INKORA_CPP_DIRTY_STROKE_OK\n";
}
