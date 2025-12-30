#!/usr/bin/env bash
#MISE description="Creates Tuist iOS app .ipa archive."

set -eo pipefail

TMP_DIR=/private$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT # Delete on exit

if [ "${CI:-}" = "true" ]; then
    echo "Creating a temporary keychain"
    KEYCHAIN_PASSWORD=$(uuidgen)
    KEYCHAIN_PATH=$TMP_DIR/certificates/temp.keychain
    security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
    security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
    security default-keychain -s $KEYCHAIN_PATH
    security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
fi

op read "op://tuist/Distribution Certificate/distribution.p12" --out-file $TMP_DIR/certificate.p12
security import $TMP_DIR/certificate.p12 -P $(op read "op://tuist/Distribution Certificate/password") -A

mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
op read "op://tuist/Tuist App Ad Hoc/Tuist_App_Ad_Hoc.mobileprovision" --out-file "$HOME/Library/MobileDevice/Provisioning Profiles/tuist.mobileprovision"

EXPORT_OPTIONS_PLIST_PATH=$TMP_DIR/ExportOptions.plist

cat << EOF > "$EXPORT_OPTIONS_PLIST_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>destination</key>
	<string>export</string>
	<key>method</key>
	<string>release-testing</string>
	<key>provisioningProfiles</key>
	<dict>
		<key>dev.tuist.app</key>
		<string>Tuist App Ad Hoc</string>
	</dict>
	<key>signingCertificate</key>
	<string>Apple Distribution: Tuist GmbH (U6LC622NKF)</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>stripSwiftSymbols</key>
	<true/>
	<key>teamID</key>
	<string>U6LC622NKF</string>
	<key>thinning</key>
	<string>&lt;none&gt;</string>
</dict>
</plist>
EOF

tuist xcodebuild archive clean -archivePath $TMP_DIR/Tuist.xcarchive -workspace Tuist.xcworkspace -scheme TuistApp -configuration Release -destination "generic/platform=iOS" CODE_SIGN_IDENTITY="Apple Distribution: Tuist GmbH (U6LC622NKF)" CODE_SIGN_STYLE="Manual" CODE_SIGN_INJECT_BASE_ENTITLEMENTS="NO"
xcodebuild -exportArchive -archivePath $TMP_DIR/Tuist.xcarchive -exportOptionsPlist $EXPORT_OPTIONS_PLIST_PATH -exportPath $TMP_DIR
mkdir -p build
cp $TMP_DIR/Tuist.ipa build/Tuist.ipa
