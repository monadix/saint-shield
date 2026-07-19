/* SPDX-License-Identifier: Apache-2.0 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

extern int saint_d012_zig_branch(const uint8_t *data, size_t length);

int
main(int argc, char **argv)
{
    uint8_t bytes[4096];
    if (argc != 2)
        return 2;
    FILE *input = fopen(argv[1], "rb");
    if (input == NULL)
        return 2;
    size_t length = fread(bytes, 1, sizeof(bytes), input);
    if (ferror(input) != 0 || (length == sizeof(bytes) && fgetc(input) != EOF)) {
        fclose(input);
        return 2;
    }
    fclose(input);

    if (saint_d012_zig_branch(bytes, length) == 77)
        abort();
    return 0;
}
