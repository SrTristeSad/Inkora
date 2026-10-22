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
         float flow,float pressureOpacity,const InkoraPaintClip* clip,
         float directionAngle,const InkoraBrushDynamics* dynamics,
         uint32_t stampIndex,const InkoraWetPaint* wet) {
    if (s.opacity <= 0.0f || flow <= 0.0f) return;
    // An eraser would change alpha, which is forbidden in alpha-lock mode.
    if (clip && clip->alpha_lock && s.eraser) return;
    const bool wetPaint=wet && wet->wetness>0.0f && !s.eraser;
    const float ink=saturate(s.opacity)*saturate(flow)*
        (1.0f-saturate(pressureOpacity)+saturate(pressureOpacity)*saturate(pressure));
    if (ink<=0.0f) return;
    // Noise is based on the globally ordered dab index, not per-tile state.
    // The same stroke yields identical pixels across tile boundaries.
    float offsetX=0.0f,offsetY=0.0f;
    float sizeFactor=1.0f;
    if(dynamics) {
        const uint32_t seed=tip ? tip->seed : 239u;
        const float a=static_cast<float>(textureHash(
            static_cast<int>(stampIndex),17,seed)&65535u)/65535.0f;
        const float b=static_cast<float>(textureHash(
            static_cast<int>(stampIndex),37,seed)&65535u)/65535.0f;
        const float j=static_cast<float>(textureHash(
            static_cast<int>(stampIndex),59,seed)&65535u)/65535.0f;
        offsetX=(a*2.0f-1.0f)*s.diameter*dynamics->scatter*0.4f;
        offsetY=(b*2.0f-1.0f)*s.diameter*dynamics->scatter*0.4f;
        sizeFactor=1.0f-dynamics->size_jitter*0.8f*j;
    }
    cx+=offsetX;cy+=offsetY;
    const float radius=std::max(0.5f,s.diameter*(0.2f+0.8f*saturate(pressure))*0.5f*sizeFactor);
    const float inner=radius*saturate(s.hardness);
    const float outer=radius+0.5f;
    const bool flat=tip && tip->tip==1;
    const bool bitmap=mask!=nullptr;
    const bool grainy=tip && tip->tip==2 && tip->grain>0.0f;
    const float angle=(flat || bitmap) && tip ?
        (tip->angle+directionAngle)*0.017453292519943295f : 0.0f;
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
            if(clip && clip->selection_enabled) {
                const int globalX=x+(tip ? tip->origin_x : 0);
                const int globalY=y+(tip ? tip->origin_y : 0);
                if(globalX<clip->left || globalX>=clip->right ||
                   globalY<clip->top || globalY>=clip->bottom) continue;
            }
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
            if(dynamics && dynamics->texture>0.0f) {
                const int gx=x+(tip ? tip->origin_x : 0);
                const int gy=y+(tip ? tip->origin_y : 0);
                const uint32_t seed=tip ? tip->seed : 239u;
                const float n=static_cast<float>(
                    textureHash(gx,gy,seed^0xB5297A4Du)&65535u)/65535.0f;
                // World-space stipple: stationary texture is not shifted
                // between events and does not create tile seams.
                if(n<dynamics->texture*0.7f) strength*=0.025f;
                else strength*=1.0f-dynamics->texture*0.25f;
            }
            if(strength<=0.0f) continue;
            if(wetPaint) {
                // Less pigment produces a softer transparent wash.
                // The dry ABI behavior remains completely unchanged.
                strength*=0.25f+0.75f*wet->pigment_load;
            }
            uint8_t* p=s.pixels+static_cast<size_t>(y)*s.stride+static_cast<size_t>(x)*4u;
            const float oldA=unit(p[3]);
            float cr=saturate(s.r),cg=saturate(s.g),cb=saturate(s.b);
            if(wetPaint && oldA>0.0f) {
                // Geometric color blend produces darker pigment overlap
                // than regular RGB interpolation (stylized watercolor).
                // This is not physical pigment advection / brush pickup.
                const float pickup=wet->wetness*oldA*
                    (1.0f-0.85f*wet->pigment_load);
                cr=cr*(1.0f-pickup)+std::sqrt(cr*unit(p[0]))*pickup;
                cg=cg*(1.0f-pickup)+std::sqrt(cg*unit(p[1]))*pickup;
                cb=cb*(1.0f-pickup)+std::sqrt(cb*unit(p[2]))*pickup;
            }
            if(clip && clip->alpha_lock) {
                if(p[3]==0) continue; // Transparent pixels stay transparent.
                // Lock existing alpha and replace RGB within that coverage.
                p[0]=byte(unit(p[0])*(1.0f-strength)+cr*strength);
                p[1]=byte(unit(p[1])*(1.0f-strength)+cg*strength);
                p[2]=byte(unit(p[2])*(1.0f-strength)+cb*strength);
            } else if(s.eraser) {
                const float newA=oldA*(1.0f-strength);
                if(newA<1.0f/512.0f) p[0]=p[1]=p[2]=p[3]=0;
                else p[3]=byte(newA);
            } else {
                const float newA=strength+oldA*(1.0f-strength);
                if(newA<1.0f/512.0f) continue;
                const float oldWeight=oldA*(1.0f-strength);
                p[0]=byte((cr*strength+unit(p[0])*oldWeight)/newA);
                p[1]=byte((cg*strength+unit(p[1])*oldWeight)/newA);
                p[2]=byte((cb*strength+unit(p[2])*oldWeight)/newA);
                p[3]=byte(newA);
            }
            touched=true;
        }
    }
    if (touched) mark(dirty,x0,y0,x1,y1);
}
} // namespace

extern "C" int32_t inkora_core_api_version(void) { return 13; }

// Two passes with the same spacing arithmetic as strokeImpl itself.
extern "C" int32_t inkora_core_dab_positions_v12(
    const InkoraStrokeState* state,float x0,float y0,float x1,float y1,
    float diameter,float spacing,float* outXY,uint32_t capacity,
    uint32_t* count) {
    if(!state || !count || !finite(x0) || !finite(y0) ||
       !finite(x1) || !finite(y1) || !finite(diameter) ||
       !finite(spacing) || !finite(state->distance_to_next) ||
       (state->initialized!=0 && state->initialized!=1) ||
       diameter<0.5f || diameter>2048.f ||
       spacing<=0.f || spacing>2.f ||
       (outXY==nullptr && capacity!=0)) return 0;
    const float dx=x1-x0,dy=y1-y0;
    const float length=std::sqrt(dx*dx+dy*dy);
    if(!finite(length) || length>200000.f) return 0;
    const float step=std::max(0.75f,diameter*spacing);
    uint32_t total=0;
    auto push=[&](float px,float py) {
        if(outXY && total<capacity) {
            outXY[total*2]=px;
            outXY[total*2+1]=py;
        }
        ++total;
    };
    if(!state->initialized) push(x0,y0);
    float travel=state->initialized ? state->distance_to_next : step;
    if(length>=0.000001f) {
        if(travel<=0.f || travel>4096.f) return 0;
        while(travel<=length+0.00001f) {
            if(total>=16384u) return 0;
            const float t=std::min(1.f,travel/length);
            push(x0+dx*t,y0+dy*t);
            travel+=step;
        }
    }
    if(outXY && capacity<total) return 0;
    *count=total;
    return 1;
}

static int32_t strokeImpl(const InkoraStroke* src,InkoraStrokeState* state,
                          InkoraRect* dirty,const InkoraTip* tip,
                          const InkoraMask* mask,float flow,float pressureOpacity,
                          const InkoraPaintClip* clip,InkoraBrushDirection* direction,
                          InkoraBrushDynamics* dynamics,
                          const InkoraWetPaint* wet,
                          InkoraPigmentCarry* carry,
                          const InkoraDabSamples* samples) {
    if (!src || !state || !dirty || !valid(*src)) return 0;
    const bool sampleEachDab=samples && carry && carry->pickup>0.f
        && wet && wet->wetness>0.f && !src->eraser;
    if(sampleEachDab) {
        uint32_t required=0;
        if(!inkora_core_dab_positions_v12(state,src->x0,src->y0,
           src->x1,src->y1,src->diameter,src->spacing,
           nullptr,0,&required) || samples->count!=required ||
           (required>0 && (!samples->rgba ||
               samples->buffer_bytes<static_cast<uint64_t>(required)*4u)))
            return 0;
    }
    if(carry) {
        const float v[]={carry->pickup,carry->retention,
            carry->sample_r,carry->sample_g,carry->sample_b,carry->sample_a,
            carry->reservoir_r,carry->reservoir_g,carry->reservoir_b};
        for(float x:v) if(!finite(x) || x<0.0f || x>1.0f) return 0;
        if(carry->initialized!=0 && carry->initialized!=1) return 0;
    }
    if(wet && (!finite(wet->wetness) || !finite(wet->pigment_load) ||
       wet->wetness<0.0f || wet->wetness>1.0f ||
       wet->pigment_load<0.0f || wet->pigment_load>1.0f)) return 0;
    if(dynamics && (!finite(dynamics->texture) ||
       !finite(dynamics->scatter) || !finite(dynamics->size_jitter) ||
       dynamics->texture<0.0f || dynamics->texture>1.0f ||
       dynamics->scatter<0.0f || dynamics->scatter>1.0f ||
       dynamics->size_jitter<0.0f || dynamics->size_jitter>1.0f)) return 0;
    if(direction && (
        (direction->follow_path!=0 && direction->follow_path!=1) ||
        (direction->initialized!=0 && direction->initialized!=1) ||
        !finite(direction->angle_degrees))) return 0;
    if(clip) {
        if((clip->alpha_lock!=0 && clip->alpha_lock!=1) ||
           (clip->selection_enabled!=0 && clip->selection_enabled!=1)) return 0;
        if(clip->selection_enabled &&
           (clip->left>=clip->right || clip->top>=clip->bottom ||
            clip->left<0 || clip->top<0 || clip->right>16384 ||
            clip->bottom>16384)) return 0;
    }
    if(tip && !validTip(tip)) return 0;
    if(!validMask(mask)) return 0;
    if(!finite(flow) || !finite(pressureOpacity) ||
        flow<0.0f || flow>1.0f || pressureOpacity<0.0f || pressureOpacity>1.0f) return 0;
    if(state->initialized!=0 && state->initialized!=1) return 0;
    if(!finite(state->distance_to_next)) return 0;

    InkoraStroke s=*src;
    *dirty={0,0,0,0};
    if(carry && !sampleEachDab && carry->pickup>0 &&
       wet && wet->wetness>0 && !s.eraser) {
        // A single sample is prepared by Lua before any tile is touched.
        // All tiles start with identical reservoir state, including those
        // not intersecting the point where the pigment was sampled.
        if(!carry->initialized) {
            carry->reservoir_r=saturate(s.r);
            carry->reservoir_g=saturate(s.g);
            carry->reservoir_b=saturate(s.b);
            carry->initialized=1;
        }
        const float uptake=carry->pickup*carry->sample_a*wet->wetness;
        carry->reservoir_r=carry->reservoir_r*(1-uptake)
            +carry->sample_r*uptake;
        carry->reservoir_g=carry->reservoir_g*(1-uptake)
            +carry->sample_g*uptake;
        carry->reservoir_b=carry->reservoir_b*(1-uptake)
            +carry->sample_b*uptake;
        // Retention means deposited pigment depends on the moving brush
        // reservoir, rather than just on the selected palette color.
        s.r=s.r*(1-carry->retention)+carry->reservoir_r*carry->retention;
        s.g=s.g*(1-carry->retention)+carry->reservoir_g*carry->retention;
        s.b=s.b*(1-carry->retention)+carry->reservoir_b*carry->retention;
    }
    const float dx=s.x1-s.x0,dy=s.y1-s.y0;
    const float distance=std::sqrt(dx*dx+dy*dy);
    float nibAngle=0.0f;
    if(direction && direction->follow_path) {
        // The tangent remains stable if the pointer pauses or sends a
        // stationary event. A new stroke falls back to the nib base angle.
        if(distance>0.000001f) {
            nibAngle=std::atan2(dy,dx)*57.29577951308232f;
            direction->angle_degrees=nibAngle;
            direction->initialized=1;
        } else if(direction->initialized) {
            nibAngle=direction->angle_degrees;
        }
    }
    uint32_t stamp=dynamics ? dynamics->stamp_index : 0;
    const float step=std::max(0.75f,s.diameter*s.spacing);
    uint32_t currentSample=0;
    auto stampPaint=[&](float px,float py,float pressure) {
        InkoraStroke paint=s;
        if(sampleEachDab) {
            const uint8_t* rgba=samples->rgba+
                static_cast<size_t>(currentSample)*4u;
            const float uptake=carry->pickup*unit(rgba[3])*wet->wetness;
            if(!carry->initialized) {
                carry->reservoir_r=saturate(s.r);
                carry->reservoir_g=saturate(s.g);
                carry->reservoir_b=saturate(s.b);
                carry->initialized=1;
            }
            carry->reservoir_r=carry->reservoir_r*(1-uptake)
                +unit(rgba[0])*uptake;
            carry->reservoir_g=carry->reservoir_g*(1-uptake)
                +unit(rgba[1])*uptake;
            carry->reservoir_b=carry->reservoir_b*(1-uptake)
                +unit(rgba[2])*uptake;
            paint.r=s.r*(1-carry->retention)
                +carry->reservoir_r*carry->retention;
            paint.g=s.g*(1-carry->retention)
                +carry->reservoir_g*carry->retention;
            paint.b=s.b*(1-carry->retention)
                +carry->reservoir_b*carry->retention;
            ++currentSample;
        }
        dab(paint,px,py,pressure,*dirty,tip,mask,flow,
            pressureOpacity,clip,nibAngle,dynamics,stamp++,wet);
    };

    if (!state->initialized) {
        stampPaint(s.x0,s.y0,s.pressure0);
        if(dynamics) dynamics->stamp_index=stamp;
        state->initialized=1;
        state->distance_to_next=step;
    }
    if(distance<0.000001f) return 1;

    float travel=state->distance_to_next;
    // Ensure a single bad state cannot hang the program.
    if (travel<=0.0f || travel>4096.0f) return 0;
    while(travel<=distance+0.00001f) {
        const float t=std::min(1.0f,travel/distance);
        stampPaint(s.x0+dx*t,s.y0+dy*t,
            s.pressure0+(s.pressure1-s.pressure0)*t);
        travel+=step;
    }
    state->distance_to_next=travel-distance;
    if(dynamics) dynamics->stamp_index=stamp;
    return 1;
}

extern "C" int32_t inkora_core_stroke_v2(
    const InkoraStroke* src,InkoraStrokeState* state,InkoraRect* dirty) {
    return strokeImpl(src,state,dirty,nullptr,nullptr,1.0f,0.0f,nullptr,nullptr,nullptr,nullptr,nullptr,nullptr);
}

extern "C" int32_t inkora_core_stroke_v3(
    const InkoraStroke* src,InkoraStrokeState* state,InkoraRect* dirty,
    const InkoraTip* tip) {
    return strokeImpl(src,state,dirty,tip,nullptr,1.0f,0.0f,nullptr,nullptr,nullptr,nullptr,nullptr,nullptr);
}

extern "C" int32_t inkora_core_stroke_v4(
    const InkoraStroke* src,InkoraStrokeState* state,InkoraRect* dirty,
    const InkoraTip* tip,const InkoraMask* mask,float flow,float pressureOpacity) {
    return strokeImpl(src,state,dirty,tip,mask,flow,pressureOpacity,nullptr,nullptr,nullptr,nullptr,nullptr,nullptr);
}

extern "C" int32_t inkora_core_stroke_v6(
    const InkoraStroke* src,InkoraStrokeState* state,InkoraRect* dirty,
    const InkoraTip* tip,const InkoraMask* mask,float flow,
    float pressureOpacity,const InkoraPaintClip* clip) {
    return strokeImpl(src,state,dirty,tip,mask,flow,pressureOpacity,clip,nullptr,nullptr,nullptr,nullptr,nullptr);
}

extern "C" int32_t inkora_core_stroke_v8(
    const InkoraStroke* src,InkoraStrokeState* state,InkoraRect* dirty,
    const InkoraTip* tip,const InkoraMask* mask,float flow,
    float pressureOpacity,const InkoraPaintClip* clip,
    InkoraBrushDirection* direction) {
    if(!direction) return 0;
    return strokeImpl(src,state,dirty,tip,mask,flow,pressureOpacity,clip,direction,nullptr,nullptr,nullptr,nullptr);
}

extern "C" int32_t inkora_core_stroke_v9(
    const InkoraStroke* src,InkoraStrokeState* state,InkoraRect* dirty,
    const InkoraTip* tip,const InkoraMask* mask,float flow,
    float pressureOpacity,const InkoraPaintClip* clip,
    InkoraBrushDirection* direction,InkoraBrushDynamics* dynamics) {
    if(!direction || !dynamics) return 0;
    return strokeImpl(src,state,dirty,tip,mask,flow,pressureOpacity,
                      clip,direction,dynamics,nullptr,nullptr,nullptr);
}

extern "C" int32_t inkora_core_stroke_v10(
    const InkoraStroke* src,InkoraStrokeState* state,InkoraRect* dirty,
    const InkoraTip* tip,const InkoraMask* mask,float flow,
    float pressureOpacity,const InkoraPaintClip* clip,
    InkoraBrushDirection* direction,InkoraBrushDynamics* dynamics,
    const InkoraWetPaint* wet) {
    if(!direction || !dynamics || !wet) return 0;
    return strokeImpl(src,state,dirty,tip,mask,flow,pressureOpacity,
                      clip,direction,dynamics,wet,nullptr,nullptr);
}

extern "C" int32_t inkora_core_stroke_v11(
    const InkoraStroke* src,InkoraStrokeState* state,InkoraRect* dirty,
    const InkoraTip* tip,const InkoraMask* mask,float flow,
    float pressureOpacity,const InkoraPaintClip* clip,
    InkoraBrushDirection* direction,InkoraBrushDynamics* dynamics,
    const InkoraWetPaint* wet,InkoraPigmentCarry* carry) {
    if(!direction || !dynamics || !wet || !carry) return 0;
    return strokeImpl(src,state,dirty,tip,mask,flow,pressureOpacity,
                      clip,direction,dynamics,wet,carry,nullptr);
}

extern "C" int32_t inkora_core_stroke_v12(
    const InkoraStroke* src,InkoraStrokeState* state,InkoraRect* dirty,
    const InkoraTip* tip,const InkoraMask* mask,float flow,
    float pressureOpacity,const InkoraPaintClip* clip,
    InkoraBrushDirection* direction,InkoraBrushDynamics* dynamics,
    const InkoraWetPaint* wet,InkoraPigmentCarry* carry,
    const InkoraDabSamples* samples) {
    if(!direction || !dynamics || !wet || !carry) return 0;
    if(src && carry->pickup>0.f && wet->wetness>0.f &&
       !src->eraser && !samples) return 0;
    return strokeImpl(src,state,dirty,tip,mask,flow,pressureOpacity,
                      clip,direction,dynamics,wet,carry,samples);
}

extern "C" int32_t inkora_core_stroke(const InkoraStroke* src) {
    InkoraStrokeState state{0,0};
    InkoraRect dirty{0,0,0,0};
    return inkora_core_stroke_v2(src,&state,&dirty);
}
