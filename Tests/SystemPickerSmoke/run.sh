#!/usr/bin/env bash
# Interactive, local-only check. Select the synthetic fixture; never reset TCC.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d /private/tmp/ScreenshotApp-picker-smoke.XXXXXX)"
export CLANG_MODULE_CACHE_PATH="$WORK/cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$WORK/cache"
export SDKROOT="${SDKROOT:-$(xcrun --show-sdk-path)}"
cd "$ROOT"
swift build --disable-sandbox --scratch-path "$WORK/build" --product CoreChecks > "$WORK/build.log" 2>&1
BIN="$(swift build --disable-sandbox --scratch-path "$WORK/build" --show-bin-path)"
swiftc -sdk "$SDKROOT" -swift-version 5 -parse-as-library -I "$BIN/Modules" \
  "$BIN"/ScreenshotCore.build/*.o \
  Sources/ScreenshotApp/Services/CaptureService.swift \
  Sources/ScreenshotApp/Services/CaptureTelemetry.swift \
  Sources/ScreenshotApp/Services/SelectedContentFrameCapture.swift \
  Sources/ScreenshotApp/Services/SystemContentCaptureController.swift \
  Tests/SystemPickerSmoke/main.swift -o "$WORK/PickerSmoke"
IDENTITY="$(bash script/ensure_local_signing_identity.sh --require-release)"
python3 - "$WORK" "$IDENTITY" <<'PY'
import pathlib,plistlib,shutil,subprocess,sys
root=pathlib.Path(sys.argv[1]); identity=sys.argv[2]
for name,suffix in [('External Fixture 552','ExternalFixture552'),('Picker Verification 552','PickerVerification552')]:
 app=root/(name+'.app');exe=app/'Contents/MacOS/PickerSmoke';exe.parent.mkdir(parents=True)
 shutil.copy2(root/'PickerSmoke',exe)
 (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'PickerSmoke','CFBundleIdentifier':'local.codex.ScreenshotApp.'+suffix,'CFBundleName':name,'CFBundlePackageType':'APPL','CFBundleVersion':'1','CFBundleShortVersionString':'1.0','LSMinimumSystemVersion':'14.0','NSPrincipalClass':'NSApplication','NSHighResolutionCapable':True}))
 subprocess.run(['codesign','--force','--sign',identity,'--timestamp=none',str(app)],check=True)
 args=['--fixture',str(root/'fixture.json')] if suffix.startswith('External') else [str(root/'result.json')]
 subprocess.run(['open','-n',str(app),'--args',*args],check=True)
print('Manual test directory:', root, flush=True)
print('Click Verify window capture, then select External fixture 5.52 in the macOS picker.',flush=True)
print('Result must have passed=true, fixtureTextMatched=true, framesCaptured=3, globalAccessBefore/After=false.',flush=True)
PY
