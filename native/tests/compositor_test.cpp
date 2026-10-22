#include "../inkora_core.h"
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>
#include <array>
#include <cmath>
#include <cstdint>
#include <iostream>
using Pixel=std::array<uint8_t,4>;

int blendPixel(Pixel& dst,const Pixel& src,float alpha,int mode) {
    return inkora_core_blend_layer(dst.data(),dst.size(),4,
                                   src.data(),src.size(),4,1,1,alpha,mode);
}
bool approx(int v,int expected,int tolerance=2) {
    return std::abs(v-expected)<=tolerance;
}
int main() {
    assert(inkora_core_api_version()==11);

    Pixel white={255,255,255,255},red={255,0,0,255};
    Pixel composed=white;
    assert(blendPixel(composed,red,0.5f,0)==1);
    assert(composed[0]==255 && approx(composed[1],128) &&
           approx(composed[2],128) && composed[3]==255);

    Pixel blue={0,0,255,255};
    composed=blue;
    assert(blendPixel(composed,red,1.0f,1)==1);
    assert(composed[0]==0 && composed[1]==0 && composed[2]==0); // multiply

    composed=blue;
    assert(blendPixel(composed,red,1.0f,2)==1);
    assert(composed[0]==255 && composed[1]==0 && composed[2]==255); // screen

    composed=blue;
    assert(blendPixel(composed,red,1.0f,3)==1);
    assert(composed[0]==255 && composed[1]==0 && composed[2]==255); // add

    Pixel gray={128,128,128,255};
    composed=gray;
    assert(blendPixel(composed,red,1.0f,4)==1);
    assert(composed[0]>=252 && composed[1]<=2 && composed[2]<=2); // overlay

    // Porter-Duff: a partially transparent layer over an empty pixel
    // retains straight RGB while preserving source alpha.
    composed={0,0,0,0};
    const Pixel translucentRed={255,0,0,128};
    assert(blendPixel(composed,translucentRed,1.0f,0)==1);
    assert(composed[0]==255 && composed[1]==0 && composed[3]==128);
    const Pixel translucentBlue={0,0,255,128};
    assert(blendPixel(composed,translucentBlue,1.0f,1)==1);
    assert(composed[0]>0 && composed[2]>0 && composed[3]>128);

    // Inputs must be validated, never read outside the supplied buffers.
    composed=white;
    assert(!inkora_core_blend_layer(composed.data(),3,4,red.data(),4,4,1,1,1,0));
    assert(!inkora_core_blend_layer(composed.data(),4,4,red.data(),3,4,1,1,1,0));
    assert(!inkora_core_blend_layer(composed.data(),4,4,red.data(),4,2,1,1,1,0));
    assert(!inkora_core_blend_layer(composed.data(),4,4,red.data(),4,4,1,1,1,5));
    assert(!inkora_core_blend_layer(composed.data(),4,4,red.data(),4,4,1,1,-0.1f,0));
    assert(!inkora_core_blend_layer(composed.data(),4,4,red.data(),4,4,1,1,NAN,0));
    assert(!inkora_core_blend_layer(composed.data(),4,4,composed.data(),4,4,1,1,1,0));

    // Row stride greater than width*4 works.
    std::array<uint8_t,16> padded={
        255,255,255,255,5,5,5,5,
        255,255,255,255,6,6,6,6
    };
    std::array<uint8_t,16> reds={
        255,0,0,255,0,0,0,0,
        255,0,0,255,0,0,0,0
    };
    assert(inkora_core_blend_layer(padded.data(),16,8,reds.data(),16,8,1,2,1,0));
    assert(padded[0]==255 && padded[1]==0 && padded[8]==255 && padded[9]==0);
    assert(padded[4]==5 && padded[12]==6);

    // ABI v7: mask coverage from RED channel, not the alpha channel.
    std::array<uint8_t,8> dst2={255,255,255,255,255,255,255,255};
    std::array<uint8_t,8> src2={255,0,0,255,255,0,0,255};
    std::array<uint8_t,8> mask2={255,255,255,255,0,0,0,255};
    InkoraLayerEffects options{};
    options.mask_rgba=mask2.data();
    options.mask_bytes=mask2.size();
    options.mask_stride=8;
    assert(inkora_core_blend_layer_v7(dst2.data(),8,8,src2.data(),8,8,
        2,1,1,0,&options));
    assert(dst2[0]==255 && dst2[1]==0 && dst2[2]==0);
    assert(dst2[4]==255 && dst2[5]==255 && dst2[6]==255);

    // Clipping depends on the immediately preceding source layer's alpha.
    std::array<uint8_t,8> base2={0,0,255,255,0,0,255,0};
    dst2={255,255,255,255,255,255,255,255};
    options.mask_rgba=nullptr;
    options.clipping_enabled=1;
    options.clip_rgba=base2.data();
    options.clip_bytes=base2.size();
    options.clip_stride=8;
    options.clip_opacity=1;
    assert(inkora_core_blend_layer_v7(dst2.data(),8,8,src2.data(),8,8,
        2,1,1,0,&options));
    assert(dst2[0]==255 && dst2[1]==0 && dst2[2]==0);
    assert(dst2[4]==255 && dst2[5]==255 && dst2[6]==255);

    // Effective alpha multiplies layer mask, base alpha, base opacity,
    // and base mask (when supplied).
    dst2={255,255,255,255,255,255,255,255};
    mask2={128,128,128,255,255,255,255,255};
    base2={0,0,255,128,0,0,255,0};
    options.mask_rgba=mask2.data();
    options.clip_opacity=1;
    assert(inkora_core_blend_layer_v7(dst2.data(),8,8,src2.data(),8,8,
        2,1,1,0,&options));
    assert(approx(dst2[1],191,2));  // 1 - .5*.5 = .75 white remain
    assert(dst2[5]==255);

    dst2={255,255,255,255,255,255,255,255};
    std::array<uint8_t,8> baseMask={0,0,0,255,255,255,255,255};
    options.clip_mask_rgba=baseMask.data();
    options.clip_mask_bytes=baseMask.size();
    options.clip_mask_stride=8;
    assert(inkora_core_blend_layer_v7(dst2.data(),8,8,src2.data(),8,8,
        2,1,1,0,&options));
    assert(dst2[0]==255 && dst2[1]==255);

    // Clipping with no base must not expose painted pixels.
    dst2={255,255,255,255,255,255,255,255};
    options.clip_rgba=nullptr; options.clip_mask_rgba=nullptr;
    assert(inkora_core_blend_layer_v7(dst2.data(),8,8,src2.data(),8,8,
        2,1,1,0,&options));
    assert(dst2[1]==255 && dst2[5]==255);

    // Invalid effect strides/sizes must be rejected before pixel reads.
    options.clipping_enabled=0;
    options.mask_rgba=mask2.data();
    options.mask_bytes=1;
    assert(!inkora_core_blend_layer_v7(dst2.data(),8,8,src2.data(),8,8,
        2,1,1,0,&options));
    options.mask_bytes=8;
    options.mask_stride=4;
    assert(!inkora_core_blend_layer_v7(dst2.data(),8,8,src2.data(),8,8,
        2,1,1,0,&options));
    options.mask_stride=8;
    options.clipping_enabled=2;
    assert(!inkora_core_blend_layer_v7(dst2.data(),8,8,src2.data(),8,8,
        2,1,1,0,&options));
    std::cout<<"INKORA_CPP_MASK_CLIPPING_OK\n";
    std::cout<<"INKORA_CPP_COMPOSITOR_OK\n";
}
