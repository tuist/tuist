//go:build darwin

package sensors

import (
	"encoding/binary"
	"errors"
	"fmt"
	"unsafe"

	"github.com/ebitengine/purego"
)

// The frameworks are called through purego rather than cgo, so the binary
// cross-builds from Linux with CGO_ENABLED=0 like every other host binary in
// the operator image. node_exporter's own Apple silicon collector uses the
// same HID calls, but through cgo, which is why the fleet can only take it
// as an upstream release.

const (
	cfStringEncodingUTF8 = 0x08000100
	cfNumberSInt32Type   = 3

	// kIOHIDEventTypeTemperature, and the page and usage the temperature
	// services are published under.
	hidTemperatureEvent = 15
	hidVendorPage       = 0xff00
	hidTemperatureUsage = 5

	// SMCKeyData_t is 80 bytes; these are the offsets of the fields read or
	// written, as AppleSMC's user client lays the struct out.
	smcStructSize     = 80
	smcOffsetKey      = 0
	smcOffsetDataSize = 28
	smcOffsetDataType = 32
	smcOffsetResult   = 40
	smcOffsetCommand  = 42
	smcOffsetBytes    = 48
	smcSelector       = 2
	smcReadKeyInfo    = 9
	smcReadBytes      = 5

	thermalPressureNotification = "com.apple.system.thermalpressurelevel"
)

type frameworks struct {
	cfNumberCreate            func(alloc uintptr, numberType int64, value unsafe.Pointer) uintptr
	cfStringCreateWithCString func(alloc uintptr, s string, encoding uint32) uintptr
	cfDictionaryCreate        func(alloc uintptr, keys, values unsafe.Pointer, count int64, keyCallBacks, valueCallBacks uintptr) uintptr
	cfArrayGetCount           func(array uintptr) int64
	cfArrayGetValueAtIndex    func(array uintptr, index int64) uintptr
	cfRelease                 func(ref uintptr)
	cfStringGetCString        func(s uintptr, buffer unsafe.Pointer, size int64, encoding uint32) bool
	cfGetTypeID               func(ref uintptr) uint64
	cfStringGetTypeID         func() uint64
	keyCallBacks              uintptr
	valueCallBacks            uintptr

	hidClientCreate         func(alloc uintptr) uintptr
	hidClientSetMatching    func(client, matching uintptr)
	hidClientCopyServices   func(client uintptr) uintptr
	hidServiceCopyProperty  func(service, key uintptr) uintptr
	hidServiceCopyEvent     func(service uintptr, eventType int64, options int32, timestamp int64) uintptr
	hidEventGetFloatValue   func(event uintptr, field int32) float64
	ioServiceMatching       func(name string) uintptr
	ioServiceGetMatching    func(mainPort uint32, matching uintptr) uint32
	ioServiceOpen           func(service uint32, task uint32, connectionType uint32, connection *uint32) int32
	ioServiceClose          func(connection uint32) int32
	ioObjectRelease         func(object uint32) int32
	ioConnectCallStructFunc func(connection uint32, selector uint32, in unsafe.Pointer, inSize uintptr, out unsafe.Pointer, outSize *uintptr) int32
	// The kernel trap behind mach_task_self(), which C reads from a variable
	// this binary has no safe way to dereference.
	taskSelf func() uint32

	notifyRegisterCheck func(name string, token *int32) uint32
	notifyGetState      func(token int32, state *uint64) uint32
}

func load() (*frameworks, error) {
	open := func(path string) (uintptr, error) {
		return purego.Dlopen(path, purego.RTLD_NOW|purego.RTLD_GLOBAL)
	}
	cf, err := open("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
	if err != nil {
		return nil, err
	}
	iokit, err := open("/System/Library/Frameworks/IOKit.framework/IOKit")
	if err != nil {
		return nil, err
	}
	libSystem, err := open("/usr/lib/libSystem.B.dylib")
	if err != nil {
		return nil, err
	}

	f := &frameworks{}
	for _, fn := range []struct {
		lib  uintptr
		ptr  any
		name string
	}{
		{cf, &f.cfNumberCreate, "CFNumberCreate"},
		{cf, &f.cfStringCreateWithCString, "CFStringCreateWithCString"},
		{cf, &f.cfDictionaryCreate, "CFDictionaryCreate"},
		{cf, &f.cfArrayGetCount, "CFArrayGetCount"},
		{cf, &f.cfArrayGetValueAtIndex, "CFArrayGetValueAtIndex"},
		{cf, &f.cfRelease, "CFRelease"},
		{cf, &f.cfStringGetCString, "CFStringGetCString"},
		{cf, &f.cfGetTypeID, "CFGetTypeID"},
		{cf, &f.cfStringGetTypeID, "CFStringGetTypeID"},
		{iokit, &f.hidClientCreate, "IOHIDEventSystemClientCreate"},
		{iokit, &f.hidClientSetMatching, "IOHIDEventSystemClientSetMatching"},
		{iokit, &f.hidClientCopyServices, "IOHIDEventSystemClientCopyServices"},
		{iokit, &f.hidServiceCopyProperty, "IOHIDServiceClientCopyProperty"},
		{iokit, &f.hidServiceCopyEvent, "IOHIDServiceClientCopyEvent"},
		{iokit, &f.hidEventGetFloatValue, "IOHIDEventGetFloatValue"},
		{iokit, &f.ioServiceMatching, "IOServiceMatching"},
		{iokit, &f.ioServiceGetMatching, "IOServiceGetMatchingService"},
		{iokit, &f.ioServiceOpen, "IOServiceOpen"},
		{iokit, &f.ioServiceClose, "IOServiceClose"},
		{iokit, &f.ioObjectRelease, "IOObjectRelease"},
		{iokit, &f.ioConnectCallStructFunc, "IOConnectCallStructMethod"},
		{libSystem, &f.taskSelf, "task_self_trap"},
		{libSystem, &f.notifyRegisterCheck, "notify_register_check"},
		{libSystem, &f.notifyGetState, "notify_get_state"},
	} {
		if _, err := purego.Dlsym(fn.lib, fn.name); err != nil {
			return nil, fmt.Errorf("%s: %w", fn.name, err)
		}
		purego.RegisterLibFunc(fn.ptr, fn.lib, fn.name)
	}
	if f.keyCallBacks, err = purego.Dlsym(cf, "kCFTypeDictionaryKeyCallBacks"); err != nil {
		return nil, err
	}
	if f.valueCallBacks, err = purego.Dlsym(cf, "kCFTypeDictionaryValueCallBacks"); err != nil {
		return nil, err
	}
	return f, nil
}

// Read samples every sensor the host exposes. It returns what it could read
// together with an error for each part that failed, so one missing source
// never costs the others.
func Read() (Readings, []error) {
	f, err := load()
	if err != nil {
		return Readings{}, []error{fmt.Errorf("load frameworks: %w", err)}
	}
	var r Readings
	var errs []error
	if err := f.readTemperatures(&r); err != nil {
		errs = append(errs, fmt.Errorf("temperatures: %w", err))
	}
	if err := f.readSMC(&r); err != nil {
		errs = append(errs, fmt.Errorf("smc: %w", err))
	}
	if err := f.readThermalPressure(&r); err != nil {
		errs = append(errs, fmt.Errorf("thermal pressure: %w", err))
	}
	return r, errs
}

func (f *frameworks) cfString(s string) uintptr {
	return f.cfStringCreateWithCString(0, s, cfStringEncodingUTF8)
}

func (f *frameworks) cfInt(v int32) uintptr {
	return f.cfNumberCreate(0, cfNumberSInt32Type, unsafe.Pointer(&v))
}

func (f *frameworks) goString(ref uintptr) string {
	if ref == 0 || f.cfGetTypeID(ref) != f.cfStringGetTypeID() {
		return ""
	}
	buf := make([]byte, 256)
	if !f.cfStringGetCString(ref, unsafe.Pointer(&buf[0]), int64(len(buf)), cfStringEncodingUTF8) {
		return ""
	}
	for i, c := range buf {
		if c == 0 {
			return string(buf[:i])
		}
	}
	return string(buf)
}

func (f *frameworks) readTemperatures(r *Readings) error {
	keys := []uintptr{f.cfString("PrimaryUsagePage"), f.cfString("PrimaryUsage")}
	values := []uintptr{f.cfInt(hidVendorPage), f.cfInt(hidTemperatureUsage)}
	defer func() {
		for _, ref := range append(keys, values...) {
			f.cfRelease(ref)
		}
	}()
	matching := f.cfDictionaryCreate(0, unsafe.Pointer(&keys[0]), unsafe.Pointer(&values[0]), int64(len(keys)), f.keyCallBacks, f.valueCallBacks)
	if matching == 0 {
		return errors.New("cannot build the HID matching dictionary")
	}
	defer f.cfRelease(matching)

	client := f.hidClientCreate(0)
	if client == 0 {
		return errors.New("cannot create a HID event system client")
	}
	defer f.cfRelease(client)
	f.hidClientSetMatching(client, matching)
	services := f.hidClientCopyServices(client)
	if services == 0 {
		return errors.New("the HID event system lists no temperature services")
	}
	defer f.cfRelease(services)

	product := f.cfString("Product")
	defer f.cfRelease(product)
	for i := int64(0); i < f.cfArrayGetCount(services); i++ {
		service := f.cfArrayGetValueAtIndex(services, i)
		name := ""
		if prop := f.hidServiceCopyProperty(service, product); prop != 0 {
			name = f.goString(prop)
			f.cfRelease(prop)
		}
		event := f.hidServiceCopyEvent(service, hidTemperatureEvent, 0, 0)
		if event == 0 {
			continue
		}
		r.AddTemperature(name, f.hidEventGetFloatValue(event, hidTemperatureEvent<<16))
		f.cfRelease(event)
	}
	return nil
}

func (f *frameworks) readSMC(r *Readings) error {
	service := f.ioServiceGetMatching(0, f.ioServiceMatching("AppleSMC"))
	if service == 0 {
		return errors.New("no AppleSMC service")
	}
	defer f.ioObjectRelease(service)
	var connection uint32
	if kr := f.ioServiceOpen(service, f.taskSelf(), 0, &connection); kr != 0 {
		return fmt.Errorf("IOServiceOpen: kern_return %d", kr)
	}
	defer f.ioServiceClose(connection)

	value := func(key string) *float64 {
		dataType, data, err := f.smcRead(connection, key)
		if err != nil {
			return nil
		}
		v, ok := DecodeSMC(dataType, data)
		if !ok {
			return nil
		}
		return &v
	}

	if fans := value("FNum"); fans != nil {
		for i := 0; i < int(*fans); i++ {
			fan := Fan{
				Index:  i,
				Speed:  value(fmt.Sprintf("F%dAc", i)),
				Target: value(fmt.Sprintf("F%dTg", i)),
				Max:    value(fmt.Sprintf("F%dMx", i)),
			}
			if fan.Speed != nil || fan.Target != nil || fan.Max != nil {
				r.Fans = append(r.Fans, fan)
			}
		}
	}
	r.PowerWatts = value("PSTR")
	return nil
}

// smcRead reads one key: its type and size first, then its bytes.
func (f *frameworks) smcRead(connection uint32, key string) (string, []byte, error) {
	if len(key) != 4 {
		return "", nil, fmt.Errorf("SMC key %q is not four characters", key)
	}
	var in, out [smcStructSize]byte
	binary.LittleEndian.PutUint32(in[smcOffsetKey:], binary.BigEndian.Uint32([]byte(key)))
	in[smcOffsetCommand] = smcReadKeyInfo
	if err := f.smcCall(connection, &in, &out); err != nil {
		return "", nil, fmt.Errorf("%s: %w", key, err)
	}
	size := binary.LittleEndian.Uint32(out[smcOffsetDataSize:])
	if size > smcStructSize-smcOffsetBytes {
		return "", nil, fmt.Errorf("%s: data size %d", key, size)
	}
	dataType := make([]byte, 4)
	binary.BigEndian.PutUint32(dataType, binary.LittleEndian.Uint32(out[smcOffsetDataType:]))

	binary.LittleEndian.PutUint32(in[smcOffsetDataSize:], size)
	in[smcOffsetCommand] = smcReadBytes
	out = [smcStructSize]byte{}
	if err := f.smcCall(connection, &in, &out); err != nil {
		return "", nil, fmt.Errorf("%s: %w", key, err)
	}
	return string(dataType), append([]byte(nil), out[smcOffsetBytes:smcOffsetBytes+int(size)]...), nil
}

func (f *frameworks) smcCall(connection uint32, in, out *[smcStructSize]byte) error {
	size := uintptr(smcStructSize)
	if kr := f.ioConnectCallStructFunc(connection, smcSelector, unsafe.Pointer(&in[0]), smcStructSize, unsafe.Pointer(&out[0]), &size); kr != 0 {
		return fmt.Errorf("kern_return %d", kr)
	}
	if result := out[smcOffsetResult]; result != 0 {
		return fmt.Errorf("SMC result %d", result)
	}
	return nil
}

func (f *frameworks) readThermalPressure(r *Readings) error {
	var token int32
	if status := f.notifyRegisterCheck(thermalPressureNotification, &token); status != 0 {
		return fmt.Errorf("notify_register_check: status %d", status)
	}
	var state uint64
	if status := f.notifyGetState(token, &state); status != 0 {
		return fmt.Errorf("notify_get_state: status %d", status)
	}
	r.ThermalPressure = &state
	return nil
}
