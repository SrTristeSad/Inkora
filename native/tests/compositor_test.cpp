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
    assert(inkora_core_api_version()==6);

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
    std::cout<<"INKORA_CPP_COMPOSITOR_OK\n";
}
