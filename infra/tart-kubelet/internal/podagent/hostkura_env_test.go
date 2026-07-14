package podagent

import (
	"strings"
	"testing"
)

func hostKuraEnvMap(t *testing.T, spec KuraSpec) map[string]string {
	t.Helper()
	m := map[string]string{}
	for _, e := range hostKuraEnv(spec, spec.DataDir+"/tmp") {
		if i := strings.IndexByte(e, '='); i >= 0 {
			m[e[:i]] = e[i+1:]
		}
	}
	return m
}

// kura exits at startup with "missing required environment variables" unless the
// OTEL identity vars are set, so the host Kura env must always carry them.
func TestHostKuraEnv_IncludesRequiredVars(t *testing.T) {
	m := hostKuraEnvMap(t, KuraSpec{AccountID: "2", DataDir: "/cache/accounts/2/current", Port: 4100})
	for _, k := range []string{
		"KURA_OTEL_SERVICE_NAME",
		"KURA_OTEL_DEPLOYMENT_ENVIRONMENT",
		"KURA_TENANT_ID",
		"KURA_DATA_DIR",
		"KURA_PORT",
		"KURA_GRPC_PORT",
		"KURA_INTERNAL_PORT",
	} {
		if m[k] == "" {
			t.Errorf("host kura env missing required %s", k)
		}
	}
	if m["KURA_TENANT_ID"] != "2" {
		t.Errorf("KURA_TENANT_ID = %q, want 2", m["KURA_TENANT_ID"])
	}
	if m["KURA_PORT"] != "4100" || m["KURA_GRPC_PORT"] != "4101" || m["KURA_INTERNAL_PORT"] != "4102" {
		t.Errorf("port block wrong: %s/%s/%s", m["KURA_PORT"], m["KURA_GRPC_PORT"], m["KURA_INTERNAL_PORT"])
	}
}

func TestHostKuraEnv_BootstrapFollowsPeer(t *testing.T) {
	islanded := hostKuraEnvMap(t, KuraSpec{AccountID: "2", DataDir: "/d", Port: 4100})
	if islanded["KURA_BOOTSTRAP_ENABLED"] != "false" {
		t.Errorf("islanded (no peer) should disable bootstrap, got %q", islanded["KURA_BOOTSTRAP_ENABLED"])
	}
	peered := hostKuraEnvMap(t, KuraSpec{AccountID: "2", DataDir: "/d", Port: 4100, PeerURL: "http://10.0.0.5:7443"})
	if peered["KURA_BOOTSTRAP_ENABLED"] != "true" {
		t.Errorf("peered should enable bootstrap, got %q", peered["KURA_BOOTSTRAP_ENABLED"])
	}
	if peered["KURA_PEERS"] != "http://10.0.0.5:7443" {
		t.Errorf("KURA_PEERS = %q", peered["KURA_PEERS"])
	}
}
