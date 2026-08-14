// flatpak_post.h — Shared Dart_PostCObject_DL helpers.
//
// Two ways to hand bytes to Dart:
//
//   post_owned  Transfers ownership of a heap buffer to the VM, which releases
//               it through the finalizer once the message is collected. The
//               bytes are not copied on send.
//   post_copy   Copies the bytes. Correct for stack buffers, and cheaper than a
//               heap allocation plus finalizer round trip for the one-byte
//               sentinels.
//
// These live in a header because all three bridge translation units post the
// same wire format and previously each carried its own copy of the helpers.

#pragma once
#include <cstdint>
#include <cstring>
#include <utility>
#include <vector>

#include "flatpak_bridge.h"

namespace flatpak_nc {

namespace detail {

inline void release_buffer(void* /*isolate_callback_data*/, void* peer) {
    delete static_cast<std::vector<uint8_t>*>(peer);
}

}  // namespace detail

// Hands ownership of buf to the VM.
//
// Per Dart_PostCObject: when it returns true the finalizer eventually runs even
// if the receiving isolate shuts down before processing the message. When it
// returns false the message was not enqueued and ownership remains with the
// caller, so the buffer is released here instead.
inline void post_owned(Dart_Port port, std::vector<uint8_t>&& buf) {
    auto* owned = new std::vector<uint8_t>(std::move(buf));
    Dart_CObject obj;
    obj.type = Dart_CObject_kExternalTypedData;
    obj.value.as_external_typed_data.type = Dart_TypedData_kUint8;
    obj.value.as_external_typed_data.length = static_cast<intptr_t>(owned->size());
    obj.value.as_external_typed_data.data = owned->data();
    obj.value.as_external_typed_data.peer = owned;
    obj.value.as_external_typed_data.callback = detail::release_buffer;
    if (!Dart_PostCObject_DL(port, &obj)) {
        delete owned;
    }
}

// Copies len bytes. For stack buffers and payloads too small to be worth a heap
// allocation.
inline void post_copy(Dart_Port port, const uint8_t* data, size_t len) {
    Dart_CObject obj;
    obj.type = Dart_CObject_kTypedData;
    obj.value.as_typed_data.type = Dart_TypedData_kUint8;
    obj.value.as_typed_data.length = static_cast<intptr_t>(len);
    obj.value.as_typed_data.values = data;
    Dart_PostCObject_DL(port, &obj);
}

// Frames a payload as [discriminator][payload] and hands it to the VM.
inline void post_framed(Dart_Port port, uint8_t discriminator, const uint8_t* data, size_t len) {
    std::vector<uint8_t> buf(1 + len);
    buf[0] = discriminator;
    if (len > 0) {
        std::memcpy(buf.data() + 1, data, len);
    }
    post_owned(port, std::move(buf));
}

// Frames an error as [discriminator][uint32_t length][UTF-8 message].
inline void post_framed_error(Dart_Port port, uint8_t discriminator, const char* msg) {
    const auto len = static_cast<uint32_t>(std::strlen(msg));
    std::vector<uint8_t> buf(1 + sizeof(uint32_t) + len);
    buf[0] = discriminator;
    std::memcpy(buf.data() + 1, &len, sizeof(uint32_t));
    std::memcpy(buf.data() + 1 + sizeof(uint32_t), msg, len);
    post_owned(port, std::move(buf));
}

}  // namespace flatpak_nc
