#include "inkora_core.h"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstddef>

namespace {
float clip(float v) { return std::max(0.0f,std::min(1.0f,v)); }
float channel(uint8_t v) { return static_cast<float>(v) / 255.0f; }
uint8_t quantize(float v) { return static_cast<uint8_t>(std::lround(clip(v)*255.0f)); }

float blend(float base,float top,int mode) {
    switch(mode) {
      case 1: return base*top;                                // multiply
      case 2: return base+top-base*top;                       // screen
      case 3: return std::min(1.0f,base+top);                 // add
      case 4: return base<=0.5f ? 2*base*top                  // overlay
                                 : 1-2*(1-base)*(1-top);
      default: return top;
    }
}
}

extern "C" int32_t inkora_core_blend_layer(
    uint8_t* dst,uint64_t dstBytes,int32_t dstStride,
    const uint8_t* src,uint64_t srcBytes,int32_t srcStride,
    int32_t width,int32_t height,float opacity,int32_t mode) {
    if(!dst || !src || dst==src || width<1 || height<1 ||
       width>16384 || height>16384 || mode<0 || mode>4 ||
       !std::isfinite(opacity) || opacity<0.0f || opacity>1.0f) return 0;
    const int64_t minimum=static_cast<int64_t>(width)*4;
    if(dstStride<minimum || srcStride<minimum) return 0;
    const uint64_t minimumDst=static_cast<uint64_t>(height-1)*dstStride
                             +static_cast<uint64_t>(minimum);
    const uint64_t minimumSrc=static_cast<uint64_t>(height-1)*srcStride
                             +static_cast<uint64_t>(minimum);
    if(dstBytes<minimumDst || srcBytes<minimumSrc) return 0;

    for(int y=0;y<height;++y) {
        uint8_t* drow=dst+static_cast<size_t>(y)*dstStride;
        const uint8_t* srow=src+static_cast<size_t>(y)*srcStride;
        for(int x=0;x<width;++x) {
            uint8_t* d=drow+4*static_cast<size_t>(x);
            const uint8_t* s=srow+4*static_cast<size_t>(x);
            const float sa=channel(s[3])*opacity;
            if(sa==0.0f) continue;
            const float da=channel(d[3]);
            const float aout=sa+da*(1.0f-sa);
            if(aout<=0) { d[0]=d[1]=d[2]=d[3]=0; continue; }
            for(int c=0;c<3;++c) {
                const float cb=channel(d[c]), cs=channel(s[c]);
                const float b=blend(cb,cs,mode);
                const float premul=(1.0f-sa)*da*cb
                     +(1.0f-da)*sa*cs+da*sa*b;
                d[c]=quantize(premul/aout);
            }
            d[3]=quantize(aout);
        }
    }
    return 1;
}
