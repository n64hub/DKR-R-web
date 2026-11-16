// A web page's Mod Store image overlay: none. The page has no Mod Store (it needs the network), and its RT64 draws
// through WebGPU, which overlay_images.cpp's Vulkan and D3D12 descriptors don't reach. Every image is "not ready",
// which the overlay's callers already handle for an upload that failed.
#include "overlay_images.hpp"

namespace dkr::store::overlay {
void begin(RT64::Application&) {}
void end() {}
View image(const std::string&, unsigned, unsigned, std::span<const unsigned char>) {
    return {};
}
void release() {}
} // namespace dkr::store::overlay
