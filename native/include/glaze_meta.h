// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Joel Winarske
#pragma once
/*
 * glaze_meta.h — Glaze-compatible compile-time reflection + binary I/O
 *
 * Provides a subset of the `glz::` API from the glaze library
 * (https://github.com/stephenberry/glaze) implemented entirely with
 * C++23 standard library features — no external dependencies.
 *
 * Why glaze-compatible instead of just using glaze?
 * ─────────────────────────────────────────────────
 * The real glaze library is header-only and can be dropped in directly
 * (replace this file with `#include <glaze/glaze.hpp>`).  Using the same
 * `glz::` namespace and `glz::meta<T>` specialization pattern means the
 * user code that registers types is identical either way.
 *
 * Wire format
 * ───────────
 * We use BEVE-Lite: a compact binary format inspired by glaze's native
 * binary format.
 *
 *   • Primitives: raw little-endian bytes (no type tags for known types).
 *   • Strings:    uint64 length prefix + UTF-8 bytes.
 *   • Arrays:     uint64 element count + N × element.
 *   • Structs:    fields in declaration order (from glz::meta<T>::fields).
 *   • Optionals:  1-byte present flag + value (if present).
 *   • Vec<T>:     same as array.
 *
 * There are no field names on the wire — the schema is the order of fields
 * in the glz::meta<T> specialization.  This is identical to bincode.
 *
 * C++23 features used
 * ───────────────────
 *   std::tuple + fold expressions   iterate field lists at compile time
 *   Concepts                        constrain write<T>/read<T>
 *   if constexpr                    branch on type traits without SFINAE
 *   Structured bindings             glz::each() over tuple elements
 *   std::span                       zero-copy buffer views
 *   [[assume(cond)]]                optimizer hints
 */

#include <algorithm>
#include <bit>
#include <concepts>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <optional>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <tuple>
#include <type_traits>
#include <vector>

namespace glz {

// ─────────────────────────────────────────────────────────────────────────
// §1  meta<T> and field() — user-facing registration API
// ─────────────────────────────────────────────────────────────────────────

/// Opaque descriptor for one field: name + member-pointer.
template <typename Struct, typename FieldT>
struct NamedField {
    std::string_view name;
    FieldT Struct::* ptr;
};

/// Factory: glz::field("name", &T::member)
template <typename Struct, typename FieldT>
[[nodiscard]] constexpr auto field(std::string_view name, FieldT Struct::* ptr) noexcept {
    return NamedField<Struct, FieldT>{name, ptr};
}

/// Specialize glz::meta<T> to register a type:
///
///   template<> struct glz::meta<MyStruct> {
///       static constexpr auto fields = std::make_tuple(
///           glz::field("x", &MyStruct::x),
///           glz::field("y", &MyStruct::y)
///       );
///   };
template <typename T>
struct meta {
    // No default — unregistered types cause a compile error if you try
    // to call write<T> or read<T> on them.
};

// ─────────────────────────────────────────────────────────────────────────
// §2  Internal helpers
// ─────────────────────────────────────────────────────────────────────────

namespace detail {

/// Apply fn to every element of a tuple.
template <typename Tuple, typename F, std::size_t... Is>
constexpr void each_impl(Tuple& t, F&& f, std::index_sequence<Is...>) {
    (f(std::get<Is>(t)), ...);
}

template <typename Tuple, typename F>
constexpr void each(Tuple& t, F&& f) {
    constexpr auto N = std::tuple_size_v<std::remove_reference_t<Tuple>>;
    each_impl(t, std::forward<F>(f), std::make_index_sequence<N>{});
}

/// True if T has a glz::meta<T>::fields specialization.
template <typename T>
concept Reflectable = requires { glz::meta<T>::fields; };

/// True if T is a std::optional<U>.
template <typename T>
struct is_optional : std::false_type {};
template <typename U>
struct is_optional<std::optional<U>> : std::true_type {};
template <typename T>
constexpr bool is_optional_v = is_optional<T>::value;

/// True if T is a std::vector<U>.
template <typename T>
struct is_vector : std::false_type {};
template <typename U>
struct is_vector<std::vector<U>> : std::true_type {};
template <typename T>
constexpr bool is_vector_v = is_vector<T>::value;

/// True if T is a std::string or std::string_view.
template <typename T>
constexpr bool is_string_v = std::is_same_v<T, std::string> || std::is_same_v<T, std::string_view>;

}  // namespace detail

// ─────────────────────────────────────────────────────────────────────────
// §3  Writer — serialize to a growing byte buffer
// ─────────────────────────────────────────────────────────────────────────

class Writer {
   public:
    std::vector<uint8_t> buf;

    // ── Primitive writers ─────────────────────────────────────────────────

    template <typename T>
        requires(std::is_arithmetic_v<T> && !std::is_same_v<T, bool>)
    void write(T v) noexcept {
        const auto* p = reinterpret_cast<const uint8_t*>(&v);
        buf.insert(buf.end(), p, p + sizeof(T));
    }

    void write(bool v) noexcept {
        buf.push_back(static_cast<uint8_t>(v ? 1u : 0u));
    }

    void write(std::string_view s) {
        write<uint64_t>(s.size());
        buf.insert(buf.end(), s.begin(), s.end());
    }

    void write(const std::string& s) {
        write(std::string_view{s});
    }

    // ── Optional writer ───────────────────────────────────────────────────

    template <typename T>
    void write(const std::optional<T>& opt) {
        write<uint8_t>(opt.has_value() ? 1u : 0u);
        if (opt)
            write(*opt);
    }

    // ── Vector writer ─────────────────────────────────────────────────────

    template <typename T>
    void write(const std::vector<T>& vec) {
        write<uint64_t>(vec.size());
        for (const auto& v : vec) write(v);
    }

    // ── Span writer (zero-copy read path — write bytes directly) ─────────

    template <typename T>
        requires std::is_arithmetic_v<T>
    void write_span(std::span<const T> s) {
        write<uint64_t>(s.size());
        const auto* p = reinterpret_cast<const uint8_t*>(s.data());
        buf.insert(buf.end(), p, p + s.size_bytes());
    }

    // ── Reflectable struct writer ─────────────────────────────────────────

    template <detail::Reflectable T>
    void write(const T& obj) {
        auto fields = glz::meta<T>::fields;
        detail::each(fields, [&](auto& f) { write(obj.*(f.ptr)); });
    }

    // ── Zero-copy export for kExternalTypedData ───────────────────────────

    /// Move internal buffer out as a malloc'd allocation.
    /// Caller is responsible for free().
    [[nodiscard]] uint8_t* release(std::size_t& out_len) {
        out_len = buf.size();
        auto* p = static_cast<uint8_t*>(std::malloc(buf.size()));
        if (!p)
            std::abort();
        std::memcpy(p, buf.data(), buf.size());
        return p;
    }

    void clear() noexcept {
        buf.clear();
    }
    [[nodiscard]] std::size_t size() const noexcept {
        return buf.size();
    }

    /// Return a span view of the buffer (no allocation).
    [[nodiscard]] std::span<const uint8_t> view() const noexcept {
        return {buf.data(), buf.size()};
    }
};

// ─────────────────────────────────────────────────────────────────────────
// §4  Reader — deserialize from a byte span (zero-copy for primitives)
// ─────────────────────────────────────────────────────────────────────────

class Reader {
   public:
    const uint8_t* p;
    const uint8_t* end;

    explicit Reader(std::span<const uint8_t> data) noexcept
        : p(data.data()), end(data.data() + data.size()) {
    }

    Reader(const uint8_t* begin, const uint8_t* end) noexcept : p(begin), end(end) {
    }

    [[nodiscard]] bool has_data(std::size_t n = 1) const noexcept {
        return p + n <= end;
    }

    // ── Primitive readers ─────────────────────────────────────────────────

    template <typename T>
        requires(std::is_arithmetic_v<T> && !std::is_same_v<T, bool>)
    [[nodiscard]] T read() {
        if (p + sizeof(T) > end)
            throw std::out_of_range("glz::Reader: read past end of buffer");
        T v;
        std::memcpy(&v, p, sizeof(T));
        p += sizeof(T);
        return v;
    }

    // bool is serialized as a single byte (0 or 1)
    [[nodiscard]] bool read_bool() {
        if (p >= end)
            throw std::out_of_range("glz::Reader: read_bool past end of buffer");
        return static_cast<bool>(*p++);
    }

    [[nodiscard]] std::string read_string() {
        auto n = read<uint64_t>();
        if (p + n > end)
            throw std::out_of_range("glz::Reader: string length exceeds buffer");
        std::string s(reinterpret_cast<const char*>(p), n);
        p += n;
        return s;
    }

    // Zero-copy string view — valid only as long as the source buffer lives.
    [[nodiscard]] std::string_view read_string_view() {
        auto n = read<uint64_t>();
        if (p + n > end)
            throw std::out_of_range("glz::Reader: string_view length exceeds buffer");
        std::string_view sv{reinterpret_cast<const char*>(p), n};
        p += n;
        return sv;
    }

    // Zero-copy span of arithmetic elements — no copy.
    template <typename T>
        requires std::is_arithmetic_v<T>
    [[nodiscard]] std::span<const T> read_span() {
        auto n = read<uint64_t>();
        if (p + n * sizeof(T) > end)
            throw std::out_of_range("glz::Reader: span length exceeds buffer");
        auto sp = std::span<const T>{reinterpret_cast<const T*>(p), n};
        p += n * sizeof(T);
        return sp;
    }

    // ── Optional reader ───────────────────────────────────────────────────

    template <typename T>
    [[nodiscard]] std::optional<T> read_optional() {
        bool present = read_bool();
        if (!present)
            return std::nullopt;
        return read_value<T>();
    }

    // ── Vector reader ─────────────────────────────────────────────────────

    template <typename T>
    [[nodiscard]] std::vector<T> read_vector() {
        auto n = read<uint64_t>();
        std::vector<T> v;
        v.reserve(n);
        for (uint64_t i = 0; i < n; ++i) v.push_back(read_value<T>());
        return v;
    }

    // ── Primitive value reader (for vector<T> where T is arithmetic) ──────

    template <typename T>
        requires(std::is_arithmetic_v<T>)
    [[nodiscard]] T read_value() {
        return read<T>();
    }

    // ── String value reader (for vector<string>) ───────────────────────────

    template <typename T>
        requires(detail::is_string_v<T>)
    [[nodiscard]] T read_value() {
        return read_string();
    }

    // ── Reflectable struct reader ─────────────────────────────────────────

    template <detail::Reflectable T>
    [[nodiscard]] T read_value() {
        T obj{};
        auto fields = glz::meta<T>::fields;
        detail::each(fields, [&](auto& f) {
            using FT = std::remove_reference_t<decltype(obj.*(f.ptr))>;
            if constexpr (detail::Reflectable<FT>) {
                obj.*(f.ptr) = read_value<FT>();
            } else if constexpr (detail::is_optional_v<FT>) {
                using U = typename FT::value_type;
                obj.*(f.ptr) = read_optional<U>();
            } else if constexpr (detail::is_vector_v<FT>) {
                using U = typename FT::value_type;
                obj.*(f.ptr) = read_vector<U>();
            } else if constexpr (detail::is_string_v<FT>) {
                obj.*(f.ptr) = read_string();
            } else if constexpr (std::is_same_v<FT, bool>) {
                obj.*(f.ptr) = read_bool();
            } else if constexpr (std::is_arithmetic_v<FT>) {
                obj.*(f.ptr) = read<FT>();
            }
        });
        return obj;
    }
};

// ─────────────────────────────────────────────────────────────────────────
// §5  Convenience free functions mirroring the glaze API
// ─────────────────────────────────────────────────────────────────────────

/// Serialize [v] into a Writer, return the buffer.
template <typename T>
[[nodiscard]] std::vector<uint8_t> write_binary(const T& v) {
    Writer w;
    w.write(v);
    return std::move(w.buf);
}

/// Deserialize [bytes] into T.
template <typename T>
[[nodiscard]] T read_binary(std::span<const uint8_t> bytes) {
    Reader r{bytes};
    return r.read_value<T>();
}

/// Deserialize [bytes] into an existing [out].  Returns true on success.
template <typename T>
bool read_binary(std::span<const uint8_t> bytes, T& out) {
    try {
        Reader r{bytes};
        out = r.read_value<T>();
        return true;
    } catch (...) {
        return false;
    }
}

}  // namespace glz