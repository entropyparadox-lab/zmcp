#!/usr/bin/env python3
"""Bounded real stdio smoke; communicate drains stdout while feeding large input."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zig", default="zig")
    args = parser.parse_args()
    text = "abcdefgh" * 32768
    requests = [
        {"id": 1, "method": "initialize", "params": {
            "protocolVersion": "2024-11-05", "capabilities": {},
            "clientInfo": {"name": "zmcp-smoke", "version": "1.0.0"}, "_meta": None}},
        {"method": "notifications/initialized"},
        {"id": 2, "method": "tools/list"},
        {"id": 3, "method": "tools/call", "params": {
            "name": "add", "arguments": {"a": 7, "b": 5}}},
        {"id": 4, "method": "tools/call", "params": {
            "name": "reverse_string", "arguments": {"text": text}}},
        {"id": 5, "method": "tools/call", "params": {
            "name": "system_status", "arguments": {}}},
        {"id": 6, "method": "tools/call", "params": {
            "name": "add", "arguments": {"a": "invalid", "b": 5}}},
    ]
    payload = b"".join((json.dumps({"jsonrpc": "2.0", **r}) + "\n").encode()
                       for r in requests)
    process = subprocess.Popen(
        [args.zig, "build", "run-example"], cwd=Path(__file__).resolve().parents[1],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        start_new_session=True,
    )
    try:
        stdout, stderr = process.communicate(payload, timeout=60)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        raise SystemExit("stdio smoke exceeded 60 seconds; process group killed")
    if process.returncode:
        raise SystemExit(stderr.decode(errors="replace"))
    replies = [json.loads(line) for line in stdout.splitlines()]
    assert [r["id"] for r in replies] == [1, 2, 3, 4, 5, 6], replies
    assert all(r["jsonrpc"] == "2.0" and "result" in r for r in replies)
    assert replies[0]["result"]["protocolVersion"] == "2024-11-05"
    assert replies[0]["result"]["serverInfo"]["version"] == "1.1.1"
    assert {t["name"] for t in replies[1]["result"]["tools"]} == {
        "add", "reverse_string", "system_status"}
    assert replies[2]["result"]["content"][0]["text"] == "Sum: 12"
    assert replies[3]["result"]["content"][0]["text"] == text[::-1]
    assert "0.17.1" in replies[4]["result"]["content"][0]["text"]
    assert all(not r["result"]["isError"] for r in replies[2:5])
    assert replies[5]["result"]["isError"] is True
    print(json.dumps({"status": "passed", "responses": len(replies),
                      "notification_responses": 0, "large_text_bytes": len(text),
                      "stdin_bytes": len(payload), "stdout_bytes": len(stdout)}))


if __name__ == "__main__":
    main()
