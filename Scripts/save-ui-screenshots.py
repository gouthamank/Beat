"""Saves the screenshots the last Mac UI-test run attached (named screenshot.<reference>) as their references in
BeatUITests/__Snapshots__. The test runner is sandboxed and can't write to the repo, so its new and changed screenshots
reach it this way. Run by `make mac-test-ui-record`; look at the failures first, since whatever was attached is saved."""
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

results = sorted(glob.glob("build/Logs/Test/Test-BeatUITests-*.xcresult"), key=os.path.getmtime)
if not results:
    sys.exit("No UI-test results in build/Logs/Test: run make mac-test-ui first.")

exported = tempfile.mkdtemp()
subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", results[-1], "--output-path", exported],
               check=True, stdout=subprocess.DEVNULL)
with open(os.path.join(exported, "manifest.json")) as manifest:
    tests = json.load(manifest)

saved = 0
for test in tests:
    for attachment in test["attachments"]:
        # xcresulttool puts "_<n>_<UUID>" before the name's last dot-part: "screenshot.A.b.mac" became
        # "screenshot.A.b_0_<UUID>.mac".
        match = re.match(r"screenshot\.(.+)_\d+_[0-9A-Fa-f-]{36}(\.[^.]+)?$", attachment.get("suggestedHumanReadableName", ""))
        if not match:
            continue
        name = match.group(1) + (match.group(2) if match.group(2) not in (None, ".png") else "")
        reference = os.path.join("BeatUITests", "__Snapshots__", name + ".png")
        os.makedirs(os.path.dirname(reference), exist_ok=True)
        shutil.copyfile(os.path.join(exported, attachment["exportedFileName"]), reference)
        print("Saved", reference)
        saved += 1
shutil.rmtree(exported)
print(f"{saved} reference(s) saved from {results[-1]}." if saved else "Nothing to save: every screenshot matched its reference.")
