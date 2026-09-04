// Package template discovers the golden templates the init container seeds
// under DATA_DIR/templates/<name>/<tag> and builds their per-shape
// snapshots on the node.
package template

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/internal/vm"
)

const (
	KernelFile   = "vmlinux"
	RootfsFile   = "rootfs.ext4"
	BootRootfs   = "rootfs.boot.ext4"
	MemFile      = "memfile"
	SnapshotFile = "snapshot"
	MetadataFile = "metadata.json"
	ReadyFile    = "ready"
	shapesDir    = "shapes"
	buildSuffix  = ".building"
)

// Shape is the vCPU and memory size a snapshot was taken with. A snapshot
// fixes both, so every shape has its own snapshot.
type Shape struct {
	VCPUs    int
	MemoryMB int
}

func (s Shape) String() string { return fmt.Sprintf("%dx%d", s.VCPUs, s.MemoryMB) }

func (s Shape) Validate() error {
	if s.VCPUs < 1 || s.VCPUs > 32 {
		return fmt.Errorf("vcpus %d out of range [1,32]", s.VCPUs)
	}
	if s.MemoryMB < 128 {
		return fmt.Errorf("memory_mb %d too small", s.MemoryMB)
	}
	return nil
}

var shapePattern = regexp.MustCompile(`^(\d+)x(\d+)$`)

// ParseShape parses "<vcpus>x<memory_mb>".
func ParseShape(s string) (Shape, error) {
	m := shapePattern.FindStringSubmatch(strings.TrimSpace(s))
	if m == nil {
		return Shape{}, fmt.Errorf("invalid shape %q (want <vcpus>x<memory_mb>)", s)
	}
	vcpus, _ := strconv.Atoi(m[1])
	mem, _ := strconv.Atoi(m[2])
	shape := Shape{VCPUs: vcpus, MemoryMB: mem}
	if err := shape.Validate(); err != nil {
		return Shape{}, fmt.Errorf("invalid shape %q: %w", s, err)
	}
	return shape, nil
}

// ParseShapes parses a comma-separated shape list (PREBUILD_SHAPES).
func ParseShapes(csv string) ([]Shape, error) {
	var shapes []Shape
	for _, part := range strings.Split(csv, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		shape, err := ParseShape(part)
		if err != nil {
			return nil, err
		}
		shapes = append(shapes, shape)
	}
	return shapes, nil
}

// Metadata describes a built shape snapshot.
type Metadata struct {
	Name               string    `json:"name"`
	Tag                string    `json:"tag"`
	Kernel             string    `json:"kernel"`
	VCPUs              int       `json:"vcpus"`
	MemoryMB           int       `json:"memory_mb"`
	WorkspaceGB        int       `json:"workspace_gb"`
	FirecrackerVersion string    `json:"firecracker_version"`
	BuiltAt            time.Time `json:"built_at"`
}

// Template is one seeded <name>/<tag> directory.
type Template struct {
	Name string
	Tag  string
	Dir  string
}

func (t Template) Kernel() string { return filepath.Join(t.Dir, KernelFile) }
func (t Template) Rootfs() string { return filepath.Join(t.Dir, RootfsFile) }

func (t Template) ShapeDir(shape Shape) string {
	return filepath.Join(t.Dir, shapesDir, shape.String())
}

func (t Template) ShapeReady(shape Shape) bool {
	return vm.Exists(filepath.Join(t.ShapeDir(shape), ReadyFile))
}

// ReadyShapes lists the shapes with a complete snapshot, sorted.
func (t Template) ReadyShapes() []Shape {
	entries, err := os.ReadDir(filepath.Join(t.Dir, shapesDir))
	if err != nil {
		return nil
	}
	var shapes []Shape
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		shape, err := ParseShape(e.Name())
		if err != nil {
			continue
		}
		if t.ShapeReady(shape) {
			shapes = append(shapes, shape)
		}
	}
	sort.Slice(shapes, func(i, j int) bool {
		if shapes[i].VCPUs != shapes[j].VCPUs {
			return shapes[i].VCPUs < shapes[j].VCPUs
		}
		return shapes[i].MemoryMB < shapes[j].MemoryMB
	})
	return shapes
}

// Artifacts are the files a sandbox is created from.
type Artifacts struct {
	Dir      string
	Rootfs   string
	Memfile  string
	Snapshot string
	Meta     Metadata
}

var ErrShapeNotReady = errors.New("template shape snapshot not built")

func (t Template) Artifacts(shape Shape) (Artifacts, error) {
	dir := t.ShapeDir(shape)
	if !t.ShapeReady(shape) {
		return Artifacts{}, fmt.Errorf("%w: %s/%s %s", ErrShapeNotReady, t.Name, t.Tag, shape)
	}
	var meta Metadata
	data, err := os.ReadFile(filepath.Join(dir, MetadataFile))
	if err != nil {
		return Artifacts{}, err
	}
	if err := json.Unmarshal(data, &meta); err != nil {
		return Artifacts{}, fmt.Errorf("decoding %s: %w", filepath.Join(dir, MetadataFile), err)
	}
	return Artifacts{
		Dir:      dir,
		Rootfs:   filepath.Join(dir, BootRootfs),
		Memfile:  filepath.Join(dir, MemFile),
		Snapshot: filepath.Join(dir, SnapshotFile),
		Meta:     meta,
	}, nil
}

// seedKernel reads the kernel name from the template-level metadata.json
// the image ships, if any.
func (t Template) seedKernel() string {
	data, err := os.ReadFile(filepath.Join(t.Dir, MetadataFile))
	if err != nil {
		return KernelFile
	}
	var meta struct {
		Kernel string `json:"kernel"`
	}
	if json.Unmarshal(data, &meta) != nil || meta.Kernel == "" {
		return KernelFile
	}
	return meta.Kernel
}

// Store is DATA_DIR/templates.
type Store struct {
	Dir string
}

func (s *Store) List() ([]Template, error) {
	names, err := os.ReadDir(s.Dir)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil, nil
		}
		return nil, err
	}
	var templates []Template
	for _, name := range names {
		if !name.IsDir() {
			continue
		}
		tags, err := os.ReadDir(filepath.Join(s.Dir, name.Name()))
		if err != nil {
			continue
		}
		for _, tag := range tags {
			if !tag.IsDir() {
				continue
			}
			t := Template{Name: name.Name(), Tag: tag.Name(), Dir: filepath.Join(s.Dir, name.Name(), tag.Name())}
			if vm.Exists(t.Kernel()) && vm.Exists(t.Rootfs()) {
				templates = append(templates, t)
			}
		}
	}
	sort.Slice(templates, func(i, j int) bool {
		if templates[i].Name != templates[j].Name {
			return templates[i].Name < templates[j].Name
		}
		return templates[i].Tag < templates[j].Tag
	})
	return templates, nil
}

func (s *Store) Get(name, tag string) (Template, error) {
	t := Template{Name: name, Tag: tag, Dir: filepath.Join(s.Dir, name, tag)}
	if !vm.Exists(t.Kernel()) || !vm.Exists(t.Rootfs()) {
		return Template{}, fmt.Errorf("template %s/%s not found under %s", name, tag, s.Dir)
	}
	return t, nil
}

// Resolve finds a template by name and optional tag: with an empty tag the
// template must have exactly one tag on the node.
func (s *Store) Resolve(name, tag string) (Template, error) {
	if tag != "" {
		return s.Get(name, tag)
	}
	all, err := s.List()
	if err != nil {
		return Template{}, err
	}
	var matches []Template
	for _, t := range all {
		if t.Name == name {
			matches = append(matches, t)
		}
	}
	switch len(matches) {
	case 0:
		return Template{}, fmt.Errorf("template %q not found under %s", name, s.Dir)
	case 1:
		return matches[0], nil
	default:
		var tags []string
		for _, t := range matches {
			tags = append(tags, t.Tag)
		}
		return Template{}, fmt.Errorf("template %q has several tags (%s); set TEMPLATE_TAG or pass template_tag", name, strings.Join(tags, ", "))
	}
}

// CleanPartialBuilds removes shape directories an interrupted build left
// behind.
func (s *Store) CleanPartialBuilds() error {
	templates, err := s.List()
	if err != nil {
		return err
	}
	for _, t := range templates {
		entries, err := os.ReadDir(filepath.Join(t.Dir, shapesDir))
		if err != nil {
			continue
		}
		for _, e := range entries {
			if !e.IsDir() {
				continue
			}
			dir := filepath.Join(t.Dir, shapesDir, e.Name())
			if strings.HasSuffix(e.Name(), buildSuffix) || !vm.Exists(filepath.Join(dir, ReadyFile)) {
				if err := os.RemoveAll(dir); err != nil {
					return err
				}
			}
		}
	}
	return nil
}
