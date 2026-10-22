#include "../inkora_core.h"
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <vector>

static const int W=256,H=64;
using Image=std::vector<uint8_t>;
static Image makeImage() {
    Image p(W*H*4,0);
    for(int y=0;y<H;y++)for(int x=8;x<48;x++) {
        const size_t i=(y*W+x)*4;
        p[i]=240;p[i+1]=24;p[i+2]=24;p[i+3]=255;
    }
    return p;
}
static int channel(const Image& p,int x,int y,int c) {
    return p[(y*W+x)*4+c];
}
struct Paint {
    InkoraStrokeState state{};
    InkoraBrushDirection direction{};
    InkoraBrushDynamics dynamics{};
    InkoraPigmentCarry carry{};
};
static void stroke(Image& img,Paint& p,float x0,float x1,
                   float sampleRed,float sampleGreen,
                   float sampleBlue,float sampleAlpha,
                   bool oldAPI=false) {
    InkoraStroke s{};
    s.pixels=img.data();s.width=W;s.height=H;s.stride=W*4;
    s.buffer_bytes=img.size();s.x0=x0;s.y0=32.5f;
    s.x1=x1;s.y1=32.5f;s.diameter=13;s.hardness=1;
    s.opacity=0.75f;s.spacing=0.17f;s.r=0.1f;s.g=0.8f;
    s.b=0.25f;s.pressure0=s.pressure1=1;
    InkoraRect dirty{};
    InkoraTip tip{0,1,0,0,239u,0,0};
    InkoraWetPaint wet{0.9f,0.45f};
    p.carry.sample_r=sampleRed;
    p.carry.sample_g=sampleGreen;
    p.carry.sample_b=sampleBlue;
    p.carry.sample_a=sampleAlpha;
    if(oldAPI) assert(inkora_core_stroke_v10(&s,&p.state,&dirty,&tip,
        nullptr,1,0,nullptr,&p.direction,&p.dynamics,&wet)==1);
    else assert(inkora_core_stroke_v11(&s,&p.state,&dirty,&tip,
        nullptr,1,0,nullptr,&p.direction,&p.dynamics,
        &wet,&p.carry)==1);
}
int main() {
    assert(inkora_core_api_version()==11);
    auto carried=makeImage(),normal=makeImage(),dry=makeImage();
    Paint brush{},ordinary{},legacy{};
    brush.carry.pickup=0.95f;brush.carry.retention=0.9f;
    ordinary.carry.pickup=0;ordinary.carry.retention=0.9f;
    // First sample is red. Second segment has no pigment underneath,
    // but the reservoir must keep depositing the previously captured red.
    stroke(carried,brush,24.5f,42.5f,240.f/255,24.f/255,24.f/255,1);
    stroke(carried,brush,42.5f,108.5f,0,0,0,0);
    stroke(normal,ordinary,24.5f,42.5f,240.f/255,24.f/255,24.f/255,1);
    stroke(normal,ordinary,42.5f,108.5f,0,0,0,0);
    stroke(dry,legacy,24.5f,42.5f,0,0,0,0,true);
    stroke(dry,legacy,42.5f,108.5f,0,0,0,0,true);
    assert(normal==dry); // zero pickup is byte-exact v10
    assert(carried!=normal);
    assert(brush.carry.initialized==1);
    assert(brush.carry.reservoir_r>0.80f);
    assert(channel(carried,95,32,0)>channel(normal,95,32,0)+18);
    assert(channel(carried,95,32,1)<channel(normal,95,32,1));
    assert(channel(carried,95,32,3)>0);

    // The same sample/reservoir state must be used for every tile.
    // Compare full-sized raster to independently processed tile buffers.
    auto base=makeImage();
    Paint large{};
    large.carry.pickup=0.8f;large.carry.retention=0.8f;
    // Use a stroke that crosses the 128 px boundary.
    auto global=base;
    InkoraStroke s{};
    s.pixels=global.data();s.width=W;s.height=H;s.stride=W*4;
    s.buffer_bytes=global.size();s.x0=110.5f;s.y0=32.5f;
    s.x1=150.5f;s.y1=32.5f;s.diameter=16;s.hardness=1;
    s.opacity=0.8f;s.spacing=0.17f;s.r=0.3f;s.g=0.9f;s.b=0.1f;
    s.pressure0=s.pressure1=1;
    InkoraWetPaint wet{0.8f,0.4f};
    InkoraTip tip{0,1,0,0,239u,0,0};
    InkoraRect rect{};
    large.carry.sample_r=0.95f;
    large.carry.sample_a=1;
    assert(inkora_core_stroke_v11(&s,&large.state,&rect,&tip,nullptr,
        1,0,nullptr,&large.direction,&large.dynamics,&wet,&large.carry)==1);
    for(int tileIndex=0;tileIndex<2;tileIndex++) {
        Image part(128*H*4,0);
        for(int y=0;y<H;y++)for(int x=0;x<128;x++)
            for(int c=0;c<4;c++) part[(y*128+x)*4+c]=
                base[(y*W+tileIndex*128+x)*4+c];
        InkoraStroke local=s;
        local.pixels=part.data();local.width=128;
        local.stride=128*4;local.buffer_bytes=part.size();
        local.x0=s.x0-tileIndex*128;local.x1=s.x1-tileIndex*128;
        InkoraTip localTip=tip;localTip.origin_x=tileIndex*128;
        Paint tileState{};
        tileState.carry.pickup=0.8f;tileState.carry.retention=0.8f;
        tileState.carry.sample_r=0.95f;tileState.carry.sample_a=1;
        InkoraRect r{};
        assert(inkora_core_stroke_v11(&local,&tileState.state,&r,
            &localTip,nullptr,1,0,nullptr,&tileState.direction,
            &tileState.dynamics,&wet,&tileState.carry)==1);
        assert(std::abs(tileState.carry.reservoir_r-
            large.carry.reservoir_r)<0.00001f);
        for(int y=0;y<H;y++)for(int x=0;x<128;x++)
            for(int c=0;c<4;c++) assert(part[(y*128+x)*4+c]==
                global[(y*W+tileIndex*128+x)*4+c]);
    }

    // Input validation must reject nonfinite / out-of-range pigment state.
    Paint invalid{};
    invalid.carry.pickup=1.1f;
    assert(!inkora_core_stroke_v11(&s,&invalid.state,&rect,&tip,nullptr,
        1,0,nullptr,&invalid.direction,&invalid.dynamics,&wet,&invalid.carry));
    invalid.carry.pickup=0.2f;
    invalid.carry.sample_a=NAN;
    assert(!inkora_core_stroke_v11(&s,&invalid.state,&rect,&tip,nullptr,
        1,0,nullptr,&invalid.direction,&invalid.dynamics,&wet,&invalid.carry));
    std::cout<<"INKORA_CPP_PIGMENT_CARRY_V11_OK\n";
}
