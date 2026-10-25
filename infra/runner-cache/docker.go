package cachevolumes

import (
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"time"
)

// KindDocker is a repository's Docker data root. The guest loop-mounts the
// branch image itself, because overlay2 needs a filesystem native to the guest
// kernel, so the host never mounts it: it exposes the unmounted image, checks
// only fixed superblock fields after the VM is gone, and publishes its extents.
const KindDocker = "docker"

const (
	// DockerVolumeBytes is a data root's logical size, the room a job had on the
	// ephemeral data root it replaces.
	DockerVolumeBytes = 100_000_000_000
	// DockerPublishBytes bounds what a data root may save.
	DockerPublishBytes = 30_000_000_000
	// DockerGrowthBytes is what admission reserves above the saved data root for
	// the job's pulls and container layers.
	DockerGrowthBytes = 20_000_000_000
	// DockerImageName is the branch image's name in the pod's directory.
	DockerImageName = "docker.img"
	// DockerReportName is the guest's teardown report beside the image.
	DockerReportName = "docker.json"
)

const dockerReportLimit = 512 << 10
const dockerImageLimit = 500
const dockerReferenceLimit = 16

var dockerImageID = regexp.MustCompile(`^sha256:[a-f0-9]{64}$`)
var dockerReference = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9._/:@-]{0,254}$`)

// DockerReport is what the guest's sidecar writes after it removed the job's
// containers, volumes and image tags and unmounted the data root. It is guest
// written: it can only withhold a publication, never force one.
type DockerReport struct {
	// Clean is set only after a clean unmount.
	Clean bool `json:"clean"`
	// Changed reports whether the set of images or build-cache records differs
	// from the one the job mounted.
	Changed         bool          `json:"changed"`
	Images          []DockerImage `json:"images"`
	BuildCacheBytes int64         `json:"build_cache_bytes"`
}

// DockerImage is one image the data root keeps, with the references the jobs
// used for it and when one last pulled, ran or built it.
type DockerImage struct {
	ID         string    `json:"id"`
	References []string  `json:"references"`
	SizeBytes  int64     `json:"size_bytes"`
	LastUsedAt time.Time `json:"last_used_at"`
}

var errNoDockerReport = fmt.Errorf("%w: no teardown report", ErrWithheld)

// ErrSuperseded withholds a data root whose lineage another job saved since it
// was mounted: it could only lose the compare-and-swap, so it is not compressed.
var ErrSuperseded = fmt.Errorf("%w: superseded", ErrWithheld)

// ReadDockerReport reads and validates the guest's report in the pod's volume
// directory without following links. Anything malformed is no report.
func ReadDockerReport(path string) (DockerReport, error) {
	var report DockerReport
	root, err := os.OpenRoot(path)
	if err != nil {
		return report, err
	}
	defer root.Close()
	info, err := root.Lstat(DockerReportName)
	if err != nil {
		return report, err
	}
	if !info.Mode().IsRegular() || info.Size() > dockerReportLimit {
		return report, errors.New("invalid docker report")
	}
	file, err := root.Open(DockerReportName)
	if err != nil {
		return report, err
	}
	defer file.Close()
	if err = json.NewDecoder(io.LimitReader(file, dockerReportLimit)).Decode(&report); err != nil {
		return DockerReport{}, err
	}
	if !validDockerReport(report) {
		return DockerReport{}, errors.New("invalid docker report")
	}
	return report, nil
}

func validDockerReport(report DockerReport) bool {
	if len(report.Images) > dockerImageLimit || report.BuildCacheBytes < 0 {
		return false
	}
	for _, image := range report.Images {
		if !dockerImageID.MatchString(image.ID) || image.SizeBytes < 0 || len(image.References) > dockerReferenceLimit {
			return false
		}
		for _, reference := range image.References {
			if !dockerReference.MatchString(reference) {
				return false
			}
		}
	}
	return true
}

// exposeDocker links the branch image into the pod's directory, which the
// guest sees over virtio-fs. A retried attach finds the same link.
func (b *LocalImages) exposeDocker(slot Slot, path string) error {
	image := b.image(slot)
	link := filepath.Join(path, DockerImageName)
	if err := os.Link(image, link); errors.Is(err, os.ErrExist) {
		if !sameFile(image, link) {
			return errors.New("docker image link replaced")
		}
	} else if err != nil {
		return err
	}
	return writeMarker(slot, path)
}

// sameFile reports whether link, never followed, is the image itself.
func sameFile(image, link string) bool {
	a, err := os.Stat(image)
	if err != nil {
		return false
	}
	b, err := os.Lstat(link)
	return err == nil && b.Mode().IsRegular() && os.SameFile(a, b)
}

// measureDocker reports the bytes the image's blocks take and its logical size.
func (b *LocalImages) measureDocker(slot Slot) (int64, int64, error) {
	info, err := os.Stat(b.image(slot))
	if err != nil {
		return 0, 0, err
	}
	return allocatedBytes(b.image(slot)), info.Size(), nil
}

// verifyDocker checks a guest-written image without interpreting it: the pod's
// link must still be the branch, and the superblock must record a clean unmount
// with no errors. It never mounts or fscks the image on the host.
func (b *LocalImages) verifyDocker(slot Slot, path string) error {
	if !sameFile(b.image(slot), filepath.Join(path, DockerImageName)) {
		return fmt.Errorf("%w: docker image replaced", ErrPoisoned)
	}
	if err := ext4Clean(b.image(slot)); err != nil {
		return errors.Join(ErrPoisoned, err)
	}
	return nil
}

func (b *LocalImages) sealDocker(slot Slot, path string) error {
	if b.Cold(slot) && !slot.PublishCold {
		return ErrWithheld
	}
	report, err := ReadDockerReport(path)
	if err != nil || !report.Clean {
		return errNoDockerReport
	}
	if err := b.verifyDocker(slot, path); err != nil {
		return err
	}
	if !report.Changed {
		b.keepUnchanged(slot, func() error { return b.verifyDocker(slot, path) })
		return ErrUnchanged
	}
	if allocatedBytes(b.image(slot)) > DockerPublishBytes {
		return ErrFull
	}
	if heads, ok := b.Transfer.(HeadReader); ok {
		if head, err := heads.Head(slot); errors.Is(err, ErrConflict) || (err == nil && head.BaseGeneration != slot.BaseGeneration) {
			return ErrSuperseded
		}
	}
	return b.publish(slot)
}

// releaseDocker removes the pod's directory, which holds only guest-written
// files and the image's link, and the branch image.
func (b *LocalImages) releaseDocker(slot Slot, path string, suffixes []string) error {
	if err := os.RemoveAll(path); err != nil {
		return err
	}
	_ = os.Remove(filepath.Dir(path))
	for _, suffix := range suffixes {
		if err := os.Remove(b.image(slot) + suffix); err != nil && !os.IsNotExist(err) {
			return err
		}
	}
	return nil
}

// ext4Clean reads the superblock's fixed fields: a filesystem the guest
// unmounted cleanly has no journal to recover and recorded no errors.
func ext4Clean(image string) error {
	f, err := os.Open(image)
	if err != nil {
		return err
	}
	defer f.Close()
	var sb [1024]byte
	if _, err = f.ReadAt(sb[:], 1024); err != nil {
		return err
	}
	if binary.LittleEndian.Uint16(sb[0x38:]) != 0xEF53 {
		return errors.New("not an ext4 filesystem")
	}
	state := binary.LittleEndian.Uint16(sb[0x3A:])
	incompat := binary.LittleEndian.Uint32(sb[0x60:])
	errorCount := binary.LittleEndian.Uint32(sb[0x194:])
	switch {
	case incompat&0x4 != 0:
		return errors.New("ext4 journal needs recovery: not unmounted cleanly")
	case state&0x1 == 0 || state&0x2 != 0 || errorCount != 0:
		return errors.New("ext4 recorded errors")
	}
	return nil
}

// dockerFormatArgs format a data root's empty image with its inode tables and
// journal zeroed, which costs nothing on a sparse file and leaves the guest's
// kernel no background zeroing to do.
var dockerFormatArgs = []string{"-F", "-q", "-m", "0", "-E", "lazy_itable_init=0,lazy_journal_init=0,nodiscard"}
