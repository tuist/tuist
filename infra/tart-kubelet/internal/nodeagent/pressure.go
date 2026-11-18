package nodeagent

import "fmt"

func memoryPressure(level uint32) (bool, string, error) {
	switch level {
	case 1:
		return false, "macOS memory pressure is normal", nil
	case 2, 4:
		return true, fmt.Sprintf("macOS memory pressure level %d", level), nil
	default:
		return false, "", fmt.Errorf("unknown macOS memory pressure level %d", level)
	}
}

func pidPressure(count, limit uint64) (bool, string, error) {
	if limit == 0 || count == 0 {
		return false, "", fmt.Errorf("invalid process count/limit %d/%d", count, limit)
	}
	// Leave ten percent of the global process table available for host work.
	return count >= limit-limit/10, fmt.Sprintf("%d/%d host process slots used", count, limit), nil
}
