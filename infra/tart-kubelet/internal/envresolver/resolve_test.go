package envresolver

import (
	"context"
	"testing"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

func newScheme(t *testing.T) *runtime.Scheme {
	t.Helper()
	s := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(s); err != nil {
		t.Fatalf("add scheme: %v", err)
	}
	return s
}

func TestResolve(t *testing.T) {
	scheme := newScheme(t)
	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{Name: "p", Namespace: "ns", UID: "uid-1"},
		Spec:       corev1.PodSpec{NodeName: "node-a", ServiceAccountName: "sa-x"},
	}

	t.Run("literal Value", func(t *testing.T) {
		r := &Resolver{K8s: fake.NewClientBuilder().WithScheme(scheme).Build()}
		env, err := r.Resolve(context.Background(), pod, corev1.Container{
			Env: []corev1.EnvVar{{Name: "FOO", Value: "bar"}},
		})
		if err != nil {
			t.Fatal(err)
		}
		if env["FOO"] != "bar" {
			t.Fatalf("FOO = %q", env["FOO"])
		}
	})

	t.Run("secretKeyRef hit", func(t *testing.T) {
		sec := &corev1.Secret{
			ObjectMeta: metav1.ObjectMeta{Name: "s", Namespace: "ns"},
			Data:       map[string][]byte{"K": []byte("v")},
		}
		r := &Resolver{K8s: fake.NewClientBuilder().WithScheme(scheme).WithObjects(sec).Build()}
		env, err := r.Resolve(context.Background(), pod, corev1.Container{
			Env: []corev1.EnvVar{{
				Name: "K",
				ValueFrom: &corev1.EnvVarSource{SecretKeyRef: &corev1.SecretKeySelector{
					LocalObjectReference: corev1.LocalObjectReference{Name: "s"},
					Key:                  "K",
				}},
			}},
		})
		if err != nil {
			t.Fatal(err)
		}
		if env["K"] != "v" {
			t.Fatalf("K = %q", env["K"])
		}
	})

	t.Run("required Secret miss errors", func(t *testing.T) {
		r := &Resolver{K8s: fake.NewClientBuilder().WithScheme(scheme).Build()}
		_, err := r.Resolve(context.Background(), pod, corev1.Container{
			Env: []corev1.EnvVar{{
				Name: "K",
				ValueFrom: &corev1.EnvVarSource{SecretKeyRef: &corev1.SecretKeySelector{
					LocalObjectReference: corev1.LocalObjectReference{Name: "missing"},
					Key:                  "K",
				}},
			}},
		})
		if err == nil {
			t.Fatal("expected error")
		}
	})

	t.Run("optional Secret miss skipped", func(t *testing.T) {
		opt := true
		r := &Resolver{K8s: fake.NewClientBuilder().WithScheme(scheme).Build()}
		env, err := r.Resolve(context.Background(), pod, corev1.Container{
			Env: []corev1.EnvVar{{
				Name: "K",
				ValueFrom: &corev1.EnvVarSource{SecretKeyRef: &corev1.SecretKeySelector{
					LocalObjectReference: corev1.LocalObjectReference{Name: "missing"},
					Key:                  "K",
					Optional:             &opt,
				}},
			}},
		})
		if err != nil {
			t.Fatal(err)
		}
		if _, ok := env["K"]; ok {
			t.Fatalf("K should be omitted")
		}
	})

	t.Run("envFrom dump with prefix", func(t *testing.T) {
		sec := &corev1.Secret{
			ObjectMeta: metav1.ObjectMeta{Name: "s", Namespace: "ns"},
			Data:       map[string][]byte{"A": []byte("1"), "B": []byte("2")},
		}
		r := &Resolver{K8s: fake.NewClientBuilder().WithScheme(scheme).WithObjects(sec).Build()}
		env, err := r.Resolve(context.Background(), pod, corev1.Container{
			EnvFrom: []corev1.EnvFromSource{{
				Prefix:    "PFX_",
				SecretRef: &corev1.SecretEnvSource{LocalObjectReference: corev1.LocalObjectReference{Name: "s"}},
			}},
		})
		if err != nil {
			t.Fatal(err)
		}
		if env["PFX_A"] != "1" || env["PFX_B"] != "2" {
			t.Fatalf("env = %v", env)
		}
	})

	t.Run("env overrides envFrom", func(t *testing.T) {
		sec := &corev1.Secret{
			ObjectMeta: metav1.ObjectMeta{Name: "s", Namespace: "ns"},
			Data:       map[string][]byte{"K": []byte("from-secret")},
		}
		r := &Resolver{K8s: fake.NewClientBuilder().WithScheme(scheme).WithObjects(sec).Build()}
		env, err := r.Resolve(context.Background(), pod, corev1.Container{
			EnvFrom: []corev1.EnvFromSource{{
				SecretRef: &corev1.SecretEnvSource{LocalObjectReference: corev1.LocalObjectReference{Name: "s"}},
			}},
			Env: []corev1.EnvVar{{Name: "K", Value: "literal"}},
		})
		if err != nil {
			t.Fatal(err)
		}
		if env["K"] != "literal" {
			t.Fatalf("K = %q", env["K"])
		}
	})

	t.Run("fieldRef common paths", func(t *testing.T) {
		r := &Resolver{K8s: fake.NewClientBuilder().WithScheme(scheme).Build()}
		env, err := r.Resolve(context.Background(), pod, corev1.Container{
			Env: []corev1.EnvVar{
				{Name: "POD_NAME", ValueFrom: &corev1.EnvVarSource{
					FieldRef: &corev1.ObjectFieldSelector{FieldPath: "metadata.name"},
				}},
				{Name: "POD_NS", ValueFrom: &corev1.EnvVarSource{
					FieldRef: &corev1.ObjectFieldSelector{FieldPath: "metadata.namespace"},
				}},
				{Name: "NODE", ValueFrom: &corev1.EnvVarSource{
					FieldRef: &corev1.ObjectFieldSelector{FieldPath: "spec.nodeName"},
				}},
			},
		})
		if err != nil {
			t.Fatal(err)
		}
		if env["POD_NAME"] != "p" || env["POD_NS"] != "ns" || env["NODE"] != "node-a" {
			t.Fatalf("env = %v", env)
		}
	})
}
