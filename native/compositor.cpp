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
      case 1: return base*top;
      case 2: return base+top-base*top;
      case 3: return std::min(1.0f,base+top);
      case 4: return base<=0.5f ? 2*base*top : 1-2*(1-base)*(1-top);
      default: return top;
    }
}

bool enough(uint64_t bytes,int32_t stride,int32_t w,int32_t h,int components) {
    if(stride < static_cast<int64_t>(w)*components) return false;
    const uint64_t used=static_cast<uint64_t>(h-1)*static_cast<uint64_t>(stride)
        +static_cast<uint64_t>(w)*components;
    return bytes>=used;
}
bool validEffects(const InkoraLayerEffects* e,int32_t w,int32_t h) {
    if(!e) return true;
    if(e->mask_rgba && !enough(e->mask_bytes,e->mask_stride,w,h,4)) return false;
    if(e->clipping_enabled!=0 && e->clipping_enabled!=1) return false;
    if(e->clipping_enabled) {
        if(!std::isfinite(e->clip_opacity) ||
           e->clip_opacity<0.0f || e->clip_opacity>1.0f) return false;
        if(e->clip_rgba && !enough(e->clip_bytes,e->clip_stride,w,h,4)) return false;
        if(e->clip_mask_rgba && (!e->clip_rgba ||
           !enough(e->clip_mask_bytes,e->clip_mask_stride,w,h,4))) return false;
    }
    return true;
}
int blendImpl(uint8_t* dst,uint64_t dstBytes,int32_t dstStride,
              const uint8_t* src,uint64_t srcBytes,int32_t srcStride,
              int32_t width,int32_t height,float opacity,int32_t mode,
              const InkoraLayerEffects* effects) {
    if(!dst || !src || dst==src || width<1 || height<1 ||
       width>16384 || height>16384 || mode<0 || mode>4 ||
       !std::isfinite(opacity) || opacity<0.0f || opacity>1.0f) return 0;
    if(!enough(dstBytes,dstStride,width,height,4) ||
       !enough(srcBytes,srcStride,width,height,4) ||
       !validEffects(effects,width,height)) return 0;

    for(int y=0;y<height;++y) {
        uint8_t* drow=dst+static_cast<size_t>(y)*dstStride;
        const uint8_t* srow=src+static_cast<size_t>(y)*srcStride;
        const size_t row=static_cast<size_t>(y);
        for(int x=0;x<width;++x) {
            const size_t col=static_cast<size_t>(x);
            uint8_t* d=drow+4*col;
            const uint8_t* s=srow+4*col;
            float sa=channel(s[3])*opacity;
            if(effects) {
                if(effects->mask_rgba) {
                    const uint8_t* mask=effects->mask_rgba+row*effects->mask_stride+4*col;
                    sa*=channel(mask[0]);
                }
                if(effects->clipping_enabled) {
                    if(!effects->clip_rgba) sa=0.0f;
                    else {
                        const uint8_t* base=effects->clip_rgba+row*effects->clip_stride+4*col;
                        sa*=channel(base[3])*effects->clip_opacity;
                        if(effects->clip_mask_rgba) {
                            const uint8_t* mask=effects->clip_mask_rgba+
                                row*effects->clip_mask_stride+4*col;
                            sa*=channel(mask[0]);
                        }
                    }
                }
            }
            if(sa<=0.0f) continue;
            const float da=channel(d[3]);
            const float aout=sa+da*(1.0f-sa);
            if(aout<=0.0f) { d[0]=d[1]=d[2]=d[3]=0; continue; }
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
}

extern "C" int32_t inkora_core_blend_layer(
    uint8_t* dst,uint64_t dstBytes,int32_t dstStride,
    const uint8_t* src,uint64_t srcBytes,int32_t srcStride,
    int32_t width,int32_t height,float opacity,int32_t mode) {
    return blendImpl(dst,dstBytes,dstStride,src,srcBytes,srcStride,
                     width,height,opacity,mode,nullptr);
}

extern "C" int32_t inkora_core_blend_layer_v7(
    uint8_t* dst,uint64_t dstBytes,int32_t dstStride,
    const uint8_t* src,uint64_t srcBytes,int32_t srcStride,
    int32_t width,int32_t height,float opacity,int32_t mode,
    const InkoraLayerEffects* effects) {
    return blendImpl(dst,dstBytes,dstStride,src,srcBytes,srcStride,
                     width,height,opacity,mode,effects);
}
