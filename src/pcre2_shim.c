#define _GNU_SOURCE
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>

#include "zgrep_pcre2.h"

#include <stdio.h>
#include <stdlib.h>
#include <regex.h>

struct zg_regex {
    pcre2_code *code;
    pcre2_match_data *match_data;
    pcre2_match_data *dfa_match_data;
    int *dfa_workspace;
    regex_t posix;
    bool has_posix;
    bool line_regexp;
    bool word_regexp;
    bool jit;
};

struct zg_regex_worker {
    const zg_regex *regex;
    pcre2_match_data *match_data;
};

static bool zg_is_word_byte(uint8_t byte) {
    return (byte >= 'a' && byte <= 'z')
        || (byte >= 'A' && byte <= 'Z')
        || (byte >= '0' && byte <= '9')
        || byte == '_';
}

static bool zg_posix_find(
    const zg_regex *regex,
    const uint8_t *subject,
    size_t subject_len,
    size_t start_offset,
    size_t *match_start,
    size_t *match_end
) {
    size_t search_offset = start_offset;
    while (search_offset <= subject_len) {
        regmatch_t match = {
            .rm_so = (regoff_t)search_offset,
            .rm_eo = (regoff_t)subject_len,
        };
        int flags = REG_STARTEND;
        if (search_offset != 0) flags |= REG_NOTBOL;
        if (regexec(&regex->posix, (const char *)subject, 1, &match, flags) != 0) {
            return false;
        }

        const size_t start = (size_t)match.rm_so;
        const size_t end = (size_t)match.rm_eo;
        if (regex->line_regexp && (start != 0 || end != subject_len)) {
            return false;
        }
        if (regex->word_regexp) {
            const bool left = start == 0 || !zg_is_word_byte(subject[start - 1]);
            const bool right = end == subject_len || !zg_is_word_byte(subject[end]);
            if (!left || !right) {
                if (start == subject_len) return false;
                search_offset = start + 1;
                continue;
            }
        }

        *match_start = start;
        *match_end = end;
        return true;
    }
    return false;
}

static bool zg_compile_posix(
    zg_regex *regex,
    const uint8_t *pattern,
    size_t pattern_len,
    int syntax,
    bool ignore_case,
    char *error_buffer,
    size_t error_buffer_len
) {
    reg_syntax_t posix_syntax = syntax == ZG_REGEX_SYNTAX_EXTENDED
        ? RE_SYNTAX_EGREP
        : RE_SYNTAX_GREP;
    if (ignore_case) posix_syntax |= RE_ICASE;
    const reg_syntax_t previous_syntax = re_set_syntax(posix_syntax);
    const char *posix_error = re_compile_pattern(
        (const char *)pattern,
        pattern_len,
        &regex->posix
    );
    re_set_syntax(previous_syntax);
    if (posix_error != NULL) {
        snprintf(error_buffer, error_buffer_len, "invalid regular expression: %s", posix_error);
        return false;
    }
    regex->has_posix = true;
    return true;
}

zg_regex *zg_regex_compile(
    const uint8_t *pcre_pattern,
    size_t pcre_pattern_len,
    const uint8_t *posix_pattern,
    size_t posix_pattern_len,
    int syntax,
    bool pcre_compatible,
    bool posix_spans,
    bool ignore_case,
    bool dot_matches_newline,
    bool line_regexp,
    bool word_regexp,
    char *error_buffer,
    size_t error_buffer_len
) {
    zg_regex *regex = calloc(1, sizeof(*regex));
    if (regex == NULL) {
        snprintf(error_buffer, error_buffer_len, "out of memory compiling regex");
        return NULL;
    }
    regex->line_regexp = line_regexp;
    regex->word_regexp = word_regexp;

    if ((syntax == ZG_REGEX_SYNTAX_BASIC || syntax == ZG_REGEX_SYNTAX_EXTENDED)
        && (!pcre_compatible || posix_spans)) {
        if (!zg_compile_posix(
            regex,
            posix_pattern,
            posix_pattern_len,
            syntax,
            ignore_case,
            error_buffer,
            error_buffer_len
        )) {
            free(regex);
            return NULL;
        }
        if (!pcre_compatible) return regex;
    }

    int error_code = 0;
    PCRE2_SIZE error_offset = 0;
    uint32_t options = (ignore_case ? PCRE2_CASELESS : 0)
        | (dot_matches_newline ? PCRE2_DOTALL : 0);
    pcre2_code *code = pcre2_compile(
        pcre_pattern,
        pcre_pattern_len,
        options,
        &error_code,
        &error_offset,
        NULL
    );
    if (code == NULL) {
        if (regex->has_posix) return regex;
        if (syntax == ZG_REGEX_SYNTAX_BASIC || syntax == ZG_REGEX_SYNTAX_EXTENDED) {
            if (zg_compile_posix(
                regex,
                posix_pattern,
                posix_pattern_len,
                syntax,
                ignore_case,
                error_buffer,
                error_buffer_len
            )) return regex;
            free(regex);
            return NULL;
        }
        PCRE2_UCHAR message[192];
        int message_len = pcre2_get_error_message(error_code, message, sizeof(message));
        if (message_len < 0) {
            snprintf(error_buffer, error_buffer_len, "regex error at byte %zu", error_offset);
        } else {
            snprintf(
                error_buffer,
                error_buffer_len,
                "regex error at byte %zu: %s",
                error_offset,
                (const char *)message
            );
        }
        free(regex);
        return NULL;
    }

    pcre2_match_data *match_data = pcre2_match_data_create_from_pattern(code, NULL);
    if (match_data == NULL) {
        pcre2_code_free(code);
        if (regex->has_posix) return regex;
        free(regex);
        snprintf(error_buffer, error_buffer_len, "out of memory compiling regex");
        return NULL;
    }

    regex->code = code;
    regex->match_data = match_data;
    if (posix_spans && regex->has_posix) {
        regex->dfa_match_data = pcre2_match_data_create(128, NULL);
        regex->dfa_workspace = malloc(4096 * sizeof(*regex->dfa_workspace));
        if (regex->dfa_match_data == NULL || regex->dfa_workspace == NULL) {
            if (regex->dfa_match_data != NULL) pcre2_match_data_free(regex->dfa_match_data);
            free(regex->dfa_workspace);
            regex->dfa_match_data = NULL;
            regex->dfa_workspace = NULL;
        }
    }
    regex->jit = pcre2_jit_compile(code, PCRE2_JIT_COMPLETE) == 0;
    return regex;
}

bool zg_regex_matches(zg_regex *regex, const uint8_t *subject, size_t subject_len) {
    int result;
    if (regex->jit) {
        result = pcre2_jit_match(
            regex->code,
            subject,
            subject_len,
            0,
            0,
            regex->match_data,
            NULL
        );
    } else {
        result = pcre2_match(
            regex->code,
            subject,
            subject_len,
            0,
            0,
            regex->match_data,
            NULL
        );
    }
    return result >= 0;
}

bool zg_regex_posix_matches(zg_regex *regex, const uint8_t *subject, size_t subject_len) {
    size_t match_start;
    size_t match_end;
    return zg_posix_find(regex, subject, subject_len, 0, &match_start, &match_end);
}

bool zg_regex_uses_pcre(const zg_regex *regex) {
    return regex->code != NULL;
}

bool zg_regex_find(
    zg_regex *regex,
    const uint8_t *subject,
    size_t subject_len,
    size_t start_offset,
    size_t *match_start,
    size_t *match_end
) {
    if (regex->dfa_match_data != NULL) {
        const int dfa_result = pcre2_dfa_match(
            regex->code,
            subject,
            subject_len,
            start_offset,
            0,
            regex->dfa_match_data,
            NULL,
            regex->dfa_workspace,
            4096
        );
        if (dfa_result >= 0) {
            PCRE2_SIZE *ovector = pcre2_get_ovector_pointer(regex->dfa_match_data);
            *match_start = ovector[0];
            *match_end = ovector[1];
            return true;
        }
        if (dfa_result == PCRE2_ERROR_NOMATCH) return false;
    }
    if (regex->has_posix && (!regex->word_regexp || regex->code == NULL)) {
        return zg_posix_find(
            regex,
            subject,
            subject_len,
            start_offset,
            match_start,
            match_end
        );
    }
    int result;
    if (regex->jit) {
        result = pcre2_jit_match(
            regex->code,
            subject,
            subject_len,
            start_offset,
            0,
            regex->match_data,
            NULL
        );
    } else {
        result = pcre2_match(
            regex->code,
            subject,
            subject_len,
            start_offset,
            0,
            regex->match_data,
            NULL
        );
    }
    if (result < 0) return false;
    PCRE2_SIZE *ovector = pcre2_get_ovector_pointer(regex->match_data);
    *match_start = ovector[0];
    *match_end = ovector[1];
    return true;
}

zg_regex_worker *zg_regex_worker_create(const zg_regex *regex) {
    zg_regex_worker *worker = malloc(sizeof(*worker));
    if (worker == NULL) return NULL;
    worker->regex = regex;
    if (regex->code == NULL) {
        worker->match_data = NULL;
        return worker;
    }
    worker->match_data = pcre2_match_data_create_from_pattern(regex->code, NULL);
    if (worker->match_data == NULL) {
        free(worker);
        return NULL;
    }
    return worker;
}

bool zg_regex_worker_matches(
    zg_regex_worker *worker,
    const uint8_t *subject,
    size_t subject_len
) {
    int result;
    if (worker->regex->jit) {
        result = pcre2_jit_match(
            worker->regex->code,
            subject,
            subject_len,
            0,
            0,
            worker->match_data,
            NULL
        );
    } else {
        result = pcre2_match(
            worker->regex->code,
            subject,
            subject_len,
            0,
            0,
            worker->match_data,
            NULL
        );
    }
    return result >= 0;
}

bool zg_regex_worker_posix_matches(
    zg_regex_worker *worker,
    const uint8_t *subject,
    size_t subject_len
) {
    size_t match_start;
    size_t match_end;
    return zg_posix_find(
        worker->regex,
        subject,
        subject_len,
        0,
        &match_start,
        &match_end
    );
}

void zg_regex_worker_free(zg_regex_worker *worker) {
    if (worker == NULL) return;
    if (worker->match_data != NULL) pcre2_match_data_free(worker->match_data);
    free(worker);
}

void zg_regex_free(zg_regex *regex) {
    if (regex == NULL) return;
    if (regex->match_data != NULL) pcre2_match_data_free(regex->match_data);
    if (regex->dfa_match_data != NULL) pcre2_match_data_free(regex->dfa_match_data);
    free(regex->dfa_workspace);
    if (regex->code != NULL) pcre2_code_free(regex->code);
    if (regex->has_posix) regfree(&regex->posix);
    free(regex);
}
