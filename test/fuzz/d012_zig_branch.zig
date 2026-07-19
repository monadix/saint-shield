// SPDX-License-Identifier: Apache-2.0

/// Exercises byte-dependent control flow compiled by Zig 0.16.0. The C launcher
/// performs no content-dependent work before or after a zero return value, so
/// differing AFL++ QEMU maps for safe equal-length inputs originate here.
export fn saint_d012_zig_branch(data: [*]const u8, length: usize) c_int {
    if (length >= 4 and data[0] == 'H' and data[1] == 'A' and
        data[2] == 'N' and data[3] == 'G')
    {
        while (true) {}
    }

    if (length >= 1 and data[0] == 'M') {
        if (length >= 2 and data[1] == '0') {
            if (length >= 3 and data[2] == 'V') {
                if (length >= 4 and data[3] == '!')
                    return 77;
            }
        }
    }
    return 0;
}
