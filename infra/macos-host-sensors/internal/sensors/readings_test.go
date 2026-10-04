package sensors

import (
	"encoding/binary"
	"math"
	"testing"
)

func ptr[T any](v T) *T { return &v }

func TestAddTemperatureKeepsTheHottestReadingPerName(t *testing.T) {
	var r Readings
	r.AddTemperature("PMU tdie1", 61.2)
	r.AddTemperature("PMU tdie1", 61.5)
	r.AddTemperature("PMU tdie1", 60.9)

	if got := r.Temperatures["PMU tdie1"]; got != 61.5 {
		t.Fatalf("PMU tdie1 = %v, want the hottest of the three, 61.5", got)
	}
}

func TestAddTemperatureIgnoresServicesWithoutAReading(t *testing.T) {
	var r Readings
	r.AddTemperature("no reading", absoluteZeroCelsius)
	r.AddTemperature("not a number", math.NaN())
	r.AddTemperature("", 40)

	if len(r.Temperatures) != 0 {
		t.Fatalf("temperatures = %v, want none", r.Temperatures)
	}
}

func TestFormatRendersEveryReadingInAStableOrder(t *testing.T) {
	r := Readings{
		Fans:            []Fan{{Index: 0, Speed: ptr(1450.5), Target: ptr(1400.0), Max: ptr(4900.0)}},
		PowerWatts:      ptr(23.25),
		ThermalPressure: ptr(uint64(0)),
	}
	r.AddTemperature("PMU tdie2", 48)
	r.AddTemperature("NAND CH0 temp", 41)

	want := `# HELP macos_sensor_temperature_celsius Temperature of a hardware sensor, the hottest reading among the HID sensors that share its name.
# TYPE macos_sensor_temperature_celsius gauge
macos_sensor_temperature_celsius{sensor="NAND CH0 temp"} 41
macos_sensor_temperature_celsius{sensor="PMU tdie2"} 48
# HELP macos_fan_speed_rpm Fan speed the SMC measures.
# TYPE macos_fan_speed_rpm gauge
macos_fan_speed_rpm{fan="0"} 1450.5
# HELP macos_fan_target_rpm Fan speed the SMC is asking for. A fan running well below its target is failing.
# TYPE macos_fan_target_rpm gauge
macos_fan_target_rpm{fan="0"} 1400
# HELP macos_fan_max_rpm Highest speed the fan is rated for.
# TYPE macos_fan_max_rpm gauge
macos_fan_max_rpm{fan="0"} 4900
# HELP macos_system_power_watts Total system power the SMC measures.
# TYPE macos_system_power_watts gauge
macos_system_power_watts 23.25
# HELP macos_thermal_pressure_level macOS thermal pressure: 0 nominal, 1 moderate, 2 heavy, 3 trapping, 4 sleeping.
# TYPE macos_thermal_pressure_level gauge
macos_thermal_pressure_level 0
`
	if got := Format(r); got != want {
		t.Fatalf("Format =\n%s\nwant\n%s", got, want)
	}
}

func TestFormatOmitsWhatTheHostDoesNotHave(t *testing.T) {
	r := Readings{Fans: []Fan{{Index: 0, Speed: ptr(1200.0)}}}

	want := `# HELP macos_fan_speed_rpm Fan speed the SMC measures.
# TYPE macos_fan_speed_rpm gauge
macos_fan_speed_rpm{fan="0"} 1200
`
	if got := Format(r); got != want {
		t.Fatalf("Format =\n%s\nwant\n%s", got, want)
	}
	if got := Format(Readings{}); got != "" {
		t.Fatalf("Format of nothing = %q, want empty", got)
	}
}

func TestFormatEscapesSensorNames(t *testing.T) {
	var r Readings
	r.AddTemperature(`a "quoted" \ name`, 30)

	want := "macos_sensor_temperature_celsius{sensor=\"a \\\"quoted\\\" \\\\ name\"} 30\n"
	if got := Format(r); got[len(got)-len(want):] != want {
		t.Fatalf("Format = %q, want it to end with %q", got, want)
	}
}

func TestDecodeSMC(t *testing.T) {
	flt := make([]byte, 4)
	binary.LittleEndian.PutUint32(flt, math.Float32bits(4174.5))
	for _, tc := range []struct {
		dataType string
		data     []byte
		want     float64
		ok       bool
	}{
		{"flt ", flt, 4174.5, true},
		{"fpe2", []byte{0x16, 0x80}, 1440, true},
		{"ui8 ", []byte{2}, 2, true},
		{"ui16", []byte{0x01, 0x00}, 256, true},
		{"ui32", []byte{0, 0, 0x01, 0x00}, 256, true},
		{"flt ", []byte{1, 2}, 0, false},
		{"sp78", []byte{0x30, 0x00}, 0, false},
	} {
		got, ok := DecodeSMC(tc.dataType, tc.data)
		if ok != tc.ok || got != tc.want {
			t.Errorf("DecodeSMC(%q, % x) = %v, %v; want %v, %v", tc.dataType, tc.data, got, ok, tc.want, tc.ok)
		}
	}
}
