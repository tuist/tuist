package podagent

import "errors"

// availableBytes is the volume's free space within its budget, capped by the
// host's physical free space above the golden-image reclaim floor. Running
// cache reservations are subtracted by callers.
func (m *CacheSpace) availableBytes() (uint64, error) {
	free, err := m.volumeFreeBytes()
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

func (m *CacheSpace) budgetBytes() uint64 { return uint64(m.BudgetGiB) * 1024 * 1024 * 1024 }

// volumeFreeBytes is the volume's free space, less what it uses beyond
// BudgetGiB.
func (m *CacheSpace) volumeFreeBytes() (uint64, error) {
	free, err := m.backend.freeBytes(m.Root)
	if err != nil || m.BudgetGiB <= 0 {
		return free, err
	}
	used, err := m.backend.usedBytes(m.Root)
	if err != nil {
		return 0, err
	}
	return min(free, saturatingSub(m.budgetBytes(), used)), nil
}

// volumeCapacityBytes is the volume's quota, or BudgetGiB when that is lower.
func (m *CacheSpace) volumeCapacityBytes() (uint64, error) {
	capacity, err := m.backend.capacityBytes(m.Root)
	if err != nil || m.BudgetGiB <= 0 {
		return capacity, err
	}
	return min(capacity, m.budgetBytes()), nil
}

// hardFreeBytes is the space writes can take before they fail: the volume's
// free space under its APFS quota, or the host's physical free space when that
// is lower. Unlike availableBytes it ignores the budget and the host floor.
func (m *CacheSpace) hardFreeBytes() (uint64, error) {
	free, err := m.backend.freeBytes(m.Root)
	if err != nil || m.HostDiskSpace == nil {
		return free, err
	}
	host, err := m.HostDiskSpace()
	if err != nil {
		return 0, err
	}
	return min(free, host.FreeBytes), nil
}
