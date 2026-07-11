#!/usr/bin/env python3

import json
import sys
from typing import Any


MARKER = "\n__DICT8_CURL_META__"


def error_category(status: int, parsed: dict[str, Any] | None) -> str | None:
    if status == 0:
        return "network_or_timeout"
    if 200 <= status < 300:
        text = parsed.get("text") if parsed else None
        return None if isinstance(text, str) and text.strip() else "empty_result"
    if status == 400:
        return "invalid_request_or_media"
    if status == 401:
        return "authentication"
    if status == 402:
        return "insufficient_credits"
    if status == 404:
        return "model_or_endpoint_unavailable"
    if status == 413:
        return "payload_too_large"
    if status == 429:
        return "rate_limit"
    if status in {408, 500, 502, 503, 504}:
        return "transient_or_unavailable"
    return "http_error"


def main() -> None:
    raw = sys.stdin.read()
    body, separator, metadata = raw.rpartition(MARKER)
    if not separator:
        body = raw
        metadata = "0\t0\t0\t0"

    metadata_fields = metadata.strip().split("\t")
    metadata_fields += ["0"] * (4 - len(metadata_fields))
    try:
        status = int(metadata_fields[0])
    except ValueError:
        status = 0

    try:
        parsed = json.loads(body) if body.strip() else None
    except json.JSONDecodeError:
        parsed = None

    parsed_object = parsed if isinstance(parsed, dict) else None
    text = parsed_object.get("text") if parsed_object else None
    text_length = len(text.strip()) if isinstance(text, str) else 0
    usage = parsed_object.get("usage") if parsed_object else None
    usage_object = usage if isinstance(usage, dict) else {}
    category = error_category(status, parsed_object)

    safe_usage_keys = (
        "cost",
        "seconds",
        "input_tokens",
        "output_tokens",
        "total_tokens",
    )
    safe_usage = {
        key: usage_object[key]
        for key in safe_usage_keys
        if isinstance(usage_object.get(key), (int, float))
    }

    result = {
        "success": category is None,
        "http_status": status,
        "latency_seconds": round(float(metadata_fields[1]), 3),
        "upload_bytes": int(float(metadata_fields[2])),
        "download_bytes": int(float(metadata_fields[3])),
        "transcript_character_count": text_length,
        "error_category": category,
        "fallback_eligible": category
        in {
            "network_or_timeout",
            "model_or_endpoint_unavailable",
            "rate_limit",
            "transient_or_unavailable",
        },
        "usage": safe_usage,
    }
    json.dump(result, sys.stdout, separators=(",", ":"))


if __name__ == "__main__":
    main()
