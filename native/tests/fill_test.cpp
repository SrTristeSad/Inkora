#include "../inkora_core.h"
#include <cassert>
#include <cstdint>
#include <vector>
int main() {
    assert(inkora_core_api_version()==13);
    const int w=260,h=260;
    std::vector<uint8_t> pixels(size_t(w)*h*4,0);
    auto i=[&](int x,int y){return (size_t(y)*w+x)*4;};
    for(int y=120;y<140;++y) for(int x=120;x<140;++x) pixels[i(x,y)+3]=255;
    InkoraFill fill={};
    fill.pixels=pixels.data();fill.buffer_bytes=pixels.size();
    fill.width=w;fill.height=h;fill.stride=w*4;fill.x=125;fill.y=125;
    fill.r=0.1f;fill.g=1;fill.b=0;
    InkoraRect dirty={};
    assert(inkora_core_fill_v13(&fill,&dirty)==1);
    assert(dirty.x==120 && dirty.y==120 && dirty.width==20 && dirty.height==20);
    assert(pixels[i(139,139)+1]==255 && pixels[i(141,139)+3]==0);
    assert(inkora_core_fill_v13(&fill,&dirty)==1 && dirty.width==0);
    fill.x=140;fill.y=140;fill.alpha_lock=1;
    assert(inkora_core_fill_v13(&fill,&dirty)==1 && dirty.width==0);
    pixels[i(133,133)+3]=100;
    fill.x=133;fill.y=133;fill.r=1;fill.g=0;fill.b=0;fill.tolerance=1;
    fill.selection_enabled=1;fill.left=133;fill.top=133;
    fill.right=135;fill.bottom=135;
    assert(inkora_core_fill_v13(&fill,&dirty)==1);
    assert(dirty.x==133 && dirty.y==133 && dirty.width==2 && dirty.height==2);
    assert(pixels[i(133,133)+3]==100 && pixels[i(135,135)+1]==255);
    fill.buffer_bytes=3;
    pixels[i(133,133)]=14;
    assert(inkora_core_fill_v13(&fill,&dirty)==0);
    assert(pixels[i(133,133)]==14);
    return 0;
}
