#ifndef ZGREP_PCRE2_H
#define ZGREP_PCRE2_H

#include "zgrep_gnu.h"

typedef struct zg_regex zg_regex;
typedef struct zg_regex_worker zg_regex_worker;

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
