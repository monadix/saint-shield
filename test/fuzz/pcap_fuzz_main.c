/* SPDX-License-Identifier: Apache-2.0 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define MAX_INPUT_BYTES (1024U * 1024U)

extern int saint_pcap_fuzz(const uint8_t *data, size_t length);

static const char *
outcome_name(int outcome)
{
    switch (outcome) {
    case 0:
        return "valid";
    case 1:
        return "truncated";
    case 2:
        return "malformed";
    case 3:
        return "unsupported";
    case 4:
        return "limit";
    case 5:
        return "arithmetic";
    default:
        return "internal-invalid-outcome";
    }
}

int
main(int argc, char **argv)
{
    uint8_t *bytes;
    FILE *input;
    size_t length;
    int outcome;

    if (argc != 2)
        return 2;
    input = fopen(argv[1], "rb");
    if (input == NULL)
        return 2;
    bytes = malloc(MAX_INPUT_BYTES);
    if (bytes == NULL) {
        fclose(input);
        return 2;
    }
    length = fread(bytes, 1, MAX_INPUT_BYTES, input);
    if (ferror(input) != 0 ||
        (length == MAX_INPUT_BYTES && fgetc(input) != EOF)) {
        free(bytes);
        fclose(input);
        return 2;
    }
    fclose(input);

    outcome = saint_pcap_fuzz(bytes, length);
    free(bytes);
    if (getenv("SAINT_PCAP_REPRODUCE") != NULL)
        printf("pcap parse outcome: %s (%d)\n", outcome_name(outcome), outcome);
    return outcome >= 0 && outcome <= 5 ? 0 : 3;
}
