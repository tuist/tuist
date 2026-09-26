// Package sensors reads a Mac's hardware sensors and renders them in the
// Prometheus text format for node_exporter's textfile collector.
package sensors

import (
	"encoding/binary"
	"fmt"
	"math"
	"sort"
	"strconv"
	"strings"
)

// absoluteZeroCelsius is what a HID temperature service reports when it has
// no reading.
const absoluteZeroCelsius = -273.15

// Readings is one sample of the host's sensors. A field the host does not
// have, or that could not be read, is absent rather than zero.
type Readings struct {
	// Temperature per HID sensor name, in Celsius. Several services share a
	// name (Apple silicon lists each die sensor three times, a few tenths of a
	// degree apart), and the hottest of them is kept, so a name maps to one
	// stable series across reboots.
	Temperatures map[string]float64
	Fans         []Fan
	// Total system power the SMC measures (PSTR), in watts.
	PowerWatts *float64
	// macOS thermal pressure: 0 nominal, 1 moderate, 2 heavy, 3 trapping,
	// 4 sleeping.
	ThermalPressure *uint64
}

// Fan is one fan as the SMC reports it.
type Fan struct {
	Index  int
	Speed  *float64
	Target *float64
	Max    *float64
}

// AddTemperature records a reading for name, keeping the hottest reading per
// name and ignoring a service that has none.
func (r *Readings) AddTemperature(name string, celsius float64) {
	if name == "" || math.IsNaN(celsius) || math.IsInf(celsius, 0) || celsius <= absoluteZeroCelsius {
		return
	}
	if r.Temperatures == nil {
		r.Temperatures = map[string]float64{}
	}
	if current, ok := r.Temperatures[name]; !ok || celsius > current {
		r.Temperatures[name] = celsius
	}
}

// Format renders the readings in the Prometheus text exposition format, in a
// stable order.
func Format(r Readings) string {
	var b strings.Builder
	if len(r.Temperatures) > 0 {
		header(&b, "macos_sensor_temperature_celsius",
			"Temperature of a hardware sensor, the hottest reading among the HID sensors that share its name.")
		names := make([]string, 0, len(r.Temperatures))
		for name := range r.Temperatures {
			names = append(names, name)
		}
		sort.Strings(names)
		for _, name := range names {
			fmt.Fprintf(&b, "macos_sensor_temperature_celsius{sensor=\"%s\"} %s\n", escape(name), number(r.Temperatures[name]))
		}
	}
	fanMetric(&b, r.Fans, "macos_fan_speed_rpm", "Fan speed the SMC measures.", func(f Fan) *float64 { return f.Speed })
	fanMetric(&b, r.Fans, "macos_fan_target_rpm",
		"Fan speed the SMC is asking for. A fan running well below its target is failing.", func(f Fan) *float64 { return f.Target })
	fanMetric(&b, r.Fans, "macos_fan_max_rpm", "Highest speed the fan is rated for.", func(f Fan) *float64 { return f.Max })
	if r.PowerWatts != nil {
		header(&b, "macos_system_power_watts", "Total system power the SMC measures.")
		fmt.Fprintf(&b, "macos_system_power_watts %s\n", number(*r.PowerWatts))
	}
	if r.ThermalPressure != nil {
		header(&b, "macos_thermal_pressure_level",
			"macOS thermal pressure: 0 nominal, 1 moderate, 2 heavy, 3 trapping, 4 sleeping.")
		fmt.Fprintf(&b, "macos_thermal_pressure_level %d\n", *r.ThermalPressure)
	}
	return b.String()
}

func fanMetric(b *strings.Builder, fans []Fan, name, help string, value func(Fan) *float64) {
	wrote := false
	for _, f := range fans {
		v := value(f)
		if v == nil {
			continue
		}
		if !wrote {
			header(b, name, help)
			wrote = true
		}
		fmt.Fprintf(b, "%s{fan=\"%d\"} %s\n", name, f.Index, number(*v))
	}
}

func header(b *strings.Builder, name, help string) {
	fmt.Fprintf(b, "# HELP %s %s\n# TYPE %s gauge\n", name, help, name)
}

func number(v float64) string {
	return strconv.FormatFloat(v, 'g', -1, 64)
}

func escape(label string) string {
	return strings.NewReplacer(`\`, `\\`, `"`, `\"`, "\n", `\n`).Replace(label)
}

// DecodeSMC reads an SMC value of the given four-character type. Apple
// silicon reports fan speeds and power as little-endian floats (`flt `); the
// integer types are big-endian, and `fpe2` is the fixed-point fan speed Intel
// Macs use.
func DecodeSMC(dataType string, data []byte) (float64, bool) {
	switch dataType {
	case "flt ":
		if len(data) < 4 {
			return 0, false
		}
		v := float64(math.Float32frombits(binary.LittleEndian.Uint32(data)))
		return v, !math.IsNaN(v) && !math.IsInf(v, 0)
	case "fpe2":
		if len(data) < 2 {
			return 0, false
		}
		return float64(binary.BigEndian.Uint16(data)) / 4, true
	case "ui8 ":
		if len(data) < 1 {
			return 0, false
		}
		return float64(data[0]), true
	case "ui16":
		if len(data) < 2 {
			return 0, false
		}
		return float64(binary.BigEndian.Uint16(data)), true
	case "ui32":
		if len(data) < 4 {
			return 0, false
		}
		return float64(binary.BigEndian.Uint32(data)), true
	}
	return 0, false
}
