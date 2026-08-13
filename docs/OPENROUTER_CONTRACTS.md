# OpenRouter Contracts — Phase 0

Verified against official OpenRouter documentation, the public Models API, and the live ZDR endpoint catalog on 2026-07-16. Re-verify before changing either pipeline because schemas, models, endpoints, prices, and privacy routes can change.

## Speech-to-text

- Endpoint: `POST https://openrouter.ai/api/v1/audio/transcriptions`
- Authentication: `Authorization: Bearer <token>`
- JSON request fields: `model`, `input_audio.data`, `input_audio.format`, optional `language`, optional `temperature`, optional `provider`
- `input_audio.data` is raw base64 without a data-URI prefix.
- Common documented formats include `wav`, `mp3`, `flac`, `m4a`, `ogg`, `webm`, and `aac`; actual support varies by provider.
- Response includes `text` and optional `usage` values such as `seconds`, token counts, and `cost`.
- The OpenAPI schema requires only `text` in the standard response. `verbose_json` adds duration and timestamps but is limited to OpenAI-compatible providers, so v0 uses the standard response for portability across the configured model fallback.
- Phase 5 sends `language: "en"`, pins temperature to `0`, and shares a 45-second deadline across both explicit model attempts.
- Multipart requests are also supported and capped at 25 MB. The JSON/base64 path remains the planned v0 integration because the PRD explicitly calls for just-in-time base64 construction.
- OpenRouter warns that large audio can encounter upstream timeouts and recommends splitting when necessary. The 180-second requirement therefore remains a measured decision, not an assumption.

Official references:

- [Speech-to-Text guide](https://openrouter.ai/docs/guides/overview/multimodal/stt)
- [Create transcription API](https://openrouter.ai/docs/api/api-reference/transcriptions/create-audio-transcriptions)

## Cleanup

- Endpoint: `POST https://openrouter.ai/api/v1/chat/completions`
- Authentication: `Authorization: Bearer <token>`
- Required v0 request shape: one system message, one user message containing the transcript, explicit `model`, non-streaming response, low temperature where supported, and a bounded output-token limit.
- Phase 6 uses `temperature: 0.1`, `stream: false`, `"reasoning": {"effort": "none"}`, and `max_completion_tokens`. It deliberately omits tools and structured response formats to preserve the simplest portable text contract.
- Read cleaned text from the first non-streaming choice message.
- Treat empty content as failure.
- Require a normal `stop` finish reason; truncated or otherwise incomplete output uses the raw transcript fallback.

Official references:

- [Chat-completion API](https://openrouter.ai/docs/api/api-reference/chat/send-chat-completion-request)
- [API overview](https://openrouter.ai/docs/api/reference/overview)

## ZDR and routing

Cleanup requests include `provider.zdr: true`, restricting routing to endpoints OpenRouter currently marks as Zero Data Retention. OpenRouter's July 22, 2026 transcription guidance states that per-request routing and data-policy controls are not applied to `/audio/transcriptions`; the STT `provider` object carries provider-specific options only. dict8 therefore requires account-level OpenAI and Google ZDR settings for its Whisper primary and Chirp fallback and does not send an unsupported STT `provider.zdr` field.

OpenRouter may use its default provider fallback for the one requested model. The applicable account-level or per-request ZDR control must restrict those routes. dict8 does not send `allow_fallbacks`, `models`, or `route` fields for automatic multi-model routing. Instead, dict8 owns the configured second-model attempt and can report when the pinned model failed.

- [Zero Data Retention](https://openrouter.ai/docs/guides/features/zdr)
- Current ZDR endpoint catalog: `GET /api/v1/endpoints/zdr`
- STT discovery query used: `GET /api/v1/models?output_modalities=transcription&zdr=true`

## Selected model configuration

| Stage | Primary | Fallback | Phase 0 rationale |
|---|---|---|---|
| STT | `openai/whisper-large-v3` | `google/chirp-3` | Both appeared in the current transcription + ZDR query; using different model families reduces correlated availability risk. |
| Cleanup | `google/gemini-2.5-flash-lite` | `anthropic/claude-haiku-4.5` | Both appeared in the current ZDR query and advertise temperature support; selection favors low latency/cost with a different-provider fallback. |

These are explicit candidates, not quality claims. The cleanup corpus and manual live tests must validate behavior before v0 readiness.

On 2026-07-16, both STT identifiers remained in the filtered transcription catalog with `audio -> transcription` modality, and both cleanup identifiers remained in the general catalog with text output and temperature support. The live ZDR endpoint catalog listed at least one route for every configured identifier: Groq and Together for Whisper, Google for Chirp and Gemini Flash Lite, and Amazon Bedrock and Google for Claude Haiku. This is a point-in-time availability check. On 2026-07-29, the owner enabled account-level OpenAI and Google ZDR for STT; cleanup continues to set `provider.zdr: true` per request.

## Errors and attempt policy

OpenRouter documents typed errors including authentication, payment required, rate limit, provider unavailable/overloaded, payload too large, invalid request, content policy, server, and timeout. `429` and `503` may include `Retry-After` as delta-seconds or an HTTP date.

dict8 permits two total model attempts per stage. Network interruption and HTTP 408, 429, 500, 502, 503, and 504 may trigger the explicit fallback. Authentication, insufficient credits, HTTP 404 configuration errors, malformed requests, unsupported/oversized media, decoding failures, empty successful output, and invalid cleanup output do not trigger fallback. A `Retry-After` wait is honored only when it fits within the caller-supplied total stage deadline.

- [Errors and debugging](https://openrouter.ai/docs/api/reference/errors-and-debugging)

## Live-test status

The owner explicitly opted into the synthetic STT benchmark on 2026-07-11. Exact 15-, 120-, and 180-second `.m4a` inputs all succeeded against `openai/whisper-large-v3` with no model fallback. Those requests included `provider.zdr: true`; OpenRouter's later transcription guidance clarified that this per-request control was not applied by that endpoint, so the benchmark cannot substantiate the earlier ZDR claim. Account-level OpenAI and Google ZDR is now required. Content-free results are stored in `PHASE_ZERO_BENCHMARK_RESULTS.json`; the API key, audio, base64 payload, and transcript text were not retained.

On 2026-07-14 the owner authorized and passed paid Phase 5 live tests for a short recording and a representative recording longer than two minutes. No material compression or missing-section issue was reported. Transcript content was not written to documentation or logs.

On 2026-07-15 the owner authorized and passed the paid Phase 6 cleanup corpus. All six synthetic fixtures passed, including prompt-injection and legitimate meta-language cases. Only content-free outcomes were recorded.
