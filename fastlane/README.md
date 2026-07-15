# fastlane — TestFlight upload for タナミル

One command on a Mac builds a Release archive and uploads it to TestFlight.

## Prerequisites (Mac)
- macOS with **Xcode 26** installed and opened once (license accepted:
  `sudo xcodebuild -license accept`).
- Command Line Tools: `xcode-select --install`.
- Ruby + bundler: `gem install bundler` then `bundle install` (installs fastlane
  from the repo `Gemfile`). Alternatively `brew install fastlane`.
- An **App Store Connect API key** (`.p8`) with the **App Manager** role, plus its
  **Key ID** and **Issuer ID**, and your **Team ID**.
- The App ID `com.tenten.tanamiru` must have **iCloud (CloudKit)** and **Push
  Notifications** enabled, with container `iCloud.com.tenten.tanamiru` assigned.

## Setup
```sh
cp fastlane/.env.example fastlane/.env
# edit fastlane/.env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, TANAMIRU_TEAM_ID
```

## Run
```sh
bundle exec fastlane beta
```

This will:
1. Authenticate with the App Store Connect API key (no Apple ID / 2FA needed).
2. Compute the next build number from TestFlight.
3. Build the **Release** configuration (uses the production-aps entitlements) with
   automatic cloud signing (`-allowProvisioningUpdates`).
4. Upload the `.ipa` to TestFlight.

After upload, the build shows in App Store Connect → TestFlight after Apple
finishes processing (a few minutes). Add it to a tester group to install.

## First-build notes
- **CloudKit Production schema**: TestFlight builds use the CloudKit **Production**
  environment. Run the app once in the simulator/device (Debug) so the schema is
  created in Development, then in CloudKit Console choose **Deploy Schema Changes
  to Production**. Otherwise sync will fail for testers.
- If cloud signing fails, open the project in Xcode once, select the team under
  Signing & Capabilities (automatic), let it create profiles, then re-run.
- `MARKETING_VERSION` (1.0.0) lives in `Scripts/generate_pbxproj.py`; bump it there
  and regenerate for a new App Store version.
