#include "../inkora_core.h"
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <vector>

constexpr int W=96,H=64;
static std::vector<uint8_t> background() {
    std::vector<uint8_t> pixels(W*H*4,0);
    for(int y=0;y<H;++y) for(int x=0;x<W;++x) {
        size_t n=(static_cast<size_t>(y)*W+x)*4;
        pixels[n]=(x<W/2)?240:20;
        pixels[n+1]=45;
        pixels[n+2]=(x<W/2)?20:230;
        pixels[n+3]=255;
    }
    return pixels;
}
static std::vector<uint8_t> render(float wetness,float load,int eraser=0,
                                    bool alphaLock=false) {
    auto pixels=background();
    InkoraStroke s{};
    s.pixels=pixels.data();s.width=W;s.height=H;s.stride=W*4;
    s.buffer_bytes=pixels.size();
    s.x0=12.5f;s.y0=32.5f;s.x1=82.5f;s.y1=32.5f;
    s.diameter=16;s.hardness=1;s.opacity=0.85f;s.spacing=0.25f;
    s.r=0.95f;s.g=0.92f;s.b=0.15f;
    s.pressure0=s.pressure1=1;s.eraser=eraser;
    InkoraTip tip{0,1,0,0,239u,0,0};
    InkoraStrokeState state{0,0};
    InkoraRect rect{0,0,0,0};
    InkoraBrushDirection dir{0,0,0};
    InkoraBrushDynamics dyn{0,0,0,0};
    InkoraPaintClip clip{alphaLock?1:0,0,0,0,0,0};
    InkoraWetPaint wet{wetness,load};
    assert(inkora_core_stroke_v10(&s,&state,&rect,&tip,nullptr,1,0,
        &clip,&dir,&dyn,&wet)==1);
    assert(rect.width>0);
    return pixels;
}
static int pixel(const std::vector<uint8_t>& p,int x,int y,int channel) {
    return p[(y*W+x)*4+channel];
}
int main() {
    assert(inkora_core_api_version()==13);
    auto dry=render(0,1);
    auto wet=render(0.95f,0.25f);
    auto wetAgain=render(0.95f,0.25f);
    assert(wet==wetAgain);
    assert(wet!=dry);
    assert(pixel(wet,65,32,0)<pixel(dry,65,32,0));
    assert(pixel(wet,65,32,2)>pixel(dry,65,32,2));
    assert(pixel(dry,65,32,3)==255 && pixel(wet,65,32,3)==255);
    assert(pixel(wet,65,0,0)==pixel(dry,65,0,0)); // outside nib
    auto heavy=render(0.95f,1);
    assert(heavy!=wet);
    auto eraserDry=render(0,1,1);
    auto eraserWet=render(1,0,1);
    assert(eraserDry==eraserWet);
    auto lock=render(0.95f,0.25f,0,true);
    for(int y=0;y<H;++y)for(int x=0;x<W;++x)
        assert(pixel(lock,x,y,3)==255);

    // Transparent pixels have no existing pigment to mix with.
    std::vector<uint8_t> empty(W*H*4,0);
    InkoraStroke s{};
    s.pixels=empty.data();s.width=W;s.height=H;s.stride=W*4;
    s.buffer_bytes=empty.size();s.x0=s.x1=48.5f;s.y0=s.y1=32.5f;
    s.diameter=20;s.hardness=1;s.opacity=1;s.spacing=0.1f;
    s.r=0.9f;s.g=0.6f;s.b=0.2f;s.pressure0=s.pressure1=1;
    InkoraStrokeState state{0,0};
    InkoraRect rect{0,0,0,0};
    InkoraBrushDirection dir{0,0,0};
    InkoraBrushDynamics dyn{0,0,0,0};
    InkoraWetPaint wetOnly{1,0.7f};
    assert(inkora_core_stroke_v10(&s,&state,&rect,nullptr,nullptr,1,0,
        nullptr,&dir,&dyn,&wetOnly)==1);
    assert(pixel(empty,48,32,3)>0);
    assert(pixel(empty,48,32,0)>200); // source color, no hidden blue

    // Existing API v9 and new API v10 with zero wetness must agree.
    auto v9Pixels=background();
    auto v10Pixels=background();
    InkoraTip tip{0,1,0,0,239u,0,0};
    auto initStroke=[&](std::vector<uint8_t>& p) {
        InkoraStroke a{};
        a.pixels=p.data();a.width=W;a.height=H;a.stride=W*4;
        a.buffer_bytes=p.size();a.x0=12.5f;a.y0=32.5f;
        a.x1=82.5f;a.y1=32.5f;
        a.diameter=16;a.hardness=1;a.opacity=0.85f;a.spacing=0.25f;
        a.r=0.95f;a.g=0.92f;a.b=0.15f;
        a.pressure0=a.pressure1=1;
        return a;
    };
    auto old=initStroke(v9Pixels),now=initStroke(v10Pixels);
    InkoraStrokeState oldState{0,0},newState{0,0};
    InkoraRect oldRect{},newRect{};
    InkoraBrushDirection oldDir{},newDir{};
    InkoraBrushDynamics oldDyn{},newDyn{};
    InkoraWetPaint zeroWet{0,0};
    assert(inkora_core_stroke_v9(&old,&oldState,&oldRect,&tip,nullptr,
        1,0,nullptr,&oldDir,&oldDyn)==1);
    assert(inkora_core_stroke_v10(&now,&newState,&newRect,&tip,nullptr,
        1,0,nullptr,&newDir,&newDyn,&zeroWet)==1);
    assert(v9Pixels==v10Pixels);

    InkoraWetPaint bad{1.01f,0.5f};
    assert(!inkora_core_stroke_v10(&now,&newState,&newRect,&tip,nullptr,
        1,0,nullptr,&newDir,&newDyn,&bad));
    bad={0.5f,-0.1f};
    assert(!inkora_core_stroke_v10(&now,&newState,&newRect,&tip,nullptr,
        1,0,nullptr,&newDir,&newDyn,&bad));
    bad={NAN,0.3f};
    assert(!inkora_core_stroke_v10(&now,&newState,&newRect,&tip,nullptr,
        1,0,nullptr,&newDir,&newDyn,&bad));
    std::cout<<"INKORA_CPP_WET_PIGMENT_MIX_OK\n";
}
