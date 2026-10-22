#include "../inkora_core.h"
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>
#include <cstdint>
#include <vector>
#include <iostream>

static constexpr int W=64,H=48;
static uint8_t px(const std::vector<uint8_t>& buf,int x,int y,int c) {
    return buf[(y*W+x)*4+c];
}
static InkoraStroke makeStroke(std::vector<uint8_t>& buf) {
    InkoraStroke s{};
    s.pixels=buf.data();s.width=W;s.height=H;s.stride=W*4;s.buffer_bytes=buf.size();
    s.x0=s.x1=32.5f;s.y0=s.y1=24.5f;
    s.diameter=28;s.hardness=1.0f;s.opacity=1;s.spacing=0.2f;
    s.r=0;s.g=0;s.b=1;s.pressure0=s.pressure1=1;
    return s;
}
int main() {
    assert(inkora_core_api_version()==9);

    std::vector<uint8_t> img(W*H*4,0);
    // Preexisting red shape with partially transparent pixels.
    for(int y=12;y<38;++y) for(int x=16;x<48;++x) {
        auto idx=(y*W+x)*4;
        img[idx]=255;img[idx+3]=x<24 ? 128 : 255;
    }
    InkoraStroke s=makeStroke(img);
    InkoraTip tip{0,1.0f,0.0f,0.0f,19u,0,0};
    InkoraPaintClip clip{1,1,24,18,40,32};
    InkoraStrokeState state{0,0};
    InkoraRect dirty{0,0,0,0};
    assert(inkora_core_stroke_v6(&s,&state,&dirty,&tip,nullptr,1,0,&clip));
    // Selection and alpha lock constrain painting.
    assert(px(img,32,24,0)==0 && px(img,32,24,2)==255);
    assert(px(img,32,24,3)==255);
    assert(px(img,23,24,0)==255 && px(img,23,24,2)==0); // selection excludes x23
    assert(px(img,32,17,0)==255 && px(img,32,17,2)==0); // excludes y17
    assert(px(img,48,24,3)==0); // no paint outside preexisting alpha
    assert(dirty.width>0 && dirty.height>0);

    // Lock preserves half alpha when that pixel is inside selection.
    clip.left=16;clip.right=32;state={0,0};s.x0=s.x1=22.5f;
    assert(inkora_core_stroke_v6(&s,&state,&dirty,&tip,nullptr,1,0,&clip));
    assert(px(img,22,24,2)==255 && px(img,22,24,3)==128);

    // Eraser must not change alpha-locked layer at all.
    auto snapshot=img;
    s.eraser=1;state={0,0};
    assert(inkora_core_stroke_v6(&s,&state,&dirty,&tip,nullptr,1,0,&clip));
    assert(img==snapshot && dirty.width==0);

    // Unlock allows eraser inside selection, but not outside.
    clip.alpha_lock=0;state={0,0};
    assert(inkora_core_stroke_v6(&s,&state,&dirty,&tip,nullptr,1,0,&clip));
    assert(px(img,22,24,3)<128);
    assert(px(img,32,24,3)==255);

    // Local tile coordinates plus tip origin must match global selection.
    std::vector<uint8_t> tile(32*32*4,0);
    InkoraStroke small{};
    small.pixels=tile.data();small.width=32;small.height=32;
    small.stride=128;small.buffer_bytes=tile.size();
    small.x0=small.x1=10.5f;small.y0=small.y1=10.5f;
    small.diameter=20;small.hardness=1;small.opacity=1;small.spacing=0.2f;
    small.r=1;small.g=0;small.b=0;small.pressure0=small.pressure1=1;
    tip.origin_x=128;tip.origin_y=256;
    clip={0,1,136,263,145,272};
    state={0,0};
    assert(inkora_core_stroke_v6(&small,&state,&dirty,&tip,nullptr,1,0,&clip));
    auto local=[&](int x,int y,int c){return tile[(y*32+x)*4+c];};
    assert(local(10,10,3)>220);
    assert(local(7,10,3)==0);  // global x135 excluded
    assert(local(10,6,3)==0); // global y262 excluded

    // Invalid clip returns failure before touching the buffer.
    clip.selection_enabled=2;
    assert(!inkora_core_stroke_v6(&small,&state,&dirty,&tip,nullptr,1,0,&clip));
    clip.selection_enabled=1;clip.right=clip.left;
    assert(!inkora_core_stroke_v6(&small,&state,&dirty,&tip,nullptr,1,0,&clip));
    clip.right=145;clip.alpha_lock=-1;
    assert(!inkora_core_stroke_v6(&small,&state,&dirty,&tip,nullptr,1,0,&clip));

    std::cout<<"INKORA_CPP_ALPHA_LOCK_SELECTION_OK\n";
}
