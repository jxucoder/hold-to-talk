cask "openmumble" do
  version "TMPL_VERSION"
  sha256 "TMPL_SHA256"

  url "https://github.com/jxucoder/openmumble/releases/download/v#{version}/OpenMumble-v#{version}.zip"
  name "OpenMumble"
  desc "Free, open-source voice dictation for macOS"
  homepage "https://github.com/jxucoder/openmumble"

  depends_on macos: ">= :sonoma"

  app "OpenMumble.app"

  zap trash: [
    "~/Library/Preferences/com.openmumble.app.plist",
  ]
end
