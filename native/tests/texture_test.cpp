#include "../inkora_core.h"
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <vector>

constexpr int W=256,H=128;
using Pixels=std::vector<uint8_t>;
static InkoraStroke stroke(Pixels& pixels,int width=W,int height=H,
                           float ox=0.0f) {
    InkoraStroke s{};
    s.pixels=pixels.data();s.width=width;s.height=height;
    s.stride=width*4;s.buffer_bytes=pixels.size();
    s.x0=22.5f-ox;s.y0=64.5f;
    s.x1=232.5f-ox;s.y1=64.5f;
    s.diameter=18;s.hardness=1;s.opacity=0.60f;
    s.spacing=0.32f;s.r=0.2f;s.g=0.8f;s.b=0.4f;
    s.pressure0=s.pressure1=1;
    return s;
}
static int paint(Pixels& pix,InkoraBrushDynamics& dynamics,int width=W,
                 int height=H,int origin=0) {
    InkoraStroke s=stroke(pix,width,height,static_cast<float>(origin));
    InkoraTip tip{0,1,0,0,101u,origin,0};
    InkoraStrokeState state{0,0};
    InkoraRect dirty{0,0,0,0};
    InkoraBrushDirection dir{0,0,0};
    const int ok=inkora_core_stroke_v9(&s,&state,&dirty,&tip,nullptr,1,0,
                                      nullptr,&dir,&dynamics);
    assert(ok==1);
    assert(state.initialized==1 && dynamics.stamp_index>25);
    return dirty.width*dirty.height;
}
static long alphaSum(const Pixels& p) {
    long total=0;
    for(size_t i=3;i<p.size();i+=4) total+=p[i];
    return total;
}
int main() {
    assert(inkora_core_api_version()==9);
    Pixels plain(W*H*4,0),textured(W*H*4,0),
           scattered(W*H*4,0),jittered(W*H*4,0);
    InkoraBrushDynamics zero{0,0,0,0},texture{0.92f,0,0,0};
    InkoraBrushDynamics scatter{0,0.85f,0,0};
    InkoraBrushDynamics size{0,0,0.90f,0};
    assert(paint(plain,zero)>0);
    assert(paint(textured,texture)>0);
    assert(paint(scattered,scatter)>0);
    assert(paint(jittered,size)>0);
    assert(texture.stamp_index==zero.stamp_index);
    assert(alphaSum(textured)<alphaSum(plain));
    assert(plain!=textured && plain!=scattered && plain!=jittered);
    // Identical settings are deterministic on every run.
    Pixels repeat(W*H*4,0);
    InkoraBrushDynamics same{0.92f,0,0,0};
    paint(repeat,same);
    assert(repeat==textured);

    // A full bitmap and two independently rendered tiles must match,
    // including stochastic dab offsets near the tile seam at x=128.
    InkoraBrushDynamics allDyn{0.74f,0.8f,0.7f,0};
    Pixels all(W*H*4,0);
    paint(all,allDyn);
    Pixels left(128*H*4,0),right(128*H*4,0);
    InkoraBrushDynamics leftDyn{0.74f,0.8f,0.7f,0},
                        rightDyn{0.74f,0.8f,0.7f,0};
    paint(left,leftDyn,128,H,0);
    paint(right,rightDyn,128,H,128);
    assert(leftDyn.stamp_index==rightDyn.stamp_index);
    assert(leftDyn.stamp_index==allDyn.stamp_index);
    for(int y=0;y<H;++y)for(int x=0;x<W;++x)for(int ch=0;ch<4;++ch) {
        const auto expected=all[(y*W+x)*4+ch];
        const auto tile=x<128 ? left[(y*128+x)*4+ch]
                             : right[(y*128+x-128)*4+ch];
        assert(expected==tile);
    }

    // Preserve mutable stamp index across successive mouse events.
    Pixels follow(W*H*4,0);
    InkoraBrushDynamics evolving{0.6f,0.5f,0.4f,0};
    InkoraStroke s=stroke(follow);
    InkoraTip tip{0,1,0,0,101u,0,0};
    InkoraStrokeState state{0,0};
    InkoraRect dirty{0,0,0,0};
    InkoraBrushDirection dir{0,0,0};
    s.x1=100.5f;
    assert(inkora_core_stroke_v9(&s,&state,&dirty,&tip,nullptr,1,0,
        nullptr,&dir,&evolving));
    auto oldCount=evolving.stamp_index;
    s.x0=100.5f;s.x1=232.5f;
    assert(inkora_core_stroke_v9(&s,&state,&dirty,&tip,nullptr,1,0,
        nullptr,&dir,&evolving));
    assert(evolving.stamp_index>oldCount);

    // Reject out-of-range values without accessing the pixel buffer.
    InkoraBrushDynamics bad{1.01f,0,0,0};
    assert(!inkora_core_stroke_v9(&s,&state,&dirty,&tip,nullptr,1,0,
        nullptr,&dir,&bad));
    bad={0,-0.1f,0,0};
    assert(!inkora_core_stroke_v9(&s,&state,&dirty,&tip,nullptr,1,0,
        nullptr,&dir,&bad));
    bad={0,0,INFINITY,0};
    assert(!inkora_core_stroke_v9(&s,&state,&dirty,&tip,nullptr,1,0,
        nullptr,&dir,&bad));
    std::cout<<"INKORA_CPP_TEXTURE_SCATTER_TILE_OK\n";
}
