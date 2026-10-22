#include "inkora_core.h"
#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>

namespace {
float saturate(float v) { return std::max(0.0f, std::min(1.0f, v)); }
uint8_t byte(float v) { return static_cast<uint8_t>(std::lround(saturate(v)*255.0f)); }
float unit(uint8_t v) { return v/255.0f; }
bool finite(float x) { return std::isfinite(x); }

uint32_t textureHash(int x,int y,uint32_t seed) {
    // Position-stable texture: splitting an input stroke across events
    // does not change the procedural grain.
    uint32_t h=seed ^ (static_cast<uint32_t>(x)*0x9E3779B9u)
                    ^ (static_cast<uint32_t>(y)*0x85EBCA6Bu);
    h ^= h >> 16;
    h *= 0x7FEB352Du;
    h ^= h >> 15;
    h *= 0x846CA68Bu;
    return h ^ (h >> 16);
}
bool validTip(const InkoraTip* tip) {
    if(!tip || tip->tip<0 || tip->tip>2) return false;
    return finite(tip->aspect) && tip->aspect>=0.1f && tip->aspect<=1.0f
        && finite(tip->angle) && std::abs(tip->angle)<=360.0f
        && finite(tip->grain) && tip->grain>=0.0f && tip->grain<=1.0f;
}

bool validMask(const InkoraMask* mask) {
    if (!mask) return true;
    if (!mask->alpha || mask->width<1 || mask->height<1 ||
        mask->width>512 || mask->height>512 || mask->stride<mask->width) return false;
    const uint64_t needed=static_cast<uint64_t>(mask->height-1)*
        static_cast<uint64_t>(mask->stride)+static_cast<uint64_t>(mask->width);
    return mask->buffer_bytes>=needed;
}

bool valid(const InkoraStroke& s) {
    if (!s.pixels || s.width < 1 || s.height < 1 || s.width > 16384 || s.height > 16384) return false;
    if (static_cast<int64_t>(s.stride) < static_cast<int64_t>(s.width)*4) return false;
    const uint64_t used=static_cast<uint64_t>(s.height-1)*static_cast<uint64_t>(s.stride)
                        +static_cast<uint64_t>(s.width)*4;
    if (s.buffer_bytes < used) return false;
    const float params[]={s.x0,s.y0,s.x1,s.y1,s.diameter,s.hardness,
        s.opacity,s.spacing,s.r,s.g,s.b,s.pressure0,s.pressure1};
    for (auto n:params) if (!finite(n)) return false;
    if (s.diameter < 0.5f || s.diameter > 2048.0f || s.spacing <= 0.0f || s.spacing > 2.0f) return false;
    if (s.eraser != 0 && s.eraser != 1) return false;
    if (std::abs(s.x0)>100000 || std::abs(s.y0)>100000 || std::abs(s.x1)>100000 || std::abs(s.y1)>100000) return false;
    return true;
}

void mark(InkoraRect& r,int x0,int y0,int x1,int y1) {
    if (x0>x1 || y0>y1) return;
    if (r.width==0 || r.height==0) {
        r={x0,y0,x1-x0+1,y1-y0+1};
        return;
    }
    const int left=std::min(r.x,x0), top=std::min(r.y,y0);
    const int right=std::max(r.x+r.width-1,x1), bottom=std::max(r.y+r.height-1,y1);
    r={left,top,right-left+1,bottom-top+1};
}

void dab(const InkoraStroke &s,float cx,float cy,float pressure,
         InkoraRect& dirty,const InkoraTip* tip,const InkoraMask* mask,
         float flow,float pressureOpacity) {
    if (s.opacity <= 0.0f || flow <= 0.0f) return;
    const float ink=saturate(s.opacity)*saturate(flow)*
        (1.0f-saturate(pressureOpacity)+saturate(pressureOpacity)*saturate(pressure));
    if (ink<=0.0f) return;
    const float radius=std::max(0.5f,s.diameter*(0.2f+0.8f*saturate(pressure))*0.5f);
    const float inner=radius*saturate(s.hardness);
    const float outer=radius+0.5f;
    const bool flat=tip && tip->tip==1;
    const bool bitmap=mask!=nullptr;
    const bool grainy=tip && tip->tip==2 && tip->grain>0.0f;
    const float angle=(flat || bitmap) && tip ? tip->angle*0.017453292519943295f : 0.0f;
    const float ca=std::cos(angle),sa=std::sin(angle);
    const float aspect=flat ? tip->aspect : 1.0f;
    const int x0=std::max(0,static_cast<int>(std::floor(cx-outer)));
    const int x1=std::min(s.width-1,static_cast<int>(std::ceil(cx+outer)));
    const int y0=std::max(0,static_cast<int>(std::floor(cy-outer)));
    const int y1=std::min(s.height-1,static_cast<int>(std::ceil(cy+outer)));
    if (x0>x1 || y0>y1) return;

    bool touched=false;
    for(int y=y0;y<=y1;++y) {
        for(int x=x0;x<=x1;++x) {
            const float dx=x+0.5f-cx,dy=y+0.5f-cy;
            const float u=ca*dx+sa*dy;
            const float v=-sa*dx+ca*dy;
            const float distance=std::sqrt(u*u+(v/aspect)*(v/aspect));
            float coverage=0.0f;
            if (bitmap) {
                // Tip image is fitted into a diameter x diameter square,
                // centred on the dab and rotated with the brush angle.
                // A 1-pixel mask is valid; samples use nearest neighbours.
                const float mx=(u/radius+1.0f)*0.5f;
                const float my=(v/radius+1.0f)*0.5f;
                if (mx>=0.0f && mx<1.0f && my>=0.0f && my<1.0f) {
                    const int ix=std::min(mask->width-1,
                        static_cast<int>(mx*static_cast<float>(mask->width)));
                    const int iy=std::min(mask->height-1,
                        static_cast<int>(my*static_cast<float>(mask->height)));
                    coverage=unit(mask->alpha[static_cast<size_t>(iy)*mask->stride+ix]);
                }
            } else {
                coverage=distance<=inner ? 1.0f
                    :saturate((outer-distance)/std::max(0.001f,outer-inner));
            }
            float strength=ink*coverage;
            if(grainy) {
                const float sample=static_cast<float>(textureHash(x+tip->origin_x,y+tip->origin_y,tip->seed)&65535u)/65535.0f;
                if (sample<tip->grain*0.80f) strength*=0.025f;
                else strength*=(0.80f+sample*0.20f);
            }
            if(strength<=0.0f) continue;
            uint8_t* p=s.pixels+static_cast<size_t>(y)*s.stride+static_cast<size_t>(x)*4u;
            const float oldA=unit(p[3]);
            if(s.eraser) {
                const float newA=oldA*(1.0f-strength);
                if(newA<1.0f/512.0f) p[0]=p[1]=p[2]=p[3]=0;
                else p[3]=byte(newA);
            } else {
                const float newA=strength+oldA*(1.0f-strength);
                if(newA<1.0f/512.0f) continue;
                const float oldWeight=oldA*(1.0f-strength);
                p[0]=byte((saturate(s.r)*strength+unit(p[0])*oldWeight)/newA);
                p[1]=byte((saturate(s.g)*strength+unit(p[1])*oldWeight)/newA);
                p[2]=byte((saturate(s.b)*strength+unit(p[2])*oldWeight)/newA);
                p[3]=byte(newA);
            }
            touched=true;
        }
    }
    if (touched) mark(dirty,x0,y0,x1,y1);
}
} // namespace

extern "C" int32_t inkora_core_api_version(void) { return 5; }

static int32_t strokeImpl(const InkoraStroke* src,InkoraStrokeState* state,
                          InkoraRect* dirty,const InkoraTip* tip,
                          const InkoraMask* mask,float flow,float pressureOpacity) {
    if (!src || !state || !dirty || !valid(*src)) return 0;
    if(tip && !validTip(tip)) return 0;
    if(!validMask(mask)) return 0;
    if(!finite(flow) || !finite(pressureOpacity) ||
        flow<0.0f || flow>1.0f || pressureOpacity<0.0f || pressureOpacity>1.0f) return 0;
    if(state->initialized!=0 && state->initialized!=1) return 0;
    if(!finite(state->distance_to_next)) return 0;

    const InkoraStroke& s=*src;
    *dirty={0,0,0,0};
    const float dx=s.x1-s.x0,dy=s.y1-s.y0;
    const float distance=std::sqrt(dx*dx+dy*dy);
    const float step=std::max(0.75f,s.diameter*s.spacing);

    if (!state->initialized) {
        dab(s,s.x0,s.y0,s.pressure0,*dirty,tip,mask,flow,pressureOpacity);
        state->initialized=1;
        state->distance_to_next=step;
    }
    if(distance<0.000001f) return 1;

    float travel=state->distance_to_next;
    // Ensure a single bad state cannot hang the program.
    if (travel<=0.0f || travel>4096.0f) return 0;
    while(travel<=distance+0.00001f) {
        const float t=std::min(1.0f,travel/distance);
        dab(s,s.x0+dx*t,s.y0+dy*t,
            s.pressure0+(s.pressure1-s.pressure0)*t,*dirty,tip,mask,flow,pressureOpacity);
        travel+=step;
    }
    state->distance_to_next=travel-distance;
    return 1;
}

extern "C" int32_t inkora_core_stroke_v2(
    const InkoraStroke* src,InkoraStrokeState* state,InkoraRect* dirty) {
    return strokeImpl(src,state,dirty,nullptr,nullptr,1.0f,0.0f);
}

extern "C" int32_t inkora_core_stroke_v3(
    const InkoraStroke* src,InkoraStrokeState* state,InkoraRect* dirty,
    const InkoraTip* tip) {
    return strokeImpl(src,state,dirty,tip,nullptr,1.0f,0.0f);
}

extern "C" int32_t inkora_core_stroke_v4(
    const InkoraStroke* src,InkoraStrokeState* state,InkoraRect* dirty,
    const InkoraTip* tip,const InkoraMask* mask,float flow,float pressureOpacity) {
    return strokeImpl(src,state,dirty,tip,mask,flow,pressureOpacity);
}

extern "C" int32_t inkora_core_stroke(const InkoraStroke* src) {
    InkoraStrokeState state{0,0};
    InkoraRect dirty{0,0,0,0};
    return inkora_core_stroke_v2(src,&state,&dirty);
}
