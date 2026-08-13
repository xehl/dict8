# Hybrid Architecture: On-Device STT (WhisperKit) + Fast Cloud Cleanup

**Status:** Proposed / Post-Demo Roadmap  
**Target:** Sub-500ms End-to-End Dictation Pipeline  
**Author:** Eric Lee  
**Date:** 2026-08-13  

---

## 1. Motivation & Latency Breakdown

The current production baseline uses a sequential two-stage remote architecture:
1. **Remote STT:** Audio upload + OpenAI Whisper Large v3 over OpenRouter ($\sim 400\text{–}600\text{ms}$).
2. **Remote Cleanup:** Text-in/text-out via OpenRouter Auto Router ($\sim 1,200\text{–}2,500\text{ms}$).
3. **Total Pipeline Latency:** $\sim 1.7\text{–}3.0\text{s}$.

### Target Hybrid Architecture
By moving Speech-to-Text directly onto the Apple Silicon Apple Neural Engine (ANE) and pairing it with a pinned, low-latency cloud model for text cleanup, we eliminate audio network upload time, eliminate Whisper server queuing, and reduce the pipeline to a single lightweight text HTTP request.

| Stage | Target Technology | Target Latency | Network Cost / Data Transfer |
| :--- | :--- | :--- | :--- |
| **Stage 1: Speech-to-Text** | Local `WhisperKit` (`distil-whisper-large-v3` or `base.en`) on ANE | $\mathbf{100\text{–}150\text{ms}}$ | $0 (Audio never leaves Mac) |
| **Stage 2: Text Cleanup** | Pinned Fast LLM via OpenRouter (`google/gemini-2.5-flash-lite` or `meta-llama/llama-3.1-8b-instruct`) | $\mathbf{200\text{–}300\text{ms}}$ | $<1\text{KB}$ JSON payload |
| **Total End-to-End** | **Hybrid Pipeline** | $\mathbf{\sim 350\text{–}480\text{ms}}$ | **~75% Latency Reduction** |

---

## 2. Component Design

### 2.1 Local Transcription Provider (`WhisperKitSpeechToTextService`)
- Implement `SpeechToTextProviding` protocol with a local CoreML / ANE engine.
- Model selection:
  - `openai/whisper-tiny.en` / `base.en`: Ultra-low latency ($\sim 50\text{–}80\text{ms}$).
  - `distil-whisper/distil-large-v3`: Production parity with Whisper Large v3 at $\sim 120\text{–}180\text{ms}$.
- Zero audio file disk serialization needed; raw `AVAudioPCMBuffer` can be handed directly to WhisperKit in memory.

### 2.2 Pinned Fast Remote Cleanup (`FastCloudTextCleanupService`)
- Direct model pin bypassing Auto Router failover cascades.
- Candidates:
  - `google/gemini-2.5-flash-lite` (TTFT $\sim 150\text{–}250\text{ms}$, $\$0.10/\text{M}$ prompt, $\$0.40/\text{M}$ completion).
  - `meta-llama/llama-3.1-8b-instruct:nitro` (TTFT $\sim 120\text{–}200\text{ms}$).
- Retain existing validation rules:
  - `max_completion_tokens` clamped to transcript length.
  - `reasoning: { effort: "none" }` to prevent thinking tokens.
  - Retention and anti-hallucination checks from `TextCleanupValidator`.

---

## 3. Step-by-Step Implementation Plan

### Phase 1: Dependency & Model Management
1. Add `WhisperKit` via Swift Package Manager (`https://github.com/argmaxinc/WhisperKit.git`).
2. Implement background model pre-warming on app launch in `AppCoordinator` so initial dictation has no cold-start delay.
3. Add asset caching under `~/Library/Application Support/dict8/models`.

### Phase 2: Local STT Service Implementation
1. Create `dict8/dict8/Services/LocalSpeechToTextService.swift` conforming to `SpeechToTextProviding`.
2. Wrap `WhisperKit.transcribe` with async/await error isolation and non-blocking actor isolation.
3. Handle fallback gracefully: If CoreML/ANE fails to initialize (e.g. low memory), fall back to `OpenRouterSpeechToTextService`.

### Phase 3: Pinned Fast Cleanup Configuration
1. Update `Supporting/AIModelConfiguration.swift` with an explicit fast-tier cleanup model option (e.g., `google/gemini-2.5-flash-lite`).
2. Configure `OpenRouterTextCleanupService` to support direct pinned routing without the Auto Router plugin wrapper when configured for fast mode.

### Phase 4: Settings & Metrics Integration
1. Add a toggle in Settings: **Transcription Engine** (`Local (WhisperKit)` vs `OpenRouter Cloud`).
2. Update `UsageMetricsSnapshot` to track:
   - `localTranscriptionLatency`
   - On-device vs cloud routing ratio.
3. Verify all privacy requirements in `PRIVACY_AND_LOGGING.md`: confirm audio buffer is wiped from memory immediately after transcription.

### Phase 5: Verification & Benchmark Suite
1. Run standard test harness (`PhaseFiveSpeechToTextTests`, `PhaseSixTextCleanupTests`, `PhaseEightPipelineTests`).
2. Benchmark 50 test utterances across short (<3s), medium (3–10s), and long (>10s) audio clips.
3. Confirm p50 $< 400\text{ms}$ and p95 $< 700\text{ms}$.
