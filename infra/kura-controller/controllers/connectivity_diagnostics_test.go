package controllers

import (
	"context"
	"fmt"
	"reflect"
	"strings"
	"testing"

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
			r := &KuraInstanceReconciler{Environment: environment}
			if selected {
				r.ConnectivityDiagnosticsInstances = []string{instance.Name}
			}
			r.configureConnectivityDiagnostics(instance, &template)
			if len(template.Spec.Containers) != 1 || len(template.Spec.InitContainers) != 0 {
				t.Fatal("diagnostics introduced a container readiness dependency")
			}
			if selected {
				container := &template.Spec.Containers[0]
				last := container.Env[len(container.Env)-1]
				if last.Name != connectivityProfileEnv || last.Value != environment || last.ValueFrom != nil {
					t.Fatal("wrong fixed profile")
				}
				container.Env = container.Env[:len(container.Env)-1]
			}
			// Everything other than the opt-in environment value must match,
			// including probes, readiness gates, image, resources and token mounts.
			if !reflect.DeepEqual(template, *before) {
				t.Fatal("diagnostics changed the serving pod configuration")
			}
		}
	}
}

func TestConnectivityDiagnosticsOwnTheReservedProfileSetting(t *testing.T) {
	instance := &kurav1alpha1.KuraInstance{ObjectMeta: metav1.ObjectMeta{Name: "kura-selected"}}
	instance.Spec.ExtraEnv = []corev1.EnvVar{{Name: connectivityProfileEnv, Value: "staging"}, {Name: connectivityProfileEnv, Value: "canary"}}
	for _, name := range []string{"", "kura", "*", instance.Name} {
		template := podTemplate(instance, "", "production", "", false, false, false)
		r := &KuraInstanceReconciler{Environment: "production", ConnectivityDiagnosticsInstances: []string{name}}
		r.configureConnectivityDiagnostics(instance, &template)
		count := 0
		for _, env := range template.Spec.Containers[0].Env {
			if env.Name == connectivityProfileEnv {
				count++
				if env.Value != "production" {
					t.Fatal("ExtraEnv overrode the fixed profile")
				}
			}
		}
		want := 0
		if name == instance.Name {
			want = 1
		}
		if count != want {
			t.Fatalf("profile count for %q: %d", name, count)
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
	r.ConnectivityDiagnosticsInstances = []string{instance.Name}
	ctx := context.Background()
	key := types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}
	for _, enabled := range []bool{true, true, false} {
		if !enabled {
			r.ConnectivityDiagnosticsInstances = nil
		}
		if err := r.reconcileStatefulSet(ctx, instance); err != nil {
			t.Fatal(err)
		}
		sts := &appsv1.StatefulSet{}
		if err := r.Get(ctx, key, sts); err != nil {
			t.Fatal(err)
		}
		if len(sts.Spec.Template.Spec.Containers) != 1 {
			t.Fatal("added a sidecar")
		}
		count := 0
		for _, env := range sts.Spec.Template.Spec.Containers[0].Env {
			if env.Name == connectivityProfileEnv {
				count++
			}
		}
		want := 0
		if enabled {
			want = 1
		}
		if count != want {
			t.Fatalf("profile count: %d", count)
		}
	}
}
