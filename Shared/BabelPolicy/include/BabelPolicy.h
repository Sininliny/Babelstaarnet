#ifndef BABEL_POLICY_H
#define BABEL_POLICY_H
#include <stdint.h>
#if defined(_WIN32)
#define BP_API __declspec(dllexport)
#else
#define BP_API __attribute__((visibility("default")))
#endif
#ifdef __cplusplus
extern "C" {
#endif
/* Stable C ABI. No UI, filesystem, network, global state or model dependency. */
BP_API int32_t bp_version(void);
BP_API int32_t bp_retry_delay(int32_t failures);
BP_API int32_t bp_anchor(int32_t level, int32_t supported, int32_t focus,
    int32_t new_sense, int32_t cooldown, int32_t challenge_selected);
BP_API int32_t bp_challenge(int32_t supported, int32_t reliable,
    int32_t learned_before, int32_t new_sense, int32_t help_count, int32_t budget_used);
BP_API int32_t bp_evidence(int32_t event, int32_t correct, int32_t hinted);
BP_API int32_t bp_fetch(int32_t enabled, int32_t background_enabled,
    int32_t background_request, int32_t manual, double seconds_since_attempt,
    double seconds_since_success);
BP_API int32_t bp_digest(int32_t enabled, int32_t background_enabled, int32_t notify,
    int32_t permitted, int32_t reading, int32_t quiet, int32_t sent_today, int32_t fresh_count);
BP_API int32_t bp_rewrite(int32_t source_allows, int32_t text_present,
    int32_t model_installed, int32_t reading, int32_t safe_preemption);
BP_API double bp_news_score(double age_hours, double interest, double matches,
    double readability, int32_t seen_without_update);
BP_API int32_t bp_contains(const char *text, const char *unit);
BP_API int32_t bp_same_story(const char *a, const char *b);
BP_API const char *bp_feed_url(int32_t topic);
BP_API const char *bp_rewrite_prompt(void);
BP_API int32_t bp_summary_valid(const char *source, const char *summary, const char *preservation_words);
BP_API int32_t bp_target_allowed(int32_t target_count, int32_t already_target);
/* DR: 0 public RSS metadata, 1 full-article fetch/adaptation, 2 local RSS excerpt simplification. */
BP_API int32_t bp_source_capability(int32_t capability);
#ifdef __cplusplus
}
#endif
#endif
