package controllers

import (
	"context"
	"encoding/json"
	"fmt"
	"reflect"
	"slices"
	"strings"
	"testing"
	"time"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
)

func TestConnectivityDiagnosticsChartSelection(t *testing.T) {
	for _, test := range []struct {
		name     string
		setting  string
		argument string
		secret   string
	}{
		{name: "disabled"},
		{
			name:     "inline",
			setting:  "kuraController.connectivityDiagnostics.instances={diagnostic-fixture-a,diagnostic-fixture-b}",
			argument: "--connectivity-diagnostics-instances=diagnostic-fixture-a,diagnostic-fixture-b",
		},
		{
			name:     "private",
			setting:  "kuraController.connectivityDiagnostics.existingSecret=diagnostic-fixture",
			argument: "--connectivity-diagnostics-instances=$(KURA_CONNECTIVITY_DIAGNOSTICS_INSTANCES)",
			secret:   "diagnostic-fixture",
		},
	} {
		for _, stableDNS := range []bool{false, true} {
			t.Run(fmt.Sprintf("%s/stable-dns-%t", test.name, stableDNS), func(t *testing.T) {
				settings := []string{
					"kuraController.enabled=true",
					"kuraController.image.tag=test",
					"kuraController.connectivityDiagnostics.prepare=true",
					"kuraController.connectivityDiagnostics.expiresAt=2030-01-01T00:00:00Z",
					fmt.Sprintf("kuraController.stableDNS.enabled=%t", stableDNS),
					"kuraController.stableDNS.hostedZoneId=diagnostic-fixture-zone",
					"kuraController.stableDNS.ownerId=diagnostic-fixture-owner",
				}
				if test.setting != "" {
					settings = append(settings, test.setting)
				}
				docs := renderStableChart(t, "tuist", []string{"templates/_helpers.tpl", "templates/kura-controller.yaml"}, settings...)
				var manager *corev1.Container
				for _, doc := range docs {
					if doc["kind"] != "Deployment" {
						continue
					}
					deployment := &appsv1.Deployment{}
					if err := runtime.DefaultUnstructuredConverter.FromUnstructured(doc, deployment); err != nil {
						t.Fatal(err)
					}
					for i := range deployment.Spec.Template.Spec.Containers {
						container := &deployment.Spec.Template.Spec.Containers[i]
						if container.Name == "manager" {
							manager = container
						}
					}
				}
				if manager == nil {
					t.Fatal("controller manager was not rendered")
				}
				var argument string
				for _, arg := range manager.Args {
					if strings.HasPrefix(arg, "--connectivity-diagnostics-instances=") {
						if argument != "" {
							t.Fatal("multiple diagnostics selection arguments")
						}
						argument = arg
					}
				}
				if argument != test.argument {
					t.Fatalf("diagnostics argument = %q, want %q", argument, test.argument)
				}
				if !slices.Contains(manager.Args, "--connectivity-diagnostics-prepare=true") || !slices.Contains(manager.Args, "--connectivity-diagnostics-expires-at=2030-01-01T00:00:00Z") {
					t.Fatal("missing preparation or absolute expiry argument")
				}
				env := map[string]corev1.EnvVar{}
				for _, variable := range manager.Env {
					env[variable.Name] = variable
				}
				var want corev1.EnvVar
				if test.secret != "" {
					want = corev1.EnvVar{
						Name: "KURA_CONNECTIVITY_DIAGNOSTICS_INSTANCES",
						ValueFrom: &corev1.EnvVarSource{SecretKeyRef: &corev1.SecretKeySelector{
							LocalObjectReference: corev1.LocalObjectReference{Name: test.secret},
							Key:                  "instances",
						}},
					}
				}
				if !reflect.DeepEqual(env["KURA_CONNECTIVITY_DIAGNOSTICS_INSTANCES"], want) {
					t.Fatal("diagnostics must use the required private Secret key only when selected")
				}
				_, awsRegion := env["AWS_REGION"]
				if awsRegion != stableDNS || (len(manager.EnvFrom) != 0) != stableDNS {
					t.Fatal("diagnostics changed stable DNS environment wiring")
				}
			})
		}
	}
}

func TestConnectivityDiagnosticsNeverAddReadinessDependencies(t *testing.T) {
	instance := &kurav1alpha1.KuraInstance{ObjectMeta: metav1.ObjectMeta{Name: "kura-selected"}}
	for _, environment := range []string{"production", "staging", "canary"} {
		for _, selected := range []bool{false, true} {
			template := podTemplate(instance, "", environment, "", false, false, false)
			before := template.DeepCopy()
			r := &KuraInstanceReconciler{Environment: environment, ConnectivityDiagnosticsPrepare: true}
			if selected {
				r.ConnectivityDiagnosticsInstances = []string{instance.Name}
			}
			r.configureConnectivityDiagnostics(instance, &template, &corev1.PodTemplateSpec{})
			if len(template.Spec.Containers) != 1 || len(template.Spec.InitContainers) != 0 {
				t.Fatal("diagnostics introduced a container readiness dependency")
			}
			container := &template.Spec.Containers[0]
			last := container.Env[len(container.Env)-1]
			if last.Name != connectivityConfigEnv || last.Value != connectivityFile || last.ValueFrom != nil || !connectivityMounted(template.Spec) {
				t.Fatal("missing inert, live annotation projection")
			}
			container.Env = container.Env[:len(container.Env)-1]
			container.VolumeMounts = container.VolumeMounts[:len(container.VolumeMounts)-1]
			template.Spec.Volumes = template.Spec.Volumes[:len(template.Spec.Volumes)-1]
			// Everything other than the inert config projection must match,
			// including probes, readiness gates, image, resources and token mounts.
			if !reflect.DeepEqual(template, *before) {
				t.Fatal("diagnostics changed the serving pod configuration")
			}
		}
	}
}

func TestConnectivityDiagnosticsOwnTheReservedProfileSetting(t *testing.T) {
	instance := &kurav1alpha1.KuraInstance{ObjectMeta: metav1.ObjectMeta{Name: "kura-selected"}}
	instance.Spec.ExtraEnv = []corev1.EnvVar{{Name: connectivityProfileEnv, Value: "staging"}, {Name: connectivityConfigEnv, Value: "/arbitrary/path"}}
	instance.Spec.PodAnnotations = map[string]string{connectivityAnnotation: `{"profile":"canary","expires_at_unix_seconds":1900000000}`}
	for _, name := range []string{"", "kura", "*", instance.Name} {
		template := podTemplate(instance, "", "production", "", false, false, false)
		r := &KuraInstanceReconciler{Environment: "production", ConnectivityDiagnosticsInstances: []string{name}, ConnectivityDiagnosticsPrepare: true}
		r.configureConnectivityDiagnostics(instance, &template, &corev1.PodTemplateSpec{})
		if template.Annotations[connectivityAnnotation] != "" {
			t.Fatal("instance annotations bypassed live-Pod selection")
		}
		count := 0
		for _, env := range template.Spec.Containers[0].Env {
			if env.Name == connectivityProfileEnv {
				t.Fatal("legacy profile enables unexpiring diagnostics")
			}
			if env.Name == connectivityConfigEnv {
				count++
				if env.Value != connectivityFile {
					t.Fatal("ExtraEnv overrode the fixed config path")
				}
			}
		}
		if count != 1 {
			t.Fatalf("config file count for %q: %d", name, count)
		}
	}
	for _, profile := range []string{"", "prod", "https://example.com"} {
		if ValidConnectivityProfile(profile) {
			t.Fatalf("accepted arbitrary profile %q", profile)
		}
	}
}

func TestConnectivityDiagnosticsReconcileAndRemoval(t *testing.T) {
	r, instance, _ := privateGatewayFixture(t)
	r.Environment = "production"
	r.ConnectivityDiagnosticsPrepare = true
	ctx := context.Background()
	key := types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}
	if err := r.reconcileStatefulSet(ctx, instance); err != nil {
		t.Fatal(err)
	}
	sts := &appsv1.StatefulSet{}
	if err := r.Get(ctx, key, sts); err != nil {
		t.Fatal(err)
	}
	for _, ordinal := range []string{"1", "2", "legacy"} {
		pod := &corev1.Pod{
			ObjectMeta: metav1.ObjectMeta{Name: instance.Name + "-" + ordinal, Namespace: instance.Namespace, UID: types.UID("fixture-" + ordinal),
				OwnerReferences: []metav1.OwnerReference{{APIVersion: "apps/v1", Kind: "StatefulSet", Name: instance.Name, UID: "fixture-set", Controller: ptr(true)}},
				Annotations:     map[string]string{"unrelated": "retained"}},
			Spec: *sts.Spec.Template.Spec.DeepCopy(),
		}
		if ordinal == "legacy" {
			pod.Spec = corev1.PodSpec{}
		}
		if err := r.Create(ctx, pod); err != nil {
			t.Fatal(err)
		}
	}
	for _, test := range []struct {
		selection []string
		expiry    time.Time
		enabled   bool
	}{
		{[]string{instance.Name}, time.Now().Add(time.Hour), true},
		{[]string{instance.Name}, time.Now().Add(time.Hour), true},
		{nil, time.Now().Add(time.Hour), false},
		{[]string{"*"}, time.Now().Add(time.Hour), false},
		{[]string{instance.Name}, time.Time{}, false},
		{[]string{instance.Name}, time.Now().Add(-time.Second), false},
		{[]string{instance.Name}, time.Now().Add(25 * time.Hour), false},
	} {
		r.ConnectivityDiagnosticsInstances, r.ConnectivityDiagnosticsExpiresAt = test.selection, test.expiry
		list := &corev1.PodList{}
		if err := r.List(ctx, list); err != nil {
			t.Fatal(err)
		}
		before := list.DeepCopy()
		if err := r.reconcileConnectivityDiagnostics(ctx, instance, list.Items); err != nil {
			t.Fatal(err)
		}
		for _, old := range before.Items {
			pod := &corev1.Pod{}
			if err := r.Get(ctx, types.NamespacedName{Name: old.Name, Namespace: old.Namespace}, pod); err != nil {
				t.Fatal(err)
			}
			value := pod.Annotations[connectivityAnnotation]
			selected := pod.Name == instance.Name+"-1" || pod.Name == instance.Name+"-2"
			if (value != "") != (test.enabled && selected) {
				t.Fatal("wrong live-Pod selection")
			}
			if value != "" {
				var selection struct {
					Profile string `json:"profile"`
					Expiry  int64  `json:"expires_at_unix_seconds"`
				}
				if err := json.Unmarshal([]byte(value), &selection); err != nil {
					t.Fatal(err)
				}
				if selection.Profile != "production" || selection.Expiry != test.expiry.Unix() {
					t.Fatal("expiry or profile changed")
				}
			}
			if pod.UID != old.UID || !reflect.DeepEqual(pod.Spec, old.Spec) || !reflect.DeepEqual(pod.Status, old.Status) || pod.Annotations["unrelated"] != old.Annotations["unrelated"] {
				t.Fatal("activation modified serving state")
			}
		}
	}
}

func TestConnectivityDiagnosticsSelectionDoesNotRollRuntime(t *testing.T) {
	r, instance, _ := privateGatewayFixture(t)
	r.Environment = "production"
	ctx := context.Background()
	key := types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}
	if err := r.reconcileStatefulSet(ctx, instance); err != nil {
		t.Fatal(err)
	}
	before := &appsv1.StatefulSet{}
	if err := r.Get(ctx, key, before); err != nil {
		t.Fatal(err)
	}
	// Model the preceding controller's template, including its legacy opt-in.
	before.Spec.Template.Spec.Containers[0].Env = append(before.Spec.Template.Spec.Containers[0].Env, corev1.EnvVar{Name: connectivityProfileEnv, Value: "production"})
	if err := r.Update(ctx, before); err != nil {
		t.Fatal(err)
	}
	r.ConnectivityDiagnosticsPrepare = true
	for _, selection := range [][]string{{instance.Name}, nil} {
		r.ConnectivityDiagnosticsInstances = selection
		if err := r.reconcileStatefulSet(ctx, instance); err != nil {
			t.Fatal(err)
		}
		after := &appsv1.StatefulSet{}
		if err := r.Get(ctx, key, after); err != nil {
			t.Fatal(err)
		}
		if !reflect.DeepEqual(before.Spec.Template, after.Spec.Template) {
			t.Fatal("changing incident selection changed the StatefulSet template")
		}
	}
	instance.Spec.Image += "-next"
	if err := r.reconcileStatefulSet(ctx, instance); err != nil {
		t.Fatal(err)
	}
	prepared := &appsv1.StatefulSet{}
	if err := r.Get(ctx, key, prepared); err != nil {
		t.Fatal(err)
	}
	if !connectivityMounted(prepared.Spec.Template.Spec) {
		t.Fatal("normal image change did not prepare diagnostics")
	}
	// Rollback to this release with preparation disabled must retain the mount.
	r.ConnectivityDiagnosticsPrepare = false
	if err := r.reconcileStatefulSet(ctx, instance); err != nil {
		t.Fatal(err)
	}
	after := &appsv1.StatefulSet{}
	if err := r.Get(ctx, key, after); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(prepared.Spec.Template, after.Spec.Template) {
		t.Fatal("compatible rollback changed the prepared template")
	}
}
