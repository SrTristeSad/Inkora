#include "../inkora_core.h"
#include <cassert>
#include <cstdint>
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
    assert(inkora_core_api_version()==2);
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
    std::cout<<"INKORA_CPP_DIRTY_STROKE_OK\n";
}
