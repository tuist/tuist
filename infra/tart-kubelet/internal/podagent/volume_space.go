package podagent

import "errors"

// availableBytes is the quota headroom capped by the host's physical free
// space above the golden-image reclaim floor. Running cache reservations are
// subtracted by callers; Stats continues to expose the raw filesystem value.
func (m *VolumeManager) availableBytes() (uint64, error) {
	free, err := m.backend.freeBytes(m.Root)
	if err != nil || m.HostDiskSpace == nil {
		return free, err
	}
	host, err := m.HostDiskSpace()
	if err != nil {
		return 0, err
	}
	if host.TotalBytes == 0 {
		return 0, errors.New("host disk capacity unavailable")
	}
	floor := uint64(float64(host.TotalBytes) * defaultGoldenReclaimFreeFloor / 100)
	return min(free, saturatingSub(host.FreeBytes, floor)), nil
}
