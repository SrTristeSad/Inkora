#include "../inkora_core.h"
#include <cassert>
#include <cstdint>
#include <vector>
#include <iostream>

static InkoraStroke sample(std::vector<uint8_t> &bytes) {
    InkoraStroke s{};
    s.pixels = bytes.data();
    s.width = 64; s.height = 64; s.stride = 64*4;
    s.buffer_bytes = bytes.size();
    s.x0 = 10.5f; s.y0 = 12.5f; s.x1 = 40.5f; s.y1 = 12.5f;
    s.diameter=12; s.hardness=0.8f; s.opacity=1; s.spacing=0.2f;
    s.r=1; s.g=0; s.b=0; s.pressure0=1; s.pressure1=1;
    return s;
}
static uint8_t channel(const std::vector<uint8_t>& img,int x,int y,int c) {
    return img[(y*64+x)*4+c];
}

int main() {
    assert(inkora_core_api_version()==1);
    std::vector<uint8_t> bytes(64*64*4,0);
    auto s=sample(bytes);
    assert(inkora_core_stroke(&s)==1);
    assert(channel(bytes,20,12,0)>220);
    assert(channel(bytes,20,12,3)>220);
    assert(channel(bytes,20,12,1)==0);
    assert(channel(bytes,20,35,3)==0); // no leakage beyond radius
    auto past=bytes;
    s.eraser=1;
    assert(inkora_core_stroke(&s)==1);
    assert(channel(bytes,20,12,3)<channel(past,20,12,3));
    s.buffer_bytes=3;
    assert(inkora_core_stroke(&s)==0);
    s.buffer_bytes=bytes.size();
    s.pixels=nullptr;
    assert(inkora_core_stroke(&s)==0);

    std::vector<uint8_t> pressureImg(64*64*4,0);
    auto p=sample(pressureImg);
    p.x0=p.x1=20.5f; p.y0=p.y1=20.5f;
    p.pressure0=p.pressure1=0;
    assert(inkora_core_stroke(&p)==1);
    assert(channel(pressureImg,20,20,3)>0);
    assert(channel(pressureImg,20,25,3)==0);
    p.pressure0=p.pressure1=1;
    assert(inkora_core_stroke(&p)==1);
    assert(channel(pressureImg,20,25,3)>0);

    std::vector<uint8_t> blendImg(64*64*4,0);
    auto q=sample(blendImg);
    q.x0=q.x1=30.5f; q.y0=q.y1=30.5f;
    q.opacity=0.5f;
    assert(inkora_core_stroke(&q)==1);
    assert(channel(blendImg,30,30,3)>105 && channel(blendImg,30,30,3)<150);
    q.r=0; q.b=1;
    assert(inkora_core_stroke(&q)==1);
    assert(channel(blendImg,30,30,3)>160 && channel(blendImg,30,30,3)<210);
    assert(channel(blendImg,30,30,0)>35 && channel(blendImg,30,30,2)>100);
    std::cout<<"INKORA_CPP_BRUSH_OK\n";
}
