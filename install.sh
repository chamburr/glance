#!/bin/zsh

xcodebuild -list -project Glance.xcodeproject
mkdir -p release
xcodebuild -scheme Glance build -allowProvisioningUpdates -configuration Release CONFIGURATION_BUILD_DIR=$(pwd)/release

# Now sign the application
xattr -cr $(pwd)/release/Glance.app
echo '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>com.apple.security.app-sandbox</key><true/><key>com.apple.security.application-groups</key><array><string>group.com.chamburr.glance</string></array><key>com.apple.security.files.user-selected.read-only</key><true/></dict></plist>' >/tmp/Glance.entitlements
codesign -s - -f --deep --entitlements /tmp/Glance.entitlements $(pwd)/release/Glance.app
rm /tmp/Glance.entitlements

# Install application
rm -rf /Applications/Glance.app
mv $(pwd)/release/Glance.app /Applications/
