package driver

import "regexp"

// Only in-process calls made while holding the pool lock carry this marker.
// Nested child lifecycle calls still acquire their own volume lock.
type borrowedPoolLock struct{}

var childVolumeIDPattern = regexp.MustCompile(`^(pvc-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})-unit-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$`)

// BorrowedRequest always names the stable parent and its current pod generation.
// UnitID is immutable and never reused after release. Useful capacity is distinct
// from the full device commitment reported by ThinStatus.
type BorrowedRequest struct {
	ThinRequest
	UnitID     string `json:"unit_id"`
	CacheBytes int64  `json:"cache_bytes"`
	Action     string `json:"action"`
}

// One durable operation is retained for bounded retry/recovery. A lost response
// must not turn a retry into a second grant or resurrect a released unit.
type BorrowedOperation struct {
	ID         string `json:"id"`
	Generation uint64 `json:"generation"`
	UnitID     string `json:"unit_id"`
	Action     string `json:"action"`
	CacheBytes int64  `json:"cache_bytes"`
	Done       bool   `json:"done"`
}
