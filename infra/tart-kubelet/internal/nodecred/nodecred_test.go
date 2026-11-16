package nodecred

import (
	"context"
	"encoding/base64"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"

	authenticationv1 "k8s.io/api/authentication/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/kubernetes/fake"
	ktesting "k8s.io/client-go/testing"
)

func jwt(iat, exp time.Time) string {
	payload := base64.RawURLEncoding.EncodeToString([]byte(fmt.Sprintf(`{"iat":%d,"exp":%d}`, iat.Unix(), exp.Unix())))
	return "h." + payload + ".s"
}

func writeKubeconfig(t *testing.T, dir, token string) string {
	t.Helper()
	path := filepath.Join(dir, "kubeconfig")
	cfg := fmt.Sprintf(`apiVersion: v1
kind: Config
current-context: tart-kubelet
clusters:
  - name: cluster
    cluster:
      server: https://example:6443
contexts:
  - name: tart-kubelet
    context:
      cluster: cluster
      user: u
users:
  - name: u
    user:
      token: %s
      tokenFile: %s
`, token, filepath.Join(dir, "token"))
	if err := os.WriteFile(path, []byte(cfg), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func read(t *testing.T, path string) string {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

// The operator's push must replace an older rotated token, and a token the
// host rotated since the push must not be replaced by the push's older one.
func TestSeedKeepsTheNewestToken(t *testing.T) {
	dir := t.TempDir()
	now := time.Now()
	pushed := jwt(now.Add(-time.Hour), now.Add(6*24*time.Hour))
	kubeconfig := writeKubeconfig(t, dir, pushed)

	file, err := Seed(kubeconfig)
	if err != nil || file != filepath.Join(dir, "token") {
		t.Fatalf("Seed = %q, %v", file, err)
	}
	if read(t, file) != pushed {
		t.Fatal("a missing token file was not seeded from the kubeconfig")
	}
	if info, _ := os.Stat(file); info.Mode().Perm() != 0o600 {
		t.Fatalf("token file mode %v", info.Mode().Perm())
	}

	rotated := jwt(now, now.Add(7*24*time.Hour))
	if err := os.WriteFile(file, []byte(rotated), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := Seed(kubeconfig); err != nil || read(t, file) != rotated {
		t.Fatal("an older pushed token replaced the host's rotated one")
	}

	newer := jwt(now.Add(time.Minute), now.Add(7*24*time.Hour))
	writeKubeconfig(t, dir, newer)
	if _, err := Seed(kubeconfig); err != nil || read(t, file) != newer {
		t.Fatal("a newer pushed token did not replace the file")
	}
}

func TestRotatorReplacesTheTokenOnlyWhenDue(t *testing.T) {
	dir := t.TempDir()
	file := filepath.Join(dir, "token")
	now := time.Now()
	client := fake.NewClientset()
	var minted []string
	client.PrependReactor("create", "selfsubjectreviews", func(ktesting.Action) (bool, runtime.Object, error) {
		r := &authenticationv1.SelfSubjectReview{}
		r.Status.UserInfo.Username = "system:serviceaccount:tuist:tart-kubelet-b01"
		return true, r, nil
	})
	client.PrependReactor("create", "serviceaccounts", func(a ktesting.Action) (bool, runtime.Object, error) {
		if a.GetSubresource() != "token" {
			return false, nil, nil
		}
		minted = append(minted, a.GetNamespace()+"/"+a.(ktesting.CreateActionImpl).Name)
		tr := &authenticationv1.TokenRequest{}
		tr.Status.Token = "new-token"
		return true, tr, nil
	})
	r := &Rotator{Client: client, File: file, Now: func() time.Time { return now }}

	// Twelve hours into a seven-day token: not due.
	if err := os.WriteFile(file, []byte(jwt(now.Add(-12*time.Hour), now.Add(6*24*time.Hour))), 0o600); err != nil {
		t.Fatal(err)
	}
	if rotated, err := r.RotateIfDue(context.Background()); err != nil || rotated || len(minted) != 0 {
		t.Fatalf("rotated a fresh token: %v %v %v", rotated, err, minted)
	}

	// A day and a minute old: due, for its own account.
	if err := os.WriteFile(file, []byte(jwt(now.Add(-24*time.Hour-time.Minute), now.Add(6*24*time.Hour))), 0o600); err != nil {
		t.Fatal(err)
	}
	if rotated, err := r.RotateIfDue(context.Background()); err != nil || !rotated {
		t.Fatalf("did not rotate a day-old token: %v", err)
	}
	if len(minted) != 1 || minted[0] != "tuist/tart-kubelet-b01" || read(t, file) != "new-token" {
		t.Fatalf("minted %v, file %q", minted, read(t, file))
	}

	// A capped two-hour token past half its life is due before a day.
	if err := os.WriteFile(file, []byte(jwt(now.Add(-61*time.Minute), now.Add(59*time.Minute))), 0o600); err != nil {
		t.Fatal(err)
	}
	if rotated, _ := r.RotateIfDue(context.Background()); !rotated {
		t.Fatal("did not rotate a capped token past half its lifetime")
	}
}
