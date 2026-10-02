package credentials

import (
	"context"
	"testing"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/apimachinery/pkg/util/validation"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

// A rack host's pin is kept under its UUID and tailnet device, longer than a
// label value may be, so the Secret's machine label holds what fits.
func TestAMachinesBootstrapSecretTakesANameLongerThanALabel(t *testing.T) {
	c := fake.NewClientBuilder().WithScheme(clientgoscheme.Scheme).Build()
	m := &Manager{Client: c, Namespace: "tuist"}
	name := "rack-linux-04450c00-63f4-11f1-81f4-3582298d5c00-ndwligymx221cntrl"

	if err := m.SetMachineHostFingerprint(context.Background(), name, "SHA256:abc"); err != nil {
		t.Fatal(err)
	}
	secret := &corev1.Secret{}
	if err := c.Get(context.Background(), types.NamespacedName{Namespace: "tuist", Name: name + "-bootstrap"}, secret); err != nil {
		t.Fatal(err)
	}
	for key, value := range secret.Labels {
		if errs := validation.IsValidLabelValue(value); len(errs) > 0 {
			t.Fatalf("label %s=%q: %v", key, value, errs)
		}
	}
	got, err := m.GetMachineBootstrap(context.Background(), name)
	if err != nil || got == nil || got.HostFingerprint != "SHA256:abc" {
		t.Fatalf("read back %+v, %v", got, err)
	}
}
