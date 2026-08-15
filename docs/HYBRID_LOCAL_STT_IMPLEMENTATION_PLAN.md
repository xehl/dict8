# Hybrid Architecture: On-Device STT (WhisperKit) + Fast Cloud Cleanup Experimentation

**Status:** Approved Post-Demo Implementation Plan  
**Target:** Sub-500ms End-to-End Dictation Pipeline  
**Author:** Eric Lee  
**Date:** 2026-08-15  

---

## 1. Objectives & Latency Target

Transition `dict8` from full cloud processing to a hybrid model:
1. **On-Device STT:** Process audio on Apple Silicon ANE using `WhisperKit` (`distil-whisper/distil-large-v3` default).
2. **Fast Cloud Cleanup:** Benchmark candidate fast models via OpenRouter (evaluating latency, TTFT, formatting quality, and reliability) before committing to a final pinned model.

### Latency Budget

| Stage | Technology / Candidate | Target Latency | Notes |
| :--- | :--- | :--- | :--- |
| **Stage 1: STT** | `WhisperKit` (`distil-large-v3`) on ANE | **$100\text{–}150\text{ms}$** | $0 egress; audio stays on-device |
| **Stage 2: Cleanup** | OpenRouter Fast Candidates (e.g., Gemini 2.5 Flash Lite, Llama 3.1 8B Nitro, GPT-4o-mini) | **$200\text{–}300\text{ms}$** | Evaluated via experimentation harness |
| **Stage 3: Paste** | Synthetic CGEvent Paste | **$<30\text{ms}$** | Native macOS pasteboard dispatch |
| **Total End-to-End** | **Hybrid Pipeline** | **$\mathbf{\sim 350\text{–}480\text{ms}}$** | **$\mathbf{\sim 75\text{–}85\%}$ latency reduction** |

---

## 2. Agreed Implementation Details

### 2.1 Local STT Provider (`LocalSpeechToTextService`)
- **Default Model:** `distil-whisper/distil-large-v3` for high accuracy matching Whisper Large v3 at fraction of latency.
- **Engine:** `WhisperKit` via Swift Package Manager (`https://github.com/argmaxinc/WhisperKit.git`).
- **Memory & Lifecycle:**
  - Model assets cached in `~/Library/Application Support/dict8/models`.
  - App launch background pre-warming in `AppCoordinator` / `dict8App` to avoid first-run cold start.
  - Direct memory buffer transcription (`AVAudioPCMBuffer`) avoiding disk I/O where possible.
  - Automatic fallback to `OpenRouterSpeechToTextService` if CoreML initialization or hardware acceleration fails.

### 2.2 Cloud Cleanup Experimentation Harness (`FastCloudTextCleanupService`)
- **Configurable Model Candidates:**
  - `google/gemini-2.5-flash-lite`
  - `meta-llama/llama-3.1-8b-instruct:nitro`
  - `openai/gpt-4o-mini`
  - `openrouter/auto` (baseline comparison)
- **Controls & Guardrails Maintained:**
  - `reasoning: { effort: "none" }` sent on all completions.
  - `provider.zdr: true` enforced on all requests.
  - `max_completion_tokens` clamped to input transcript length with conservative floor.
  - Zero-completion retry accommodation retained.
  - Strict retention and anti-hallucination validation via `TextCleanupValidator`.

### 2.3 Settings & Telemetry
- **Settings UI:**
  - Transcription Engine: `Local (WhisperKit)` (default) vs. `Cloud (OpenRouter)`.
  - Cleanup Model Selector / Experiment Toggle to easily switch candidate models during benchmarking.
- **Metrics:**
  - Separate logging for `localSTTLatency`, `cloudCleanupLatency`, and candidate model identifier.
  - Aggregate metrics preserved without logging transcript text or PII.

---

## 3. Phased Implementation Roadmap

1. **Phase A — SPM Dependencies & Local STT Service:**
   - Integrate `WhisperKit` package.
   - Implement `LocalSpeechToTextService: SpeechToTextProviding`.
2. **Phase B — Model Lifecycle & Pre-Warming:**
   - Implement model download, asset verification, and launch pre-warming.
3. **Phase C — Multi-Model Cleanup Configuration:**
   - Update `AIModelConfiguration.swift` and `OpenRouterClient.swift` to support clean swapping across fast cleanup candidate models.
4. **Phase D — Settings & Metrics Integration:**
   - Add engine toggle & model selector in `SettingsView.swift`.
   - Update `MetricsService.swift` to record per-model latency distributions.
5. **Phase E — Benchmarking & Verification:**
   - Benchmark 50 test utterances across short (<3s), medium (3–10s), and long (>10s) audio clips.
   - Record and compare p50/p95 latency and quality across candidate models.
