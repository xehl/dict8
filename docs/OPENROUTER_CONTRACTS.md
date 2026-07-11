# OpenRouter Contracts — Phase 0

Verified against official OpenRouter documentation and the public Models API on 2026-07-10. Re-verify before implementing Phase 4–6 because schemas, models, endpoints, prices, and privacy routes can change.

## Speech-to-text

- Endpoint: `POST https://openrouter.ai/api/v1/audio/transcriptions`
- Authentication: `Authorization: Bearer <token>`
- JSON request fields: `model`, `input_audio.data`, `input_audio.format`, optional `language`, optional `temperature`, optional `provider`
- `input_audio.data` is raw base64 without a data-URI prefix.
- Common documented formats include `wav`, `mp3`, `flac`, `m4a`, `ogg`, `webm`, and `aac`; actual support varies by provider.
- Response includes `text` and optional `usage` values such as `seconds`, token counts, and `cost`.
- Multipart requests are also supported and capped at 25 MB. The JSON/base64 path remains the planned v0 integration because the PRD explicitly calls for just-in-time base64 construction.
- OpenRouter warns that large audio can encounter upstream timeouts and recommends splitting when necessary. The 180-second requirement therefore remains a measured decision, not an assumption.

Official references:

- [Speech-to-Text guide](https://openrouter.ai/docs/guides/overview/multimodal/stt)
- [Create transcription API](https://openrouter.ai/docs/api/api-reference/transcriptions/create-audio-transcriptions)

## Cleanup

- Endpoint: `POST https://openrouter.ai/api/v1/chat/completions`
- Authentication: `Authorization: Bearer <token>`
- Required v0 request shape: one system message, one user message containing the transcript, explicit `model`, non-streaming response, low temperature where supported, and a bounded output-token limit.
- Read cleaned text from the first non-streaming choice message.
- Treat empty content as failure.

Official references:

- [Chat-completion API](https://openrouter.ai/docs/api/api-reference/chat/send-chat-completion-request)
- [API overview](https://openrouter.ai/docs/api/reference/overview)

## ZDR and routing

Every request must include `provider.zdr: true`. This restricts routing to endpoints OpenRouter currently marks as Zero Data Retention. A model can become unavailable under this restriction even if it remains generally available.

- [Zero Data Retention](https://openrouter.ai/docs/guides/features/zdr)
- Public discovery query: `GET /api/v1/models?zdr=true`
- STT discovery query used: `GET /api/v1/models?output_modalities=transcription&zdr=true`

## Selected model configuration

| Stage | Primary | Fallback | Phase 0 rationale |
|---|---|---|---|
| STT | `openai/whisper-large-v3` | `google/chirp-3` | Both appeared in the current transcription + ZDR query; using different model families reduces correlated availability risk. |
| Cleanup | `google/gemini-2.5-flash-lite` | `anthropic/claude-haiku-4.5` | Both appeared in the current ZDR query and advertise temperature support; selection favors low latency/cost with a different-provider fallback. |

These are explicit candidates, not quality claims. The cleanup corpus and manual live tests must validate behavior before v0 readiness.

## Errors and attempt policy

OpenRouter documents typed errors including authentication, payment required, rate limit, provider unavailable/overloaded, payload too large, invalid request, content policy, server, and timeout. `429` and `503` may include `Retry-After`.

dict8 permits two total model attempts per stage. Authentication, insufficient credits, malformed requests, unsupported/oversized media, decoding failures, empty successful output, and invalid cleanup output do not trigger fallback.

- [Errors and debugging](https://openrouter.ai/docs/api/reference/errors-and-debugging)

## Live-test status

The owner explicitly opted into the synthetic STT benchmark on 2026-07-11. Exact 15-, 120-, and 180-second `.m4a` inputs all succeeded against `openai/whisper-large-v3` with per-request ZDR and no fallback. Content-free results are stored in `PHASE_ZERO_BENCHMARK_RESULTS.json`; the API key, audio, base64 payload, and transcript text were not retained. Cleanup-quality tests and representative non-repetitive prose tests remain manual and opt-in.
