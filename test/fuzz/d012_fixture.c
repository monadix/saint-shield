/* SPDX-License-Identifier: Apache-2.0 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void
exercise_fixture(const uint8_t *data, size_t length)
{
    if (length >= 4 && memcmp(data, "HANG", 4) == 0) {
        volatile uint64_t counter = 0;
        for (;;)
            counter++;
    }

    if (length >= 4 && data[0] == 'M' && data[1] == '0' &&
        data[2] == 'V' && data[3] == '!') {
        /* Intentional local test defect: ASan must report this read. */
        volatile uint8_t observed = data[length + 8];
        (void)observed;
    }
}

int
main(int argc, char **argv)
{
    if (argc != 2)
        return 2;
    FILE *input = fopen(argv[1], "rb");
    if (input == NULL)
        return 2;
    if (fseek(input, 0, SEEK_END) != 0)
        return 2;
    long size = ftell(input);
    if (size < 0 || size > 4096)
        return 2;
    rewind(input);
    size_t length = (size_t)size;
    uint8_t *bytes = malloc(length == 0 ? 1 : length);
    if (bytes == NULL)
        return 2;
    if (length != 0 && fread(bytes, 1, length, input) != length)
        return 2;
    fclose(input);
    exercise_fixture(bytes, length);
    free(bytes);
    return 0;
}

