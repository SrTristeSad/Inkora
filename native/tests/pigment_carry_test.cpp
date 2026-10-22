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
    assert(inkora_core_api_version()==12);
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
    // ABI v12 enumerates the same dab centers with a continuous spacing
    // phase across segments. A capacity mismatch never writes out of range.
    InkoraStrokeState fresh{};
    uint32_t n=0;
    assert(inkora_core_dab_positions_v12(&fresh,12.5f,32.5f,
        220.5f,32.5f,12,0.2f,nullptr,0,&n)==1);
    assert(n>70 && n<100);
    std::vector<float> locations(n*2);
    assert(inkora_core_dab_positions_v12(&fresh,12.5f,32.5f,
        220.5f,32.5f,12,0.2f,locations.data(),n,&n)==1);
    assert(std::abs(locations[0]-12.5f)<0.001f);
    uint32_t tooSmall=0;
    assert(!inkora_core_dab_positions_v12(&fresh,12.5f,32.5f,
        220.5f,32.5f,12,0.2f,locations.data(),n-1,&tooSmall));

    // A single input segment travels over red, blue then transparent
    // substrate. Every dab has a distinct source sample from the unmodified
    // image; the final reservoir should be blue, not red or source green.
    Image original(W*H*4,0);
    for(int y=0;y<H;y++)for(int x=8;x<140;x++) {
        const size_t i=(y*W+x)*4;
        original[i]=(x<74)?255:0;
        original[i+2]=(x<74)?0:255;
        original[i+3]=255;
    }
    InkoraStroke sweep{};
    Image transported=original,oldWay=original,matchOriginal=original;
    sweep.pixels=transported.data();sweep.width=W;sweep.height=H;
    sweep.stride=W*4;sweep.buffer_bytes=transported.size();
    sweep.x0=12.5f;sweep.y0=32.5f;sweep.x1=220.5f;
    sweep.y1=32.5f;sweep.diameter=12;sweep.hardness=1;
    sweep.opacity=0.9f;sweep.spacing=0.2f;
    sweep.r=0.15f;sweep.g=0.85f;sweep.b=0.1f;
    sweep.pressure0=sweep.pressure1=1;
    InkoraTip nib{0,1,0,0,239u,0,0};
    InkoraWetPaint water{0.9f,0.45f};
    std::vector<uint8_t> samples(n*4,0);
    for(uint32_t i=0;i<n;i++) {
        const int x=static_cast<int>(std::floor(locations[2*i]));
        const int y=static_cast<int>(std::floor(locations[2*i+1]));
        const size_t source=(static_cast<size_t>(y)*W+x)*4;
        for(int c=0;c<4;c++) samples[i*4+c]=original[source+c];
    }
    InkoraDabSamples dabSamples{samples.data(),samples.size(),n};
    Paint v12{};
    v12.carry.pickup=0.95f;v12.carry.retention=0.9f;
    InkoraRect mark{};
    assert(inkora_core_stroke_v12(&sweep,&v12.state,&mark,&nib,
        nullptr,1,0,nullptr,&v12.direction,&v12.dynamics,
        &water,&v12.carry,&dabSamples)==1);
    assert(mark.width>0 && v12.carry.initialized==1);
    assert(v12.carry.reservoir_b>v12.carry.reservoir_r+0.2f);
    Paint v11{};
    v11.carry.pickup=0.95f;v11.carry.retention=0.9f;
    v11.carry.sample_a=0;
    sweep.pixels=oldWay.data();sweep.buffer_bytes=oldWay.size();
    assert(inkora_core_stroke_v11(&sweep,&v11.state,&mark,&nib,
        nullptr,1,0,nullptr,&v11.direction,&v11.dynamics,
        &water,&v11.carry)==1);
    assert(oldWay!=transported);
    assert(channel(transported,195,32,2)>channel(oldWay,195,32,2));
    // Disabling pickup preserves exactly the old v11 raster.
    Paint noPickup{},legacyNoPickup{};
    sweep.pixels=matchOriginal.data();
    assert(inkora_core_stroke_v12(&sweep,&noPickup.state,&mark,&nib,
        nullptr,1,0,nullptr,&noPickup.direction,&noPickup.dynamics,
        &water,&noPickup.carry,nullptr)==1);
    Image classic=original;
    sweep.pixels=classic.data();
    assert(inkora_core_stroke_v11(&sweep,&legacyNoPickup.state,&mark,&nib,
        nullptr,1,0,nullptr,&legacyNoPickup.direction,&legacyNoPickup.dynamics,
        &water,&legacyNoPickup.carry)==1);
    assert(classic==matchOriginal);

    // Invalid sample count and buffer length reject before painting.
    Paint rejected{};
    rejected.carry.pickup=0.8f;rejected.carry.retention=0.5f;
    auto snapshot=original;
    sweep.pixels=snapshot.data();
    InkoraDabSamples shortCount{samples.data(),samples.size(),n-1};
    assert(!inkora_core_stroke_v12(&sweep,&rejected.state,&mark,&nib,
        nullptr,1,0,nullptr,&rejected.direction,&rejected.dynamics,
        &water,&rejected.carry,&shortCount));
    assert(snapshot==original && rejected.state.initialized==0);
    InkoraDabSamples shortBytes{samples.data(),samples.size()-1,n};
    assert(!inkora_core_stroke_v12(&sweep,&rejected.state,&mark,&nib,
        nullptr,1,0,nullptr,&rejected.direction,&rejected.dynamics,
        &water,&rejected.carry,&shortBytes));

    // Two tiles share the same sampled source and initial reservoir;
    // independently rasterized halves must be byte-for-byte identical
    // to a single full-width call.
    for(int tile=0;tile<2;tile++) {
        Image half(128*H*4);
        for(int y=0;y<H;y++)for(int x=0;x<128;x++)
            for(int ch=0;ch<4;ch++)half[(y*128+x)*4+ch]=
                original[(y*W+tile*128+x)*4+ch];
        InkoraStroke local=sweep;
        local.pixels=half.data();local.width=128;local.stride=128*4;
        local.buffer_bytes=half.size();
        local.x0=sweep.x0-tile*128;
        local.x1=sweep.x1-tile*128;
        InkoraTip localNib=nib;localNib.origin_x=tile*128;
        Paint state{};
        state.carry.pickup=0.95f;state.carry.retention=0.9f;
        InkoraRect localDirty{};
        assert(inkora_core_stroke_v12(&local,&state.state,&localDirty,
            &localNib,nullptr,1,0,nullptr,&state.direction,&state.dynamics,
            &water,&state.carry,&dabSamples)==1);
        assert(std::abs(state.carry.reservoir_b-
            v12.carry.reservoir_b)<0.00001f);
        for(int y=0;y<H;y++)for(int x=0;x<128;x++)
            for(int ch=0;ch<4;ch++)assert(half[(y*128+x)*4+ch]==
                transported[(y*W+x+128*tile)*4+ch]);
    }
    std::cout<<"INKORA_CPP_PIGMENT_PER_DAB_V12_OK\\n";
    std::cout<<"INKORA_CPP_PIGMENT_CARRY_V11_OK\n";
}
