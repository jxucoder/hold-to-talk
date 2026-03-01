cask "pushietalkie" do
  version "TMPL_VERSION"
  sha256 "TMPL_SHA256"

  url "https://github.com/jxucoder/pushietalkie/releases/download/v#{version}/PushieTalkie-v#{version}.zip"
  name "PushieTalkie"
  desc "Free, open-source voice dictation for macOS"
  homepage "https://github.com/jxucoder/pushietalkie"

  depends_on macos: ">= :sonoma"

  app "PushieTalkie.app"

  zap trash: [
    "~/Library/Preferences/com.pushietalkie.app.plist",
  ]
end
