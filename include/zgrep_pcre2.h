#ifndef ZGREP_PCRE2_H
#define ZGREP_PCRE2_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct zg_regex zg_regex;
typedef struct zg_regex_worker zg_regex_worker;

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

zg_regex *zg_regex_compile(
    const uint8_t *pcre_pattern,
    size_t pcre_pattern_len,
    const uint8_t *posix_pattern,
    size_t posix_pattern_len,
    int syntax,
    bool pcre_compatible,
    bool ascii_witness,
    bool posix_spans,
    bool ignore_case,
    bool dot_matches_newline,
    bool line_regexp,
    bool word_regexp,
    char *error_buffer,
    size_t error_buffer_len
);

bool zg_regex_matches(zg_regex *regex, const uint8_t *subject, size_t subject_len);
bool zg_regex_posix_matches(zg_regex *regex, const uint8_t *subject, size_t subject_len);
bool zg_regex_uses_pcre(const zg_regex *regex);
bool zg_regex_find(
    zg_regex *regex,
    const uint8_t *subject,
    size_t subject_len,
    size_t start_offset,
    size_t *match_start,
    size_t *match_end
);
bool zg_regex_pcre_find(
    zg_regex *regex,
    const uint8_t *subject,
    size_t subject_len,
    size_t start_offset,
    size_t *match_start,
    size_t *match_end
);
zg_regex_worker *zg_regex_worker_create(const zg_regex *regex);
bool zg_regex_worker_matches(
    zg_regex_worker *worker,
    const uint8_t *subject,
    size_t subject_len
);
bool zg_regex_worker_ascii_witness_matches(
    zg_regex_worker *worker,
    const uint8_t *subject,
    size_t subject_len
);
bool zg_regex_worker_posix_matches(
    zg_regex_worker *worker,
    const uint8_t *subject,
    size_t subject_len
);
void zg_regex_worker_free(zg_regex_worker *worker);
void zg_regex_free(zg_regex *regex);

#endif
