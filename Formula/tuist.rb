class Tuist < Formula
  desc "Generate, maintain, and interact with Xcode projects easily"
  homepage "https://tuist.io"
  url "https://github.com/tuist/tuist/raw/0.4.0/bin/tuistenv"
  sha256 "c2bb0a1e3416f71132e8ff12fb9dfe1aefe086022d89aea878c0de91ac3498c3"

  def install
    File.rename("tuistenv", "tuist")
    bin.install "tuist"
  end

  test do
    # Shows all available commands
    system "#{bin}/tuist", "--help-env"
    # Pins tuist to the given version
    system "#{bin}/tuist", "local", "0.2.0"
  end
end
