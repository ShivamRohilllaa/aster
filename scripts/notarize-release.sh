#!/bin/bash
# Deliberately separate upload, status and finalization: Apple can take time.
set -euo pipefail
export ASTER_RELEASE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec /usr/bin/python3 - "$@" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import uuid

ROOT = Path(os.environ["ASTER_RELEASE_ROOT"])
STATE = ROOT / ".build/release-state.json"
LOCAL_ZIP = ROOT / "dist/Aster-universal-local.zip"


def fail(message):
    raise RuntimeError(message)


def run(*args, capture=False):
    return subprocess.run(
        [str(arg) for arg in args], check=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
        text=True,
    )


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest() if hasattr(hashlib, "file_digest") else digest_older_python(source)


def digest_older_python(source):
    result = hashlib.sha256()
    for block in iter(lambda: source.read(1024 * 1024), b""):
        result.update(block)
    return result.hexdigest()


def save(state):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    temporary = STATE.with_suffix(".tmp")
    temporary.write_text(json.dumps(state, indent=2) + "\n")
    temporary.replace(STATE)


def load():
    state = json.loads(STATE.read_text())
    stage = Path(state["stage"])
    if stage.parent != Path("/private/tmp") or not stage.name.startswith("aster-release."):
        fail("Unexpected release staging directory in saved state.")
    archive = stage / "Aster-notarization.zip"
    if not archive.is_file() or digest(archive) != state["archiveSHA256"]:
        fail("The submitted archive is missing or changed. Do not reuse this submission for another build.")
    if state.get("submissionID"):
        uuid.UUID(state["submissionID"])
    return state, stage, archive


def profile(state=None):
    value = os.environ.get("ASTER_NOTARY_PROFILE", "")
    if not value:
        fail("Set ASTER_NOTARY_PROFILE to the name of credentials already stored in Keychain.")
    if state and state.get("notaryProfile") != value:
        fail("Use the same ASTER_NOTARY_PROFILE as the saved submission.")
    return value


def metadata(app):
    with (app / "Contents/Info.plist").open("rb") as source:
        data = plistlib.load(source)
    version = data["CFBundleShortVersionString"]
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,3}", version):
        fail("The version must contain only a numeric release version.")
    if data.get("CFBundleExecutable") != "Aster":
        fail("Unexpected executable name.")
    run("/usr/bin/lipo", app / "Contents/MacOS/Aster", "-verify_arch", "arm64", "x86_64")
    return {
        "version": version,
        "build": data["CFBundleVersion"],
        "bundleID": data["CFBundleIdentifier"],
    }


def verify_signature(app):
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", app)
    details = run("/usr/bin/codesign", "--display", "--verbose=4", app, capture=True)
    text = details.stdout + details.stderr
    if "Authority=Developer ID Application:" not in text:
        fail("A Developer ID Application signature is required; ad-hoc and development signatures are insufficient.")
    if "(runtime)" not in text or not re.search(r"^Timestamp=", text, re.MULTILINE):
        fail("The signature must enable Hardened Runtime and include a secure timestamp.")


def assess(app):
    metadata(app)
    verify_signature(app)
    run("xcrun", "stapler", "validate", app)
    run("/usr/sbin/spctl", "--assess", "--type", "execute", "--verbose=4", app)
    if Path("/usr/bin/syspolicy_check").is_file():
        run("/usr/bin/syspolicy_check", "distribution", app)
    else:
        print("syspolicy_check unavailable on this host; codesign, stapler and Gatekeeper checks are still required.")


def notarization_info(state, stage):
    result = run(
        "xcrun", "notarytool", "info", state["submissionID"],
        "--keychain-profile", profile(state), "--output-format", "json", capture=True,
    )
    (stage / "notary-status.json").write_text(result.stdout)
    info = json.loads(result.stdout)
    if info.get("id") != state["submissionID"]:
        fail("Apple returned a different submission ID; refusing to continue.")
    state["status"] = info["status"]
    save(state)
    print("Apple notarization status:", info["status"])
    return info["status"]


def prepare():
    if STATE.exists():
        fail("Release state already exists. Resume it, or move .build/release-state.json aside before preparing a new build.")
    identity = os.environ.get("ASTER_SIGN_IDENTITY", "")
    if not identity or identity == "-":
        fail("Set ASTER_SIGN_IDENTITY to your Developer ID Application identity name or SHA-1.")
    if not LOCAL_ZIP.is_file():
        fail("Build the universal local archive first: ./scripts/build-app.sh --universal")
    stage = Path(tempfile.mkdtemp(prefix="aster-release.", dir="/private/tmp"))
    try:
        unpacked = stage / "prepare"
        run("/usr/bin/ditto", "-x", "-k", "--noqtn", LOCAL_ZIP, unpacked)
        app = unpacked / "Aster.app"
        release = metadata(app)
        # Only clean our generated staging copy, never a user's app or files.
        # A recursive xattr clear also removes File Provider metadata before signing.
        run("/usr/bin/xattr", "-cr", app)
        run("/usr/bin/codesign", "--force", "--sign", identity,
            "--options", "runtime", "--timestamp", app)
        verify_signature(app)
        archive = stage / "Aster-notarization.zip"
        run("/usr/bin/ditto", "-c", "-k", "--keepParent", "--norsrc",
            "--noextattr", "--noqtn", app, archive)
        # Verify exactly what will be submitted, after extraction.
        verification = stage / "submission-check"
        run("/usr/bin/ditto", "-x", "-k", "--noqtn", archive, verification)
        verify_signature(verification / "Aster.app")
        metadata(verification / "Aster.app")
        save({
            **release, "schema": 1, "stage": str(stage),
            "sourceSHA256": digest(LOCAL_ZIP), "archiveSHA256": digest(archive),
            "status": "Prepared", "submissionID": None,
        })
    except BaseException:
        shutil.rmtree(stage)
        raise
    print("Prepared and verified a signed universal archive:", archive)
    print("Next: ASTER_NOTARY_PROFILE=your-profile ./scripts/notarize-release.sh submit")


def submit():
    state, stage, archive = load()
    if state["submissionID"]:
        fail("Already submitted. Use status or finalize; do not submit the same build again.")
    name = profile()
    response = stage / "notary-submit.json"
    if response.exists() and response.stat().st_size:
        fail("A previous upload response exists. Inspect it and recover its submission ID before retrying, to avoid duplicate uploads.")
    # Persist the response even if the caller interrupts after Apple accepts it.
    # No --wait: uploading and polling are separate operations.
    with response.open("w") as output:
        subprocess.run([
            "xcrun", "notarytool", "submit", str(archive),
            "--keychain-profile", name, "--output-format", "json", "--no-wait",
        ], stdout=output, check=True, text=True)
    result = json.loads(response.read_text())
    submission = str(uuid.UUID(result["id"]))
    state.update(submissionID=submission, notaryProfile=name, status="Submitted")
    save(state)
    print("Submitted to Apple:", submission)
    print("Next: ./scripts/notarize-release.sh status (keep ASTER_NOTARY_PROFILE set)")


def finalize():
    state, stage, archive = load()
    if not state["submissionID"]:
        fail("Submit this build first.")
    if notarization_info(state, stage) != "Accepted":
        fail("Apple has not accepted this exact build. No website release archive was produced.")
    final = ROOT / "dist" / ("Aster-" + state["version"] + "-universal.zip")
    checksum = final.with_suffix(".zip.sha256")
    if final.exists() or checksum.exists():
        fail("The versioned release output already exists. Preserve it; use a new app version for a different release.")
    # Always extract the hashed submission artifact, not a possibly modified app.
    workspace = Path(tempfile.mkdtemp(prefix="finalize.", dir=stage))
    try:
        run("/usr/bin/ditto", "-x", "-k", "--noqtn", archive, workspace / "input")
        app = workspace / "input/Aster.app"
        if metadata(app) != {key: state[key] for key in ("version", "build", "bundleID")}:
            fail("The saved submission metadata does not match the archive.")
        verify_signature(app)
        run("xcrun", "stapler", "staple", app)
        assess(app)
        candidate = workspace / final.name
        # Preserve stapler's ticket and bundle metadata. The staging app was
        # cleaned before signing; never strip metadata after stapling.
        run("/usr/bin/ditto", "-c", "-k", "--keepParent", "--sequesterRsrc",
            "--noqtn", app, candidate)
        run("/usr/bin/ditto", "-x", "-k", "--noqtn", candidate, workspace / "archive-check")
        assess(workspace / "archive-check/Aster.app")
        expected_hash = digest(candidate)
        # Copy to a temporary destination and check bytes before publishing.
        final.parent.mkdir(parents=True, exist_ok=True)
        pending = final.with_suffix(".zip.pending")
        shutil.copyfile(candidate, pending)
        if digest(pending) != expected_hash:
            pending.unlink()
            fail("The final copy failed its SHA-256 check.")
        pending.replace(final)
        checksum.write_text(expected_hash + "  " + final.name + "\n")
        state.update(status="Finalized", finalArchive=str(final), finalSHA256=expected_hash)
        save(state)
        print("Website release ready:", final)
        print("SHA-256:", expected_hash)
        print("Checksum file:", checksum)
    finally:
        shutil.rmtree(workspace)


try:
    command = sys.argv[1] if len(sys.argv) == 2 else ""
    if command == "prepare":
        prepare()
    elif command == "submit":
        submit()
    elif command == "status":
        state, stage, _ = load()
        if not state["submissionID"]:
            fail("This archive has not been submitted.")
        status = notarization_info(state, stage)
        if status == "Invalid":
            fail("Apple rejected the build. Retrieve its notarytool log and fix the issue before preparing a new build.")
    elif command == "finalize":
        finalize()
    else:
        print("Usage: ./scripts/notarize-release.sh {prepare|submit|status|finalize}", file=sys.stderr)
        sys.exit(2)
except (RuntimeError, OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
    print("Release stopped:", error, file=sys.stderr)
    if isinstance(error, subprocess.CalledProcessError) and error.stderr:
        print(error.stderr, file=sys.stderr)
    sys.exit(1)
PY
