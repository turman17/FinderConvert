# Homebrew cask for FinderConvert.
#
# This file lives in the app repo as the template of record. To publish,
# copy it into a tap repository named `homebrew-tap` under your GitHub
# account, at Casks/finderconvert.rb. Users then install with:
#
#   brew install --cask turman17/tap/finderconvert
#
# After each release, update `version` and `sha256` (scripts/release.sh
# prints both).
cask "finderconvert" do
  version "1.0.3"
  sha256 "9cc6a4092a8495f3280a2a81e0889436c8ac5a438acfaa67e69e9e0af2e9d95b"

  url "https://github.com/turman17/FinderConvert/releases/download/v#{version}/FinderConvert-v#{version}.zip"
  name "FinderConvert"
  desc "File converter in Finder's right-click menu"
  homepage "https://github.com/turman17/FinderConvert"

  depends_on macos: :sonoma

  app "FinderConvert.app"

  caveats <<~EOS
    FinderConvert is not notarized (no paid Apple Developer account).
    After installing, clear the quarantine flag once:

      xattr -dr com.apple.quarantine /Applications/FinderConvert.app

    Then launch the app and enable the Finder extension in
    System Settings > Privacy & Security > Extensions > Finder.
  EOS

  zap trash: [
    "~/Library/Group Containers/YJ3UZ772GP.com.finderconvert.app.shared",
    "~/Library/Containers/com.finderconvert.app.ActionExtension",
  ]
end
