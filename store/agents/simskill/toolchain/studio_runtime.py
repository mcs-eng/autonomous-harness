"""Portable runner copied into each independently installable studio package."""
import contextlib
import errno
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import uuid


_INVALID_PUBLICATION = object()


def workspace():
    return Path(os.environ.get("HARNESS_WORKSPACE", os.getcwd())).resolve()


def package():
    return Path(__file__).resolve().parent.parent


def contained(path):
    target = Path(path).resolve()
    target.relative_to(workspace())
    return target


def atomic_write(path, data):
    path = contained(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    file = tempfile.NamedTemporaryFile(mode="wb", dir=path.parent, prefix=".studio-", delete=False)
    temp = Path(file.name)
    try:
        with file:
            file.write(data)
            file.flush()
            os.fsync(file.fileno())
        os.replace(temp, path)
    finally:
        with contextlib.suppress(OSError):
            temp.unlink()


def atomic_json(path, data):
    content = (json.dumps(data, indent=2, allow_nan=False) + "\n").encode()
    atomic_write(path, content)


def _publication(data):
    if not isinstance(data, dict):
        return _INVALID_PUBLICATION
    if "publication" not in data:
        return None
    publication = data["publication"]
    if (not isinstance(publication, dict) or publication.get("spec") != 1 or
            not isinstance(publication.get("token"), str) or len(publication["token"]) != 32 or
            any(char not in "0123456789abcdef" for char in publication["token"])):
        return _INVALID_PUBLICATION
    return publication


def _read_json(path):
    return json.loads(contained(path).read_text())


def _published(path, result, verdict):
    publication = _publication(result)
    if publication is None:
        return True
    if publication is _INVALID_PUBLICATION or result.get("id") != path.parent.name:
        return False
    relative = path.relative_to(workspace()).as_posix()
    if (verdict.get("ready") is True and verdict.get("runId") == result["id"] and
            verdict.get("publication") == publication and verdict.get("artifact") == relative):
        return True
    try:
        marker = _read_json(path.parent / ".published.json")
    except (OSError, ValueError):
        return False
    return marker == {"spec": 1, "id": result["id"], "token": publication["token"]}


def _current_verdict():
    try:
        verdict = _read_json(workspace() / ".harness/verdict.json")
        return verdict if isinstance(verdict, dict) else {}
    except (OSError, ValueError):
        return {}


def _archive_current_result():
    try:
        verdict = _read_json(workspace() / ".harness/verdict.json")
    except FileNotFoundError:
        return
    if not isinstance(verdict, dict):
        raise ValueError("The current studio result has invalid publication state")
    if verdict.get("ready") is not True or "publication" not in verdict:
        return
    run_id = verdict.get("runId")
    artifact = verdict.get("artifact")
    if not isinstance(run_id, str) or not isinstance(artifact, str):
        raise ValueError("The current studio result has invalid publication state")
    result_path = contained(workspace() / artifact)
    expected = contained(workspace() / "out/runs" / run_id / "result.json")
    try:
        result = _read_json(result_path)
    except (FileNotFoundError, ValueError) as exc:
        raise ValueError("The current studio result cannot be finalized") from exc
    if result_path != expected or not _published(result_path, result, verdict):
        raise ValueError("The current studio result has invalid publication state")
    publication = _publication(result)
    marker_path = result_path.parent / ".published.json"
    marker = {"spec": 1, "id": run_id, "token": publication["token"]}
    try:
        existing = _read_json(marker_path)
    except FileNotFoundError:
        atomic_json(marker_path, marker)
    else:
        if existing != marker:
            raise ValueError("The current studio result has invalid publication state")


def _owns_verdict(verdict, run_id, publication):
    return (verdict.get("runId") == run_id and verdict.get("publication") == publication and
            verdict.get("ready") is False)


def _file_lock(handle, acquire, platform=os.name, backend=None):
    if backend is None:
        backend = __import__({"nt": "msvcrt", "posix": "fcntl"}[platform])
    handle.seek(0)
    if platform == "nt":
        backend.locking(handle.fileno(), backend.LK_NBLCK if acquire else backend.LK_UNLCK, 1)
    else:
        operation = backend.LOCK_EX | backend.LOCK_NB if acquire else backend.LOCK_UN
        backend.flock(handle.fileno(), operation)


def _acquire_run_lock():
    path = contained(workspace() / ".harness/studio.lock")
    path.parent.mkdir(parents=True, exist_ok=True)
    handle = path.open("a+b")
    try:
        handle.seek(0, os.SEEK_END)
        if handle.tell() == 0:
            handle.write(b"\0")
            handle.flush()
        try:
            _file_lock(handle, True)
        except OSError as exc:
            if exc.errno in (errno.EACCES, errno.EAGAIN):
                raise RuntimeError("Another studio run is already in progress") from None
            raise
        return handle
    except Exception:
        handle.close()
        raise


def _release_run_lock(handle):
    with contextlib.suppress(OSError):
        _file_lock(handle, False)
    with contextlib.suppress(OSError):
        handle.close()


def _error_line(exc):
    detail = exc.strerror if isinstance(exc, OSError) and exc.strerror else str(exc)
    detail = " ".join(detail.splitlines()).strip() or type(exc).__name__
    return f"Studio run failed: {detail}"


def command(argv, cwd=None, timeout=120, env=None):
    """No shell interpolation; keep complete logs as output, bound execution time."""
    result = subprocess.run([str(x) for x in argv], cwd=cwd, timeout=timeout,
                            env=env, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError((result.stderr or result.stdout)[-1600:] or f"{argv[0]} exited {result.returncode}")
    return result.stdout


def parameters(config, values):
    if not isinstance(values, dict) or set(values) - {c["id"] for c in config["controls"]}:
        raise ValueError("Invalid studio controls")
    result = {}
    for c in config["controls"]:
        value = values.get(c["id"], c["value"])
        if c["type"] == "number":
            if type(value) not in (int, float) or not math.isfinite(value) or not c["min"] <= value <= c["max"]:
                raise ValueError(f'{c["label"]} is outside its range')
            if c.get("integer") and value != int(value):
                raise ValueError(f'{c["label"]} must be a whole number')
        elif c["type"] == "select":
            if value not in [o["value"] for o in c["options"]]:
                raise ValueError(f'Unknown {c["label"]}')
        elif not isinstance(value, str) or len(value) > c.get("maxLength", 500):
            raise ValueError(f'Invalid {c["label"]}')
        result[c["id"]] = value
    return result


def metric(label, value, unit=""):
    return {"label": label, "value": value, "unit": unit}


def previous_runs():
    base = contained(workspace() / "out/runs")
    verdict = _current_verdict()
    rows = []
    for p in sorted(base.glob("*/result.json")):
        try:
            result = _read_json(p)
            if _published(p, result, verdict):
                rows.append(result)
        except (ValueError, OSError):
            continue
    return rows[-100:]


def execute(actions):
    root = workspace()
    config = json.loads((package() / "studio.config.json").read_text())
    action = sys.argv[1] if len(sys.argv) > 1 else config["actions"][0]["id"]
    started = time.monotonic()
    verdict_path = root / ".harness/verdict.json"
    run_id = time.strftime("%Y%m%dT%H%M%S", time.gmtime()) + "-" + uuid.uuid4().hex[:8]
    publication = {"spec": 1, "token": uuid.uuid4().hex}
    verdict = {"spec": 1, "ready": False, "summary": "Preparing the studio run", "findings": [],
               "runId": run_id, "publication": publication,
               "phases": [{"id": "run", "name": "Make", "state": "active"},
                          {"id": "inspect", "name": "Inspect", "state": "pending"}]}
    preparing_written = False
    latest_path = root / "out/latest.json"
    latest_before = None
    latest_existed = False
    latest_written = False
    releases = contextlib.ExitStack()
    try:
        lock = _acquire_run_lock()
        releases.callback(_release_run_lock, lock)
        _archive_current_result()
        atomic_json(verdict_path, verdict)
        preparing_written = True
        if action not in actions:
            raise ValueError(f"Unknown action: {action}")
        source = contained(root / "studio.json")
        if source.stat().st_size > 16384:
            raise ValueError("studio.json is too large")
        project = json.loads(source.read_text())
        p = parameters(config, project["parameters"])
        output = contained(root / "out/runs" / run_id)
        output.mkdir(parents=True)
        print(f'{config["title"]}: {action}', flush=True)
        result = actions[action](p, output)
        artifacts = []
        for artifact in result.pop("files", []):
            file = contained(output / artifact["name"])
            file.relative_to(output)
            if not file.is_file() or not file.stat().st_size:
                raise ValueError(f'Missing output: {artifact["name"]}')
            artifacts.append({"label": artifact["label"], "path": str(file.relative_to(root))})
        result.update({"spec": 1, "id": run_id, "action": action, "parameters": p,
                       "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                       "durationSeconds": round(time.monotonic() - started, 3), "artifacts": artifacts,
                       "upstream": json.loads((package() / "upstream.lock.json").read_text()),
                       "publication": publication})
        atomic_json(output / "result.json", result)
        try:
            latest_before = contained(latest_path).read_bytes()
            latest_existed = True
        except FileNotFoundError:
            pass
        atomic_json(latest_path, result)
        latest_written = True
        verdict.update({"ready": True, "summary": f'{result["title"]} · {result["engine"]}',
                        "artifact": (output / "result.json").relative_to(root).as_posix(),
                        "runId": run_id, "publication": publication,
                        "phases": [{"id": "run", "name": "Make", "state": "done"},
                                   {"id": "inspect", "name": "Inspect", "state": "done"}],
                        "updatedAt": result["createdAt"]})
        if not _owns_verdict(_current_verdict(), run_id, publication):
            raise RuntimeError("Another studio run replaced this run's state")
        atomic_json(verdict_path, verdict)
    except Exception as exc:
        if latest_written:
            try:
                current_latest = _read_json(latest_path)
                if current_latest.get("id") == run_id and current_latest.get("publication") == publication:
                    if latest_existed:
                        atomic_write(latest_path, latest_before)
                    else:
                        contained(latest_path).unlink(missing_ok=True)
            except (AttributeError, OSError, ValueError):
                pass
        if preparing_written and _owns_verdict(_current_verdict(), run_id, publication):
            failure = {"spec": 1, "ready": False, "summary": str(exc)[:500],
                       "runId": run_id, "publication": publication,
                       "findings": [{"severity": "error", "kind": "run-failed", "message": str(exc)[:1000]}],
                       "phases": [{"id": "run", "name": "Make", "state": "failed"}]}
            try:
                atomic_json(verdict_path, failure)
            except (ValueError, OSError):
                pass
        print(_error_line(exc), file=sys.stderr)
        raise SystemExit(1) from exc
    finally:
        releases.close()
    print(f'Ready: {result["title"]}', flush=True)
