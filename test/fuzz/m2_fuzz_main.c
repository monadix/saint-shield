/* SPDX-License-Identifier: Apache-2.0 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#ifndef SAINT_FUZZ_FUNCTION
#error "SAINT_FUZZ_FUNCTION must name the Zig export"
#endif
#ifndef SAINT_FUZZ_NEGATIVE_FUNCTION
#error "SAINT_FUZZ_NEGATIVE_FUNCTION must name the Zig negative-control export"
#endif

#define MAX_INPUT_BYTES 4096U

extern int SAINT_FUZZ_FUNCTION(const uint8_t *data, size_t length);
extern int SAINT_FUZZ_NEGATIVE_FUNCTION(const uint8_t *data, size_t length);

int
main(int argc, char **argv)
{
    uint8_t bytes[MAX_INPUT_BYTES];
    FILE *input;
    size_t length;
    int outcome;

    if (argc != 2)
        return 2;
    input = fopen(argv[1], "rb");
    if (input == NULL)
        return 2;
    length = fread(bytes, 1, sizeof(bytes), input);
    if (ferror(input) != 0 ||
        (length == sizeof(bytes) && fgetc(input) != EOF)) {
        fclose(input);
        return 2;
    }
    fclose(input);
    if (getenv("SAINT_M2_NEGATIVE_CONTROL") != NULL)
        outcome = SAINT_FUZZ_NEGATIVE_FUNCTION(bytes, length);
    else
        outcome = SAINT_FUZZ_FUNCTION(bytes, length);
    if (getenv("SAINT_M2_REPRODUCE") != NULL)
        printf("M2 bounded outcome: %d\n", outcome);
    return outcome >= 0 && outcome <= 5 ? 0 : 3;
}
