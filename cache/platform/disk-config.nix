{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              priority = 1;
              name = "ESP";
              start = "1M";
              end = "128M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = ["umask=0077"];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                extraArgs = ["-F"];
                mountpoint = "/";
                mountOptions = [
                  "noatime"
                  "commit=30"
                  "lazytime"
                ];
              };
            };
          };
        };
      };
      sdb = {
        type = "disk";
        device = "/dev/sdb";
        content = {
          type = "gpt";
          partitions = {
            cas = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                extraArgs = ["-F" "-i" "8192"];
                mountpoint = "/cas";
                mountOptions = [
                  "noatime"
                  "nodiratime"
                  "commit=60"
                  "lazytime"
                  "discard"
                ];
              };
            };
          };
        };
      };
    };
  };
}
