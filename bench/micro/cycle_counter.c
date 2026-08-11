// SPDX-License-Identifier: Apache-2.0
#include <stdint.h>

#if defined(__x86_64__)
#include <x86intrin.h>

uint64_t saint_cycle_begin(void) {
    _mm_lfence();
    return __rdtsc();
}

uint64_t saint_cycle_end(void) {
    unsigned int auxiliary;
    uint64_t value = __rdtscp(&auxiliary);
    _mm_lfence();
    return value;
}
#else
#error "M2 host-local cycle evidence currently requires x86_64"
#endif
