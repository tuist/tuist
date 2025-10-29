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
      cache = {
        type = "disk";
        device = "/dev/sdb";
        content = {
          type = "gpt";
          partitions = {
            data = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                extraArgs = ["-F" "-E" "lazy_itable_init=0,lazy_journal_init=0"];
                mountpoint = "/cache";
                mountOptions = [
                  "noatime"
                  "nodiratime"
                  "commit=60"
                  "lazytime"
                  "data=ordered"
                ];
              };
            };
          };
        };
      };
    };
  };
}
