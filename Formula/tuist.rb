class Tuist < Formula
  desc "Generate, maintain, and interact with Xcode projects easily"
  homepage "https://tuist.io"
  url "https://github.com/tuist/tuist/raw/0.3.0/bin/tuistenv"
  sha256 "43915c5373f9fe22ac04be730aca625d8320bb27688d3acd8b1687a4728af8cb"

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
