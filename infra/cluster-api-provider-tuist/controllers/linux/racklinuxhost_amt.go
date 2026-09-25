package linux

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"math/big"
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

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

// AMTActivatedCondition reports whether a host that asks for AMT has it
// activated in admin control mode.
const AMTActivatedCondition clusterv1.ConditionType = "AMTActivated"

// rpc is the Device Management Toolkit's AMT client. Hosts download it once,
// pinned by the release tarball's digest.
const (
	amtRPCURL    = "https://github.com/device-management-toolkit/rpc-go/releases/download/v2.52.6/rpc_linux_x64.tar.gz"
	amtRPCSHA256 = "d59072295dedd2c457c28b5193be01ffb1ee10f4d50b52df7d4ac71585c81a9e"
	amtRPCPath   = "/usr/local/lib/tuist/rpc-2.52.6"

	amtScriptTimeout     = 10 * time.Minute
	amtActivationBackoff = time.Hour
	amtObserveInterval   = time.Hour

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
}

// amtActivation is what a script that may activate AMT carries.
type amtActivation struct {
	Password    string
	PFX         string
	PFXPassword string
}

// reconcileAMT activates the host's AMT in admin control mode when the host
// asks for it and AMT is still pre-provisioned, and otherwise reads AMT's
// state now and then. It returns when to look again.
func (r *RackLinuxHostReconciler) reconcileAMT(ctx context.Context, host *infrav1.RackLinuxHost) time.Duration {
	if host.Spec.AMT == nil || !host.Spec.AMT.Activate {
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

	now := r.now()
	status := host.Status.AMT
	var activation *amtActivation
	if status == nil || status.ControlMode == "" || status.ControlMode == amtPreProvisioning {
		if status != nil && status.ActivationError != "" && status.LastActivation != nil {
			if wait := status.LastActivation.Add(amtActivationBackoff).Sub(now); wait > 0 {
				return wait
			}
		}
		var reason string
		var err error
		activation, reason, err = r.amtActivation(ctx, host)
		if err != nil {
			conditions.MarkFalse(host, AMTActivatedCondition, "AMTSecretsUnreadable", clusterv1.ConditionSeverityWarning, "%v", err)
			return time.Minute
		}
		if reason != "" {
			conditions.MarkFalse(host, AMTActivatedCondition, "NoProvisioningCertificate", clusterv1.ConditionSeverityWarning, "%s", reason)
			return 10 * time.Minute
		}
	} else if status.ObservedAt != nil {
		if wait := status.ObservedAt.Add(amtObserveInterval).Sub(now); wait > 0 {
			return wait
		}
	}

	out, runErr := runOnRackHost(ctx, r.Client, r.CredentialsManager, r.AMT.FleetName, r.egress(), r.RunScript,
		host, renderAMTScript(activation), amtScriptTimeout)
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
	next := &infrav1.RackLinuxHostAMTStatus{
		ControlMode: amtControlMode(result.info.ControlMode),
		Version:     result.info.Version,
		Link:        result.info.Wired.LinkStatus,
		Address:     result.info.Wired.Address,
		ObservedAt:  &observed,
	}
	if status != nil {
		next.LastActivation = status.LastActivation
		next.ActivationError = status.ActivationError
	}
	if result.activated {
		next.LastActivation = &observed
		next.ActivationError = ""
		switch {
		case result.activationExit != 0:
			next.ActivationError = truncateMessage(fmt.Sprintf("rpc activate exit %d: %s", result.activationExit, result.activationOutput))
		case next.ControlMode != amtAdminControl:
			next.ActivationError = truncateMessage(fmt.Sprintf("rpc activate succeeded, and AMT reports %q: %s", result.info.ControlMode, result.activationOutput))
		}
		if next.ActivationError == "" {
			r.Recorder.Event(host, corev1.EventTypeNormal, "AMTActivated", "Activated AMT in admin control mode")
		} else {
			r.Recorder.Eventf(host, corev1.EventTypeWarning, "AMTActivationFailed", "%s", next.ActivationError)
		}
	}
	host.Status.AMT = next

	switch next.ControlMode {
	case amtAdminControl:
		conditions.MarkTrue(host, AMTActivatedCondition)
		return amtObserveInterval
	case amtClientControl:
		conditions.MarkFalse(host, AMTActivatedCondition, "ClientControlMode", clusterv1.ConditionSeverityWarning,
			"AMT is activated in client control mode; deactivate it for the operator to activate it in admin control mode")
		return amtObserveInterval
	}
	if next.ActivationError != "" {
		conditions.MarkFalse(host, AMTActivatedCondition, "ActivationFailed", clusterv1.ConditionSeverityWarning, "%s", next.ActivationError)
		return amtActivationBackoff
	}
	conditions.MarkFalse(host, AMTActivatedCondition, "NotActivated", clusterv1.ConditionSeverityInfo, "AMT reports %q", result.info.ControlMode)
	return amtObserveInterval
}

// amtActivation reads the provisioning certificate and the host's admin
// password, generating and storing the password first if the host has none,
// so an activation never sets a password the operator did not keep. A
// non-empty reason means the certificate is missing.
func (r *RackLinuxHostReconciler) amtActivation(ctx context.Context, host *infrav1.RackLinuxHost) (*amtActivation, string, error) {
	namespace := r.CredentialsManager.Namespace
	provisioning := &corev1.Secret{}
	if err := r.Get(ctx, types.NamespacedName{Namespace: namespace, Name: r.AMT.ProvisioningSecret}, provisioning); err != nil {
		if apierrors.IsNotFound(err) {
			return nil, fmt.Sprintf("the Secret %s/%s holding the AMT provisioning certificate does not exist", namespace, r.AMT.ProvisioningSecret), nil
		}
		return nil, "", fmt.Errorf("read the AMT provisioning certificate: %w", err)
	}
	pfx, pfxPassword := string(provisioning.Data["pfx"]), string(provisioning.Data["password"])
	if pfx == "" || pfxPassword == "" {
		return nil, fmt.Sprintf("the Secret %s/%s lacks pfx or password", namespace, r.AMT.ProvisioningSecret), nil
	}

	name := amtSecretName(host)
	secret := &corev1.Secret{}
	err := r.Get(ctx, types.NamespacedName{Namespace: namespace, Name: name}, secret)
	switch {
	case err == nil:
		if password := string(secret.Data["password"]); validAMTPassword(password) {
			return &amtActivation{Password: password, PFX: pfx, PFXPassword: pfxPassword}, "", nil
		}
		return nil, "", fmt.Errorf("the Secret %s/%s holds no valid AMT password", namespace, name)
	case !apierrors.IsNotFound(err):
		return nil, "", fmt.Errorf("read the AMT password: %w", err)
	}
	password, err := generateAMTPassword()
	if err != nil {
		return nil, "", err
	}
	secret = &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: namespace,
			Labels:    map[string]string{"app.kubernetes.io/component": "rack-amt", "tuist.dev/rack-linux-host": host.Name},
		},
		Type: corev1.SecretTypeOpaque,
		Data: map[string][]byte{"username": []byte("admin"), "password": []byte(password)},
	}
	if err := r.Create(ctx, secret); err != nil {
		return nil, "", fmt.Errorf("store the AMT password: %w", err)
	}
	return &amtActivation{Password: password, PFX: pfx, PFXPassword: pfxPassword}, "", nil
}

// amtSecretName is the Secret holding a host's AMT admin credentials. It
// outlives the RackLinuxHost: an activated AMT keeps the password.
func amtSecretName(host *infrav1.RackLinuxHost) string {
	return host.Name + "-amt"
}

// renderAMTScript installs rpc on the host if it is missing and prints AMT's
// state after a `--- amtinfo` line. With an activation, it first activates a
// pre-provisioned AMT in admin control mode, between `--- activate` and
// `--- activate exit <status>`. The secrets reach rpc through its environment,
// set by bash builtins, so they appear on no command line and in no file.
func renderAMTScript(a *amtActivation) string {
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
info() { "$rpc" amtinfo -json -ver -mode -lan 2>/dev/null; }
`, amtRPCPath, amtRPCURL, amtRPCSHA256)
	if a != nil {
		fmt.Fprintf(&b, `if [ "$(info | jq -r .controlMode)" = 'pre-provisioning state' ]; then
  export AMT_PASSWORD=%s
  export PROVISIONING_CERT=%s
  export PROVISIONING_CERT_PASSWORD=%s
  echo '--- activate'
  status=0
  "$rpc" activate -local -acm -skipIPRenew -json 2>&1 || status=$?
  unset AMT_PASSWORD PROVISIONING_CERT PROVISIONING_CERT_PASSWORD
  echo "--- activate exit $status"
fi
`, shellSingleQuote(a.Password), shellSingleQuote(a.PFX), shellSingleQuote(a.PFXPassword))
	}
	b.WriteString("echo '--- amtinfo'\ninfo\n")
	return b.String()
}

type amtInfo struct {
	Version     string `json:"amt"`
	ControlMode string `json:"controlMode"`
	Wired       struct {
		LinkStatus string `json:"linkStatus"`
		Address    string `json:"ipAddress"`
	} `json:"wiredAdapter"`
}

type amtScriptResult struct {
	info             amtInfo
	activated        bool
	activationExit   int
	activationOutput string
}

func parseAMTScriptOutput(out string) (amtScriptResult, error) {
	var res amtScriptResult
	const activateMarker, exitMarker, infoMarker = "--- activate\n", "--- activate exit ", "--- amtinfo\n"
	if i := strings.Index(out, activateMarker); i >= 0 {
		rest := out[i+len(activateMarker):]
		j := strings.Index(rest, exitMarker)
		if j < 0 {
			return res, fmt.Errorf("the activation did not finish: %s", truncateMessage(rest))
		}
		line, _, _ := strings.Cut(rest[j+len(exitMarker):], "\n")
		code, err := strconv.Atoi(strings.TrimSpace(line))
		if err != nil {
			return res, fmt.Errorf("unreadable activation exit status %q", line)
		}
		res.activated = true
		res.activationExit = code
		res.activationOutput = strings.TrimSpace(rest[:j])
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
	case "pre-provisioning state":
		return amtPreProvisioning
	case "activated in client control mode":
		return amtClientControl
	case "activated in admin control mode":
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
