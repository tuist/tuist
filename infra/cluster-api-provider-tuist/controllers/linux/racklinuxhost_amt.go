package linux

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"math/big"
	"net"
	"regexp"
	"strconv"
	"strings"
	"time"
	"unicode"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/controller-runtime/pkg/client"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

// AMTActivatedCondition reports whether a host that asks for AMT has it
// activated in admin control mode.
const AMTActivatedCondition clusterv1.ConditionType = "AMTActivated"

// rpc is the Device Management Toolkit's AMT client. Hosts download it once,
// pinned by the release tarball's digest. It is a 3.0 prerelease: 2.x talks to
// AMT over a transport that hangs on the MS-01 without Intel's LMS daemon.
const (
	amtRPCURL    = "https://github.com/device-management-toolkit/rpc-go/releases/download/v3.0.0-beta.61/rpc_linux_x64.tar.gz"
	amtRPCSHA256 = "e6513f029fbdfa6b982ff20ff9181d4fdcb12eb38124373751a136310f41200c"
	amtRPCPath   = "/usr/local/lib/tuist/rpc-3.0.0-beta.61"

	amtScriptTimeout     = 15 * time.Minute
	amtActivationBackoff = time.Hour
	amtObserveInterval   = time.Hour
	// amtAddressInterval is how soon an activated AMT without an address, which
	// it takes by DHCP after the activation, is looked at again, and how long
	// AMT given its static address is left before it is given it again.
	amtAddressInterval = 2 * time.Minute

	amtPreProvisioning = "pre-provisioning"
	amtClientControl   = "client"
	amtAdminControl    = "admin"

	amtPasswordLength = 24
	// amtPasswordSpecials are the symbols a generated password draws from:
	// AMT refuses `"`, `,` and `:`.
	amtPasswordSpecials = "!#%*+-.=?@^_~"
)

// RackAMT is what the operator activates rack hosts' AMT with.
type RackAMT struct {
	// FleetName names the fleet whose SSH key reaches the hosts.
	FleetName string
	// ProvisioningSecret is the Secret, in the operator's namespace, holding
	// the provisioning certificate as a base64 PKCS#12 (`pfx`) and its
	// `password`.
	ProvisioningSecret string
	// Products are the hardware models, as their SMBIOS vendor and product
	// name, whose AMT is activated unless a host sets spec.amt.activate.
	Products []string
	// AddressRange is the range, a CIDR, the operator gives activated AMT
	// static addresses from, and Gateway the gateway of the segment it is on
	// with the segment's prefix length (192.168.50.1/24), which the address
	// AMT gets carries. A host's spec.amt.address takes precedence.
	AddressRange string
	Gateway      string
}

// amtWanted reports whether the operator activates the host's AMT:
// spec.amt.activate when set, else whether the machine is a model the fleet
// lists.
func (r *RackLinuxHostReconciler) amtWanted(host *infrav1.RackLinuxHost) bool {
	if host.Spec.AMT.Activate != nil {
		return *host.Spec.AMT.Activate
	}
	if r.AMT == nil || host.Status.Hardware == nil {
		return false
	}
	for _, product := range r.AMT.Products {
		if product != "" && product == host.Status.Hardware.Product {
			return true
		}
	}
	return false
}

// amtRun is what a run of the AMT script does besides reading AMT's state,
// and the secrets it takes to do it.
type amtRun struct {
	// Password is AMT's admin password.
	Password string
	// PFX and PFXPassword, the provisioning certificate, activate AMT.
	PFX, PFXPassword string
	// MEBxPassword, when set, replaces MEBx's password on activated AMT.
	MEBxPassword string
	// Address, Mask and Gateway, when set, give activated AMT a static
	// address.
	Address, Mask, Gateway string
}

// reconcileAMT takes the host's AMT to admin control mode when the host asks
// for it and AMT is not there yet, then configures it (its MEBx password, its
// static address), and otherwise reads AMT's state now and then. It returns
// when to look again.
func (r *RackLinuxHostReconciler) reconcileAMT(ctx context.Context, host *infrav1.RackLinuxHost) time.Duration {
	if !r.amtWanted(host) {
		conditions.Delete(host, AMTActivatedCondition)
		return 0
	}
	if r.AMT == nil || r.AMT.ProvisioningSecret == "" {
		conditions.MarkFalse(host, AMTActivatedCondition, "NoProvisioningCertificate", clusterv1.ConditionSeverityWarning,
			"the operator has no AMT provisioning certificate (--rack-linux-amt-provisioning-secret-name)")
		return 0
	}
	if host.Status.Tailnet == nil || !host.Status.Tailnet.Connected {
		return 0
	}
	address, err := r.amtAddress(ctx, host)
	if err != nil {
		conditions.MarkFalse(host, AMTActivatedCondition, "InvalidAddress", clusterv1.ConditionSeverityWarning, "%v", err)
		return 0
	}

	now := r.now()
	status := host.Status.AMT
	activate := status == nil || status.ControlMode == "" || status.ControlMode == amtPreProvisioning || status.ControlMode == amtClientControl
	// AMT without a link reports no address, whatever it was given.
	configure := !activate && (!status.MEBxPasswordSet || (address != nil && status.Link != "down" && status.Address != address.ip))
	switch {
	case activate:
		if status != nil && status.ActivationError != "" && status.LastActivation != nil {
			if wait := status.LastActivation.Add(amtActivationBackoff).Sub(now); wait > 0 {
				return wait
			}
		}
	case configure:
		// AMT reports its old address for a while after it is given a static one.
		if status.LastConfiguration != nil {
			backoff := amtAddressInterval
			if status.ConfigurationError != "" {
				backoff = amtActivationBackoff
			}
			if wait := status.LastConfiguration.Add(backoff).Sub(now); wait > 0 {
				return wait
			}
		}
	case status.ObservedAt != nil:
		if wait := status.ObservedAt.Add(amtObserveAfter(status)).Sub(now); wait > 0 {
			return wait
		}
	}

	var run *amtRun
	if activate || configure {
		var reason string
		run, reason, err = r.amtRun(ctx, host, activate, status == nil || !status.MEBxPasswordSet, address)
		if err != nil {
			conditions.MarkFalse(host, AMTActivatedCondition, "AMTSecretsUnreadable", clusterv1.ConditionSeverityWarning, "%v", err)
			return time.Minute
		}
		if reason != "" {
			conditions.MarkFalse(host, AMTActivatedCondition, "NoProvisioningCertificate", clusterv1.ConditionSeverityWarning, "%s", reason)
			return 10 * time.Minute
		}
	}

	out, runErr := runOnRackHost(ctx, r.Client, r.CredentialsManager, r.AMT.FleetName, r.egress(), r.RunScript,
		host, renderAMTScript(run), amtScriptTimeout)
	result, parseErr := parseAMTScriptOutput(out)
	if parseErr != nil {
		err := parseErr
		if runErr != nil {
			err = runErr
		}
		r.Recorder.Eventf(host, corev1.EventTypeWarning, "AMTUnreadable", "Could not read AMT's state: %v", err)
		conditions.MarkFalse(host, AMTActivatedCondition, "AMTUnreadable", clusterv1.ConditionSeverityWarning, "%v", err)
		return 10 * time.Minute
	}

	observed := metav1.NewTime(now)
	next := &infrav1.RackLinuxHostAMTStatus{}
	if status != nil {
		next = status.DeepCopy()
	}
	next.ControlMode = amtControlMode(result.info.ControlMode)
	next.Version = result.info.Version
	next.Link = result.info.Wired.LinkStatus
	next.Address = result.info.Wired.Address
	if uuid := strings.ToLower(result.info.UUID); smbiosUUIDPattern.MatchString(uuid) {
		next.UUID = uuid
	}
	next.ObservedAt = &observed
	if step, ok := result.steps["activate"]; ok {
		next.LastActivation = &observed
		next.ActivationError = ""
		switch {
		case step.exit != 0:
			next.ActivationError = truncateMessage("rpc activate " + step.String())
		case next.ControlMode != amtAdminControl:
			next.ActivationError = truncateMessage(fmt.Sprintf("rpc activate succeeded, and AMT reports %q: %s", result.info.ControlMode, step.output))
		}
		if next.ActivationError == "" {
			r.Recorder.Event(host, corev1.EventTypeNormal, "AMTActivated", "Activated AMT in admin control mode")
		} else {
			r.Recorder.Eventf(host, corev1.EventTypeWarning, "AMTActivationFailed", "%s", next.ActivationError)
		}
	}
	requested := ""
	if address != nil {
		requested = address.ip
	}
	r.recordAMTConfiguration(host, next, result, requested, &observed)
	host.Status.AMT = next

	if next.ControlMode == amtAdminControl {
		next.ActivationError = ""
		conditions.MarkTrue(host, AMTActivatedCondition)
		return amtObserveAfter(next)
	}
	if next.ActivationError != "" {
		conditions.MarkFalse(host, AMTActivatedCondition, "ActivationFailed", clusterv1.ConditionSeverityWarning, "%s", next.ActivationError)
		return amtActivationBackoff
	}
	conditions.MarkFalse(host, AMTActivatedCondition, "NotActivated", clusterv1.ConditionSeverityInfo, "AMT reports %q", result.info.ControlMode)
	return amtObserveInterval
}

// recordAMTConfiguration records the configuration steps a run took.
func (r *RackLinuxHostReconciler) recordAMTConfiguration(host *infrav1.RackLinuxHost, next *infrav1.RackLinuxHostAMTStatus,
	result amtScriptResult, address string, observed *metav1.Time) {
	var done, failed []string
	for _, name := range []string{"mebx", "wired"} {
		step, ok := result.steps[name]
		switch {
		case !ok:
			continue
		case step.exit != 0:
			failed = append(failed, fmt.Sprintf("rpc configure %s %s", name, step))
		case name == "mebx":
			next.MEBxPasswordSet = true
			done = append(done, "set the MEBx password")
		default:
			done = append(done, "gave AMT the address "+address)
		}
	}
	if len(done) == 0 && len(failed) == 0 {
		return
	}
	next.LastConfiguration = observed
	next.ConfigurationError = truncateMessage(strings.Join(failed, "; "))
	if len(done) > 0 {
		r.Recorder.Eventf(host, corev1.EventTypeNormal, "AMTConfigured", "Configured AMT: %s", strings.Join(done, ", "))
	}
	if len(failed) > 0 {
		r.Recorder.Eventf(host, corev1.EventTypeWarning, "AMTConfigurationFailed", "%s", next.ConfigurationError)
	}
}

// amtAddress is a static address for AMT.
type amtAddress struct {
	ip, mask, gateway string
}

// amtStaticAddress is the static address spec asks for, nil when it asks for
// none.
func amtStaticAddress(cidr, gatewayAddress string) (*amtAddress, error) {
	ip, network, err := net.ParseCIDR(cidr)
	if err != nil || ip.To4() == nil {
		return nil, fmt.Errorf("the AMT address %q is not an IPv4 address with its prefix length", cidr)
	}
	gateway := net.ParseIP(gatewayAddress)
	if gateway == nil || gateway.To4() == nil || !network.Contains(gateway) {
		return nil, fmt.Errorf("the AMT address %s needs a gateway, an IPv4 address in %s", cidr, network)
	}
	return &amtAddress{ip: ip.String(), mask: net.IP(network.Mask).String(), gateway: gateway.String()}, nil
}

// amtAddress is the static address the host's AMT gets: spec.amt.address, or
// one the operator takes from the fleet's range and records in
// status.amt.assignedAddress, so the host keeps it. A host without either
// leaves AMT on DHCP.
func (r *RackLinuxHostReconciler) amtAddress(ctx context.Context, host *infrav1.RackLinuxHost) (*amtAddress, error) {
	gateway := host.Spec.AMT.Gateway
	if gateway == "" && r.AMT != nil {
		gateway, _, _ = strings.Cut(r.AMT.Gateway, "/")
	}
	if host.Spec.AMT.Address != "" {
		address, err := amtStaticAddress(host.Spec.AMT.Address, gateway)
		if err == nil {
			r.assignAMTAddress(host, host.Spec.AMT.Address)
		}
		return address, err
	}
	if r.AMT == nil || r.AMT.AddressRange == "" {
		return nil, nil
	}
	assigned, err := r.allocateAMTAddress(ctx, host)
	if err != nil {
		return nil, err
	}
	r.assignAMTAddress(host, assigned)
	return amtStaticAddress(assigned, gateway)
}

func (r *RackLinuxHostReconciler) assignAMTAddress(host *infrav1.RackLinuxHost, cidr string) {
	if host.Status.AMT == nil {
		host.Status.AMT = &infrav1.RackLinuxHostAMTStatus{}
	}
	host.Status.AMT.AssignedAddress = cidr
}

// allocateAMTAddress takes the host an address from the fleet's range: the one
// it was given before while it is still in the range and no other host holds
// it, else the one AMT has now if that is free, else the lowest free one.
func (r *RackLinuxHostReconciler) allocateAMTAddress(ctx context.Context, host *infrav1.RackLinuxHost) (string, error) {
	_, network, err := net.ParseCIDR(r.AMT.AddressRange)
	if err != nil || network.IP.To4() == nil {
		return "", fmt.Errorf("the fleet's AMT address range %q is not an IPv4 CIDR", r.AMT.AddressRange)
	}
	prefix, _ := network.Mask.Size()
	gateway := net.ParseIP(r.AMT.Gateway)
	if ip, segment, err := net.ParseCIDR(r.AMT.Gateway); err == nil {
		if !segment.Contains(network.IP) {
			return "", fmt.Errorf("the fleet's AMT address range %s is not on the segment of its gateway %s", r.AMT.AddressRange, r.AMT.Gateway)
		}
		gateway = ip
		prefix, _ = segment.Mask.Size()
	}
	var reader client.Reader = r.Client
	if r.APIReader != nil {
		reader = r.APIReader
	}
	hosts := &infrav1.RackLinuxHostList{}
	if err := reader.List(ctx, hosts, client.InNamespace(host.Namespace)); err != nil {
		return "", fmt.Errorf("list rack Linux hosts: %w", err)
	}
	taken := map[string]bool{}
	for i := range hosts.Items {
		h := &hosts.Items[i]
		if h.Name == host.Name {
			continue
		}
		if h.Spec.AMT.Address != "" {
			taken[strings.Split(h.Spec.AMT.Address, "/")[0]] = true
		}
		if h.Status.AMT != nil && h.Status.AMT.AssignedAddress != "" {
			taken[strings.Split(h.Status.AMT.AssignedAddress, "/")[0]] = true
		}
	}
	usable := func(ip net.IP) bool {
		ip4 := ip.To4()
		return ip4 != nil && network.Contains(ip4) && !ip4.Equal(network.IP) && !ip4.Equal(amtBroadcast(network)) &&
			!ip4.Equal(gateway) && !taken[ip4.String()]
	}
	withPrefix := func(ip net.IP) string { return fmt.Sprintf("%s/%d", ip.To4(), prefix) }
	if s := host.Status.AMT; s != nil && s.AssignedAddress != "" {
		if ip, _, err := net.ParseCIDR(s.AssignedAddress); err == nil && usable(ip) {
			return withPrefix(ip), nil
		}
	}
	if s := host.Status.AMT; s != nil && s.Address != "" {
		if ip := net.ParseIP(s.Address); ip != nil && usable(ip) {
			return withPrefix(ip), nil
		}
	}
	for ip := amtNext(network.IP.To4()); network.Contains(ip); ip = amtNext(ip) {
		if usable(ip) {
			return withPrefix(ip), nil
		}
	}
	return "", fmt.Errorf("no address is left in the fleet's AMT range %s", r.AMT.AddressRange)
}

func amtNext(ip net.IP) net.IP {
	next := make(net.IP, len(ip))
	copy(next, ip)
	for i := len(next) - 1; i >= 0; i-- {
		next[i]++
		if next[i] != 0 {
			break
		}
	}
	return next
}

func amtBroadcast(network *net.IPNet) net.IP {
	ip := network.IP.To4()
	broadcast := make(net.IP, len(ip))
	for i := range ip {
		broadcast[i] = ip[i] | ^network.Mask[i]
	}
	return broadcast
}

// amtRun reads what a run that activates or configures AMT needs: the host's
// admin and MEBx passwords, generated and stored first when the host has none,
// so a run never sets a password the operator did not keep, and, to activate,
// the provisioning certificate. A non-empty reason means the certificate is
// missing.
func (r *RackLinuxHostReconciler) amtRun(ctx context.Context, host *infrav1.RackLinuxHost, activate, mebx bool, address *amtAddress) (*amtRun, string, error) {
	namespace := r.CredentialsManager.Namespace
	run := &amtRun{}
	if activate {
		provisioning := &corev1.Secret{}
		if err := r.Get(ctx, types.NamespacedName{Namespace: namespace, Name: r.AMT.ProvisioningSecret}, provisioning); err != nil {
			if apierrors.IsNotFound(err) {
				return nil, fmt.Sprintf("the Secret %s/%s holding the AMT provisioning certificate does not exist", namespace, r.AMT.ProvisioningSecret), nil
			}
			return nil, "", fmt.Errorf("read the AMT provisioning certificate: %w", err)
		}
		run.PFX, run.PFXPassword = string(provisioning.Data["pfx"]), string(provisioning.Data["password"])
		if run.PFX == "" || run.PFXPassword == "" {
			return nil, fmt.Sprintf("the Secret %s/%s lacks pfx or password", namespace, r.AMT.ProvisioningSecret), nil
		}
	}

	name := amtSecretName(host)
	secret := &corev1.Secret{}
	err := r.Get(ctx, types.NamespacedName{Namespace: namespace, Name: name}, secret)
	switch {
	case apierrors.IsNotFound(err):
		secret = &corev1.Secret{
			ObjectMeta: metav1.ObjectMeta{
				Name:      name,
				Namespace: namespace,
				Labels:    map[string]string{"app.kubernetes.io/component": "rack-amt", "tuist.dev/rack-linux-host": host.Name},
			},
			Type: corev1.SecretTypeOpaque,
			Data: map[string][]byte{"username": []byte("admin")},
		}
	case err != nil:
		return nil, "", fmt.Errorf("read the AMT password: %w", err)
	}
	if secret.Data == nil {
		secret.Data = map[string][]byte{}
	}
	generated := false
	for _, key := range []string{"password", "mebx-password"} {
		if _, ok := secret.Data[key]; ok {
			continue
		}
		password, err := generateAMTPassword()
		if err != nil {
			return nil, "", err
		}
		secret.Data[key] = []byte(password)
		generated = true
	}
	switch {
	case secret.ResourceVersion == "":
		if err := r.Create(ctx, secret); err != nil {
			return nil, "", fmt.Errorf("store the AMT passwords: %w", err)
		}
	case generated:
		if err := r.Update(ctx, secret); err != nil {
			return nil, "", fmt.Errorf("store the AMT passwords: %w", err)
		}
	}
	run.Password = string(secret.Data["password"])
	if !validAMTPassword(run.Password) || !validAMTPassword(string(secret.Data["mebx-password"])) {
		return nil, "", fmt.Errorf("the Secret %s/%s holds no valid AMT or MEBx password", namespace, name)
	}
	if mebx {
		run.MEBxPassword = string(secret.Data["mebx-password"])
	}
	if address != nil {
		run.Address, run.Mask, run.Gateway = address.ip, address.mask, address.gateway
	}
	return run, "", nil
}

// amtSecretName is the Secret holding a host's AMT admin credentials. It
// outlives the RackLinuxHost: an activated AMT keeps the password.
func amtSecretName(host *infrav1.RackLinuxHost) string {
	return host.Name + "-amt"
}

// renderAMTScript installs rpc on the host if it is missing and prints AMT's
// state after a `--- amtinfo` line. Each step it takes first prints its output
// between `--- <step>` and `--- <step> exit <status>`.
//
// With a certificate, it takes AMT to admin control mode (activate). AMT
// checks the provisioning certificate against the DHCP domain, and learns
// that only from a lease of its own, which it takes once activated: so a
// pre-provisioned AMT is activated in client control mode, given time to take
// its lease, and then upgraded, as is an AMT left in client control mode.
// Activated AMT then gets the MEBx password (mebx) and the static address
// (wired) the run carries.
//
// The secrets reach rpc only through the environment of the runs that need
// them, so they appear on no command line and in no file.
func renderAMTScript(a *amtRun) string {
	var b strings.Builder
	fmt.Fprintf(&b, `set -euo pipefail
rpc=%[1]s
if [ ! -x "$rpc" ]; then
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL --retry 3 --max-time 300 -o "$tmp/rpc.tar.gz" %[2]s
  echo "%[3]s  $tmp/rpc.tar.gz" | sha256sum -c --quiet
  tar -xzf "$tmp/rpc.tar.gz" -C "$tmp" rpc_linux_x64
  install -D -m 0755 "$tmp/rpc_linux_x64" "$rpc"
fi
info() { timeout 120 "$rpc" amtinfo --json --ver --mode --lan --uuid 2>/dev/null; }
`, amtRPCPath, amtRPCURL, amtRPCSHA256)
	if a != nil {
		fmt.Fprintf(&b, `amt_password=%s
provisioning_cert=%s
provisioning_cert_password=%s
mebx_password=%s
static_address=%s
static_mask=%s
static_gateway=%s
activate() {
  AMT_PASSWORD="$amt_password" PROVISIONING_CERT="$provisioning_cert" PROVISIONING_CERT_PASSWORD="$provisioning_cert_password" \
    timeout --kill-after=10 300 "$rpc" activate "$@" --skipIPRenew --json 2>&1
}
configure() {
  AMT_PASSWORD="$amt_password" MEBX_PASSWORD="$mebx_password" \
    timeout --kill-after=10 120 "$rpc" configure "$@" --json 2>&1
}
mode=$(info | jq -r .controlMode)
if [ -n "$provisioning_cert" ] && { [ "$mode" = 'not activated' ] || [ "$mode" = 'client control mode' ]; }; then
  echo '--- activate'
  status=0
  if [ "$mode" = 'not activated' ]; then
    activate --ccm || status=$?
    for _ in $(seq 1 36); do
      [ "$status" = 0 ] && [ "$(info | jq -r .wiredAdapter.ipAddress)" = 0.0.0.0 ] || break
      sleep 5
    done
  fi
  if [ "$status" = 0 ]; then
    activate --acm || status=$?
  fi
  echo "--- activate exit $status"
  mode=$(info | jq -r .controlMode)
fi
if [ "$mode" = 'admin control mode' ]; then
  if [ -n "$mebx_password" ]; then
    echo '--- mebx'
    status=0
    configure mebx || status=$?
    echo "--- mebx exit $status"
  fi
  if [ -n "$static_address" ] && [ "$(info | jq -r .wiredAdapter.ipAddress)" != "$static_address" ]; then
    echo '--- wired'
    status=0
    configure wired --ipaddress "$static_address" --subnetmask "$static_mask" --gateway "$static_gateway" --primarydns "$static_gateway" || status=$?
    echo "--- wired exit $status"
  fi
fi
unset amt_password provisioning_cert provisioning_cert_password mebx_password
`, shellSingleQuote(a.Password), shellSingleQuote(a.PFX), shellSingleQuote(a.PFXPassword), shellSingleQuote(a.MEBxPassword),
			shellSingleQuote(a.Address), shellSingleQuote(a.Mask), shellSingleQuote(a.Gateway))
	}
	b.WriteString("echo '--- amtinfo'\ninfo\n")
	return b.String()
}

type amtInfo struct {
	Version     string `json:"amt"`
	ControlMode string `json:"controlMode"`
	UUID        string `json:"uuid"`
	Wired       struct {
		LinkStatus string `json:"linkStatus"`
		Address    string `json:"ipAddress"`
	} `json:"wiredAdapter"`
}

// amtStep is one step the AMT script took: its exit status and output.
type amtStep struct {
	exit   int
	output string
}

func (s amtStep) String() string {
	return fmt.Sprintf("exit %d: %s", s.exit, s.output)
}

type amtScriptResult struct {
	info  amtInfo
	steps map[string]amtStep
}

func parseAMTScriptOutput(out string) (amtScriptResult, error) {
	res := amtScriptResult{steps: map[string]amtStep{}}
	const infoMarker = "--- amtinfo\n"
	for _, step := range []string{"activate", "mebx", "wired"} {
		start, end := "--- "+step+"\n", "--- "+step+" exit "
		i := strings.Index(out, start)
		if i < 0 {
			continue
		}
		rest := out[i+len(start):]
		j := strings.Index(rest, end)
		if j < 0 {
			return res, fmt.Errorf("the %s step did not finish: %s", step, truncateMessage(rest))
		}
		line, _, _ := strings.Cut(rest[j+len(end):], "\n")
		code, err := strconv.Atoi(strings.TrimSpace(line))
		if err != nil {
			return res, fmt.Errorf("unreadable %s exit status %q", step, line)
		}
		res.steps[step] = amtStep{exit: code, output: strings.TrimSpace(rest[:j])}
	}
	i := strings.LastIndex(out, infoMarker)
	if i < 0 {
		return res, fmt.Errorf("rpc amtinfo did not run: %s", truncateMessage(out))
	}
	if err := json.NewDecoder(strings.NewReader(out[i+len(infoMarker):])).Decode(&res.info); err != nil {
		return res, fmt.Errorf("rpc amtinfo printed no JSON: %s", truncateMessage(out[i+len(infoMarker):]))
	}
	if res.info.ControlMode == "" {
		return res, fmt.Errorf("rpc amtinfo reported no control mode")
	}
	return res, nil
}

func amtControlMode(reported string) string {
	switch reported {
	case "not activated":
		return amtPreProvisioning
	case "client control mode":
		return amtClientControl
	case "admin control mode":
		return amtAdminControl
	}
	return reported
}

func truncateMessage(s string) string {
	s = strings.TrimSpace(s)
	if len(s) > 1000 {
		return s[:1000] + "..."
	}
	return s
}

// generateAMTPassword draws a password AMT accepts: 8 to 32 printable ASCII
// characters with a lowercase and an uppercase letter, a digit and a symbol.
func generateAMTPassword() (string, error) {
	const alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" + amtPasswordSpecials
	for {
		b := make([]byte, amtPasswordLength)
		for i := range b {
			n, err := rand.Int(rand.Reader, big.NewInt(int64(len(alphabet))))
			if err != nil {
				return "", fmt.Errorf("generate an AMT password: %w", err)
			}
			b[i] = alphabet[n.Int64()]
		}
		if p := string(b); validAMTPassword(p) {
			return p, nil
		}
	}
}

func validAMTPassword(p string) bool {
	if len(p) < 8 || len(p) > 32 || strings.ContainsAny(p, `",:`) {
		return false
	}
	var lower, upper, digit, symbol bool
	for _, c := range p {
		switch {
		case c > unicode.MaxASCII || !unicode.IsPrint(c) || c == ' ':
			return false
		case unicode.IsLower(c):
			lower = true
		case unicode.IsUpper(c):
			upper = true
		case unicode.IsDigit(c):
			digit = true
		default:
			symbol = true
		}
	}
	return lower && upper && digit && symbol
}

func amtObserveAfter(status *infrav1.RackLinuxHostAMTStatus) time.Duration {
	if status.Address == "" || status.Address == "0.0.0.0" {
		return amtAddressInterval
	}
	return amtObserveInterval
}

var smbiosUUIDPattern = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)
