// src/core/result.h -- typed results at module boundaries.
//
// House rule (CLAUDE.md, Code standards): errors cross module boundaries as
// typed results, never as exceptions. Kernels cannot throw, so a Result-shaped
// boundary keeps host and device error handling the same shape.
#pragma once

#include <cstdint>

namespace astro {

enum class Status : int32_t {
    Ok = 0,
    OutOfMemory,
    CudaError,
    InvalidArgument,
    NotFound,
    ParseError,
    ContractVersionMismatch,
    CapacityExceeded,
    FileIoError,
    Unsupported,
};

inline const char* status_str(Status s) {
    switch (s) {
        case Status::Ok:                      return "Ok";
        case Status::OutOfMemory:             return "OutOfMemory";
        case Status::CudaError:               return "CudaError";
        case Status::InvalidArgument:         return "InvalidArgument";
        case Status::NotFound:                return "NotFound";
        case Status::ParseError:              return "ParseError";
        case Status::ContractVersionMismatch: return "ContractVersionMismatch";
        case Status::CapacityExceeded:        return "CapacityExceeded";
        case Status::FileIoError:             return "FileIoError";
        case Status::Unsupported:             return "Unsupported";
    }
    return "Unknown";
}

struct Error {
    Status      status = Status::Ok;
    const char* detail = nullptr;   // static string; never owns
    explicit operator bool() const { return status != Status::Ok; }
};

inline Error ok() { return Error{}; }
inline Error fail(Status s, const char* detail) { return Error{s, detail}; }

#define ASTRO_TRY(expr)                              \
    do {                                             \
        ::astro::Error _e = (expr);                  \
        if (_e) return _e;                           \
    } while (0)

} // namespace astro
