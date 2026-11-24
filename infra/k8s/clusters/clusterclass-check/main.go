// Command clusterclass-check renders the tuist-hcloud ClusterClass's
// control-plane patches the way Cluster API does and fails when one patch
// silently drops another's API server flag, volume or file.
//
// Several opt-in features (the metrics label manifest, the API server audit
// log, GitHub Actions OIDC) each need an API server flag, a hostPath volume
// and a file. CAPI patches can only add or replace whole arrays at
// `apiServer.extraArgs` and `apiServer.extraVolumes` (the base template has
// no volumes, and arrays cannot be indexed), so the patches that write those
// arrays must carry every feature's entries. A patch that adds the whole
// array after another one replaces it, and nothing reports it: the control
// plane rolls without the earlier feature.
//
// Checks, with every variable switched on:
//   - every extraArgs and extraVolumes entry any enabled patch renders is in
//     the final KubeadmControlPlaneTemplate,
//   - every File volume has a matching kubeadmConfigSpec.files entry,
//   - the named features below are all present,
//
// and with every variable at its default, the API server args and volumes
// equal the base template's, so applying the ClusterClass rolls no cluster
// that has not opted in.
//
// Run with `mise run k8s:lint-clusterclass-patches`.
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"reflect"
	"sort"
	"strings"
	"text/template"

	"github.com/Masterminds/sprig/v3"
	jsonpatch "github.com/evanphx/json-patch/v5"
	"sigs.k8s.io/yaml"
)

// Features that must survive together when all variables are on. Entries are
// checked only when the ClusterClass declares the variable, so the check
// works before and after each feature lands.
var features = []struct {
	variable string
	args     []string
	volumes  []string
}{
	{"aggregateApiServerMetrics", []string{"allow-metric-labels-manifest"}, []string{"metric-labels"}},
	{"apiServerAuditLog", []string{"audit-policy-file", "audit-log-path"}, []string{"audit-policy", "audit-log"}},
	{"githubActionsOIDCAudience", []string{"authentication-config"}, []string{"authentication-config"}},
}

const controlPlaneVersion = "v1.34.6"

type jsonPatchOp struct {
	Op        string `json:"op"`
	Path      string `json:"path"`
	Value     any    `json:"value,omitempty"`
	ValueFrom *struct {
		Variable string `json:"variable,omitempty"`
		Template string `json:"template,omitempty"`
	} `json:"valueFrom,omitempty"`
}

type clusterClass struct {
	Spec struct {
		Variables []struct {
			Name   string `json:"name"`
			Schema struct {
				OpenAPIV3Schema struct {
					Type    string `json:"type"`
					Default any    `json:"default"`
				} `json:"openAPIV3Schema"`
			} `json:"schema"`
		} `json:"variables"`
		Patches []struct {
			Name        string `json:"name"`
			EnabledIf   string `json:"enabledIf"`
			Definitions []struct {
				Selector struct {
					Kind           string `json:"kind"`
					MatchResources struct {
						ControlPlane bool `json:"controlPlane"`
					} `json:"matchResources"`
				} `json:"selector"`
				JSONPatches []jsonPatchOp `json:"jsonPatches"`
			} `json:"definitions"`
		} `json:"patches"`
	} `json:"spec"`
}

const (
	argsPath    = "/spec/template/spec/kubeadmConfigSpec/clusterConfiguration/apiServer/extraArgs"
	volumesPath = "/spec/template/spec/kubeadmConfigSpec/clusterConfiguration/apiServer/extraVolumes"
)

func main() {
	path := "infra/k8s/clusters/clusterclass-tuist.yaml"
	if len(os.Args) > 1 {
		path = os.Args[1]
	}
	if errs := check(path); len(errs) > 0 {
		for _, e := range errs {
			fmt.Fprintln(os.Stderr, "FAIL:", e)
		}
		os.Exit(1)
	}
	fmt.Println("OK: ClusterClass control-plane patches keep every feature's API server flags, volumes and files")
}

func check(path string) []string {
	raw, err := os.ReadFile(path)
	if err != nil {
		return []string{err.Error()}
	}
	var cc clusterClass
	var base []byte
	for _, doc := range strings.Split(string(raw), "\n---\n") {
		var meta struct{ Kind string }
		if err := yaml.Unmarshal([]byte(doc), &meta); err != nil {
			return []string{err.Error()}
		}
		switch meta.Kind {
		case "ClusterClass":
			if err := yaml.Unmarshal([]byte(doc), &cc); err != nil {
				return []string{err.Error()}
			}
		case "KubeadmControlPlaneTemplate":
			if base, err = yaml.YAMLToJSON([]byte(doc)); err != nil {
				return []string{err.Error()}
			}
		}
	}
	if base == nil {
		return []string{"no KubeadmControlPlaneTemplate in " + path}
	}

	defaults := map[string]any{}
	allOn := map[string]any{}
	declared := map[string]bool{}
	for _, v := range cc.Spec.Variables {
		s := v.Schema.OpenAPIV3Schema
		declared[v.Name] = true
		defaults[v.Name] = s.Default
		allOn[v.Name] = s.Default
		switch s.Type {
		case "boolean":
			allOn[v.Name] = true
			if s.Default == nil {
				defaults[v.Name] = false
			}
		case "string":
			if s.Default == nil || s.Default == "" {
				allOn[v.Name] = "clusterclass-check"
			}
		case "array":
			if s.Default == nil {
				defaults[v.Name] = []any{}
				allOn[v.Name] = []any{}
			}
		case "object":
			// Unset, a field lookup on it errors; an empty object renders
			// each field as missing, which is what a patch guards against.
			if s.Default == nil {
				defaults[v.Name] = map[string]any{}
				allOn[v.Name] = map[string]any{}
			}
		}
	}

	var errs []string

	final, contributed, err := render(cc, base, allOn)
	if err != nil {
		return []string{"all variables on: " + err.Error()}
	}
	args, volumes, files := apiServer(final)
	for _, c := range contributed {
		for _, a := range c.args {
			if !args[a] {
				errs = append(errs, fmt.Sprintf("patch %s adds API server flag --%s, but a later patch replaces extraArgs without it", c.patch, a))
			}
		}
		for _, v := range c.volumes {
			if _, ok := volumes[v]; !ok {
				errs = append(errs, fmt.Sprintf("patch %s adds API server volume %q, but a later patch replaces extraVolumes without it", c.patch, v))
			}
		}
	}
	for name, v := range volumes {
		if v.PathType == "File" && !files[v.HostPath] {
			errs = append(errs, fmt.Sprintf("volume %q mounts file %s, which no kubeadmConfigSpec.files entry writes", name, v.HostPath))
		}
	}
	for _, f := range features {
		if !declared[f.variable] {
			continue
		}
		for _, a := range f.args {
			if !args[a] {
				errs = append(errs, fmt.Sprintf("%s on: API server flag --%s missing", f.variable, a))
			}
		}
		for _, v := range f.volumes {
			if _, ok := volumes[v]; !ok {
				errs = append(errs, fmt.Sprintf("%s on: API server volume %q missing", f.variable, v))
			}
		}
	}

	off, _, err := render(cc, base, defaults)
	if err != nil {
		return append(errs, "defaults: "+err.Error())
	}
	for _, p := range []string{argsPath, volumesPath} {
		before, after := lookup(base, p), lookup(off, p)
		if !reflect.DeepEqual(before, after) {
			b, _ := json.Marshal(before)
			a, _ := json.Marshal(after)
			errs = append(errs, fmt.Sprintf("with every variable at its default %s changes from %s to %s, which rolls every control plane", p, b, a))
		}
	}
	return errs
}

type contribution struct {
	patch   string
	args    []string
	volumes []string
}

// render applies every enabled patch to the KubeadmControlPlaneTemplate in
// ClusterClass order, as Cluster API's inline patch engine does, and records
// the flags and volumes each patch's own value carries.
func render(cc clusterClass, base []byte, vars map[string]any) ([]byte, []contribution, error) {
	data := map[string]any{}
	for k, v := range vars {
		data[k] = v
	}
	// The builtin variables Cluster API passes to control-plane patches, with
	// placeholder values, so a patch using any of them renders here as it
	// does there.
	data["builtin"] = map[string]any{
		"cluster": map[string]any{
			"name":      "clusterclass-check",
			"namespace": "org-tuist",
			"uid":       "00000000-0000-0000-0000-000000000000",
			"metadata":  map[string]any{"labels": map[string]any{}, "annotations": map[string]any{}},
			"topology":  map[string]any{"version": controlPlaneVersion, "class": "tuist-hcloud", "classNamespace": "org-tuist"},
			"network":   map[string]any{"serviceDomain": "cluster.local", "services": []any{}, "pods": []any{}},
		},
		"controlPlane": map[string]any{
			"version":  controlPlaneVersion,
			"name":     "clusterclass-check-control-plane",
			"replicas": 3,
			"metadata": map[string]any{"labels": map[string]any{}, "annotations": map[string]any{}},
			"machineTemplate": map[string]any{
				"infrastructureRef": map[string]any{"name": "clusterclass-check-control-plane"},
			},
		},
	}

	doc := base
	var contributed []contribution
	for _, p := range cc.Spec.Patches {
		controlPlane := false
		for _, d := range p.Definitions {
			controlPlane = controlPlane || (d.Selector.Kind == "KubeadmControlPlaneTemplate" && d.Selector.MatchResources.ControlPlane)
		}
		if !controlPlane {
			continue
		}
		if p.EnabledIf != "" {
			out, err := execute(p.EnabledIf, data)
			if err != nil {
				return nil, nil, fmt.Errorf("patch %s enabledIf: %w", p.Name, err)
			}
			if strings.TrimSpace(out) != "true" {
				continue
			}
		}
		for _, d := range p.Definitions {
			if d.Selector.Kind != "KubeadmControlPlaneTemplate" || !d.Selector.MatchResources.ControlPlane {
				continue
			}
			for _, op := range d.JSONPatches {
				value := op.Value
				if op.ValueFrom != nil {
					switch {
					case op.ValueFrom.Template != "":
						out, err := execute(op.ValueFrom.Template, data)
						if err != nil {
							return nil, nil, fmt.Errorf("patch %s %s: %w", p.Name, op.Path, err)
						}
						j, err := yaml.YAMLToJSON([]byte(out))
						if err != nil {
							return nil, nil, fmt.Errorf("patch %s %s renders invalid YAML: %w", p.Name, op.Path, err)
						}
						if err := json.Unmarshal(j, &value); err != nil {
							return nil, nil, err
						}
					case op.ValueFrom.Variable != "":
						value = data[op.ValueFrom.Variable]
					}
				}
				c := contribution{patch: p.Name}
				switch op.Path {
				case argsPath:
					c.args = names(value)
				case volumesPath:
					c.volumes = names(value)
				}
				contributed = append(contributed, c)

				patch, err := json.Marshal([]map[string]any{{"op": op.Op, "path": op.Path, "value": value}})
				if err != nil {
					return nil, nil, err
				}
				decoded, err := jsonpatch.DecodePatch(patch)
				if err != nil {
					return nil, nil, err
				}
				if doc, err = decoded.Apply(doc); err != nil {
					return nil, nil, fmt.Errorf("patch %s %s %s: %w", p.Name, op.Op, op.Path, err)
				}
			}
		}
	}
	return doc, contributed, nil
}

func execute(t string, data map[string]any) (string, error) {
	tpl, err := template.New("").Funcs(sprig.HermeticTxtFuncMap()).Parse(t)
	if err != nil {
		return "", err
	}
	var b bytes.Buffer
	if err := tpl.Execute(&b, data); err != nil {
		return "", err
	}
	return b.String(), nil
}

func names(value any) []string {
	list, _ := value.([]any)
	var out []string
	for _, item := range list {
		if m, ok := item.(map[string]any); ok {
			if n, ok := m["name"].(string); ok {
				out = append(out, n)
			}
		}
	}
	sort.Strings(out)
	return out
}

type volume struct {
	HostPath string `json:"hostPath"`
	PathType string `json:"pathType"`
}

func apiServer(doc []byte) (args map[string]bool, volumes map[string]volume, files map[string]bool) {
	var t struct {
		Spec struct {
			Template struct {
				Spec struct {
					KubeadmConfigSpec struct {
						ClusterConfiguration struct {
							APIServer struct {
								ExtraArgs    []struct{ Name string } `json:"extraArgs"`
								ExtraVolumes []struct {
									Name string `json:"name"`
									volume
								} `json:"extraVolumes"`
							} `json:"apiServer"`
						} `json:"clusterConfiguration"`
						Files []struct{ Path string } `json:"files"`
					} `json:"kubeadmConfigSpec"`
				} `json:"spec"`
			} `json:"template"`
		} `json:"spec"`
	}
	_ = json.Unmarshal(doc, &t)
	s := t.Spec.Template.Spec.KubeadmConfigSpec
	args, volumes, files = map[string]bool{}, map[string]volume{}, map[string]bool{}
	for _, a := range s.ClusterConfiguration.APIServer.ExtraArgs {
		args[a.Name] = true
	}
	for _, v := range s.ClusterConfiguration.APIServer.ExtraVolumes {
		volumes[v.Name] = v.volume
	}
	for _, f := range s.Files {
		files[f.Path] = true
	}
	return args, volumes, files
}

func lookup(doc []byte, pointer string) any {
	var v any
	_ = json.Unmarshal(doc, &v)
	for _, key := range strings.Split(strings.TrimPrefix(pointer, "/"), "/") {
		m, ok := v.(map[string]any)
		if !ok {
			return nil
		}
		v = m[key]
	}
	return v
}
