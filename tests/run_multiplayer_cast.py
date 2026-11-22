"""Run the standalone Ability Demo host and client with the pinned formal plugin."""

import argparse
import io
import json
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time
import zipfile


PLUGIN_COMMIT = "4e85c03ccbc523dee7a711f303bcf1134dc3f0af"
DEMO = Path(__file__).resolve().parents[1] / "multiplayer_demo"
DIAGNOSTICS = ("ERROR:", "ObjectDB instances leaked", "ObjectDB instances were leaked",
               "Resource still in use", "Resources still in use")


def prepare_project(plugin: Path, project: Path) -> None:
    shutil.copytree(DEMO, project, ignore=shutil.ignore_patterns(".gdignore", ".godot", "addons"))
    archive = subprocess.run(
        ["git", "-C", str(plugin), "archive", "--format=zip", PLUGIN_COMMIT],
        check=True, stdout=subprocess.PIPE, timeout=30,
    ).stdout
    addon = project / "addons" / "godot_gameplay_abilities"
    with zipfile.ZipFile(io.BytesIO(archive)) as source:
        source.extractall(addon)


def check_output(output: str, label: str) -> None:
    if any(diagnostic in output for diagnostic in DIAGNOSTICS):
        raise RuntimeError(f"{label} produced Godot errors")


def wait_for_listening(host: subprocess.Popen, log: Path) -> None:
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline and host.poll() is None:
        if "HOST_LISTENING" in log.read_text(encoding="utf-8", errors="replace").splitlines():
            return
        time.sleep(0.05)
    raise RuntimeError("Host did not start listening")


def load_report(output: str, marker: str) -> dict:
    lines = [line[len(marker):] for line in output.splitlines() if line.startswith(marker)]
    if len(lines) != 1:
        raise RuntimeError(f"Expected one report with marker {marker!r}")
    return json.loads(lines[0])


def verify(host_output: str, client_output: str, reconnect: bool, failure: str) -> None:
    host = load_report(host_output, "HOST_REPORT ")
    client = load_report(client_output, "CLIENT_REPORT ")
    if client["rules_nodes"] != 0 or client["ignored_snapshots"] != 0:
        raise RuntimeError("Client must have no GAS rule nodes")
    if client["snapshot"] != host["snapshot"] or any(
        host["snapshot"][key] != value for key, value in host["rules"].items()
    ):
        raise RuntimeError("Final client display, host snapshot and live rules must agree")

    snapshots = client["displayed_snapshots"]
    versions = [snapshot["version"] for snapshot in snapshots]
    if versions != sorted(set(versions)):
        raise RuntimeError("Each distinct snapshot must be displayed once in version order")
    fields = ("session", "phase", "mana", "cooldown_active", "status_active", "request_id")
    states = [tuple(snapshot[field] for field in fields) for snapshot in snapshots]
    receipts = [(r["request_id"], r["phase"], r["result"]) for r in client["receipts"]]
    if failure:
        verify_failure(host, receipts, failure)
        return
    for counter in ("payments", "cooldown_starts", "applications", "removals"):
        if host[counter] != 1:
            raise RuntimeError(f"Host {counter}: expected 1, got {host[counter]}")
    if reconnect:
        verify_reconnect(host, client, states)
        return

    counts = (host["accepted"], host["replayed_windup"], host["replayed_result"], client["ignored_receipts"])
    if counts != (1, 1, 1, 2):
        raise RuntimeError("Expected one accepted cast and two ignored replay snapshots")
    expected_states = [
        (1, "ready", 10, False, False, 0),
        (1, "windup", 10, False, False, 1),
        (1, "settled", 6, True, True, 1),
        (1, "expired", 6, True, False, 1),
        (1, "ready", 6, False, False, 1),
    ]
    if states != expected_states:
        raise RuntimeError(f"Unexpected displayed states: {states}")
    if receipts != [
        (1, "accepted", ""), (1, "accepted", ""), (2, "rejected", "BUSY"),
        (1, "finished", "APPLIED"), (1, "finished", "APPLIED"), (3, "rejected", "COOLDOWN"),
    ]:
        raise RuntimeError(f"Unexpected receipt order or content: {receipts}")
    print("Host: 2 replays, 1 payment, 1 cooldown start, 1 status application, 1 status expiry")
    print("Client: 0 rule nodes, 2 replay receipts ignored; busy and cooldown reject without altering snapshots")


def verify_failure(host: dict, receipts: list, failure: str) -> None:
    result, mana, payments = {
        "payment": ("PAYMENT_FAILED", 3, 0),
        "target": ("TARGET_INVALID", 10, 0),
        "effect": ("STATUS_NOT_APPLIED", 6, 1),
    }[failure]
    if receipts != [(1, "accepted", ""), (1, "finished", result)] or host["accepted"] != 1:
        raise RuntimeError(f"Wrong result for {failure}: {receipts}")
    if (host["payments"], host["cooldown_starts"], host["applications"], host["removals"]) != (payments, payments, 0, 0):
        raise RuntimeError(f"Wrong rule writes for {failure}: {host}")
    if host["rules"] != {"mana": mana, "cast_active": False, "cooldown_active": False, "status_active": False}:
        raise RuntimeError(f"Wrong final state for {failure}: {host['rules']}")
    print(f"Failure receipt {result}: Mana {mana}, {payments} payment, 0 status applications")


def verify_reconnect(host: dict, client: dict, states: list) -> None:
    counts = (host["accepted"], host["cancelled_casts"], host["stale_requests"], client["cleared_displays"])
    if counts != (2, 1, 2, 2):
        raise RuntimeError("Expected two accepted casts, one cancellation, two stale requests and two display resets")
    if host["replayed_windup"] or host["replayed_result"]:
        raise RuntimeError("A stale session's request reached the replay cache")
    disconnects = host["disconnects"]
    if [entry["session"] for entry in disconnects] != [1, 2]:
        raise RuntimeError("Expected windup and post-commit disconnect checkpoints")
    initial = {"mana": 10, "cooldown_active": False, "status_active": False, "cast_active": False}
    committed = {"mana": 6, "cooldown_active": True, "status_active": True, "cast_active": False}
    before_payment, after_payment = disconnects
    if before_payment["before"] != {**initial, "cast_active": True} or before_payment["after"] != initial:
        raise RuntimeError("Windup disconnect must remove the active cast without settling")
    if after_payment["before"] != committed or after_payment["after"] != committed:
        raise RuntimeError("Post-commit disconnect must preserve the settled outcome")
    for checkpoint, count in ((before_payment, 0), (after_payment, 1)):
        if any(checkpoint[key] != count for key in ("payments", "cooldown_starts", "applications")):
            raise RuntimeError(f"Unexpected writes at disconnect: {checkpoint}")
    expected = [
        (1, "ready", 10, False, False, 0),
        (1, "windup", 10, False, False, 1),
        (2, "ready", 10, False, False, 0),
        (2, "windup", 10, False, False, 1),
        (2, "settled", 6, True, True, 1),
        (3, "settled", 6, True, True, 0),
        (3, "expired", 6, True, False, 0),
        (3, "ready", 6, False, False, 0),
    ]
    if states != expected:
        raise RuntimeError(f"Unexpected reconnect snapshots: {states}")
    print("Reconnect: windup cancelled with zero writes; submitted cast preserved; 2 old-session requests rejected")


def stop(process: subprocess.Popen) -> None:
    if process.poll() is None:
        process.terminate()
        process.wait(timeout=5)


def run_pair(godot: Path, project: Path, scratch: Path, port: int, play: bool, reconnect: bool = False,
             failure: str = "") -> None:
    base = [str(godot), "--path", str(project)]
    flags = [] if play else ["--headless"]
    verify_arg = [] if play else ["--verify-reconnect" if reconnect else "--verify"]
    if failure:
        verify_arg = ["--verify-failure", failure]
    label = failure or ("reconnect" if reconnect else "cast")
    host_log = scratch / f"{label}-host.log"
    client_log = scratch / f"{label}-client.log"
    with host_log.open("wb") as server_log, client_log.open("wb") as peer_log:
        with subprocess.Popen(
            [*base, *flags, "--", "host", str(port), *verify_arg],
            stdout=server_log, stderr=subprocess.STDOUT,
        ) as host:
            try:
                wait_for_listening(host, host_log)
                print(f"Host listening on 127.0.0.1:{port}", flush=True)
                with subprocess.Popen(
                    [*base, *flags, "--", "client", str(port), *verify_arg],
                    stdout=peer_log, stderr=subprocess.STDOUT,
                ) as client:
                    try:
                        if play:
                            print("Press Enter or Space to cast, R to disconnect or reconnect. Press Ctrl+C to exit.")
                            while host.poll() is None and client.poll() is None:
                                time.sleep(0.2)
                        else:
                            if client.wait(timeout=30) != 0:
                                raise RuntimeError("Client failed")
                            if host.wait(timeout=5) != 0:
                                raise RuntimeError("Host failed")
                    finally:
                        stop(client)
            finally:
                stop(host)

    host_output = host_log.read_text(encoding="utf-8", errors="replace")
    client_output = client_log.read_text(encoding="utf-8", errors="replace")
    check_output(host_output, "Host")
    check_output(client_output, "Client")
    if not play:
        verify(host_output, client_output, reconnect, failure)


def available_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path, help="Godot console executable")
    parser.add_argument("--plugin", required=True, type=Path, help="Git checkout containing the pinned commit")
    parser.add_argument("--port", type=int, help="Optional loopback UDP port")
    parser.add_argument("--play", action="store_true", help="Open two interactive windows")
    args = parser.parse_args()
    if args.port is not None and not 1 <= args.port <= 65535:
        parser.error("--port must be between 1 and 65535")

    with tempfile.TemporaryDirectory(prefix="ability-multiplayer-") as directory:
        scratch = Path(directory)
        project = scratch / "project"
        prepare_project(args.plugin, project)
        godot = args.godot.resolve()
        imported = subprocess.run(
            [str(godot), "--headless", "--path", str(project), "--editor", "--import"],
            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120,
        )
        if imported.returncode or any(item in imported.stdout + imported.stderr for item in DIAGNOSTICS):
            raise SystemExit(imported.stdout + imported.stderr)
        try:
            run_pair(godot, project, scratch, args.port or available_port(), args.play)
            if not args.play:
                run_pair(godot, project, scratch, args.port or available_port(), False, reconnect=True)
                for failure in ("payment", "target", "effect"):
                    run_pair(godot, project, scratch, args.port or available_port(), False, failure=failure)
        except KeyboardInterrupt:
            return
        except (RuntimeError, subprocess.TimeoutExpired) as error:
            for log in sorted(scratch.glob("*.log")):
                print(f"{log.name}\n{log.read_text(encoding='utf-8', errors='replace')}")
            raise SystemExit(str(error)) from error
    if not args.play:
        print(f"PASS Ability Demo two-process cast against GAS {PLUGIN_COMMIT[:7]}")
        print("PASS Ability Demo disconnect and reconnect isolation")
        print("PASS Ability Demo per-request receipts and failure isolation")


if __name__ == "__main__":
    main()
