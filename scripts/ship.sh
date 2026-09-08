#!/usr/bin/env bash
#
# ship.sh — source to a validated App Store archive, in one re-runnable command.
#
# Does every step that needs no credentials:
#   preconditions -> (optional build bump) -> xcodegen -> release checks
#   -> clean -> build -> unit tests -> UI/screenshot tours -> archive
#   -> validate the archive the way App Store Connect will
#
# It deliberately stops before anything that needs your Apple credentials.
# The last thing it prints is the export + upload command for you to run.
#
#   scripts/ship.sh                 # full run against the current build number
#   scripts/ship.sh --bump          # increment CURRENT_PROJECT_VERSION first
#   scripts/ship.sh --no-archive    # regenerate, check, build and test only
#   scripts/ship.sh --skip-ui-tests # unit tests only (the UI tours are slow)
#   scripts/ship.sh --device 'iPhone 17 Pro'
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

# The branch that carries the app. `fix/app-review-2026-08` was a branch of
# the thin GitHub `main` lineage, which is missing two thirds of the app;
# shipping from there uploads a build without the PA audio, the real-world
# window scenery or the round-3 design work. Update this if the branch is
# renamed, or pass --any-branch.
EXPECTED_BRANCH="release/app-review-on-submission-base"
SCHEME="Voyage"
PROJECT="Voyage.xcodeproj"
DEVICE="${VOYAGE_SIM_DEVICE:-iPhone 17}"
BUILD_DIR="$REPO/build"
DERIVED="$BUILD_DIR/DerivedData"
LOGS="$BUILD_DIR/logs"

DO_BUMP=0
DO_ARCHIVE=1
DO_TESTS=1
DO_UI_TESTS=1
ALLOW_ANY_BRANCH=0

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BOLD=$'\033[1m'; OFF=$'\033[0m'
STEP="startup"

die() { printf '\n%s✗ %s%s\n%s\n' "$RED$BOLD" "$STEP failed" "$OFF" "$*" >&2; exit 1; }
step() { STEP="$1"; printf '\n%s==> %s%s\n' "$BOLD" "$1" "$OFF"; }
note() { printf '    %s\n' "$*"; }
ok()   { printf '%s    ✓ %s%s\n' "$GREEN" "$*" "$OFF"; }
warn() { printf '%s    ! %s%s\n' "$YELLOW" "$*" "$OFF"; }

trap 'rc=$?; [ $rc -ne 0 ] && printf "\n%s✗ aborted during: %s (exit %d)%s\n" "$RED$BOLD" "$STEP" "$rc" "$OFF" >&2; exit $rc' EXIT

while [ $# -gt 0 ]; do
  case "$1" in
    --bump) DO_BUMP=1 ;;
    --no-archive) DO_ARCHIVE=0 ;;
    --skip-tests) DO_TESTS=0 ;;
    --skip-ui-tests) DO_UI_TESTS=0 ;;
    --any-branch) ALLOW_ANY_BRANCH=1 ;;
    --device) shift; DEVICE="${1:-}"; [ -n "$DEVICE" ] || die "--device needs a simulator name" ;;
    -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; trap - EXIT; exit 0 ;;
    *) die "unknown argument: $1  (try --help)" ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
step "Checking preconditions"
# ---------------------------------------------------------------------------

DEVELOPER_DIR_PATH="$(xcode-select -p 2>/dev/null || true)"
case "$DEVELOPER_DIR_PATH" in
  *CommandLineTools*|"")
    die "Xcode is not selected — xcode-select points at '${DEVELOPER_DIR_PATH:-nothing}'.
Command Line Tools alone cannot build, test or archive an iOS app.
  Install Xcode from the App Store, then:
    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" ;;
esac
XCODE_VER="$(xcodebuild -version 2>/dev/null | head -1 || true)"
[ -n "$XCODE_VER" ] || die "\`xcodebuild -version\` failed. If this is a fresh install you may still owe:
    sudo xcodebuild -license accept"
ok "$XCODE_VER at $DEVELOPER_DIR_PATH"

if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
  die "Xcode has not completed its first launch (simulator runtimes and toolchains are missing).
    sudo xcodebuild -runFirstLaunch"
fi
ok "first-launch components installed"

# Voyage/Support/Shaders.metal needs the Metal toolchain, which is NOT part of a
# stock Xcode install — the build fails at the .metal file without it.
if ! xcrun -f metal >/dev/null 2>&1; then
  die "The Metal toolchain is missing, and Voyage/Support/Shaders.metal will not compile.
    xcodebuild -downloadComponent MetalToolchain"
fi
ok "Metal toolchain present ($(xcrun -f metal))"

command -v xcodegen >/dev/null 2>&1 || die "xcodegen is not installed, and $PROJECT is generated from project.yml.
    brew install xcodegen"
ok "xcodegen $(xcodegen --version 2>/dev/null | tr -d '\n')"

command -v python3 >/dev/null 2>&1 || die "python3 is required for the release checks"

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
if [ "$BRANCH" != "$EXPECTED_BRANCH" ] && [ "$ALLOW_ANY_BRANCH" -eq 0 ]; then
  die "On branch '$BRANCH', expected '$EXPECTED_BRANCH' (the branch carrying the 2.5.4 and
5.2.5 App Review fixes). Shipping from anywhere else re-uploads the rejected code.
  Either:  git switch $EXPECTED_BRANCH
  Or, if you really mean it:  scripts/ship.sh --any-branch"
fi
ok "branch $BRANCH"
[ -z "$(git status --porcelain --untracked-files=no)" ] || warn "working tree has uncommitted changes — the archive will include them"

xcrun simctl list devices available | grep -q "^ *${DEVICE} (" \
  || die "No available simulator named '$DEVICE'. Pick one from:
$(xcrun simctl list devices available | grep -E '^ +iPhone' | sed 's/^/    /')
  then re-run with:  scripts/ship.sh --device 'iPhone …'"
DESTINATION="platform=iOS Simulator,name=$DEVICE"
ok "simulator destination: $DEVICE"

mkdir -p "$LOGS"

# ---------------------------------------------------------------------------
if [ "$DO_BUMP" -eq 1 ]; then
step "Bumping the build number"
# ---------------------------------------------------------------------------
  CUR="$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *"\{0,1\}\([0-9][0-9]*\)"\{0,1\} *$/\1/p' project.yml | head -1)"
  [ -n "$CUR" ] || die "could not find CURRENT_PROJECT_VERSION in project.yml"
  NEXT=$((CUR + 1))
  # project.yml is the single source of truth: the base `settings` block feeds
  # every target, and both Info.plists read $(CURRENT_PROJECT_VERSION), so this
  # one edit moves the app and the widget extension together.
  /usr/bin/sed -i '' "s/^\( *CURRENT_PROJECT_VERSION: *\)\"\{0,1\}$CUR\"\{0,1\} *$/\1\"$NEXT\"/" project.yml
  ok "CURRENT_PROJECT_VERSION $CUR -> $NEXT (commit project.yml before you upload)"
fi

BUILD_NUMBER="$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *"\{0,1\}\([0-9][0-9]*\)"\{0,1\} *$/\1/p' project.yml | head -1)"
MARKETING="$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([0-9.]*\)"\{0,1\} *$/\1/p' project.yml | head -1)"
ARCHIVE="$BUILD_DIR/Voyage-$MARKETING-$BUILD_NUMBER.xcarchive"
EXPORT_DIR="$BUILD_DIR/export-$MARKETING-$BUILD_NUMBER"

# ---------------------------------------------------------------------------
step "Regenerating $PROJECT from project.yml"
# ---------------------------------------------------------------------------
# Safe to re-run: XcodeGen rewrites the pbxproj, the shared scheme and
# VoyageWidgets/Info.plist from scratch every time. Never hand-edit those.
xcodegen generate > "$LOGS/xcodegen.log" 2>&1 || { cat "$LOGS/xcodegen.log"; die "xcodegen generate failed (see $LOGS/xcodegen.log)"; }
ok "generated (version $MARKETING build $BUILD_NUMBER)"

# ---------------------------------------------------------------------------
step "Validating release configuration"
# ---------------------------------------------------------------------------
python3 scripts/check_release.py || die "Fix the blockers above before building. Each one is something
App Store Connect rejects at upload, after the archive is already built."

# ---------------------------------------------------------------------------
step "Cleaning"
# ---------------------------------------------------------------------------
rm -rf "$DERIVED" "$ARCHIVE" "$EXPORT_DIR"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED" clean > "$LOGS/clean.log" 2>&1 \
  || { tail -30 "$LOGS/clean.log"; die "clean failed (see $LOGS/clean.log)"; }
ok "removed DerivedData, any previous archive for build $BUILD_NUMBER, and the export dir"

# ---------------------------------------------------------------------------
step "Building for the simulator"
# ---------------------------------------------------------------------------
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED" -configuration Debug build > "$LOGS/build.log" 2>&1 \
  || { grep -E "error:|warning: .*deprecat" "$LOGS/build.log" | head -30; die "build failed — full log: $LOGS/build.log"; }
ok "built Voyage.app and VoyageWidgets.appex"

# ---------------------------------------------------------------------------
if [ "$DO_TESTS" -eq 1 ]; then
step "Running unit tests (VoyageTests)"
# ---------------------------------------------------------------------------
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED" -only-testing:VoyageTests test > "$LOGS/unit-tests.log" 2>&1 \
    || { grep -E "error:|failed|XCTAssert" "$LOGS/unit-tests.log" | head -40; die "unit tests failed — full log: $LOGS/unit-tests.log"; }
  ok "$(grep -c "Test Case .* passed" "$LOGS/unit-tests.log" || echo '?') unit test cases passed"

  if [ "$DO_UI_TESTS" -eq 1 ]; then
# ---------------------------------------------------------------------------
step "Running UI tests and the QA screenshot tour (VoyageUITests)"
# ---------------------------------------------------------------------------
    # ScreenshotTourUITests writes PNGs to the repo's QA/ directory via an
    # absolute path hardcoded in the test, so it only produces artifacts when
    # the repo lives at /Users/patliu/Desktop/Coding/Voyage.
    warn "these drive the simulator in real time and take several minutes"
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" \
      -derivedDataPath "$DERIVED" -only-testing:VoyageUITests test > "$LOGS/ui-tests.log" 2>&1 \
      || { grep -E "error:|failed|XCTAssert" "$LOGS/ui-tests.log" | head -40; die "UI tests failed — full log: $LOGS/ui-tests.log"; }
    ok "UI tours passed; screenshots refreshed in $REPO/QA/"
  else
    warn "UI tests skipped (--skip-ui-tests)"
  fi
else
  warn "tests skipped (--skip-tests) — do not ship a build you have not tested"
fi

# ---------------------------------------------------------------------------
if [ "$DO_ARCHIVE" -eq 0 ]; then
  step "Done (--no-archive)"
  trap - EXIT
  exit 0
fi
step "Archiving for App Store distribution"
# ---------------------------------------------------------------------------
if [ -z "${VOYAGE_TEAM_ID:-}" ]; then
  die "VOYAGE_TEAM_ID is not set, and project.yml carries no DEVELOPMENT_TEAM, so a device
archive cannot be signed — xcodebuild would stop with
  \"Signing for 'Voyage' requires a development team\".
Your 10-character Team ID is not a secret; find it at
  https://developer.apple.com/account  ->  Membership details
Then:
  export VOYAGE_TEAM_ID=ABCDE12345
  scripts/ship.sh"
fi

# -allowProvisioningUpdates lets Xcode create/refresh the App Store provisioning
# profiles for com.patliu.voyage and com.patliu.voyage.widgets. It authenticates
# with the Apple ID signed into Xcode, or with an App Store Connect API key if
# you pass one — see the upload instructions printed at the end.
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$VOYAGE_TEAM_ID" \
  -allowProvisioningUpdates \
  archive > "$LOGS/archive.log" 2>&1 \
  || { grep -E "error:|Signing|provisioning" "$LOGS/archive.log" | head -30; die "archive failed — full log: $LOGS/archive.log
If this is a signing error, confirm the Apple ID with access to team $VOYAGE_TEAM_ID is
added in Xcode > Settings > Accounts, and that the bundle ids com.patliu.voyage and
com.patliu.voyage.widgets exist in App Store Connect."; }
ok "archived to $ARCHIVE"

# ---------------------------------------------------------------------------
step "Validating the archive"
# ---------------------------------------------------------------------------
python3 scripts/check_release.py --archive "$ARCHIVE" \
  || die "The archive would be rejected by App Store Connect. Fix the blockers, then re-run."

cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>teamID</key>
	<string>$VOYAGE_TEAM_ID</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>uploadSymbols</key>
	<true/>
	<key>destination</key>
	<string>export</string>
</dict>
</plist>
PLIST
ok "wrote $BUILD_DIR/ExportOptions.plist"

# ---------------------------------------------------------------------------
trap - EXIT
cat <<EOF

${GREEN}${BOLD}Archive ready: Voyage $MARKETING (build $BUILD_NUMBER)${OFF}
  $ARCHIVE

${BOLD}Remaining steps need your Apple credentials — run them yourself.${OFF}
This script never asks for, stores or uses a credential.

1. Export a signed .ipa:

   xcodebuild -exportArchive \\
     -archivePath "$ARCHIVE" \\
     -exportPath "$EXPORT_DIR" \\
     -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \\
     -allowProvisioningUpdates

2. Upload it. Pick ONE of these:

   a) App Store Connect API key (preferred; no interactive prompt).
      Create it at App Store Connect > Users and Access > Integrations > Keys
      with the App Manager role, download the .p8 ONCE and put it in
      ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8, then:

        xcrun altool --upload-app -f "$EXPORT_DIR/Voyage.ipa" -t ios \\
          --apiKey <YOUR_KEY_ID> --apiIssuer <YOUR_ISSUER_UUID>

   b) Apple ID + app-specific password. Generate the password at
      appleid.apple.com > Sign-In and Security > App-Specific Passwords,
      store it in the keychain once:

        xcrun altool --store-password-in-keychain-item VOYAGE_ALTOOL \\
          -u <your-apple-id> -p <the-app-specific-password>

      then upload with:

        xcrun altool --upload-app -f "$EXPORT_DIR/Voyage.ipa" -t ios \\
          -u <your-apple-id> -p @keychain:VOYAGE_ALTOOL

   Your normal Apple ID password will not work for either path.

3. Processing takes 5-30 minutes. When build $BUILD_NUMBER appears in App Store
   Connect, attach it to the 1.0 version, and in the "What's new"/review notes
   say what changed for the 2026-08-05 rejection:
     - 2.5.4: the audio background mode is gone; audio is foreground-only.
     - 5.2.5: WeatherKit is gone; readings come from Open-Meteo, credited in Settings.

4. Before the NEXT upload, bump again — App Store Connect refuses a repeat of
   build $BUILD_NUMBER:

     scripts/ship.sh --bump

EOF
