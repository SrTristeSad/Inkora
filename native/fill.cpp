#include "inkora_core.h"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

namespace {
uint8_t channel(float f) {
    return static_cast<uint8_t>(std::lround(std::max(0.0f,std::min(1.0f,f))*255.0f));
}
bool similar(const uint8_t *p,const uint8_t *target,float tolerance) {
    for(int k=0;k<4;++k)
        if(std::abs(int(p[k])-int(target[k]))/255.0f>tolerance) return false;
    return true;
}
}
// Flood fill in-place on the caller's CPU ImageData, returning exact dirty
// bounds; pixel coordinates are global, selection edges are exclusive.
extern "C" int32_t inkora_core_fill_v13(const InkoraFill *args,InkoraRect *dirty) {
    if(!args || !dirty) return 0;
    *dirty={0,0,0,0};
    const InkoraFill& f=*args;
    if(!f.pixels || f.width<1 || f.height<1 || f.width>16384 || f.height>16384 ||
       f.x<0 || f.y<0 || f.x>=f.width || f.y>=f.height ||
       f.alpha_lock<0 || f.alpha_lock>1 ||
       f.selection_enabled<0 || f.selection_enabled>1 ||
       !std::isfinite(f.r) || !std::isfinite(f.g) || !std::isfinite(f.b) ||
       !std::isfinite(f.tolerance) || f.tolerance<0 || f.tolerance>1 ||
       int64_t(f.stride)<int64_t(f.width)*4) return 0;
    const uint64_t needed=uint64_t(f.height-1)*uint64_t(f.stride)+uint64_t(f.width)*4;
    if(f.buffer_bytes<needed) return 0;
    if(f.selection_enabled && (f.left<0 || f.top<0 || f.right>f.width ||
       f.bottom>f.height || f.left>=f.right || f.top>=f.bottom)) return 0;
    auto allowed=[&](int x,int y){
        return x>=0 && y>=0 && x<f.width && y<f.height &&
            (!f.selection_enabled ||
             (x>=f.left && x<f.right && y>=f.top && y<f.bottom));
    };
    if(!allowed(f.x,f.y)) return 1;
    auto at=[&](int x,int y)->uint8_t* {
        return f.pixels+size_t(y)*size_t(f.stride)+size_t(x)*4u;
    };
    uint8_t target[4];
    for(int k=0;k<4;++k) target[k]=at(f.x,f.y)[k];
    if(f.alpha_lock && target[3]==0) return 1;
    const uint8_t color[3]={channel(f.r),channel(f.g),channel(f.b)};
    const uint8_t replacement[4]={color[0],color[1],color[2],
        static_cast<uint8_t>(f.alpha_lock?target[3]:255)};
    if(similar(replacement,target,f.tolerance)) return 1;
    const size_t count=size_t(f.width)*size_t(f.height);
    std::vector<uint8_t> visited(count,0);
    std::vector<size_t> pending{size_t(f.y)*size_t(f.width)+size_t(f.x)};
    int minX=f.width,minY=f.height,maxX=-1,maxY=-1;
    auto matches=[&](int x,int y){
        if(!allowed(x,y) || visited[size_t(y)*size_t(f.width)+size_t(x)]) return false;
        const uint8_t *p=at(x,y);
        return (!f.alpha_lock || p[3]>0) && similar(p,target,f.tolerance);
    };
    while(!pending.empty()) {
        const size_t pos=pending.back();
        pending.pop_back();
        const int sy=int(pos/size_t(f.width)),sx=int(pos%size_t(f.width));
        if(!matches(sx,sy)) continue;
        int left=sx,right=sx;
        while(left>0 && matches(left-1,sy)) --left;
        while(right+1<f.width && matches(right+1,sy)) ++right;
        for(int x=left;x<=right;++x) {
            uint8_t *p=at(x,sy);
            p[0]=color[0];p[1]=color[1];p[2]=color[2];
            if(!f.alpha_lock) p[3]=255;
            visited[size_t(sy)*size_t(f.width)+size_t(x)]=1;
        }
        minX=std::min(minX,left);maxX=std::max(maxX,right);
        minY=std::min(minY,sy);maxY=std::max(maxY,sy);
        for(int ny : {sy-1,sy+1}) {
            if(ny<0 || ny>=f.height) continue;
            int x=left;
            while(x<=right) {
                if(matches(x,ny)) {
                    pending.push_back(size_t(ny)*size_t(f.width)+size_t(x));
                    do { ++x; } while(x<=right && matches(x,ny));
                } else ++x;
            }
        }
    }
    if(maxX>=minX) *dirty={minX,minY,maxX-minX+1,maxY-minY+1};
    return 1;
}
