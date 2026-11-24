// sandboxd runs Firecracker microVM sandboxes on a bare-metal node for
// coding-agent sessions. See infra/sandboxd/AGENTS.md for the protocol and
// the node layout.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"net/netip"
	"net/url"
	"os"
	"os/signal"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	"github.com/tuist/tuist/infra/sandboxd/internal/admin"
	"github.com/tuist/tuist/infra/sandboxd/internal/blobcache"
	"github.com/tuist/tuist/infra/sandboxd/internal/checkout"
	"github.com/tuist/tuist/infra/sandboxd/internal/direct"
	"github.com/tuist/tuist/infra/sandboxd/internal/diskusage"
	"github.com/tuist/tuist/infra/sandboxd/internal/envfile"
	"github.com/tuist/tuist/infra/sandboxd/internal/firecracker"
	"github.com/tuist/tuist/infra/sandboxd/internal/hostinfo"
	"github.com/tuist/tuist/infra/sandboxd/internal/network"
	"github.com/tuist/tuist/infra/sandboxd/internal/sandbox"
	"github.com/tuist/tuist/infra/sandboxd/internal/template"
	"github.com/tuist/tuist/infra/sandboxd/internal/vm"
	"github.com/tuist/tuist/infra/sandboxd/internal/vsock"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
	"github.com/tuist/tuist/infra/sandboxd/pkg/server"
)

// version is set with -ldflags "-X main.version=...".
var version = "dev"

func main() {
	// Deploy-varying configuration, LOG_LEVEL included, comes from a mounted
	// ConfigMap, so a change to it does not change the Pod's spec; the Pod's
	// own variables win.
	configErr := envfile.Load(os.Getenv("SANDBOXD_CONFIG"))
	level, levelErr := levelEnv("LOG_LEVEL", slog.LevelInfo)
	logger := slog.New(slog.NewJSONHandler(os.Stderr, &slog.HandlerOptions{Level: level}))
	if configErr != nil {
		logger.Error("loading the config file", "error", configErr)
		os.Exit(1)
	}
	if levelErr != nil {
		logger.Error("invalid log level", "env", "LOG_LEVEL", "value", os.Getenv("LOG_LEVEL"), "error", levelErr)
		os.Exit(1)
	}

	nodeName := os.Getenv("NODE_NAME")
	serverURL := os.Getenv("SERVER_URL")
	tokenPath := envOr("TOKEN_PATH", "/var/run/secrets/tuist/token")
	dataDir := envOr("DATA_DIR", "/data/sandboxes")
	templateName := envOr("TEMPLATE_NAME", "default")
	templateTag := os.Getenv("TEMPLATE_TAG")
	firecrackerBin := envOr("FIRECRACKER_BIN", "/usr/local/bin/firecracker")
	jailerBin := envOr("JAILER_BIN", "/usr/local/bin/jailer")
	jailerEnabled := boolEnv(logger, "JAILER_ENABLED", true)
	uidBase := intEnv(logger, "JAIL_UID_BASE", 10000)
	metricsAddr := envOr("METRICS_ADDR", ":9470")
	adminAddr := os.Getenv("ADMIN_ADDR")
	directExecAddr := os.Getenv("DIRECT_EXEC_ADDR")
	bootTimeout := durationEnv(logger, "BOOT_TIMEOUT", sandbox.DefaultBootTimeout)
	templateBootTimeout := durationEnv(logger, "TEMPLATE_BOOT_TIMEOUT", template.DefaultBootTimeout)
	shutdownTimeout := durationEnv(logger, "SHUTDOWN_TIMEOUT", 60*time.Second)
	templateWorkspaceGB := intEnv(logger, "TEMPLATE_WORKSPACE_GB", template.DefaultWorkspaceGB)
	memoryFloorGiB := intEnv(logger, "MEMORY_FLOOR_GIB", 0)
	executionSlots := intEnv(logger, "EXECUTION_SLOTS", 0)
	memoryCeilingGiB := intEnv(logger, "MEMORY_CEILING_GIB", 0)
	cpuFloorMilli := intEnv(logger, "CPU_FLOOR_MILLI", 0)
	cpuCeilingMilli := intEnv(logger, "CPU_CEILING_MILLI", 0)
	if memoryFloorGiB < 0 || memoryCeilingGiB < 0 || cpuFloorMilli < 0 || cpuCeilingMilli < 0 {
		logger.Error("MEMORY_FLOOR_GIB, MEMORY_CEILING_GIB, CPU_FLOOR_MILLI and CPU_CEILING_MILLI must not be negative",
			"memory_floor", memoryFloorGiB, "memory_ceiling", memoryCeilingGiB, "cpu_floor", cpuFloorMilli, "cpu_ceiling", cpuCeilingMilli)
		os.Exit(1)
	}
	elastic := protocol.Elastic{
		PodName:            os.Getenv("POD_NAME"),
		MemoryFloorBytes:   uint64(memoryFloorGiB) << 30,   //nolint:gosec // Checked non-negative above.
		MemoryCeilingBytes: uint64(memoryCeilingGiB) << 30, //nolint:gosec // Checked non-negative above.
		CPUFloorMilli:      uint64(cpuFloorMilli),          //nolint:gosec // Checked non-negative above.
		CPUCeilingMilli:    uint64(cpuCeilingMilli),        //nolint:gosec // Checked non-negative above.
	}
	// Each VM gets its own cgroup, weighted by its guarantee, so one busy
	// sandbox cannot take another's guaranteed CPU. Without them (no cgroup
	// v2, a read-only hierarchy) every VM shares the daemon's cgroup as
	// before, and hello does not offer cpu_guarantees.
	var vmCgroups *hostinfo.VMCgroups
	// With a vmm container the VMs are spawned there and sit in its cgroup,
	// which the server resizes, instead of this container's.
	vmmSocket := os.Getenv("VMM_SOCKET")
	var vmmGone <-chan struct{}
	if vmmSocket != "" {
		ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
		var base string
		var err error
		base, vmmGone, err = vm.VMMCgroup(ctx, vmmSocket)
		cancel()
		if err != nil {
			logger.Error("reaching the vmm container", "error", err)
			os.Exit(1)
		}
		if vmCgroups, err = hostinfo.AdoptVMCgroups(base); err != nil {
			logger.Warn("per-VM cgroups are off; every VM shares the vmm container's", "error", err)
			vmCgroups = nil
			hostinfo.UseContainerCgroup(base)
		}
	} else if boolEnv(logger, "VM_CGROUPS", true) {
		daemonWeight := elastic.CPUFloorMilli
		if daemonWeight == 0 {
			daemonWeight = protocol.DefaultCPUGuaranteeMilli
		}
		var err error
		if vmCgroups, err = hostinfo.SetupVMCgroups(daemonWeight); err != nil {
			logger.Warn("per-VM cgroups are off; every VM shares the daemon's", "error", err)
			vmCgroups = nil
		}
	}
	diskBudgetGiB := intEnv(logger, "DISK_BUDGET_GIB", 0)
	if diskBudgetGiB < 0 {
		logger.Error("DISK_BUDGET_GIB must not be negative", "value", diskBudgetGiB)
		os.Exit(1)
	}
	blobCacheGiB := intEnv(logger, "BLOB_CACHE_GIB", 0)
	if blobCacheGiB < 0 {
		logger.Error("BLOB_CACHE_GIB must not be negative", "value", blobCacheGiB)
		os.Exit(1)
	}
	checkoutWorkspacesGiB := intEnv(logger, "CHECKOUT_WORKSPACES_GIB", 0)
	if checkoutWorkspacesGiB < 0 {
		logger.Error("CHECKOUT_WORKSPACES_GIB must not be negative", "value", checkoutWorkspacesGiB)
		os.Exit(1)
	}
	cacheImagesGiB := intEnv(logger, "CACHE_IMAGES_GIB", 0)
	if cacheImagesGiB < 0 {
		logger.Error("CACHE_IMAGES_GIB must not be negative", "value", cacheImagesGiB)
		os.Exit(1)
	}
	// The blob cache, the prepared checkout workspaces and the copied cache
	// images come out of the disk budget: the server places sandboxes against
	// the budget the daemon reports, so it never counts on the bytes they may
	// hold.
	sandboxBudgetGiB := diskBudgetGiB
	if reserved := blobCacheGiB + checkoutWorkspacesGiB + cacheImagesGiB; diskBudgetGiB > 0 && reserved > 0 {
		if reserved >= diskBudgetGiB {
			logger.Error("BLOB_CACHE_GIB, CHECKOUT_WORKSPACES_GIB and CACHE_IMAGES_GIB must stay below DISK_BUDGET_GIB",
				"blob_cache_gib", blobCacheGiB, "checkout_workspaces_gib", checkoutWorkspacesGiB, "cache_images_gib", cacheImagesGiB, "disk_budget_gib", diskBudgetGiB)
			os.Exit(1)
		}
		sandboxBudgetGiB -= reserved
	}
	prebuild, err := template.ParseShapes(os.Getenv("PREBUILD_SHAPES"))
	if err != nil {
		logger.Error("invalid PREBUILD_SHAPES", "error", err)
		os.Exit(1)
	}
	allowedShapes, err := template.ParseShapes(os.Getenv("ALLOWED_SHAPES"))
	if err != nil {
		logger.Error("invalid ALLOWED_SHAPES", "error", err)
		os.Exit(1)
	}
	for _, shape := range prebuild {
		if len(allowedShapes) > 0 && !slices.Contains(allowedShapes, shape) {
			logger.Error("PREBUILD_SHAPES lists a shape ALLOWED_SHAPES does not offer", "shape", shape.String())
			os.Exit(1)
		}
	}
	if serverURL != "" && nodeName == "" {
		logger.Error("NODE_NAME is required when SERVER_URL is set (downward API)")
		os.Exit(1)
	}
	if serverURL == "" && adminAddr == "" {
		logger.Error("neither SERVER_URL nor ADMIN_ADDR is set; nothing would drive the daemon")
		os.Exit(1)
	}
	if uidBase < 1000 {
		logger.Error("JAIL_UID_BASE must be at least 1000", "value", uidBase)
		os.Exit(1)
	}

	if err := vm.SetChildSubreaper(); err != nil {
		logger.Error("setting child subreaper", "error", err)
		os.Exit(1)
	}

	dns := hostinfo.Resolvers()
	if len(dns) == 0 {
		logger.Warn("no resolvers found in /etc/resolv.conf; guests get no DNS")
	}
	// Startup discards template shapes and memory images another version
	// wrote, so a daemon that cannot tell its own version must not start:
	// guessing would throw away every snapshot on the node.
	fcVersion, err := firecracker.BinaryVersion(context.Background(), firecrackerBin)
	if err != nil {
		logger.Error("reading the firecracker version", "bin", firecrackerBin, "error", err)
		os.Exit(1)
	}
	snapshotCompat := hostinfo.SnapshotCompat(fcVersion)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	// A vmm that stopped took its VMs along, and a restarted one has another
	// cgroup: stop as on SIGTERM and let the kubelet restart the daemon.
	go func() {
		select {
		case <-vmmGone:
			logger.Error("the vmm container stopped; restarting the daemon")
			stop()
		case <-ctx.Done():
		}
	}()
	defer stop()

	registry := prometheus.NewRegistry()
	registry.MustRegister(collectors.NewGoCollector())
	metrics := sandbox.NewMetrics(registry)
	var blobs *blobcache.Cache
	if blobCacheGiB > 0 {
		if blobs, err = blobcache.New(filepath.Join(dataDir, "blobs"), int64(blobCacheGiB)<<30, logger, blobcache.NewMetrics(registry)); err != nil {
			logger.Error("creating the blob cache", "error", err)
			os.Exit(1)
		}
	}

	netManager := network.NewManager(logger)
	netManager.PodInterface = os.Getenv("POD_INTERFACE")
	netManager.DaemonOnlyTCPPorts = tcpPortsEnv(logger, "DAEMON_ONLY_TCP_PORTS")
	// The single-port variable an older chart sets.
	if port := intEnv(logger, "DAEMON_ONLY_TCP_PORT", 0); port > 0 {
		netManager.DaemonOnlyTCPPorts = append(netManager.DaemonOnlyTCPPorts, port)
	}
	// Guests reach the Tuist API through its public URL. The in-cluster
	// server is the daemon's control channel, so the guests are kept off
	// its Service address unless the deployment needs them to reach it.
	if serverURL != "" && !boolEnv(logger, "GUESTS_REACH_SERVER", false) {
		endpoints, err := serviceEndpoints(ctx, serverURL)
		if err != nil {
			logger.Error("resolving SERVER_URL to keep the guests off it", "error", err)
			os.Exit(1)
		}
		netManager.DaemonOnlyEndpoints = endpoints
	}
	switch backend := os.Getenv("NETWORK_BACKEND"); backend {
	case "", "iproute2":
	case "netlink":
		if err := netManager.UseNetlink(); err != nil {
			logger.Error("network backend", "error", err)
			os.Exit(1)
		}
	default:
		logger.Error("unknown NETWORK_BACKEND", "backend", backend)
		os.Exit(1)
	}
	if err := netManager.EnsurePodNAT(ctx); err != nil {
		logger.Error("pod NAT setup", "error", err)
		os.Exit(1)
	}

	jailBase := filepath.Join(dataDir, "jail")
	snapshotDir := filepath.Join(dataDir, "snapshots")
	if err := os.MkdirAll(snapshotDir, 0o700); err != nil {
		logger.Error("creating the disk snapshot directory", "error", err)
		os.Exit(1)
	}
	// Experimental: only meaningful with CACHE_IMAGE_DIR. Changing it makes
	// startup remove shape snapshots built the other way, which the next
	// create rebuilds.
	cacheDriveInTemplate := os.Getenv("CACHE_IMAGE_DIR") != "" && os.Getenv("CACHE_DRIVE_IN_TEMPLATE") == "true"
	// Experimental too: guests boot with a free-page-reporting balloon and
	// return the memory they free. Changing it rebuilds shape snapshots the
	// same way.
	balloon := os.Getenv("BALLOON_FREE_PAGE_REPORTING") == "true"
	store := &template.Store{Dir: filepath.Join(dataDir, "templates")}
	if err := store.CleanPartialBuilds(fcVersion, templateWorkspaceGB, cacheDriveInTemplate, balloon); err != nil {
		logger.Error("cleaning partial template builds", "error", err)
		os.Exit(1)
	}
	templates, err := store.List()
	if err != nil {
		logger.Error("listing templates", "error", err)
		os.Exit(1)
	}
	if len(templates) == 0 {
		logger.Error("no templates under data dir; the init container must seed vmlinux and rootfs.ext4", "dir", store.Dir)
		os.Exit(1)
	}
	// With TEMPLATE_TAG set the daemon runs that tag until it restarts.
	// Without it, it follows the tag the template installer DaemonSet
	// completed last (the template's current file), so a template upgrade
	// reaches the node without restarting the daemon and its VMs.
	followCurrent := templateTag == ""
	// keepTag is the tag pruning keeps besides the ones in use; empty while
	// nothing names one, which keeps every tag.
	keepTag := templateTag
	startTag := templateTag
	if followCurrent {
		if keepTag, err = store.CurrentTag(templateName); err != nil {
			logger.Error("reading the current template tag", "template", templateName, "error", err)
			os.Exit(1)
		}
		startTag = keepTag
		if startTag == "" {
			// No installer has run on this node yet: the tag the last
			// template init container installed (it rewrote that tag's
			// metadata.json), or the only one on disk.
			if startTag, err = store.PreviousTag(templateName, ""); err != nil {
				logger.Error("finding the newest template tag", "template", templateName, "error", err)
				os.Exit(1)
			}
		}
	}
	defaultTemplate, err := store.Resolve(templateName, startTag)
	if err != nil {
		logger.Error("resolving default template", "error", err)
		os.Exit(1)
	}
	logger.Info("default template", "name", defaultTemplate.Name, "tag", defaultTemplate.Tag, "ready_shapes", defaultTemplate.ReadyShapes())

	// events fans daemon events out to the server connection once it
	// exists.
	var serverClient *server.Client
	events := func(event protocol.Event) {
		if serverClient != nil {
			serverClient.Emit(event)
		}
	}
	slots := network.NewSlots(network.MaxSlots)
	var launcher vm.Launcher = &vm.FirecrackerLauncher{Log: logger}
	if vmmSocket != "" {
		launcher = &vm.VMMLauncher{Socket: vmmSocket, Log: logger}
	}
	agent := func(path string) vsock.Agent { return vsock.NewUDSClient(path, firecracker.AgentPort) }
	builder := &template.Builder{
		Store: store, Launcher: launcher, Network: netManager, Slots: slots, Agent: agent,
		JailBase: jailBase, FirecrackerBin: firecrackerBin, JailerBin: jailerBin, JailerEnabled: jailerEnabled,
		UIDBase: uidBase, DNS: dns, FirecrackerVersion: fcVersion, WorkspaceGB: templateWorkspaceGB,
		BootTimeout: templateBootTimeout, Log: logger, Events: events,
		CacheDrive: cacheDriveInTemplate,
		Balloon:    balloon,
		Observe: func(shape template.Shape, elapsed time.Duration, err error) {
			if err == nil {
				metrics.TemplateBuild.WithLabelValues(shape.String()).Observe(elapsed.Seconds())
			}
		},
	}
	// The node's runner-cache agent seeds workers' repositories from its
	// checkout masters and takes their exports. It authorizes this Pod by
	// name and address; without either, workers clone as before.
	var checkouts checkout.Agent
	// The same agent copies runner-cache masters for cache grants, when
	// CACHE_IMAGE_DIR and CACHE_IMAGES_GIB are set.
	var cacheImages sandbox.CacheImageSource
	if agentURL := os.Getenv("CHECKOUT_AGENT_URL"); agentURL != "" {
		if elastic.PodName == "" {
			logger.Warn("CHECKOUT_AGENT_URL is set without POD_NAME; checkouts stay off")
		} else {
			client := &checkout.Client{URL: agentURL, PodName: elastic.PodName, HTTP: checkout.NewHTTPClient()}
			checkouts = client
			if cacheImagesGiB > 0 {
				cacheImages = client
			}
		}
	}
	// Prepared workspaces let a fresh sandbox start from the node's last seed
	// of its repository instead of copying the tree into the guest again.
	var workspaces *checkout.Workspaces
	if checkouts != nil && checkoutWorkspacesGiB > 0 {
		workspaces = &checkout.Workspaces{
			Dir: filepath.Join(dataDir, "checkouts"), MaxBytes: int64(checkoutWorkspacesGiB) << 30,
			TTL: durationEnv(logger, "CHECKOUT_WORKSPACES_TTL", 6*time.Hour), Log: logger,
		}
		if err := workspaces.Clean(); err != nil {
			logger.Error("preparing the checkout workspaces directory", "error", err)
			os.Exit(1)
		}
		workspaces.Expire()
		go func() {
			for range time.Tick(10 * time.Minute) {
				workspaces.Expire()
			}
		}()
	}
	manager := sandbox.New(sandbox.Config{
		JailBase: jailBase, FirecrackerBin: firecrackerBin, JailerBin: jailerBin, JailerEnabled: jailerEnabled,
		UIDBase: uidBase, DNS: dns, DefaultTemplate: templateName, DefaultTemplateTag: defaultTemplate.Tag, BootTimeout: bootTimeout,
		AllowedShapes: allowedShapes,
		SnapshotDir:   snapshotDir, FirecrackerVersion: fcVersion, SnapshotCompat: snapshotCompat,
		// Cache images must share the data filesystem so attaching one is a reflink.
		CacheImageDir: os.Getenv("CACHE_IMAGE_DIR"), CacheImagesBytes: int64(cacheImagesGiB) << 30,
		CacheImagesTTL: durationEnv(logger, "CACHE_IMAGES_TTL", 24*time.Hour),
	}, sandbox.Deps{
		Store: store, Builder: builder, Launcher: launcher, Network: netManager, Slots: slots, Agent: agent,
		Metrics: metrics, Events: events, Log: logger,
		Blobs: blobs, Checkouts: checkouts, Workspaces: workspaces, CacheImages: cacheImages, Cgroups: vmCgroups,
	})
	if err := manager.Recover(ctx); err != nil {
		logger.Error("recovering sandboxes", "error", err)
		os.Exit(1)
	}
	if cacheImages != nil {
		manager.ExpireCacheImages()
		go func() {
			for range time.Tick(10 * time.Minute) {
				manager.ExpireCacheImages()
			}
		}()
	}
	// Remote-execution daemons also keep the tag they ran before this one:
	// the server places executions on the tag most nodes are configured
	// with, so a node that dropped it during an OnDelete rollout would take
	// no work until most nodes rolled. Older tags serve nothing; keeping
	// every one filled runner disks past the blob cache's free-space floor.
	pruneTemplateTags := func(current string) {
		if current == "" {
			return
		}
		inUse := map[string]bool{}
		if executionSlots > 0 {
			previous, err := store.PreviousTag(templateName, current)
			if err != nil {
				// Keep every tag rather than drop the one a rollout still needs.
				logger.Warn("finding the previous template tag", "template", templateName, "error", err)
				return
			}
			if previous != "" {
				inUse[previous] = true
			}
		}
		for _, sb := range manager.List() {
			if sb.Template == templateName {
				inUse[sb.TemplateTag] = true
			}
		}
		for _, snap := range manager.DiskSnapshots() {
			if snap.Template == templateName {
				inUse[snap.TemplateTag] = true
			}
		}
		removed, err := store.RemoveStaleTags(templateName, current, func(tag string) bool { return inUse[tag] })
		if err != nil {
			logger.Warn("removing stale template tags", "template", templateName, "removed", removed, "error", err)
		} else if len(removed) > 0 {
			logger.Info("removed stale template tags", "template", templateName, "tags", removed)
		}
	}
	pruneTemplateTags(keepTag)

	go func() {
		for _, shape := range prebuild {
			if ctx.Err() != nil {
				return
			}
			if _, err := builder.Ensure(ctx, defaultTemplate, shape); err != nil {
				logger.Error("prebuilding template shape", "shape", shape.String(), "error", err)
			}
		}
	}()

	mux := http.NewServeMux()
	mux.Handle("/metrics", promhttp.HandlerFor(registry, promhttp.HandlerOpts{}))
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	metricsServer := &http.Server{Addr: metricsAddr, Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	go func() {
		if err := metricsServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("metrics server", "error", err)
			os.Exit(1)
		}
	}()

	var adminServer *http.Server
	if adminAddr != "" {
		adminServer = &http.Server{Addr: adminAddr, Handler: admin.NewHandler(manager, logger), ReadHeaderTimeout: 5 * time.Second}
		go func() {
			logger.Info("admin API listening (unauthenticated)", "addr", adminAddr)
			if err := adminServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
				logger.Error("admin server", "error", err)
				os.Exit(1)
			}
		}()
	}

	var directExecServer *http.Server
	directExecEndpoint := ""
	if directExecAddr != "" {
		directExecEndpoint = "http://" + directExecAddr
		directExecServer = &http.Server{Addr: directExecAddr, Handler: direct.NewHandler(manager.Claims()), ReadHeaderTimeout: 5 * time.Second}
		go func() {
			logger.Info("direct exec claims listening", "addr", directExecAddr)
			if err := directExecServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
				logger.Error("direct exec server", "error", err)
				os.Exit(1)
			}
		}()
	}

	disk := diskusage.Accounter{
		DataDir: dataDir, TemplatesDir: store.Dir, SnapshotsDir: snapshotDir, JailDir: jailBase,
		BlobCacheDir: filepath.Join(dataDir, "blobs"), CheckoutsDir: filepath.Join(dataDir, "checkouts"), CacheImagesDir: os.Getenv("CACHE_IMAGE_DIR"), BudgetBytes: uint64(sandboxBudgetGiB) << 30, //nolint:gosec // Checked non-negative above.
	}
	diskReport := func() protocol.DiskReport {
		report, err := disk.Report()
		if err != nil {
			logger.Warn("measuring disk usage", "error", err)
		}
		return report
	}
	// Each sandbox carries its jail's share of the disk report. The list is
	// taken before the measurement, so a sandbox listed as paused was
	// measured after its pause wrote its memory image.
	withDisk := func(infos []protocol.SandboxInfo, report protocol.DiskReport) []protocol.SandboxInfo {
		for i := range infos {
			infos[i].DiskBytes = report.Jails[infos[i].ID]
		}
		return infos
	}
	capacity := hostinfo.Capacity()
	metrics.MemoryBudgetBytes.Set(float64(capacity.MemoryBytes))
	metrics.DiskBudgetBytes.Set(float64(disk.BudgetBytes))
	logger.Info("capacity", "memory_bytes", capacity.MemoryBytes, "cpus", capacity.CPUs, "disk_budget_bytes", disk.BudgetBytes)

	serverDone := make(chan struct{})
	if serverURL != "" {
		serverClient = server.New(server.Config{
			URL: serverURL, NodeName: nodeName, TokenPath: tokenPath, Log: logger,
			Hello: func() protocol.Hello {
				sandboxes := manager.List()
				disk := diskReport()
				return protocol.Hello{
					ExecutionDeadlines:   true,
					ExecutionSlots:       executionSlots,
					DirectExecEndpoint:   directExecEndpoint,
					SnapshotCompat:       snapshotCompat,
					LazyDisks:            true,
					CPUGuarantees:        vmCgroups != nil,
					CacheGrants:          cacheImages != nil,
					CacheDriveInTemplate: cacheDriveInTemplate,
					DefaultTemplate:      templateName,
					DefaultTemplateTag:   manager.DefaultTemplateTag(),
					DaemonVersion:        version, FirecrackerVersion: fcVersion, Capacity: hostinfo.Capacity(), Elastic: elastic, Disk: disk,
					Templates: manager.Templates(), Sandboxes: withDisk(sandboxes, disk), DiskSnapshots: manager.DiskSnapshots(),
				}
			},
			Report: func() protocol.Report {
				used := hostinfo.MemoryUsed()
				sandboxes := manager.List()
				report := diskReport()
				metrics.MemoryUsedBytes.Set(float64(used))
				metrics.DiskSandboxesBytes.Set(float64(report.SandboxesBytes))
				metrics.DiskAvailableBytes.Set(float64(report.AvailableBytes))
				metrics.ObserveVMs(sandboxes)
				out := protocol.Report{Capacity: hostinfo.Capacity(), Sandboxes: withDisk(sandboxes, report), DiskSnapshots: manager.DiskSnapshots(), Memory: protocol.MemoryReport{UsedBytes: used}, Disk: report}
				if followCurrent {
					out.Templates = manager.Templates()
					out.DefaultTemplate = templateName
					out.DefaultTemplateTag = manager.DefaultTemplateTag()
				}
				return out
			},
			Handler: func(ctx context.Context, cmd protocol.Command, stream func(protocol.Stream)) protocol.Result {
				return sandbox.Dispatch(ctx, manager, cmd, stream)
			},
		})
		go func() {
			serverClient.Run(ctx)
			close(serverDone)
		}()
		go watchMemoryLimit(ctx, capacity.MemoryBytes, func(limit uint64) {
			metrics.MemoryBudgetBytes.Set(float64(limit))
			logger.Info("memory limit changed", "memory_bytes", limit)
			serverClient.ReportNow()
		})
	} else {
		close(serverDone)
		logger.Info("SERVER_URL not set; running admin-only")
	}

	if followCurrent {
		go followTemplate(ctx, logger, store, builder, manager, templateName, prebuild, keepTag != "", pruneTemplateTags, func() {
			if serverClient != nil {
				serverClient.ReportNow()
			}
		})
	}

	logger.Info("sandboxd started", "version", version, "node", nodeName, "firecracker", fcVersion, "jailer", jailerEnabled, "data_dir", dataDir, "dns", dns)
	<-ctx.Done()
	stop()
	logger.Info("shutting down: pausing idle sandboxes", "timeout", shutdownTimeout)
	// Stop taking commands first: the server connection closes and its
	// in-flight lifecycle ops finish on their own detached contexts.
	<-serverDone
	if adminServer != nil {
		_ = adminServer.Close()
	}
	if directExecServer != nil {
		_ = directExecServer.Close()
	}
	shutdownCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()
	manager.Shutdown(shutdownCtx)
	_ = metricsServer.Close()
	logger.Info("sandboxd stopped")
}

func levelEnv(key string, fallback slog.Level) (slog.Level, error) {
	value := os.Getenv(key)
	if value == "" {
		return fallback, nil
	}
	var level slog.Level
	if err := level.UnmarshalText([]byte(value)); err != nil {
		return fallback, err
	}
	return level, nil
}

func envOr(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func boolEnv(logger *slog.Logger, key string, fallback bool) bool {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	parsed, err := strconv.ParseBool(value)
	if err != nil {
		logger.Error("invalid boolean", "env", key, "value", value)
		os.Exit(1)
	}
	return parsed
}

func tcpPortsEnv(logger *slog.Logger, key string) []int {
	var ports []int
	for _, field := range strings.Split(os.Getenv(key), ",") {
		field = strings.TrimSpace(field)
		if field == "" {
			continue
		}
		port, err := strconv.Atoi(field)
		if err != nil || port < 1 || port > 65535 {
			logger.Error("invalid TCP port", "env", key, "value", field)
			os.Exit(1)
		}
		ports = append(ports, port)
	}
	return ports
}

// serviceEndpoints resolves a URL's host to its IPv4 addresses and port.
// Cluster DNS can lag a Pod's start, so a failed lookup is retried for
// about a minute before startup gives up.
func serviceEndpoints(ctx context.Context, rawURL string) ([]netip.AddrPort, error) {
	u, err := url.Parse(rawURL)
	if err != nil || u.Hostname() == "" {
		return nil, fmt.Errorf("parsing %q: no host", rawURL)
	}
	port := 80
	if u.Scheme == "https" {
		port = 443
	}
	if u.Port() != "" {
		if port, err = strconv.Atoi(u.Port()); err != nil {
			return nil, fmt.Errorf("parsing the port of %q: %w", rawURL, err)
		}
	}
	var addrs []netip.Addr
	for attempt := 1; ; attempt++ {
		lookupCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
		addrs, err = net.DefaultResolver.LookupNetIP(lookupCtx, "ip4", u.Hostname())
		cancel()
		if err == nil || attempt == 12 || ctx.Err() != nil {
			break
		}
		time.Sleep(5 * time.Second)
	}
	if err != nil {
		return nil, err
	}
	endpoints := make([]netip.AddrPort, 0, len(addrs))
	for _, addr := range addrs {
		endpoints = append(endpoints, netip.AddrPortFrom(addr.Unmap(), uint16(port)))
	}
	return endpoints, nil
}

func intEnv(logger *slog.Logger, key string, fallback int) int {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(value)
	if err != nil {
		logger.Error("invalid integer", "env", key, "value", value)
		os.Exit(1)
	}
	return parsed
}

func durationEnv(logger *slog.Logger, key string, fallback time.Duration) time.Duration {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	parsed, err := time.ParseDuration(value)
	if err != nil {
		logger.Error("invalid duration", "env", key, "value", value)
		os.Exit(1)
	}
	return parsed
}

// memoryLimitPollInterval is how often the daemon rereads its cgroup's
// memory limit. The server resizes the Pod in place and waits for the new
// limit to be reported before it places a guest into it.
const memoryLimitPollInterval = 250 * time.Millisecond

// watchMemoryLimit calls changed whenever the cgroup's memory limit moves
// away from the last value seen.
func watchMemoryLimit(ctx context.Context, initial uint64, changed func(uint64)) {
	ticker := time.NewTicker(memoryLimitPollInterval)
	defer ticker.Stop()
	last := initial
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if limit := hostinfo.Capacity().MemoryBytes; limit != last {
				last = limit
				changed(limit)
			}
		}
	}
}

// templateFollowInterval is how often a daemon without TEMPLATE_TAG checks
// its template's current file, and templateRetryAfter how long it waits
// before building a tag whose shapes failed to build again.
var (
	templateFollowInterval = 30 * time.Second
	templateRetryAfter     = 10 * time.Minute
)

// followTemplate moves the daemon's default template to the tag the
// installer completed last. The prebuilt shapes are built first, so the
// first sandbox on the new tag does not wait for a template boot, and the
// switch happens only once they are ready; until then creates keep using the
// previous tag. Sandboxes already created keep their own tag. Tags nothing
// uses any longer are removed after each switch, and report announces the
// new default to the server.
func followTemplate(ctx context.Context, logger *slog.Logger, store *template.Store, builder *template.Builder, manager *sandbox.Manager,
	name string, prebuild []template.Shape, pruned bool, prune func(current string), report func(),
) {
	var failedTag string
	var failedAt time.Time
	ticker := time.NewTicker(templateFollowInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
		tag, err := store.CurrentTag(name)
		if err != nil {
			logger.Warn("reading the current template tag", "template", name, "error", err)
			continue
		}
		if tag == "" {
			continue
		}
		if tag == manager.DefaultTemplateTag() {
			// The daemon started before the installer first named its tag.
			if !pruned {
				prune(tag)
				pruned = true
			}
			continue
		}
		if tag == failedTag && time.Since(failedAt) < templateRetryAfter {
			continue
		}
		tmpl, err := store.Get(name, tag)
		if err == nil {
			for _, shape := range prebuild {
				if _, err = builder.Ensure(ctx, tmpl, shape); err != nil {
					break
				}
			}
		}
		if err != nil {
			if ctx.Err() == nil {
				logger.Error("preparing the current template tag; creates keep the previous one", "template", name, "tag", tag, "error", err)
				failedTag, failedAt = tag, time.Now()
			}
			continue
		}
		previous := manager.DefaultTemplateTag()
		manager.SetDefaultTemplateTag(tag)
		logger.Info("default template tag changed", "template", name, "from", previous, "to", tag)
		prune(tag)
		pruned = true
		report()
	}
}
