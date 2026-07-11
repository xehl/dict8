#!/usr/bin/env python3

import base64
import json
import pathlib
import sys


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: make_stt_payload.py <audio-path> <model>")

    audio_path = pathlib.Path(sys.argv[1])
    model = sys.argv[2]
    encoded_audio = base64.b64encode(audio_path.read_bytes()).decode("ascii")

    json.dump(
        {
            "model": model,
            "input_audio": {
                "data": encoded_audio,
                "format": "m4a",
            },
            "language": "en",
            "provider": {
                "zdr": True,
            },
        },
        sys.stdout,
        separators=(",", ":"),
    )


if __name__ == "__main__":
    main()
