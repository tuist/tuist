def main [
  --version: string = "1.6.2",
  --target-dir: string = "/usr/local/bin",
] {
  let archive = $"/tmp/xcodes-($version).tar.gz"
  let url = $"https://github.com/XcodesOrg/xcodes/releases/download/($version)/xcodes-($version).macos.arm64.tar.gz"

  curl -fsSL -o $archive $url

  mkdir /tmp/xcodes-install
  tar -xzf $archive -C /tmp/xcodes-install

  let binary = $"/tmp/xcodes-install/xcodes/($version)/bin/xcodes"

  sudo mkdir -p $target_dir
  sudo cp $binary $"($target_dir)/xcodes"
  sudo chmod 0755 $"($target_dir)/xcodes"

  ^xcodes version
}
