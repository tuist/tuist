package shared

import (
	"bufio"
	"bytes"
	"context"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"testing"
	"time"

	authenticationv1 "k8s.io/api/authentication/v1"
	corev1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	yamlutil "k8s.io/apimachinery/pkg/util/yaml"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"k8s.io/client-go/rest"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/envtest"
)

// TestOperatorCannotReachCredentialsOutsideItsNamespace renders the chart's
// operator RBAC and admission policy into a real API server and checks the
// boundary: no Secret outside its namespace (the 1Password token included),
// kube-system bootstrap tokens write-only, and ClusterRoleBindings only as
// tart-kubelet-<machine> node identities.
func TestOperatorCannotReachCredentialsOutsideItsNamespace(t *testing.T) {
	helm, err := exec.LookPath("helm")
	if err != nil || os.Getenv("KUBEBUILDER_ASSETS") == "" {
		t.Skip("needs helm and KUBEBUILDER_ASSETS")
	}
	_, file, _, _ := runtime.Caller(0)
	chart := filepath.Join(filepath.Dir(file), "..", "..", "..", "helm", "tuist")
	b, err := exec.Command(helm, "template", "tuist", chart, "-n", "tuist-staging",
		"-f", filepath.Join(chart, "values-managed-common.yaml"),
		"-f", filepath.Join(chart, "values-managed-staging.yaml"),
		"-f", filepath.Join(chart, "values-ci.yaml"),
		"--show-only", "templates/capi-scaleway-applesilicon.yaml").Output()
	if err != nil {
		t.Fatalf("helm template: %v", err)
	}
	env := &envtest.Environment{}
	cfg, err := env.Start()
	if err != nil {
		t.Fatal(err)
	}
	defer env.Stop()
	ctx := context.Background()
	admin, _ := client.New(cfg, client.Options{Scheme: clientgoscheme.Scheme})
	for _, ns := range []string{"tuist-staging", "onepassword", "tailscale-operator", "tuist-runners", "tuist-sandboxes"} {
		_ = admin.Create(ctx, &corev1.Namespace{ObjectMeta: metav1.ObjectMeta{Name: ns}})
	}
	r := yamlutil.NewYAMLReader(bufio.NewReader(bytes.NewReader(b)))
	for {
		doc, err := r.Read()
		if err == io.EOF {
			break
		}
		u := &unstructured.Unstructured{}
		if err := yamlutil.Unmarshal(doc, &u.Object); err != nil || len(u.Object) == 0 {
			continue
		}
		switch u.GetKind() {
		case "ClusterRole", "ClusterRoleBinding", "Role", "RoleBinding", "ValidatingAdmissionPolicy", "ValidatingAdmissionPolicyBinding", "ServiceAccount":
			if u.GetNamespace() == "" && (u.GetKind() == "Role" || u.GetKind() == "RoleBinding" || u.GetKind() == "ServiceAccount") {
				u.SetNamespace("tuist-staging")
			}
			if err := admin.Create(ctx, u); err != nil {
				t.Fatalf("%s %s: %v", u.GetKind(), u.GetName(), err)
			}
		}
	}
	time.Sleep(3 * time.Second) // the policy's informer sync
	op := rest.CopyConfig(cfg)
	op.Impersonate = rest.ImpersonationConfig{UserName: "system:serviceaccount:tuist-staging:tuist-tuist-capi-scaleway-applesilicon",
		Groups: []string{"system:serviceaccounts", "system:serviceaccounts:tuist-staging", "system:authenticated"}}
	oc, _ := client.New(op, client.Options{Scheme: clientgoscheme.Scheme})

	_ = admin.Create(ctx, &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Namespace: "onepassword", Name: "onepassword-sa-token"}})
	crb := func(name, role, saNS, sa string) *rbacv1.ClusterRoleBinding {
		return &rbacv1.ClusterRoleBinding{ObjectMeta: metav1.ObjectMeta{Name: name},
			RoleRef:  rbacv1.RoleRef{APIGroup: "rbac.authorization.k8s.io", Kind: "ClusterRole", Name: role},
			Subjects: []rbacv1.Subject{{Kind: "ServiceAccount", Namespace: saNS, Name: sa}}}
	}
	check := func(what string, wantOK bool, err error) {
		if (err == nil) != wantOK {
			t.Errorf("%s: wantOK=%v err=%v", what, wantOK, err)
		} else {
			t.Logf("%s: ok=%v (%v)", what, err == nil, err)
		}
	}
	check("get onepassword token", false, oc.Get(ctx, client.ObjectKey{Namespace: "onepassword", Name: "onepassword-sa-token"}, &corev1.Secret{}))
	check("list secrets cluster-wide", false, oc.List(ctx, &corev1.SecretList{}))
	check("list secrets own ns", true, oc.List(ctx, &corev1.SecretList{}, client.InNamespace("tuist-staging")))
	check("create SA own ns", true, oc.Create(ctx, &corev1.ServiceAccount{ObjectMeta: metav1.ObjectMeta{Namespace: "tuist-staging", Name: "tart-kubelet-m1"}}))
	check("create SA default", false, oc.Create(ctx, &corev1.ServiceAccount{ObjectMeta: metav1.ObjectMeta{Namespace: "default", Name: "x"}}))
	check("node identity CRB system:node", true, oc.Create(ctx, crb("tart-kubelet-m1", "system:node", "tuist-staging", "tart-kubelet-m1")))
	check("node identity CRB tart-kubelet", true, oc.Create(ctx, crb("tart-kubelet-m2", "tuist-tuist-tart-kubelet", "tuist-staging", "tart-kubelet-m2")))
	check("bind system:node to operator", false, oc.Create(ctx, crb("tart-kubelet-evil", "system:node", "tuist-staging", "tuist-tuist-capi-scaleway-applesilicon")))
	check("CRB with other name", false, oc.Create(ctx, crb("evil", "system:node", "tuist-staging", "evil")))
	check("CRB other ns subject", false, oc.Create(ctx, crb("tart-kubelet-x", "system:node", "default", "tart-kubelet-x")))
	check("delete node identity CRB", true, oc.Delete(ctx, &rbacv1.ClusterRoleBinding{ObjectMeta: metav1.ObjectMeta{Name: "tart-kubelet-m1"}}))
	check("bootstrap token", true, oc.Create(ctx, &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Namespace: "kube-system", Name: "bootstrap-token-abcdef"}, Type: "bootstrap.kubernetes.io/token"}))
	check("opaque in kube-system", false, oc.Create(ctx, &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Namespace: "kube-system", Name: "bootstrap-token-zzzzzz"}}))
	check("read kube-system secret", false, oc.Get(ctx, client.ObjectKey{Namespace: "kube-system", Name: "bootstrap-token-abcdef"}, &corev1.Secret{}))
	check("delete bootstrap token", true, oc.Delete(ctx, &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Namespace: "kube-system", Name: "bootstrap-token-abcdef"}}))
	check("secret in onepassword", false, oc.Create(ctx, &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Namespace: "onepassword", Name: "bootstrap-token-x"}, Type: "bootstrap.kubernetes.io/token"}))
	_ = admin.Create(ctx, &corev1.ServiceAccount{ObjectMeta: metav1.ObjectMeta{Namespace: "onepassword", Name: "external-secrets"}})
	_ = admin.Create(ctx, &corev1.ServiceAccount{ObjectMeta: metav1.ObjectMeta{Namespace: "tuist-runners", Name: "runner"}})
	tokenFor := func(ns, name string) error {
		sa := &corev1.ServiceAccount{ObjectMeta: metav1.ObjectMeta{Namespace: ns, Name: name}}
		return oc.SubResource("token").Create(ctx, sa, &authenticationv1.TokenRequest{})
	}
	check("token for a runner ServiceAccount", true, tokenFor("tuist-runners", "runner"))
	check("token for a ServiceAccount elsewhere", false, tokenFor("onepassword", "external-secrets"))
	check("get secret in the runner namespace", true, client.IgnoreNotFound(oc.Get(ctx, client.ObjectKey{Namespace: "tuist-runners", Name: "x"}, &corev1.Secret{})))
	rb := func(ns, kind, role, sa string) *rbacv1.RoleBinding {
		return &rbacv1.RoleBinding{ObjectMeta: metav1.ObjectMeta{Namespace: ns, Name: "tart-kubelet-m1-pod-refs"},
			RoleRef:  rbacv1.RoleRef{APIGroup: "rbac.authorization.k8s.io", Kind: kind, Name: role},
			Subjects: []rbacv1.Subject{{Kind: "ServiceAccount", Namespace: "tuist-staging", Name: sa}}}
	}
	check("bind system:node into onepassword", false, oc.Create(ctx, rb("onepassword", "ClusterRole", "system:node", "tart-kubelet-m1")))
	_ = admin.Create(ctx, &rbacv1.Role{ObjectMeta: metav1.ObjectMeta{Namespace: "tuist-runners", Name: "tart-kubelet-m1-pod-refs"},
		Rules: []rbacv1.PolicyRule{{APIGroups: []string{""}, Resources: []string{"secrets"}, ResourceNames: []string{"env"}, Verbs: []string{"get"}}}})
	check("bind a node Role to a host", true, oc.Create(ctx, rb("tuist-runners", "Role", "tart-kubelet-m1-pod-refs", "tart-kubelet-m1")))
	_ = admin.Delete(ctx, rb("tuist-runners", "Role", "", ""))
	check("bind a node Role to the operator", false, oc.Create(ctx, rb("tuist-runners", "Role", "tart-kubelet-m1-pod-refs", "tuist-tuist-capi-scaleway-applesilicon")))
}
