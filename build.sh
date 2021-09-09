#!/bin/zsh

xcodebuild -list -project Glance.xcodeproject
mkdir -p release
xcodebuild -scheme Glance build -allowProvisioningUpdates -configuration Release CONFIGURATION_BUILD_DIR=$(pwd)/release
