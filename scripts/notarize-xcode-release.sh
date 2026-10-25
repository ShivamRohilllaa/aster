#!/bin/bash
# Optional Xcode-account workflow. Never invoke both upload workflows for a build.
set -euo pipefail
export ASTER_RELEASE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec /usr/bin/python3 - "$@" <<'PY'
import datetime
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

ROOT = Path(os.environ["ASTER_RELEASE_ROOT"])
STATE = ROOT / ".build/xcode-release-state.json"
SOURCE_STATE = ROOT / ".build/release-state.json"


def fail(message):
    raise RuntimeError(message)


def run(*args, capture=False):
    return subprocess.run(
        [str(arg) for arg in args], check=True, text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
    )


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def bundle_digest(app):
    value = hashlib.sha256()
    for path in sorted(app.rglob("*")):
        value.update(str(path.relative_to(app)).encode() + b"\0")
        if path.is_symlink():
            value.update(b"link\0" + os.readlink(path).encode())
        elif path.is_file():
            value.update(b"file\0" + digest(path).encode())
        else:
            value.update(b"directory")
        value.update(b"\0")
    return value.hexdigest()


def save(state):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    temporary = STATE.with_suffix(".tmp")
    temporary.write_text(json.dumps(state, indent=2) + "\n")
    temporary.replace(STATE)


def source():
    state = json.loads(SOURCE_STATE.read_text())
    stage = Path(state["stage"])
    if stage.parent != Path("/private/tmp") or not stage.name.startswith("aster-release."):
        fail("Unexpected source staging directory.")
    archive = stage / "Aster-notarization.zip"
    if not archive.is_file() or digest(archive) != state["archiveSHA256"]:
        fail("The prepared source archive is missing or changed.")
    if state.get("submissionID"):
        fail("This build was already submitted with notarytool. Continue that workflow instead.")
    return state, stage, archive


def load():
    state = json.loads(STATE.read_text())
    original, stage, archive = source()
    if state["sourceSHA256"] != original["archiveSHA256"] or state["stage"] != str(stage / "xcode-release"):
        fail("Xcode state belongs to a different prepared build.")
    app = Path(state["stage"]) / "Aster.xcarchive/Products/Applications/Aster.app"
    if bundle_digest(app) != state["archiveAppSHA256"]:
        fail("The app in the Xcode archive changed. Inspect the change before continuing.")
    return state, Path(state["stage"])


def metadata(app):
    with (app / "Contents/Info.plist").open("rb") as handle:
        data = plistlib.load(handle)
    if data.get("CFBundleExecutable") != "Aster":
        fail("Unexpected application executable.")
    version = data["CFBundleShortVersionString"]
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,3}", version):
        fail("Invalid release version.")
    run("/usr/bin/lipo", app / "Contents/MacOS/Aster", "-verify_arch", "arm64", "x86_64")
    return {"version": version, "build": data["CFBundleVersion"], "bundleID": data["CFBundleIdentifier"]}


def signature(app):
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", app)
    result = run("/usr/bin/codesign", "--display", "--verbose=4", app, capture=True)
    text = result.stdout + result.stderr
    identity = re.search(r"^Authority=(Developer ID Application:.+)$", text, re.MULTILINE)
    team = re.search(r"^TeamIdentifier=([A-Z0-9]{10})$", text, re.MULTILINE)
    if not identity or not team or "(runtime)" not in text or not re.search(r"^Timestamp=", text, re.MULTILINE):
        fail("Expected a timestamped Developer ID Application signature with Hardened Runtime and TeamIdentifier.")
    return identity.group(1), team.group(1)


def assess(app, state):
    if metadata(app) != {key: state[key] for key in ("version", "build", "bundleID")}:
        fail("The exported app's identity, version or build differs from the prepared build.")
    _, team = signature(app)
    if team != state["teamID"]:
        fail("Unexpected signing team.")
    run("xcrun", "stapler", "validate", app)
    run("/usr/sbin/spctl", "--assess", "--type", "execute", "--verbose=4", app)
    if Path("/usr/bin/syspolicy_check").is_file():
        run("/usr/bin/syspolicy_check", "distribution", app)
    else:
        print("syspolicy_check unavailable; strict signature, ticket and Gatekeeper validation remain required.")


def logged(log, *args):
    print("Xcode operation log:", log, flush=True)
    with log.open("w") as output:
        result = subprocess.run([str(arg) for arg in args], stdout=output, stderr=subprocess.STDOUT, text=True)
    if result.returncode:
        fail("Xcode stopped (exit " + str(result.returncode) + "). Inspect " + str(log) + ". No final release was produced.")


def prepare():
    if STATE.exists():
        fail("Xcode release state already exists. Resume it instead of replacing a pending submission.")
    original, parent, archive = source()
    stage = parent / "xcode-release"
    if stage.exists():
        fail("Xcode staging already exists. Inspect and preserve any previous upload before starting again.")
    stage.mkdir()
    try:
        wrapper = stage / "Aster.xcarchive"
        applications = wrapper / "Products/Applications"
        run("/usr/bin/ditto", "-x", "-k", "--noqtn", archive, applications)
        app = applications / "Aster.app"
        release = metadata(app)
        if release != {key: original[key] for key in ("version", "build", "bundleID")}:
            fail("Source archive metadata differs from its recorded release state.")
        identity, team = signature(app)
        info = {
            "ArchiveVersion": 2, "CreationDate": datetime.datetime.utcnow(),
            "Name": "Aster", "SchemeName": "Aster",
            "ApplicationProperties": {
                "ApplicationPath": "Applications/Aster.app", "Architectures": ["arm64", "x86_64"],
                "CFBundleIdentifier": release["bundleID"],
                "CFBundleShortVersionString": release["version"], "CFBundleVersion": release["build"],
                "SigningIdentity": identity, "Team": team,
            },
        }
        with (wrapper / "Info.plist").open("wb") as handle:
            plistlib.dump(info, handle)
        options = {
            "method": "developer-id", "destination": "upload", "signingStyle": "manual",
            "signingCertificate": identity, "teamID": team, "manageAppVersionAndBuildNumber": False,
        }
        with (stage / "DeveloperIDUpload.plist").open("wb") as handle:
            plistlib.dump(options, handle)
        save({
            **release, "schema": 1, "stage": str(stage), "sourceSHA256": original["archiveSHA256"],
            "archiveAppSHA256": bundle_digest(app), "teamID": team, "status": "Prepared",
            "exportOptionsSHA256": digest(stage / "DeveloperIDUpload.plist"),
        })
    except BaseException:
        shutil.rmtree(stage)
        raise
    print("Prepared Xcode archive without signing or uploading:", wrapper)
    print("Next: ./scripts/notarize-xcode-release.sh submit")


def submit():
    state, stage = load()
    if state["status"] != "Prepared":
        fail("An upload was already attempted. Inspect upload.log and use finalize; do not blindly upload twice.")
    options = stage / "DeveloperIDUpload.plist"
    if digest(options) != state["exportOptionsSHA256"]:
        fail("Export options changed after preparation.")
    # Record intent before launching Xcode so an interrupted upload is not repeated.
    state["status"] = "UploadAttempted"
    save(state)
    logged(stage / "upload.log", "xcodebuild", "-exportArchive",
           "-archivePath", stage / "Aster.xcarchive",
           "-exportOptionsPlist", options, "-exportPath", stage / "upload-export")
    state["status"] = "Submitted"
    save(state)
    print("Xcode upload completed. Apple may still be processing.")
    print("Next: ./scripts/notarize-xcode-release.sh finalize")


def finalize():
    state, stage = load()
    if state["status"] not in ("Submitted", "UploadAttempted"):
        fail("An unresolved Xcode upload is required before finalization.")
    final = ROOT / "dist" / ("Aster-" + state["version"] + "-universal.zip")
    checksum = final.with_suffix(".zip.sha256")
    if final.exists() or checksum.exists():
        fail("The versioned release output already exists; refusing to overwrite it.")
    workspace = Path(tempfile.mkdtemp(prefix="finalize.", dir=stage))
    # Preserve each attempt's log outside its temporary export directory.
    log = stage / (workspace.name + ".log")
    try:
        logged(log, "xcodebuild", "-exportNotarizedApp",
               "-archivePath", stage / "Aster.xcarchive", "-exportPath", workspace / "export")
        app = workspace / "export/Aster.app"
        if not app.is_dir():
            fail("Xcode did not export the expected Aster.app.")
        # exportNotarizedApp is Apple's acceptance gate and attaches its ticket.
        # An absent/invalid ticket remains a hard failure.
        assess(app, state)
        candidate = workspace / final.name
        run("/usr/bin/ditto", "-c", "-k", "--keepParent", "--sequesterRsrc", "--noqtn", app, candidate)
        run("/usr/bin/ditto", "-x", "-k", "--noqtn", candidate, workspace / "archive-check")
        assess(workspace / "archive-check/Aster.app", state)
        checksum_value = digest(candidate)
        final.parent.mkdir(parents=True, exist_ok=True)
        pending = final.with_suffix(".zip.pending")
        shutil.copyfile(candidate, pending)
        if digest(pending) != checksum_value:
            pending.unlink()
            fail("Final archive copy failed its SHA-256 check.")
        pending.replace(final)
        checksum.write_text(checksum_value + "  " + final.name + "\n")
        state.update(status="Finalized", finalArchive=str(final), finalSHA256=checksum_value)
        save(state)
        print("Verified website release ready:", final)
        print("SHA-256:", checksum_value)
    finally:
        shutil.rmtree(workspace)


try:
    command = sys.argv[1] if len(sys.argv) == 2 else ""
    if command == "prepare":
        prepare()
    elif command == "submit":
        submit()
    elif command == "finalize":
        finalize()
    else:
        print("Usage: ./scripts/notarize-xcode-release.sh {prepare|submit|finalize}", file=sys.stderr)
        sys.exit(2)
except (RuntimeError, OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
    print("Release stopped:", error, file=sys.stderr)
    if isinstance(error, subprocess.CalledProcessError) and error.stderr:
        print(error.stderr, file=sys.stderr)
    sys.exit(1)
PY
