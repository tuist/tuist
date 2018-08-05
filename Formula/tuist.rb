class Tuist < Formula
  desc "Generate, maintain, and interact with Xcode projects easily"
  homepage "https://tuist.io"
  url "https://github.com/tuist/tuist/raw/0.2.0/bin/tuistenv"
  version "0.2.0"
  # make sha256
  sha256 "6769e784ade1a6c5726a71afc78b13dd1509f2b421deb6719fd2ff9ab796afda"

  def install
    File.rename("tuistenv", "tuist")
    bin.install "tuist"
  end

  test do
    system "#{bin}/tuist", "local", "0.2.0"
  end
end
