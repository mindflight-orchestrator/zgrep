#define _GNU_SOURCE
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>

#include "zgrep_pcre2.h"

#include <stdio.h>
#include <stdlib.h>

struct zg_regex {
    pcre2_code *code;
    pcre2_code *ascii_witness_code;
    pcre2_match_data *match_data;
    pcre2_match_data *dfa_match_data;
    int *dfa_workspace;
    zg_posix_regex *posix;
    bool line_regexp;
    bool word_regexp;
    bool jit;
    bool ascii_witness_jit;
};

struct zg_regex_worker {
    const zg_regex *regex;
    pcre2_match_data *match_data;
    pcre2_match_data *ascii_witness_match_data;
};

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
        regex->posix = zg_posix_compile(
            posix_pattern,
            posix_pattern_len,
            syntax,
            ignore_case,
            line_regexp,
            word_regexp,
            error_buffer,
            error_buffer_len
        );
        if (regex->posix == NULL) {
            free(regex);
            return NULL;
        }
        if (!pcre_compatible) return regex;
    }

    int error_code = 0;
    PCRE2_SIZE error_offset = 0;
    uint32_t options = (ignore_case ? PCRE2_CASELESS : 0)
        | (dot_matches_newline ? PCRE2_DOTALL : 0);
    if (zg_locale_is_utf8()) {
        options |= PCRE2_UTF;
        if (syntax == ZG_REGEX_SYNTAX_PERL) options |= PCRE2_MATCH_INVALID_UTF;
    }
    pcre2_code *code = pcre2_compile(
        pcre_pattern,
        pcre_pattern_len,
        options,
        &error_code,
        &error_offset,
        NULL
    );
    if (code == NULL) {
        if (regex->posix != NULL) return regex;
        if (syntax == ZG_REGEX_SYNTAX_BASIC || syntax == ZG_REGEX_SYNTAX_EXTENDED) {
            regex->posix = zg_posix_compile(
                posix_pattern,
                posix_pattern_len,
                syntax,
                ignore_case,
                line_regexp,
                word_regexp,
                error_buffer,
                error_buffer_len
            );
            if (regex->posix != NULL) return regex;
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
        if (regex->posix != NULL) return regex;
        free(regex);
        snprintf(error_buffer, error_buffer_len, "out of memory compiling regex");
        return NULL;
    }

    regex->code = code;
    regex->match_data = match_data;
    if (ascii_witness) {
        int witness_error = 0;
        PCRE2_SIZE witness_error_offset = 0;
        regex->ascii_witness_code = pcre2_compile(
            pcre_pattern,
            pcre_pattern_len,
            dot_matches_newline ? PCRE2_DOTALL : 0,
            &witness_error,
            &witness_error_offset,
            NULL
        );
        if (regex->ascii_witness_code != NULL) {
            regex->ascii_witness_jit =
                pcre2_jit_compile(regex->ascii_witness_code, PCRE2_JIT_COMPLETE) == 0;
        }
    }
    if (posix_spans && regex->posix != NULL) {
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
    return regex->posix != NULL && zg_posix_matches(regex->posix, subject, subject_len);
}

bool zg_regex_uses_pcre(const zg_regex *regex) {
    return regex->code != NULL;
}

bool zg_regex_required_literal(
    const zg_regex *regex,
    const uint8_t **ptr,
    size_t *len
) {
    (void)regex;
    (void)ptr;
    (void)len;
    return false;
}

bool zg_regex_pcre_find(
    zg_regex *regex,
    const uint8_t *subject,
    size_t subject_len,
    size_t start_offset,
    size_t *match_start,
    size_t *match_end
) {
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
    if (regex->posix != NULL && (!regex->word_regexp || regex->code == NULL)) {
        return zg_posix_find(
            regex->posix,
            subject,
            subject_len,
            start_offset,
            match_start,
            match_end
        );
    }
    return zg_regex_pcre_find(
        regex,
        subject,
        subject_len,
        start_offset,
        match_start,
        match_end
    );
}

zg_regex_worker *zg_regex_worker_create(const zg_regex *regex) {
    zg_regex_worker *worker = malloc(sizeof(*worker));
    if (worker == NULL) return NULL;
    worker->regex = regex;
    worker->ascii_witness_match_data = NULL;
    if (regex->code == NULL) {
        worker->match_data = NULL;
        return worker;
    }
    worker->match_data = pcre2_match_data_create_from_pattern(regex->code, NULL);
    if (worker->match_data == NULL) {
        free(worker);
        return NULL;
    }
    if (regex->ascii_witness_code != NULL) {
        worker->ascii_witness_match_data = pcre2_match_data_create_from_pattern(
            regex->ascii_witness_code,
            NULL
        );
        if (worker->ascii_witness_match_data == NULL) {
            pcre2_match_data_free(worker->match_data);
            free(worker);
            return NULL;
        }
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

bool zg_regex_worker_ascii_witness_matches(
    zg_regex_worker *worker,
    const uint8_t *subject,
    size_t subject_len
) {
    if (worker->regex->ascii_witness_code == NULL) return false;
    const int result = worker->regex->ascii_witness_jit
        ? pcre2_jit_match(
            worker->regex->ascii_witness_code,
            subject,
            subject_len,
            0,
            0,
            worker->ascii_witness_match_data,
            NULL
        )
        : pcre2_match(
            worker->regex->ascii_witness_code,
            subject,
            subject_len,
            0,
            0,
            worker->ascii_witness_match_data,
            NULL
        );
    return result >= 0;
}

bool zg_regex_worker_posix_matches(
    zg_regex_worker *worker,
    const uint8_t *subject,
    size_t subject_len
) {
    return worker->regex->posix != NULL
        && zg_posix_matches(worker->regex->posix, subject, subject_len);
}

void zg_regex_worker_free(zg_regex_worker *worker) {
    if (worker == NULL) return;
    if (worker->match_data != NULL) pcre2_match_data_free(worker->match_data);
    if (worker->ascii_witness_match_data != NULL)
        pcre2_match_data_free(worker->ascii_witness_match_data);
    free(worker);
}

void zg_regex_free(zg_regex *regex) {
    if (regex == NULL) return;
    if (regex->match_data != NULL) pcre2_match_data_free(regex->match_data);
    if (regex->dfa_match_data != NULL) pcre2_match_data_free(regex->dfa_match_data);
    free(regex->dfa_workspace);
    if (regex->code != NULL) pcre2_code_free(regex->code);
    if (regex->ascii_witness_code != NULL) pcre2_code_free(regex->ascii_witness_code);
    zg_posix_free(regex->posix);
    free(regex);
}
