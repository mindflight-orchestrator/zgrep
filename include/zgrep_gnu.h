#ifndef ZGREP_GNU_H
#define ZGREP_GNU_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define ZG_REGEX_SYNTAX_BASIC 0
#define ZG_REGEX_SYNTAX_EXTENDED 1
#define ZG_REGEX_SYNTAX_PERL 2

#define ZG_LOCALE_CLASS_ALNUM (1u << 0)
#define ZG_LOCALE_CLASS_ALPHA (1u << 1)
#define ZG_LOCALE_CLASS_BLANK (1u << 2)
#define ZG_LOCALE_CLASS_DIGIT (1u << 3)
#define ZG_LOCALE_CLASS_GRAPH (1u << 4)
#define ZG_LOCALE_CLASS_LOWER (1u << 5)
#define ZG_LOCALE_CLASS_PRINT (1u << 6)
#define ZG_LOCALE_CLASS_PUNCT (1u << 7)
#define ZG_LOCALE_CLASS_UPPER (1u << 8)
#define ZG_LOCALE_CLASS_XDIGIT (1u << 9)

typedef struct zg_posix_regex zg_posix_regex;

bool zg_initialize_locale(void);
bool zg_locale_is_utf8(void);
bool zg_locale_has_simple_ascii_casefold(void);
bool zg_locale_has_standard_ascii_classes(void);
bool zg_locale_ascii_case_literal_matches(
    const uint8_t *subject,
    size_t subject_len,
    const uint8_t *pattern,
    size_t pattern_len
);
bool zg_locale_ascii_literal_word_matches(
    const uint8_t *subject,
    size_t subject_len,
    const uint8_t *pattern,
    size_t pattern_len
);
bool zg_locale_class_run_matches(
    const uint8_t *subject,
    size_t subject_len,
    uint64_t ascii_mask_low,
    uint64_t ascii_mask_high,
    uint32_t classes,
    size_t minimum
);

zg_posix_regex *zg_posix_compile(
    const uint8_t *pattern,
    size_t pattern_len,
    int syntax,
    bool ignore_case,
    bool line_regexp,
    bool word_regexp,
    char *error_buffer,
    size_t error_buffer_len
);
bool zg_posix_find(
    const zg_posix_regex *regex,
    const uint8_t *subject,
    size_t subject_len,
    size_t start_offset,
    size_t *match_start,
    size_t *match_end
);
bool zg_posix_matches(
    const zg_posix_regex *regex,
    const uint8_t *subject,
    size_t subject_len
);
void zg_posix_free(zg_posix_regex *regex);

#endif
