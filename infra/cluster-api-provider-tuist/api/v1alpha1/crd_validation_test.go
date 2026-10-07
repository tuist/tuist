package v1alpha1

import (
	"context"
	"os"
	"testing"

	"k8s.io/apiextensions-apiserver/pkg/apis/apiextensions"
	apiextensionsv1 "k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1"
	"k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/validation"
	structuralschema "k8s.io/apiextensions-apiserver/pkg/apiserver/schema"
	"k8s.io/apiextensions-apiserver/pkg/apiserver/schema/cel"
	structuraldefaulting "k8s.io/apiextensions-apiserver/pkg/apiserver/schema/defaulting"
	apiservervalidation "k8s.io/apiextensions-apiserver/pkg/apiserver/validation"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/util/validation/field"
	celconfig "k8s.io/apiserver/pkg/apis/cel"
	"sigs.k8s.io/yaml"
)

// generatedCRD loads a committed CRD, checks it the way the API server does
// on apply (CEL rules compiled and within their cost budget included), and
// returns what validates objects against it.
func generatedCRD(t *testing.T, file string) (*structuralschema.Structural, apiservervalidation.SchemaValidator) {
	t.Helper()
	raw, err := os.ReadFile("../../../helm/tuist/crds/" + file)
	if err != nil {
		t.Fatal(err)
	}
	v1 := &apiextensionsv1.CustomResourceDefinition{}
	if err := yaml.Unmarshal(raw, v1); err != nil {
		t.Fatal(err)
	}
	scheme := runtime.NewScheme()
	if err := apiextensions.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := apiextensionsv1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	crd := &apiextensions.CustomResourceDefinition{}
	if err := scheme.Convert(v1, crd, nil); err != nil {
		t.Fatal(err)
	}
	crd.Status.StoredVersions = []string{crd.Spec.Versions[0].Name}
	if errs := validation.ValidateCustomResourceDefinition(context.Background(), crd); len(errs) > 0 {
		t.Fatalf("%s: %v", file, errs.ToAggregate())
	}
	schema := crd.Spec.Validation
	if schema == nil {
		schema = crd.Spec.Versions[0].Schema
	}
	structural, err := structuralschema.NewStructural(schema.OpenAPIV3Schema)
	if err != nil {
		t.Fatal(err)
	}
	validator, _, err := apiservervalidation.NewSchemaValidator(schema.OpenAPIV3Schema)
	if err != nil {
		t.Fatal(err)
	}
	return structural, validator
}

func admits(t *testing.T, structural *structuralschema.Structural, validator apiservervalidation.SchemaValidator, obj map[string]any) field.ErrorList {
	t.Helper()
	structuraldefaulting.Default(obj, structural)
	errs := apiservervalidation.ValidateCustomResource(field.NewPath(""), obj, validator)
	celErrs, _ := cel.NewValidator(structural, true, celconfig.PerCallLimit).
		Validate(context.Background(), field.NewPath(""), structural, obj, nil, celconfig.RuntimeCELCostBudget)
	return append(errs, celErrs...)
}

func TestRackHostPowerAdmission(t *testing.T) {
	structural, validator := generatedCRD(t, "infrastructure.cluster.x-k8s.io_rackhosts.yaml")
	for name, c := range map[string]struct {
		power map[string]any
		ok    bool
	}{
		"a pdu outlet":                {map[string]any{"pdu": "ber1-pdu-b", "outlet": "1"}, true},
		"a pdu outlet by default 0":   {map[string]any{"pdu": "ber1-pdu-b"}, false},
		"a pdu outlet 0":              {map[string]any{"pdu": "ber1-pdu-b", "outlet": "0"}, false},
		"an empty pdu":                {map[string]any{"pdu": "", "outlet": "1"}, false},
		"an empty host":               {map[string]any{"host": "", "outlet": "1"}, false},
		"a pdu and a host":            {map[string]any{"pdu": "ber1-pdu-b", "outlet": "1", "host": "192.168.0.16"}, false},
		"a pdu and a driver":          {map[string]any{"pdu": "ber1-pdu-b", "outlet": "1", "driver": "shelly"}, false},
		"a pdu and credentials":       {map[string]any{"pdu": "ber1-pdu-b", "outlet": "1", "credentialsSecretRef": map[string]any{"name": "x"}}, false},
		"a shelly":                    {map[string]any{"driver": "shelly", "host": "192.168.0.50"}, true},
		"a plug with no driver named": {map[string]any{"host": "192.168.0.50"}, true},
		"an eaton by host":            {map[string]any{"driver": "eaton", "host": "192.168.0.16", "outlet": "1"}, false},
		"neither pdu nor host":        {map[string]any{"outlet": "1"}, false},
	} {
		obj := map[string]any{
			"apiVersion": "infrastructure.cluster.x-k8s.io/v1alpha1", "kind": "RackHost",
			"metadata": map[string]any{"name": "mini-01"},
			"spec":     map[string]any{"power": c.power},
		}
		if errs := admits(t, structural, validator, obj); (len(errs) == 0) != c.ok {
			t.Errorf("%s: errors %v, want admitted=%t", name, errs, c.ok)
		}
	}
}

func TestRackPDUAdmission(t *testing.T) {
	structural, validator := generatedCRD(t, "infrastructure.cluster.x-k8s.io_rackpdus.yaml")
	pdu := func(spec map[string]any) map[string]any {
		return map[string]any{
			"apiVersion": "infrastructure.cluster.x-k8s.io/v1alpha1", "kind": "RackPDU",
			"metadata": map[string]any{"name": "ber1-pdu-b"}, "spec": spec,
		}
	}
	good := pdu(map[string]any{"site": "ber1", "model": "evmafc20a", "address": "192.168.0.16", "managedBy": "controller"})
	if errs := admits(t, structural, validator, good); len(errs) != 0 {
		t.Fatalf("a rendered RackPDU was refused: %v", errs)
	}
	if spec := good["spec"].(map[string]any); spec["outletStateOnStartup"] != "on" {
		t.Fatalf("outletStateOnStartup defaulted to %v, want on", spec["outletStateOnStartup"])
	}
	for name, spec := range map[string]map[string]any{
		"an upper-case MAC": {"site": "ber1", "model": "evmafc20a", "address": "192.168.0.16", "mac": "00:20:85:D7:00:CA"},
		"no address":        {"site": "ber1", "model": "evmafc20a"},
		"another model":     {"site": "ber1", "model": "ap8959", "address": "192.168.0.16"},
	} {
		if errs := admits(t, structural, validator, pdu(spec)); len(errs) == 0 {
			t.Errorf("%s was admitted", name)
		}
	}
}
