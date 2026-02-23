{
  modulesPath,
  lib,
  pkgs,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
    ./nginx.nix
    ./secrets.nix
    ./alloy.nix
  ];
  system.stateVersion = "25.11";

  boot = {
    loader.grub = {
      device = "nodev";
      efiSupport = true;
      efiInstallAsRemovable = true;
    };
    kernelPackages = pkgs.linuxPackages_6_18;
    # THP causes latency spikes under nginx: the kernel stalls
    # defragmenting 2 MB pages while workers allocate small buffers.
    kernelParams = ["transparent_hugepage=never"];
    kernel.sysctl = {
      # Handle burst reconnections (many CI clients at once) without
      # dropping SYN packets in the backlog queue.
      "net.core.somaxconn" = 16384;
      "net.ipv4.tcp_max_syn_backlog" = 16384;
      # TCP buffer ceilings at 64 MB — just a max; autotuning allocates
      # only what each socket needs. Covers 1 Gbps × 500 ms RTT BDP
      # without capping fast or intercontinental clients.
      "net.core.rmem_max" = 67108864;
      "net.core.wmem_max" = 67108864;
      "net.ipv4.tcp_rmem" = "4096 131072 67108864";
      "net.ipv4.tcp_wmem" = "4096 65536 67108864";
      # System-wide FD ceiling. Each connection, open CAS file, and
      # cached FD (open_file_cache) consumes one. 1 M gives headroom
      # for thousands of concurrent downloads + the file cache.
      "fs.file-max" = 1048576;
      "fs.nr_open" = 1048576;
      # Max outstanding AIO operations system-wide. The cacheio thread
      # pool submits AIO reads for every large-file download chunk.
      "fs.aio-max-nr" = 1048576;
      # Per-socket ancillary buffer (cmsg). 64 KB covers the overhead
      # for SO_TIMESTAMP / IP_PKTINFO used by the network stack.
      "net.core.optmem_max" = 65536;

      # BBR congestion control — bandwidth-based instead of loss-based (cubic).
      # Ramps up faster on WAN links and sustains higher throughput for
      # both large module downloads and bursty Xcode fetches.
      "net.ipv4.tcp_congestion_control" = "bbr";
      # Fair Queue qdisc — required companion for BBR. Provides per-flow
      # pacing so concurrent downloads get fair bandwidth allocation.
      "net.core.default_qdisc" = "fq";

      # Keep the congestion window warm between HTTP/2 stream bursts instead
      # of falling back to slow-start after brief idle periods.
      "net.ipv4.tcp_slow_start_after_idle" = 0;

      # Limit unsent data buffered per socket to 128 KB. With HTTP/2
      # multiplexing 100+ streams, unlimited buffering (the default) lets
      # large streams starve small ones. 128 KB wakes nginx more often
      # than 256 KB, improving stream interleaving for tiny-file bursts
      # at a negligible syscall cost.
      "net.ipv4.tcp_notsent_lowat" = 131072;

      # Accept up to 16 K packets per NAPI cycle before handing off to
      # the network stack. The default (1000) can drop packets when many
      # concurrent downloads burst at the NIC.
      "net.core.netdev_max_backlog" = 16384;

      # Enable TCP Fast Open for client and server sides. Saves one RTT
      # on new TLS connections. Minor win since HTTP/2 connections are
      # long-lived, but helps when many Xcode clients connect at once.
      "net.ipv4.tcp_fastopen" = 3;

      # Probe for the largest MTU when ICMP black-holes block PMTUD.
      # Avoids silent packet drops on WAN paths with clamped MTU.
      "net.ipv4.tcp_mtu_probing" = 1;

      # Recycle TIME-WAIT sockets for new outbound connections and shorten
      # FIN timeout. nginx makes outbound connections to S3 for remote
      # proxying; under burst loads this prevents ephemeral port exhaustion.
      "net.ipv4.tcp_tw_reuse" = 1;
      "net.ipv4.tcp_fin_timeout" = 15;

      # Widen ephemeral port range for outbound S3 proxy connections.
      # Default ~28 K ports can exhaust under burst with TIME-WAIT
      # stacking up (each remote download opens a fresh connection).
      "net.ipv4.ip_local_port_range" = "10240 65535";

      # Detect dead HTTP/2 peers faster than the default 2-hour probe.
      # Total detection: 300 + (15 × 5) = 375 s ≈ 6 min.
      "net.ipv4.tcp_keepalive_time" = 300;
      "net.ipv4.tcp_keepalive_intvl" = 15;
      "net.ipv4.tcp_keepalive_probes" = 5;

      # Process more packets (600, default 300) and spend more time
      # (16 ms, default 8 ms) per NAPI poll cycle before yielding.
      # Prevents packet drops when many concurrent downloads burst
      # at the NIC simultaneously. Tradeoff: slightly higher per-cycle
      # CPU cost, but avoids softnet backlog overflows.
      "net.core.netdev_budget" = 600;
      "net.core.netdev_budget_usecs" = 16000;
    };
  };

  services.openssh.enable = true;
  security.sudo.wheelNeedsPassword = false;

  security.pam.loginLimits = [
    {
      domain = "*";
      type = "soft";
      item = "nofile";
      value = "65535";
    }
    {
      domain = "*";
      type = "hard";
      item = "nofile";
      value = "65535";
    }
  ];

  networking = {
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22
        80
        443
        4369
      ];
      allowedTCPPortRanges = [
        {
          from = 9100;
          to = 9155;
        }
      ];
      interfaces."br-+" = {
        allowedTCPPorts = [
          3100
          4317
        ];
      };
    };
  };

  virtualisation.docker = {
    enable = true;
    logDriver = "json-file";
    daemon.settings = {
      "default-ulimits" = {
        nofile = {
          Name = "nofile";
          Soft = 65535;
          Hard = 65535;
        };
      };
    };
  };

  systemd.settings = {
    Manager = {
      DefaultLimitNOFILE = "65535";
    };
  };

  environment.systemPackages = map lib.lowPrio [
    pkgs.curl
    pkgs.gitMinimal
    pkgs.parted
    pkgs.gptfdisk
    pkgs.sqlite
  ];

  systemd.tmpfiles.rules = [
    "d /cas 0755 cache cache - -"
    "d /cas/tmp 1777 cache cache - -"
    "d /var/lib/cache 0755 cache cache - -"
    "d /run/cache 0777 root root - -"
  ];
}
