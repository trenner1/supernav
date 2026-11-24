#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${RELEASE_IDENTITY:?Set RELEASE_IDENTITY to your Developer ID Application certificate name or SHA-1}"
: "${NOTARY_PROFILE:=supernav-notary}"
: "${SDK:=$(xcrun --sdk macosx --show-sdk-path)}"
out=build/release
app="$out/SuperNav.app"
# A failed attempt must never leave an older distributable at the output path.
rm -rf "$out"
# Validate credentials before rebuilding. No passwords are stored in the repo.
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null
./scripts/build-icon.sh
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp build/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
for arch in arm64 x86_64; do
    xcrun swiftc -O -swift-version 5 -sdk "$SDK" -target "$arch-apple-macos14" \
        ./*.swift -o "$out/$arch"
done
xcrun lipo -create -output "$app/Contents/MacOS/SuperNav" "$out/arm64" "$out/x86_64"
cp Info.plist "$app/Contents/Info.plist"
codesign --force --options runtime --timestamp --sign "$RELEASE_IDENTITY" "$app"
codesign --verify --strict --verbose=2 "$app"
# Check the actual signer even when an identity hash was supplied.
codesign -d --verbose=4 "$app" 2> "$out/signature.txt"
if ! grep -q '^Authority=Developer ID Application:' "$out/signature.txt"; then
    echo "Release requires a Developer ID Application certificate." >&2
    exit 1
fi
ditto -c -k --keepParent "$app" "$out/submission.zip"
xcrun notarytool submit "$out/submission.zip" --keychain-profile "$NOTARY_PROFILE" \
    --wait --output-format json > "$out/notarization.json"
if ! /usr/bin/plutil -extract status raw -o - "$out/notarization.json" | grep -qx Accepted; then
    echo "Notarization was not accepted. See $out/notarization.json; retrieve the submission log with notarytool log." >&2
    exit 1
fi
xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --strict --verbose=2 "$app"
spctl --assess --type execute --verbose=2 "$app"
# Package only after the ticket has been stapled and Gatekeeper has accepted it.
ditto -c -k --keepParent "$app" "$out/SuperNav.zip"
shasum -a 256 "$out/SuperNav.zip"
