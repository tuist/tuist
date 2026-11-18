package macosandbox

import "sync"

// TemplateConfig is one template the host serves: the name the server asks
// for and the digest-pinned image its VMs clone. Each Xcode the host serves
// is its own template, `macos-xcode-<version>`, whose image is that Xcode's
// CI runner image, and `macos` names the default Xcode's image too, so two
// templates can share an image.
type TemplateConfig struct {
	Template string `json:"template"`
	Image    string `json:"image"`
}

// Templates are the host's prepared templates: the image each one clones, by
// template name. A configured template joins it once its image is in the
// sandbox store, so creates, warm boots and reports never reach a template
// whose image would have to be pulled first. It has its own lock because
// reports and warm boots read it outside the launch gate.
type Templates struct {
	mu     sync.RWMutex
	images map[string]string
}

func NewTemplates(images map[string]string) *Templates {
	t := &Templates{images: map[string]string{}}
	for name, image := range images {
		t.images[name] = image
	}
	return t
}

// Image is the image template clones, when it is prepared.
func (t *Templates) Image(template string) (string, bool) {
	if t == nil {
		return "", false
	}
	t.mu.RLock()
	defer t.mu.RUnlock()
	image, ok := t.images[template]
	return image, ok
}

// Name is a prepared template whose VMs clone image: of several, the first
// by name (`macos` before `macos-xcode-<version>`), so it does not change
// between calls.
func (t *Templates) Name(image string) (string, bool) {
	if t == nil {
		return "", false
	}
	t.mu.RLock()
	defer t.mu.RUnlock()
	found := ""
	for name, candidate := range t.images {
		if candidate == image && (found == "" || name < found) {
			found = name
		}
	}
	return found, found != ""
}

// Images lists the prepared templates' images.
func (t *Templates) Images() []string {
	if t == nil {
		return nil
	}
	t.mu.RLock()
	defer t.mu.RUnlock()
	images := make([]string, 0, len(t.images))
	for _, image := range t.images {
		images = append(images, image)
	}
	return images
}

func (t *Templates) set(template, image string) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.images[template] = image
}

func (t *Templates) replace(images map[string]string) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.images = map[string]string{}
	for name, image := range images {
		t.images[name] = image
	}
}
