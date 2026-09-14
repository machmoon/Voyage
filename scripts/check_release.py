#!/usr/bin/env python3
"""Pre-upload validation for Voyage — catches what App Store Connect would reject.

Two modes, both dependency-free (stdlib only):

    python3 scripts/check_release.py                    # source mode: project.yml + Info.plists + icon
    python3 scripts/check_release.py --archive build/Voyage.xcarchive   # built-bundle mode

Source mode runs before a build, so a problem costs seconds instead of a
40-minute archive and a rejected upload. Archive mode re-checks the same
invariants against what actually got built, including the keys Xcode injects
at build time (CFBundleIconName) that cannot be seen in the source plist.

Exit status: 0 all clear, 1 at least one BLOCKER. WARN never fails the run.
"""
import os
import plistlib
import re
import struct
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

APP_PLIST = "Voyage/Support/Info.plist"
WIDGET_PLIST = "VoyageWidgets/Info.plist"
ICON = "Voyage/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
PROJECT_YML = "project.yml"

# API used in Swift source -> Info.plist key App Review requires for it.
# A missing usage-description string is an automatic rejection, so this is
# derived from the code rather than trusted to stay in sync by hand.
PERMISSION_APIS = [
    (r"requestWhenInUseAuthorization|requestLocation\(", "NSLocationWhenInUseUsageDescription"),
    (r"requestAlwaysAuthorization", "NSLocationAlwaysAndWhenInUseUsageDescription"),
    (r"AVCaptureDevice|UIImagePickerController", "NSCameraUsageDescription"),
    (r"AVAudioRecorder|AVAudioEngine\(\)\.inputNode|\.record\b", "NSMicrophoneUsageDescription"),
    (r"PHPhotoLibrary|PHPickerViewController", "NSPhotoLibraryUsageDescription"),
    (r"CNContactStore", "NSContactsUsageDescription"),
    (r"EKEventStore", "NSCalendarsUsageDescription"),
    (r"HKHealthStore", "NSHealthShareUsageDescription"),
    (r"SFSpeechRecognizer", "NSSpeechRecognitionUsageDescription"),
    (r"CMMotionManager|CMPedometer", "NSMotionUsageDescription"),
    (r"ATTrackingManager", "NSUserTrackingUsageDescription"),
    (r"LAContext", "NSFaceIDUsageDescription"),
    (r"CBCentralManager", "NSBluetoothAlwaysUsageDescription"),
    (r"MPMediaLibrary", "NSAppleMusicUsageDescription"),
]

problems = []


def blocker(msg):
    problems.append(("BLOCKER", msg))


def warn(msg):
    problems.append(("WARN", msg))


def rel(path):
    return os.path.join(ROOT, path)


def load_plist(path):
    with open(path, "rb") as f:
        return plistlib.load(f)


# --------------------------------------------------------------------------
# icon
# --------------------------------------------------------------------------

def check_icon(path, label):
    """Reads the PNG header directly — no Xcode, no Pillow needed."""
    if not os.path.exists(path):
        blocker("%s: app icon missing at %s" % (label, path))
        return
    with open(path, "rb") as f:
        head = f.read(33)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        blocker("%s: %s is not a PNG" % (label, path))
        return
    width, height, depth, color = struct.unpack(">IIBB", head[16:26])
    if color in (4, 6):
        blocker(
            "%s: app icon has an ALPHA CHANNEL (PNG color type %d). App Store Connect "
            "rejects this at upload (ITMS-90717) even when every pixel is opaque.\n"
            "        Fix: python3 scripts/flatten_icon.py %s"
            % (label, color, path))
    if (width, height) != (1024, 1024):
        blocker("%s: app icon is %dx%d; the App Store icon must be 1024x1024"
                % (label, width, height))
    if depth != 8:
        warn("%s: app icon bit depth is %d, expected 8" % (label, depth))


# --------------------------------------------------------------------------
# source mode
# --------------------------------------------------------------------------

def yml_setting(text, key):
    m = re.search(r"^\s*%s:\s*\"?([^\"\n#]+?)\"?\s*(?:#.*)?$" % re.escape(key), text, re.M)
    return m.group(1).strip() if m else None


def swift_sources():
    for base in ("Voyage", "VoyageWidgets"):
        for dirpath, _, files in os.walk(rel(base)):
            for name in files:
                if name.endswith(".swift"):
                    yield os.path.join(dirpath, name)


def check_source():
    yml = open(rel(PROJECT_YML)).read()
    app = load_plist(rel(APP_PLIST))
    widget = load_plist(rel(WIDGET_PLIST))

    marketing = yml_setting(yml, "MARKETING_VERSION")
    build = yml_setting(yml, "CURRENT_PROJECT_VERSION")
    print("  project.yml MARKETING_VERSION=%s CURRENT_PROJECT_VERSION=%s" % (marketing, build))

    # -- versioning ---------------------------------------------------------
    if not build or not build.isdigit():
        blocker("project.yml: CURRENT_PROJECT_VERSION %r is not an integer" % build)
    elif build == "1":
        blocker(
            "project.yml: CURRENT_PROJECT_VERSION is still 1 — that is the build App Review "
            "rejected on 2026-08-05. App Store Connect refuses an upload that reuses a build "
            "number.\n        Fix: scripts/ship.sh --bump")

    for plist, name in ((app, "app"), (widget, "widget")):
        if plist.get("CFBundleVersion") != "$(CURRENT_PROJECT_VERSION)":
            blocker("%s Info.plist: CFBundleVersion is %r, not $(CURRENT_PROJECT_VERSION). "
                    "A hardcoded value drifts from the app and fails upload validation on an "
                    "app/extension build-number mismatch." % (name, plist.get("CFBundleVersion")))
        if plist.get("CFBundleShortVersionString") != "$(MARKETING_VERSION)":
            blocker("%s Info.plist: CFBundleShortVersionString is %r, not $(MARKETING_VERSION)."
                    % (name, plist.get("CFBundleShortVersionString")))

    # -- bundle identifiers -------------------------------------------------
    ids = re.findall(r"PRODUCT_BUNDLE_IDENTIFIER:\s*(\S+)", yml)
    # The distributable id, registered under team 3QQL2XA4VS. The script
    # arrived from a lineage that still used the pre-submission
    # "com.patliu.voyage" and flagged the real one as a blocker.
    app_id = "com.patrickliu.voyage"
    if app_id not in ids:
        blocker("project.yml: expected the app bundle id %s" % app_id)
    for bid in ids:
        if bid != app_id and not bid.startswith(app_id + "."):
            warn("project.yml: bundle id %s is not nested under %s" % (bid, app_id))
    widget_ids = [b for b in ids if b.endswith(".widgets")]
    if not widget_ids:
        blocker("project.yml: no widget-extension bundle id found")
    elif not widget_ids[0].startswith(app_id + "."):
        blocker("project.yml: widget bundle id %s must be a child of the app id %s, or the "
                "embedded extension is rejected" % (widget_ids[0], app_id))

    # -- device family ------------------------------------------------------
    families = set(re.findall(r"TARGETED_DEVICE_FAMILY:\s*\"?([0-9,]+)\"?", yml))
    if families != {"1"}:
        warn("project.yml: TARGETED_DEVICE_FAMILY values %s — the app ships iPhone-only ('1'); "
             "a mismatch between app and extension changes what App Review installs on"
             % sorted(families))
    orientations = app.get("UISupportedInterfaceOrientations", [])
    if orientations != ["UIInterfaceOrientationPortrait"]:
        warn("app Info.plist: UISupportedInterfaceOrientations is %s; the app is designed "
             "portrait-only" % orientations)

    # -- permission usage strings ------------------------------------------
    code = ""
    for path in swift_sources():
        code += open(path, encoding="utf-8", errors="replace").read()
    for pattern, key in PERMISSION_APIS:
        if re.search(pattern, code) and key not in app:
            blocker("app Info.plist: code calls an API matching /%s/ but %s is missing — "
                    "an automatic App Review rejection" % (pattern, key))
    for key in [k for k in app if k.endswith("UsageDescription")]:
        print("  usage string present: %s" % key)

    # -- export compliance --------------------------------------------------
    if "ITSAppUsesNonExemptEncryption" not in app:
        blocker("app Info.plist: ITSAppUsesNonExemptEncryption is missing. Without it every "
                "upload stalls waiting for a manual export-compliance answer in App Store "
                "Connect before the build can be submitted.")

    # -- signing ------------------------------------------------------------
    if "DEVELOPMENT_TEAM" not in yml:
        warn("project.yml: no DEVELOPMENT_TEAM. `xcodebuild archive` for a device will fail "
             "with \"Signing for 'Voyage' requires a development team\" unless the team id is "
             "passed on the command line (ship.sh does this from $VOYAGE_TEAM_ID).")

    # -- deployment target vs SDK ------------------------------------------
    target = yml_setting(yml, "iOS")
    try:
        sdk = subprocess.check_output(
            ["xcrun", "--sdk", "iphoneos", "--show-sdk-version"], text=True).strip()
        print("  deployment target iOS %s, building against iOS SDK %s" % (target, sdk))
        if target and float(target) > float(sdk.split(".")[0] + "." + (sdk.split(".") + ["0"])[1]):
            blocker("deployment target iOS %s is newer than the installed SDK %s" % (target, sdk))
    except (OSError, subprocess.CalledProcessError):
        warn("could not read the iOS SDK version (is Xcode selected?)")

    check_icon(rel(ICON), "source")


# --------------------------------------------------------------------------
# archive mode
# --------------------------------------------------------------------------

def check_archive(archive):
    apps = os.path.join(archive, "Products", "Applications")
    if not os.path.isdir(apps):
        blocker("%s: no Products/Applications — not a valid .xcarchive" % archive)
        return
    bundle = os.path.join(apps, next(n for n in os.listdir(apps) if n.endswith(".app")))
    app = load_plist(os.path.join(bundle, "Info.plist"))
    print("  archived %s  version %s (%s)"
          % (app.get("CFBundleIdentifier"), app.get("CFBundleShortVersionString"),
             app.get("CFBundleVersion")))

    # actool writes the iOS asset-catalog name under CFBundlePrimaryIcon.
    primary_icon = app.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon", {})
    if not primary_icon.get("CFBundleIconName") and not app.get("CFBundleIconName"):
        blocker("built app Info.plist: CFBundleIconName is missing (ITMS-90713). The asset "
                "catalog icon was not compiled in — check ASSETCATALOG_COMPILER_APPICON_NAME.")
    if "ITSAppUsesNonExemptEncryption" not in app:
        blocker("built app Info.plist: ITSAppUsesNonExemptEncryption is missing")

    if not app.get("NSSupportsLiveActivities"):
        blocker("built app Info.plist: NSSupportsLiveActivities is missing — Activity.request "
                "would throw and FlightActivityController swallows it, so no Live Activity ever appears")
    if not os.path.exists(os.path.join(bundle, "PrivacyInfo.xcprivacy")):
        blocker("built app: PrivacyInfo.xcprivacy is not in the bundle")
    pa_clips = [n for n in os.listdir(bundle) if n.endswith(".m4a")]
    expected_clips = len([n for n in os.listdir(os.path.join(ROOT, "Voyage", "Resources", "PA"))
                          if n.endswith(".m4a")]) if os.path.isdir(
        os.path.join(ROOT, "Voyage", "Resources", "PA")) else 0
    if expected_clips and len(pa_clips) != expected_clips:
        blocker("built app: %d of %d PA clips were bundled — missing clips fall back to "
                "speech synthesis without any error" % (len(pa_clips), expected_clips))

    plugins = os.path.join(bundle, "PlugIns")
    appexes = ([os.path.join(plugins, n) for n in os.listdir(plugins) if n.endswith(".appex")]
               if os.path.isdir(plugins) else [])
    if not appexes:
        blocker("built app has no PlugIns/*.appex — the widget extension was not embedded")
    for appex in appexes:
        ext = load_plist(os.path.join(appex, "Info.plist"))
        print("  embedded %s  version %s (%s)"
              % (ext.get("CFBundleIdentifier"), ext.get("CFBundleShortVersionString"),
                 ext.get("CFBundleVersion")))
        if ext.get("CFBundleVersion") != app.get("CFBundleVersion"):
            blocker("%s: CFBundleVersion %s does not match the app's %s — upload validation "
                    "fails on this" % (os.path.basename(appex), ext.get("CFBundleVersion"),
                                       app.get("CFBundleVersion")))
        if ext.get("CFBundleShortVersionString") != app.get("CFBundleShortVersionString"):
            blocker("%s: CFBundleShortVersionString %s does not match the app's %s"
                    % (os.path.basename(appex), ext.get("CFBundleShortVersionString"),
                       app.get("CFBundleShortVersionString")))
        if not str(ext.get("CFBundleIdentifier", "")).startswith(
                str(app.get("CFBundleIdentifier")) + "."):
            blocker("%s: bundle id %s is not nested under the app's %s"
                    % (os.path.basename(appex), ext.get("CFBundleIdentifier"),
                       app.get("CFBundleIdentifier")))


def main(argv):
    if len(argv) > 1 and argv[1] == "--archive":
        if len(argv) < 3:
            raise SystemExit("usage: check_release.py --archive <path.xcarchive>")
        print("Validating archive %s" % argv[2])
        check_archive(argv[2])
    else:
        print("Validating sources in %s" % ROOT)
        check_source()

    print("")
    for level, msg in problems:
        print("  [%s] %s" % (level, msg))
    blockers = [p for p in problems if p[0] == "BLOCKER"]
    if blockers:
        print("\n%d blocker(s) — this would fail App Store Connect validation." % len(blockers))
        return 1
    print("No blockers.%s" % (" %d warning(s)." % len(problems) if problems else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
