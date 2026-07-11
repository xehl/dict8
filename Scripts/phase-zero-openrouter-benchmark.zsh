#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
MODEL_CONFIG="$REPO_ROOT/Supporting/AIModelConfiguration.swift"
PAYLOAD_HELPER="$SCRIPT_DIR/Benchmark/make_stt_payload.py"
SANITIZER="$SCRIPT_DIR/Benchmark/sanitize_stt_response.py"
OUTPUT_PATH="$REPO_ROOT/docs/PHASE_ZERO_BENCHMARK_RESULTS.json"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dict8-phase-zero.XXXXXX")"
RESULTS_JSONL="$WORK_DIR/results.jsonl"

cleanup() {
    unset OPENROUTER_API_KEY
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

for command_name in say avconvert afinfo jq curl python3; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        print -u2 "Missing required command: $command_name"
        exit 1
    fi
done

primary_model="$(sed -n 's/.*transcriptionModel: "\([^"]*\)".*/\1/p' "$MODEL_CONFIG" | head -1)"
fallback_model="$(sed -n 's/.*transcriptionFallbackModel: "\([^"]*\)".*/\1/p' "$MODEL_CONFIG" | head -1)"
if [[ -z "$primary_model" || -z "$fallback_model" ]]; then
    print -u2 "Could not read the centralized STT model configuration."
    exit 1
fi

print "This benchmark sends synthetic speech to OpenRouter and may consume API credits."
print "The key, base64 audio, and returned transcript are never written to disk or printed."
print -n "OpenRouter API key: "
IFS= read -r -s OPENROUTER_API_KEY
print
if [[ -z "$OPENROUTER_API_KEY" ]]; then
    print -u2 "No API key entered."
    exit 1
fi

synthetic_phrase="This is synthetic technical prose for the dict eight speech benchmark. We are testing punctuation, timing, and reliable transcription. The quick brown fox jumps over the lazy dog. Please record this generated sentence as ordinary prose."

measured_duration() {
    afinfo "$1" | awk '/estimated duration/ { print $3; exit }'
}

generate_audio() {
    local duration="$1"
    local text_path="$WORK_DIR/synthetic-${duration}s.txt"
    local source_path="$WORK_DIR/synthetic-${duration}s.aiff"
    local output_path="$WORK_DIR/synthetic-${duration}s.m4a"
    local repeats=$(( (duration * 4 / 30) + 4 ))

    : > "$text_path"
    local index
    for (( index = 1; index <= repeats; index++ )); do
        print -r -- "$synthetic_phrase" >> "$text_path"
    done

    say -r 180 -f "$text_path" -o "$source_path"
    local source_duration="$(measured_duration "$source_path")"
    if [[ -z "$source_duration" ]] || (( ${source_duration%.*} < duration )); then
        print -u2 "Synthetic speech generation was shorter than ${duration}s."
        return 1
    fi

    avconvert \
        --source "$source_path" \
        --preset PresetAppleM4A \
        --output "$output_path" \
        --duration "$duration" \
        --replace >/dev/null

    print -r -- "$output_path"
}

run_attempt() {
    local duration="$1"
    local audio_path="$2"
    local model="$3"
    local attempt_kind="$4"
    local sanitized

    print "Testing ${duration}s with ${attempt_kind} model ${model}..."
    sanitized="$(
        python3 "$PAYLOAD_HELPER" "$audio_path" "$model" \
            | curl --silent --show-error \
                --connect-timeout 15 \
                --max-time 120 \
                --request POST \
                --header @<(printf 'Authorization: Bearer %s\n' "$OPENROUTER_API_KEY") \
                --header 'Content-Type: application/json' \
                --data-binary @- \
                --write-out $'\n__DICT8_CURL_META__%{http_code}\t%{time_total}\t%{size_upload}\t%{size_download}\n' \
                'https://openrouter.ai/api/v1/audio/transcriptions' \
            | python3 "$SANITIZER"
    )"

    jq -c \
        --argjson requested_duration_seconds "$duration" \
        --argjson measured_duration_seconds "$(measured_duration "$audio_path")" \
        --arg model "$model" \
        --arg attempt "$attempt_kind" \
        '. + {
            requested_duration_seconds: $requested_duration_seconds,
            measured_duration_seconds: $measured_duration_seconds,
            model: $model,
            attempt: $attempt
        }' <<<"$sanitized" | tee -a "$RESULTS_JSONL"

    if [[ "$(jq -r '.success' <<<"$sanitized")" == "true" ]]; then
        return 0
    fi
    if [[ "$(jq -r '.fallback_eligible' <<<"$sanitized")" == "true" ]]; then
        return 2
    fi
    return 1
}

overall_success=true
for duration in 15 120 180; do
    audio_path="$(generate_audio "$duration")"

    set +e
    run_attempt "$duration" "$audio_path" "$primary_model" "primary"
    attempt_status=$?
    set -e

    if (( attempt_status == 2 )); then
        set +e
        run_attempt "$duration" "$audio_path" "$fallback_model" "fallback"
        fallback_status=$?
        set -e
        if (( fallback_status != 0 )); then
            overall_success=false
        fi
    elif (( attempt_status != 0 )); then
        overall_success=false
    fi
done

jq -s \
    --arg generated_at "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    --argjson all_requests_succeeded "$overall_success" \
    '{
        generated_at: $generated_at,
        synthetic_audio_only: true,
        per_request_zdr: true,
        all_requests_succeeded: $all_requests_succeeded,
        results: .
    }' "$RESULTS_JSONL" > "$OUTPUT_PATH"

print "Content-free results written to $OUTPUT_PATH"
if [[ "$overall_success" != "true" ]]; then
    exit 1
fi
