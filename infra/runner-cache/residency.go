package cachevolumes

import (
	"os"
	"path/filepath"
	"strings"
)

// MasterNodeLabelPrefix advertises one lineage with an installed master per
// Node label. The suffix is the first 48 characters of the lineage's scope,
// which the server derives from the volume and its generation.
const MasterNodeLabelPrefix = "tuist.dev/cache-volume-"

// MasterNodeLabels reports which lineages have a master on this host, read
// from the masters directory under root, so dispatch can prefer this host for
// jobs that attach them. A partial download or copy does not count.
func MasterNodeLabels(root string) (map[string]string, error) {
	labels := map[string]string{}
	scopes, err := os.ReadDir(filepath.Join(root, "masters"))
	if os.IsNotExist(err) {
		return labels, nil
	}
	if err != nil {
		return nil, err
	}
	for _, scope := range scopes {
		if !scope.IsDir() || !scopePattern.MatchString(scope.Name()) {
			continue
		}
		images, err := os.ReadDir(filepath.Join(root, "masters", scope.Name()))
		if err != nil {
			return nil, err
		}
		for _, image := range images {
			if image.Type().IsRegular() && strings.HasSuffix(image.Name(), ".img") {
				labels[MasterNodeLabelPrefix+scope.Name()[:48]] = "true"
				break
			}
		}
	}
	return labels, nil
}
