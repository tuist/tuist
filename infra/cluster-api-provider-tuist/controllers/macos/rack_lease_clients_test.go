package macos

import (
	"context"
	"strings"
	"testing"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

const borrowerKubeconfig = `apiVersion: v1
kind: Config
current-context: rack-lender
clusters:
  - name: staging
    cluster:
      server: https://kube-staging.example:443
contexts:
  - name: rack-lender
    context:
      cluster: staging
      user: rack-lender
users:
  - name: rack-lender
    user:
      token: lender-token
`

func borrowerClients(t *testing.T, data map[string][]byte) *SecretBorrowerClients {
	t.Helper()
	scheme := runtime.NewScheme()
	if err := corev1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := infrav1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	reader := fake.NewClientBuilder().WithScheme(scheme).WithRuntimeObjects(&corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: "rack-borrower-staging", Namespace: testNamespace, ResourceVersion: "1"},
		Data:       data,
	}).Build()
	return &SecretBorrowerClients{
		Reader:    reader,
		Namespace: testNamespace,
		Secrets:   map[string]string{"staging": "rack-borrower-staging"},
		Scheme:    scheme,
	}
}

func TestBorrowerClientComesFromItsEnvsSecret(t *testing.T) {
	clients := borrowerClients(t, map[string][]byte{"kubeconfig": []byte(borrowerKubeconfig), "namespace": []byte("tuist-staging")})

	c, ns, err := clients.Borrower(context.Background(), "staging")
	if err != nil || c == nil || ns != "tuist-staging" {
		t.Fatalf("Borrower = %v, %q, %v", c, ns, err)
	}
	again, _, err := clients.Borrower(context.Background(), "staging")
	if err != nil || again != c {
		t.Fatal("an unchanged Secret built a new client")
	}
}

func TestBorrowerClientRefusesAnUnknownEnvOrAnIncompleteSecret(t *testing.T) {
	clients := borrowerClients(t, map[string][]byte{"kubeconfig": []byte(borrowerKubeconfig)})

	if _, _, err := clients.Borrower(context.Background(), "canary"); err == nil || !strings.Contains(err.Error(), "staging") {
		t.Fatalf("err = %v, want one naming the envs this operator lends to", err)
	}
	if _, _, err := clients.Borrower(context.Background(), "staging"); err == nil || !strings.Contains(err.Error(), "namespace") {
		t.Fatalf("err = %v, want the missing namespace named", err)
	}
}
