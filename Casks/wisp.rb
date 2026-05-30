# Homebrew cask for Wisp.
#
# Distribute via your own tap so users can:
#   brew install --cask Attikus-Labs/tap/wisp
#
# Create the tap once (a repo named `homebrew-tap`), then copy this file to
# `Casks/wisp.rb` there. The release workflow prints the dmg's sha256 in
# SHA256SUMS.txt — paste it below on each release (or automate the bump).
cask "wisp" do
  version "0.2.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/Attikus-Labs/wisp/releases/download/v#{version}/Wisp-#{version}.dmg",
      verified: "github.com/Attikus-Labs/wisp/"
  name "Wisp"
  desc "Light, fast, secure clipboard bezel for macOS"
  homepage "https://github.com/Attikus-Labs/wisp"

  depends_on macos: ">= :ventura"

  app "Wisp.app"

  zap trash: [
    "~/Library/Preferences/com.brinas.wisp.plist",
  ]
end
