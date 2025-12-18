//
// RT64
//

#pragma once

#include "shared/rt64_hlsl.h"

#ifdef HLSL_CPU
namespace interop {
#endif
    struct VideoInterfaceCB {
        float2 videoResolution;
        float2 textureResolution;
        float gamma;
        uint viFlags;
        uint viFlagsPadding0;
        uint viFlagsPadding1;
    };
#ifdef HLSL_CPU
};
#endif
