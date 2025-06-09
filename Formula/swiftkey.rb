class Swiftkey < Formula
  desc "Hackable launcher for macOS"
  homepage "https://swiftkey.app"
  url "https://github.com/amebalabs/SwiftKey/releases/download/v1.3.0/SwiftKey-1.3.0.zip"
  sha256 "a2abe45f145c8948ca7badf94423f4164ec8446f419f055afbbe71ce7c04d81a"
  version "1.3.0"
  
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