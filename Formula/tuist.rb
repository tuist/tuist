class Tuist < Formula
  desc "Generate, maintain, and interact with Xcode projects easily"
  homepage "https://tuist.io"
  url "https://github.com/tuist/tuist/raw/0.5.0/bin/tuistenv"
  sha256 "a8bd5eb690b846ec69f6c2fdc7e676cb5b25a16147d60d50db1cb9c81f7b5e2e"

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
