#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// Reveals the handwritten wordmark where the pen has arrived. `arrival`'s
/// alpha holds when the pen reaches each point (0 to 1, from
/// scripts/generate-logo-arrival.py); `feather` softens the pen's leading edge.
/// Progress is stretched so 0 shows nothing, even where the pen starts, and 1
/// shows everything.
[[ stitchable ]] half4 zenReveal(float2 position, half4 color, texture2d<half> arrival,
                                 float2 size, float progress, float feather) {
    constexpr sampler bilinear(address::clamp_to_edge, filter::linear);
    float reached = arrival.sample(bilinear, position / size).a;
    return color * half(saturate((progress * (1.0 + feather) - reached) / feather));
}
