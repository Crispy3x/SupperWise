# Upload with fastlane

1. Install fastlane (https://docs.fastlane.tools) and create an App Store Connect API key.
2. From this folder's parent: `fastlane deliver --metadata_path fastlane/metadata --screenshots_path fastlane/screenshots --skip_binary_upload --overwrite_screenshots --api_key_path <key.json>`
3. Check the result in App Store Connect before submitting. Nothing is submitted for review by this command.
