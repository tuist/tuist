#ifndef VC_COMMON_ERROR_INL
#define VC_COMMON_ERROR_INL

static inline int vc_error_or(int fallback) {
    int error = vc_last_error();
    return error != 0 ? error : fallback;
}

#endif
