//go:build darwin

package podagent

import (
	"runtime"
	"sync"

	"github.com/ebitengine/purego"
)

// setiopolicy_np arguments (<sys/resource.h>).
const (
	iopolTypeDisk    = 0
	iopolScopeThread = 1
	iopolThrottle    = 3
)

var setIOPolicy = sync.OnceValue(func() func(int32, int32, int32) int32 {
	lib, err := purego.Dlopen("/usr/lib/libSystem.B.dylib", purego.RTLD_NOW|purego.RTLD_GLOBAL)
	if err != nil {
		return nil
	}
	if _, err := purego.Dlsym(lib, "setiopolicy_np"); err != nil {
		return nil
	}
	var fn func(int32, int32, int32) int32
	purego.RegisterLibFunc(&fn, lib, "setiopolicy_np")
	return fn
})

// withThrottledIO runs fn on an OS thread whose disk I/O macOS throttles, as
// `taskpolicy -b` does for a whole process, so the writes fn makes yield to the
// host's running VMs. fn must do its disk writes on its own goroutine, as the
// cache-volume download and restore do. The thread is never unlocked: it exits
// with the goroutine and takes the policy with it, so no other work inherits
// it. Without setiopolicy_np, fn runs unthrottled.
func withThrottledIO(fn func()) {
	done := make(chan struct{})
	go func() {
		defer close(done)
		runtime.LockOSThread()
		if set := setIOPolicy(); set != nil {
			set(iopolTypeDisk, iopolScopeThread, iopolThrottle)
		}
		fn()
	}()
	<-done
}
