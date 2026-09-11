package controllers

import (
	"context"
	"reflect"
	"testing"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
)

func TestConnectivityProbeReconcileAndRemoval(t *testing.T) {
	r, instance, _ := privateGatewayFixture(t)
	r.Environment = "production"
	r.ConnectivityProbeImage = "controller:test"
	r.ConnectivityProbeInstances = []string{instance.Name}
	ctx := context.Background()
	key := types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}
	for _, count := range []int{2, 2, 1} {
		if count == 1 {
			r.ConnectivityProbeInstances = nil
		}
		if err := r.reconcileStatefulSet(ctx, instance); err != nil {
			t.Fatal(err)
		}
		sts := &appsv1.StatefulSet{}
		if err := r.Get(ctx, key, sts); err != nil {
			t.Fatal(err)
		}
		if len(sts.Spec.Template.Spec.Containers) != count {
			t.Fatalf("want %d containers, got %d", count, len(sts.Spec.Template.Spec.Containers))
		}
		if count == 1 && sts.Spec.Template.Spec.AutomountServiceAccountToken != nil {
			t.Fatal("rollback did not restore original token setting")
		}
	}
}

func TestConnectivityProbeOptInAndIsolation(t *testing.T) {
	instance := &kurav1alpha1.KuraInstance{ObjectMeta: metav1.ObjectMeta{Name: "kura-selected"}}
	for _, tc := range []struct {
		name, image string
		instances   []string
		enabled     bool
	}{
		{"default", "", nil, false},
		{"missing_image", "", []string{instance.Name}, false},
		{"no_instances", "controller:test", nil, false},
		{"no_prefix_match", "controller:test", []string{"kura"}, false},
		{"no_wildcard", "controller:test", []string{"*"}, false},
		{"selected", "controller:test", []string{instance.Name}, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			template := podTemplate(instance, "", "production", "", false)
			before := template.DeepCopy()
			r := &KuraInstanceReconciler{Environment: "production", ConnectivityProbeImage: tc.image, ConnectivityProbeInstances: tc.instances}
			r.addConnectivityProbe(instance, &template)
			if !tc.enabled {
				if !reflect.DeepEqual(*before, template) {
					t.Fatal("non-selected pod template changed")
				}
				return
			}
			if len(template.Spec.Containers) != 2 || !reflect.DeepEqual(before.Spec.Containers[0], template.Spec.Containers[0]) {
				t.Fatal("runtime container changed")
			}
			if template.Spec.AutomountServiceAccountToken == nil || *template.Spec.AutomountServiceAccountToken {
				t.Fatal("service account token can be injected")
			}
			probe := template.Spec.Containers[1]
			if probe.Name != "connectivity-probe" || probe.Image != tc.image || !reflect.DeepEqual(probe.Command, []string{"/connectivity-probe"}) {
				t.Fatal("wrong probe")
			}
			if len(probe.Env)+len(probe.EnvFrom)+len(probe.VolumeMounts)+len(probe.Ports) != 0 {
				t.Fatal("probe acquired extra inputs or mounts")
			}
			if !reflect.DeepEqual(probe.Args, []string{"production"}) {
				t.Fatal("wrong fixed profile")
			}
			security := probe.SecurityContext
			if !*security.RunAsNonRoot || *security.RunAsUser != 65532 || *security.AllowPrivilegeEscalation || !*security.ReadOnlyRootFilesystem || !reflect.DeepEqual(security.Capabilities.Drop, []corev1.Capability{"ALL"}) || security.SeccompProfile.Type != corev1.SeccompProfileTypeRuntimeDefault {
				t.Fatal("unsafe security context")
			}
			if probe.Resources.Limits.Cpu().MilliValue() != 50 || probe.Resources.Limits.Memory().Value() != 32*1024*1024 {
				t.Fatal("unbounded resources")
			}
		})
	}
}
