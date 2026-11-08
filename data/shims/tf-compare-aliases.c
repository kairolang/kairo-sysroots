#define QUAD_PRECISION
#include "fp_lib.h"
#if defined(CRT_HAS_TF_MODE)
#include "fp_compare_impl.inc"
COMPILER_RT_ABI CMP_RESULT __letf2(fp_t a, fp_t b);
COMPILER_RT_ABI CMP_RESULT __getf2(fp_t a, fp_t b);
COMPILER_RT_ABI CMP_RESULT __cmptf2(fp_t a, fp_t b) { return __letf2(a, b); }
COMPILER_RT_ABI CMP_RESULT __eqtf2(fp_t a, fp_t b) { return __letf2(a, b); }
COMPILER_RT_ABI CMP_RESULT __lttf2(fp_t a, fp_t b) { return __letf2(a, b); }
COMPILER_RT_ABI CMP_RESULT __netf2(fp_t a, fp_t b) { return __letf2(a, b); }
COMPILER_RT_ABI CMP_RESULT __gttf2(fp_t a, fp_t b) { return __getf2(a, b); }
#else
#error "no TF mode on this target"
#endif
