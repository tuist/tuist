def main [
  vlan_tag: int,
  --vlan-name: string = "pn",
  --parent-interface: string = "en0",
] {
  let existing = (do { ^networksetup -listVLANs } | complete)

  if ($existing.stdout | str contains $"Tag: ($vlan_tag)") {
    print $"VLAN tag ($vlan_tag) already exists"
  } else {
    sudo networksetup -createVLAN $vlan_name $parent_interface ($vlan_tag | into string)
  }

  networksetup -listVLANs

  let vlan_device = (
    do { networksetup -listVLANs } | lines | where ($it | str contains 'Device ("Hardware" Port):') | last | split row ': ' | last
  )

  print $"Using VLAN device: ($vlan_device)"
  do { ipconfig getifaddr $vlan_device } | complete
}
