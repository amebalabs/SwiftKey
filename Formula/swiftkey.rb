class Swiftkey < Formula
  desc "Hackable launcher for macOS"
  homepage "https://swiftkey.app"
  url "https://github.com/amebalabs/SwiftKey/releases/download/v1.4.0/SwiftKey-1.4.0.zip"
  sha256 "5ce100abd54eacd7052b130d67e8908ba075d9b2cb21c2e118d3effd35a07410"
  version "1.4.0"
  
  depends_on macos: ">= :monterey"
  
  app "SwiftKey.app"
  
  zap trash: [
    "~/Library/Application Support/SwiftKey",
    "~/Library/Caches/com.ameba.SwiftKey",
    "~/Library/Preferences/com.ameba.SwiftKey.plist",
  ]
  
  def caveats
    <<~EOS
      SwiftKey has been installed to:
        #{appdir}/SwiftKey.app
    EOS
  end
end