package v1alpha1_test

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"k8s.io/apiextensions-apiserver/pkg/apis/apiextensions"
	apiextensionsv1 "k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1"
	"k8s.io/apiextensions-apiserver/pkg/apiserver/schema"
	"k8s.io/apiextensions-apiserver/pkg/apiserver/schema/cel"
	"k8s.io/apiextensions-apiserver/pkg/apiserver/validation"
	"k8s.io/apimachinery/pkg/util/validation/field"
	celconfig "k8s.io/apiserver/pkg/apis/cel"
	"sigs.k8s.io/yaml"

	"github.com/tuist/tuist/infra/rack-switch-controller/api/v1alpha1"
)

const (
	crdPath     = "../../../helm/tuist/crds/tuist.dev_rackswitches.yaml"
	objectsGlob = "../../../rack-switch-fleet/k8s/*/*.yaml"
)

// A RackSwitch as the renderer will write it once it emits mac, managedBy and
// config: every field name the Go types accept.
const controllerManaged = `
apiVersion: tuist.dev/v1alpha1
kind: RackSwitch
metadata:
  name: ber1-tor-b
spec:
  site: ber1
  role: tor
  model: sx3832
  managementAddress: 192.168.0.12
  applyOrder: 1
  applyNote: first
  credentialItem: ber1-tor-b switch admin
  configRevision: 5ef04ee11ceedbe0
  ports:
    - {port: 32, purpose: isl, peer: ber1-tor-a, detail: dac}
  mac: d4:d6:df:03:d8:b2
  managedBy: controller
  config:
    hostname: ber1-tor-b
    managementVlan: 1
    managementPrefixLength: 24
    gateway: 192.168.0.10
    spanningTree: rstp
    lldp: true
    snmp: false
    vlans:
      - {id: 20, name: storage}
    lags:
      - {id: 1, ports: [31, 32]}
    ports:
      - {port: 1, description: "", spanningTree: true, nativeVlan: 1, taggedVlans: [20]}
      - {port: 32, description: isl ber1-tor-a}
status:
  observedRevision: 5ef04ee11ceedbe0
  observedGeneration: 1
  drift: none
  reachable: true
  lastVerified: "2026-09-23T12:00:00Z"
  connectionsUsedSinceBoot: 2
  message: adopted, connected, and at revision 5ef04ee11ceedbe0
  adopted: true
  controllerStatus: connected
  conditions:
    - {type: Ready, status: "True", reason: Ready, message: ok, lastTransitionTime: "2026-09-23T12:00:00Z"}
`

func schemaProps(t *testing.T) *apiextensions.JSONSchemaProps {
	t.Helper()
	raw, err := os.ReadFile(crdPath)
	if err != nil {
		t.Fatal(err)
	}
	var crd apiextensionsv1.CustomResourceDefinition
	if err := yaml.Unmarshal(raw, &crd); err != nil {
		t.Fatal(err)
	}
	var props apiextensions.JSONSchemaProps
	if err := apiextensionsv1.Convert_v1_JSONSchemaProps_To_apiextensions_JSONSchemaProps(crd.Spec.Versions[0].Schema.OpenAPIV3Schema, &props, nil); err != nil {
		t.Fatal(err)
	}
	return &props
}

func schemaValidator(t *testing.T) validation.SchemaValidator {
	t.Helper()
	validator, _, err := validation.NewSchemaValidator(schemaProps(t))
	if err != nil {
		t.Fatal(err)
	}
	return validator
}

// celErrors runs the CRD's CEL rules over an object, as admission does.
func celErrors(t *testing.T, raw string) []string {
	t.Helper()
	structural, err := schema.NewStructural(schemaProps(t))
	if err != nil {
		t.Fatal(err)
	}
	var object map[string]any
	if err := yaml.Unmarshal([]byte(raw), &object); err != nil {
		t.Fatal(err)
	}
	validator := cel.NewValidator(structural, true, celconfig.PerCallLimit)
	errs, _ := validator.Validate(context.Background(), field.NewPath(""), structural, object, nil, celconfig.RuntimeCELCostBudget)
	var messages []string
	for _, e := range errs {
		messages = append(messages, e.Error())
	}
	return messages
}

func validate(t *testing.T, validator validation.SchemaValidator, raw []byte) []string {
	t.Helper()
	var object map[string]any
	if err := yaml.Unmarshal(raw, &object); err != nil {
		t.Fatal(err)
	}
	var errs []string
	for _, e := range validation.ValidateCustomResource(nil, object, validator) {
		errs = append(errs, e.Error())
	}
	return errs
}

func TestTheCommittedObjectsFitTheTypesAndTheSchema(t *testing.T) {
	validator := schemaValidator(t)
	paths, err := filepath.Glob(objectsGlob)
	if err != nil || len(paths) == 0 {
		t.Fatalf("no committed RackSwitch objects at %s", objectsGlob)
	}
	for _, path := range paths {
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		var rs v1alpha1.RackSwitch
		if err := yaml.UnmarshalStrict(raw, &rs); err != nil {
			t.Errorf("%s does not fit the Go types: %v", path, err)
		}
		if errs := validate(t, validator, raw); len(errs) > 0 {
			t.Errorf("%s does not fit the CRD: %v", path, errs)
		}
	}
}

func TestAControllerManagedObjectFitsTheTypesAndTheSchema(t *testing.T) {
	var rs v1alpha1.RackSwitch
	if err := yaml.UnmarshalStrict([]byte(controllerManaged), &rs); err != nil {
		t.Fatalf("the Go types do not accept the renderer's field names: %v", err)
	}
	if rs.Spec.Config.Ports[0].TaggedVLANs[0] != 20 || rs.Spec.Config.LAGs[0].Ports[1] != 32 || !*rs.Spec.Config.LLDP {
		t.Fatalf("config = %+v", rs.Spec.Config)
	}
	if errs := validate(t, schemaValidator(t), []byte(controllerManaged)); len(errs) > 0 {
		t.Fatalf("does not fit the CRD: %v", errs)
	}
}

func TestAControllerManagedSwitchNeedsItsMAC(t *testing.T) {
	withoutMAC := strings.Replace(controllerManaged, "  mac: d4:d6:df:03:d8:b2\n", "", 1)
	if errs := celErrors(t, withoutMAC); len(errs) != 1 || !strings.Contains(errs[0], "a switch the controller manages needs its mac") {
		t.Fatalf("errors = %v", errs)
	}
	if errs := celErrors(t, controllerManaged); len(errs) != 0 {
		t.Fatalf("errors = %v", errs)
	}
	standalone := strings.Replace(withoutMAC, "managedBy: controller", "managedBy: standalone", 1)
	if errs := celErrors(t, standalone); len(errs) != 0 {
		t.Fatalf("a standalone switch without a mac was refused: %v", errs)
	}
}

func TestTheSchemaRefusesWhatTheControllerCannotUse(t *testing.T) {
	validator := schemaValidator(t)
	cases := map[string]string{
		"mac: D4-D6-DF-03-D8-B2":                 "spec.mac",
		"managedBy: someone":                     "spec.managedBy",
		"config: {spanningTree: pvst}":           "spec.config.spanningTree",
		"config: {vlans: [{id: 4095, name: x}]}": "spec.config.vlans[0].id",
	}
	base := strings.SplitN(controllerManaged, "  mac:", 2)[0]
	for field, path := range cases {
		raw := base + "  " + field + "\n"
		errs := validate(t, validator, []byte(raw))
		if len(errs) == 0 || !strings.Contains(strings.Join(errs, "; "), path) {
			t.Errorf("%q: errors = %v, want one about %s", field, errs, path)
		}
	}
}
