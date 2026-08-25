#define _GNU_SOURCE
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>

#include "zgrep_pcre2.h"

#include <langinfo.h>
#include <locale.h>
#include <stdio.h>
#include <stdlib.h>
#include <regex.h>
#include <string.h>
#include <strings.h>
#include <wchar.h>
#include <wctype.h>

static bool zg_utf8_locale = false;
static bool zg_simple_ascii_casefold = false;
static bool zg_standard_ascii_classes = false;

static bool zg_validate_ascii_classes(void) {
    for (wint_t character = 0; character < 128; character++) {
        const bool upper = character >= L'A' && character <= L'Z';
        const bool lower = character >= L'a' && character <= L'z';
        const bool alpha = upper || lower;
        const bool digit = character >= L'0' && character <= L'9';
        const bool alnum = alpha || digit;
        const bool blank = character == L' ' || character == L'\t';
        const bool cntrl = character < 32 || character == 127;
        const bool graph = character >= 33 && character <= 126;
        const bool print = character >= 32 && character <= 126;
        const bool punct = graph && !alnum;
        const bool space = character == L' ' ||
            (character >= L'\t' && character <= L'\r');
        const bool xdigit = digit ||
            (character >= L'A' && character <= L'F') ||
            (character >= L'a' && character <= L'f');
        if ((iswalnum(character) != 0) != alnum ||
            (iswalpha(character) != 0) != alpha ||
            (iswblank(character) != 0) != blank ||
            (iswcntrl(character) != 0) != cntrl ||
            (iswdigit(character) != 0) != digit ||
            (iswgraph(character) != 0) != graph ||
            (iswlower(character) != 0) != lower ||
            (iswprint(character) != 0) != print ||
            (iswpunct(character) != 0) != punct ||
            (iswspace(character) != 0) != space ||
            (iswupper(character) != 0) != upper ||
            (iswxdigit(character) != 0) != xdigit) return false;
    }
    return true;
}

bool zg_initialize_locale(void) {
    if (setlocale(LC_ALL, "") == NULL) {
        zg_utf8_locale = false;
        zg_simple_ascii_casefold = false;
        zg_standard_ascii_classes = false;
        return false;
    }
    const char *codeset = nl_langinfo(CODESET);
    zg_utf8_locale = codeset != NULL
        && (strcasecmp(codeset, "UTF-8") == 0 || strcasecmp(codeset, "UTF8") == 0);
    const char *locale_name = setlocale(LC_CTYPE, NULL);
    const bool validated_locale = locale_name != NULL
        && (strcasecmp(locale_name, "C.UTF-8") == 0
            || strcasecmp(locale_name, "C.utf8") == 0
            || strncasecmp(locale_name, "en_", 3) == 0
            || strncasecmp(locale_name, "nl_", 3) == 0);
    zg_simple_ascii_casefold = zg_utf8_locale && validated_locale
        && towupper((wint_t)0x0131) == L'I'
        && towupper((wint_t)0x017f) == L'S'
        && towupper((wint_t)0x212a) != L'K';
    zg_standard_ascii_classes = zg_validate_ascii_classes();
    return zg_utf8_locale;
}

bool zg_locale_is_utf8(void) {
    return zg_utf8_locale;
}

bool zg_locale_has_simple_ascii_casefold(void) {
    return zg_simple_ascii_casefold;
}

bool zg_locale_has_standard_ascii_classes(void) {
    return zg_standard_ascii_classes;
}

static uint32_t zg_ascii_upper(uint8_t byte) {
    if (byte >= 'a' && byte <= 'z') return (uint32_t)(byte - ('a' - 'A'));
    return byte;
}

static bool zg_locale_ascii_case_equal(
    const uint8_t *subject,
    size_t subject_len,
    uint8_t expected,
    size_t *consumed
) {
    if (subject_len == 0) return false;
    const uint32_t expected_upper = zg_ascii_upper(expected);
    if (subject[0] < 0x80) {
        *consumed = 1;
        return zg_ascii_upper(subject[0]) == expected_upper;
    }
    if (subject_len >= 2 && expected_upper == 'I'
        && subject[0] == 0xc4 && subject[1] == 0xb1) {
        *consumed = 2;
        return true;
    }
    if (subject_len >= 2 && expected_upper == 'S'
        && subject[0] == 0xc5 && subject[1] == 0xbf) {
        *consumed = 2;
        return true;
    }
    return false;
}

bool zg_locale_ascii_case_literal_matches(
    const uint8_t *subject,
    size_t subject_len,
    const uint8_t *pattern,
    size_t pattern_len
) {
    if (pattern_len == 0) return true;
    const uint8_t first_upper = (uint8_t)zg_ascii_upper(pattern[0]);
    const uint8_t first_lower = first_upper >= 'A' && first_upper <= 'Z'
        ? (uint8_t)(first_upper + ('a' - 'A'))
        : first_upper;
    const uint8_t candidates[3] = {
        first_upper,
        first_lower,
        first_upper == 'I' ? 0xc4 : 0xc5,
    };
    const size_t candidate_count = first_upper == 'I' || first_upper == 'S' ? 3 : 2;

    for (size_t candidate_index = 0; candidate_index < candidate_count; candidate_index++) {
        if (candidate_index == 1 && first_lower == first_upper) continue;
        const uint8_t *cursor = subject;
        size_t remaining = subject_len;
        while (remaining != 0) {
            const uint8_t *candidate = memchr(cursor, candidates[candidate_index], remaining);
            if (candidate == NULL) break;
            const size_t candidate_remaining = subject_len - (size_t)(candidate - subject);
            size_t offset = 0;
            size_t pattern_index = 0;
            while (pattern_index < pattern_len && offset < candidate_remaining) {
                size_t character_length = 0;
                if (!zg_locale_ascii_case_equal(
                    candidate + offset,
                    candidate_remaining - offset,
                    pattern[pattern_index],
                    &character_length
                )) break;
                offset += character_length;
                pattern_index++;
            }
            if (pattern_index == pattern_len) return true;
            const size_t consumed = (size_t)(candidate - cursor) + 1;
            cursor += consumed;
            remaining -= consumed;
        }
    }
    return false;
}

struct zg_regex {
    pcre2_code *code;
    pcre2_code *ascii_witness_code;
    pcre2_match_data *match_data;
    pcre2_match_data *dfa_match_data;
    int *dfa_workspace;
    regex_t posix;
    bool has_posix;
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

static bool zg_is_word_byte(uint8_t byte) {
    return (byte >= 'a' && byte <= 'z')
        || (byte >= 'A' && byte <= 'Z')
        || (byte >= '0' && byte <= '9')
        || byte == '_';
}

static bool zg_is_word_character(
    const uint8_t *subject,
    size_t subject_len,
    size_t offset
) {
    if (offset >= subject_len) return false;
    if (!zg_utf8_locale) return zg_is_word_byte(subject[offset]);
    mbstate_t state = {0};
    wchar_t character = 0;
    const size_t decoded = mbrtowc(
        &character,
        (const char *)(subject + offset),
        subject_len - offset,
        &state
    );
    if (decoded == (size_t)-1 || decoded == (size_t)-2) return false;
    return character == L'_' || iswalnum((wint_t)character) != 0;
}

static bool zg_is_word_before(
    const uint8_t *subject,
    size_t subject_len,
    size_t offset
) {
    if (offset == 0) return false;
    size_t character_start = offset - 1;
    if (zg_utf8_locale) {
        while (character_start != 0 && (subject[character_start] & 0xc0) == 0x80) {
            character_start--;
        }
    }
    return zg_is_word_character(subject, subject_len, character_start);
}

bool zg_locale_ascii_literal_word_matches(
    const uint8_t *subject,
    size_t subject_len,
    const uint8_t *pattern,
    size_t pattern_len
) {
    if (pattern_len == 0 || pattern_len > subject_len) return false;
    const uint8_t *cursor = subject;
    size_t remaining = subject_len;
    while (remaining >= pattern_len) {
        const uint8_t *match = memmem(cursor, remaining, pattern, pattern_len);
        if (match == NULL) return false;
        const size_t start = (size_t)(match - subject);
        const size_t end = start + pattern_len;
        if (!zg_is_word_before(subject, subject_len, start)
            && !zg_is_word_character(subject, subject_len, end)) return true;
        const size_t consumed = (size_t)(match - cursor) + 1;
        cursor += consumed;
        remaining -= consumed;
    }
    return false;
}

static bool zg_locale_wide_class_matches(wint_t character, uint32_t classes) {
    return ((classes & ZG_LOCALE_CLASS_ALNUM) != 0 && iswalnum(character) != 0)
        || ((classes & ZG_LOCALE_CLASS_ALPHA) != 0 && iswalpha(character) != 0)
        || ((classes & ZG_LOCALE_CLASS_BLANK) != 0 && iswblank(character) != 0)
        || ((classes & ZG_LOCALE_CLASS_DIGIT) != 0 && iswdigit(character) != 0)
        || ((classes & ZG_LOCALE_CLASS_GRAPH) != 0 && iswgraph(character) != 0)
        || ((classes & ZG_LOCALE_CLASS_LOWER) != 0 && iswlower(character) != 0)
        || ((classes & ZG_LOCALE_CLASS_PRINT) != 0 && iswprint(character) != 0)
        || ((classes & ZG_LOCALE_CLASS_PUNCT) != 0 && iswpunct(character) != 0)
        || ((classes & ZG_LOCALE_CLASS_UPPER) != 0 && iswupper(character) != 0)
        || ((classes & ZG_LOCALE_CLASS_XDIGIT) != 0 && iswxdigit(character) != 0);
}

static size_t zg_decode_utf8(
    const uint8_t *subject,
    size_t subject_len,
    uint32_t *character
) {
    if (subject_len == 0) return 0;
    const uint8_t first = subject[0];
    if (first < 0x80) {
        *character = first;
        return 1;
    }
    if (first >= 0xc2 && first <= 0xdf && subject_len >= 2 &&
        (subject[1] & 0xc0) == 0x80)
    {
        *character = ((uint32_t)(first & 0x1f) << 6) | (subject[1] & 0x3f);
        return 2;
    }
    if (first >= 0xe0 && first <= 0xef && subject_len >= 3 &&
        (subject[1] & 0xc0) == 0x80 && (subject[2] & 0xc0) == 0x80 &&
        (first != 0xe0 || subject[1] >= 0xa0) &&
        (first != 0xed || subject[1] < 0xa0))
    {
        *character = ((uint32_t)(first & 0x0f) << 12)
            | ((uint32_t)(subject[1] & 0x3f) << 6)
            | (subject[2] & 0x3f);
        return 3;
    }
    if (first >= 0xf0 && first <= 0xf4 && subject_len >= 4 &&
        (subject[1] & 0xc0) == 0x80 && (subject[2] & 0xc0) == 0x80 &&
        (subject[3] & 0xc0) == 0x80 &&
        (first != 0xf0 || subject[1] >= 0x90) &&
        (first != 0xf4 || subject[1] < 0x90))
    {
        *character = ((uint32_t)(first & 0x07) << 18)
            | ((uint32_t)(subject[1] & 0x3f) << 12)
            | ((uint32_t)(subject[2] & 0x3f) << 6)
            | (subject[3] & 0x3f);
        return 4;
    }
    return 0;
}

bool zg_locale_class_run_matches(
    const uint8_t *subject,
    size_t subject_len,
    uint64_t ascii_mask_low,
    uint64_t ascii_mask_high,
    uint32_t classes,
    size_t minimum
) {
    if (minimum == 0) return true;
    size_t run = 0;
    size_t offset = 0;
    while (offset < subject_len) {
        const uint8_t byte = subject[offset];
        bool accepted = false;
        size_t width = 1;
        if (byte < 0x80) {
            const uint64_t mask = byte < 64 ? ascii_mask_low : ascii_mask_high;
            accepted = (mask & (UINT64_C(1) << (byte & 63))) != 0;
        } else {
            uint32_t character = 0;
            const size_t decoded = zg_decode_utf8(
                subject + offset,
                subject_len - offset,
                &character
            );
            if (decoded != 0) {
                width = decoded;
                accepted = zg_locale_wide_class_matches((wint_t)character, classes);
            }
        }
        if (accepted) {
            run++;
            if (run >= minimum) return true;
        } else {
            run = 0;
        }
        offset += width;
    }
    return false;
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
            const bool left = !zg_is_word_before(subject, subject_len, start);
            const bool right = !zg_is_word_character(subject, subject_len, end);
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
    if (zg_utf8_locale) {
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
    if (regex->has_posix) regfree(&regex->posix);
    free(regex);
}
