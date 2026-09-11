package bootstrap

import (
	"reflect"
	"testing"
)

// fleetWideConfigFields are the Config fields that are identical across every
// host in a fleet, and so must survive a WithPerHost overlay and feed
// HostConfigHash. Adding a field to Config means naming it here or in PerHost;
// TestConfigFieldsAreEitherFleetWideOrPerHost fails until one of them does.
//
// This list is not the mechanism that keeps the drift path honest -- the single
// PerHost definition is. It is the tripwire that makes a new Config field a
// deliberate decision about which side of the split it belongs on, because
// every past outage in this area began with that decision being made
// implicitly, by whichever construction sites the author happened to edit.
var fleetWideConfigFields = map[string]bool{
	"TartKubeletBinary":       true,
	"TartTarball":             true,
	"TailscaleBinaries":       true,
	"TailscaleTags":           true,
	"TailscaleAcceptRoutes":   true,
	"VMKuraEgressCIDR":        true,
	"VMClusterDNSIP":          true,
	"VMCachePNCIDR":           true,
	"SSHIngressAllowCIDRs":    true,
	"NodeExporterBinary":      true,
	"LogShipperBinary":        true,
	"LogShipURL":              true,
	"LogShipEnv":              true,
	"HostCPU":                 true,
	"HostMemoryMB":            true,
	"MaxPods":                 true,
	"RunnerCacheVolumeGiB":    true,
	"CacheVolumeMasterCapGiB": true,
	"CacheVolumeCASGiB":       true,
	"VNCRelayPort":            true,
	"VNCRelayPortCount":       true,
	"MinGoldensKept":          true,
}

// Every Config field is either fleet-wide or per-host, and PerHost is the
// authority on the second set. A field that is neither has no defined
// behaviour: HostConfigHash would fold it into a fleet-wide fingerprint while
// a caller set it per host, which is exactly the shape that stamps a host as
// converged to a config it never received.
func TestConfigFieldsAreEitherFleetWideOrPerHost(t *testing.T) {
	perHost := map[string]bool{}
	pt := reflect.TypeOf(PerHost{})
	for i := range pt.NumField() {
		perHost[pt.Field(i).Name] = true
	}

	ct := reflect.TypeOf(Config{})
	for i := range ct.NumField() {
		name := ct.Field(i).Name
		switch {
		case perHost[name] && fleetWideConfigFields[name]:
			t.Errorf("Config.%s is listed as both per-host and fleet-wide; it must be exactly one", name)
		case !perHost[name] && !fleetWideConfigFields[name]:
			t.Errorf("Config.%s is neither in PerHost nor in fleetWideConfigFields.\n"+
				"Decide which it is: per-host fields go in PerHost (HostConfigHash strips them, "+
				"and every push path sets them through the overlay); fleet-wide fields go in the "+
				"list above and must be set on the operator's single fleet config.", name)
		}
	}
}

// WithPerHost must replace precisely the per-host fields and leave every
// fleet-wide one untouched. This is what lets HostConfigHash strip per-host
// state by applying an empty PerHost: if the overlay touched a fleet-wide
// field the fingerprint would lose it, and if it missed a per-host field the
// fingerprint would vary per host and every machine would drift forever.
func TestWithPerHostReplacesExactlyThePerHostFields(t *testing.T) {
	fleet := nonZeroConfig(t)
	got := fleet.WithPerHost(PerHost{})

	gv, fv := reflect.ValueOf(got), reflect.ValueOf(fleet)
	ct := reflect.TypeOf(Config{})
	for i := range ct.NumField() {
		name := ct.Field(i).Name
		zeroed := gv.Field(i).IsZero()
		if fleetWideConfigFields[name] && zeroed {
			t.Errorf("WithPerHost cleared fleet-wide Config.%s; HostConfigHash would stop tracking it", name)
		}
		if !fleetWideConfigFields[name] && !zeroed {
			t.Errorf("WithPerHost left per-host Config.%s set to %v; the fleet fingerprint would vary per host",
				name, gv.Field(i).Interface())
		}
	}
	_ = fv
}

// nonZeroConfig builds a Config with every field set to a distinctive non-zero
// value, so a field the overlay silently drops cannot coincidentally match the
// zero it was supposed to keep.
func nonZeroConfig(t *testing.T) Config {
	t.Helper()
	var cfg Config
	v := reflect.ValueOf(&cfg).Elem()
	for i := range v.NumField() {
		f := v.Field(i)
		switch f.Kind() {
		case reflect.String:
			f.SetString("x")
		case reflect.Int, reflect.Int32, reflect.Int64:
			f.SetInt(7)
		case reflect.Uint, reflect.Uint32, reflect.Uint64:
			f.SetUint(7)
		case reflect.Bool:
			f.SetBool(true)
		case reflect.Slice:
			f.Set(reflect.MakeSlice(f.Type(), 1, 1))
			if f.Type().Elem().Kind() == reflect.String {
				f.Index(0).SetString("x")
			} else {
				f.Index(0).Set(reflect.New(f.Type().Elem()).Elem())
				if f.Type().Elem().Kind() == reflect.Uint8 {
					f.Index(0).SetUint(1)
				}
			}
		case reflect.Map:
			m := reflect.MakeMap(f.Type())
			m.SetMapIndex(reflect.ValueOf("k"), reflect.ValueOf("v"))
			f.Set(m)
		case reflect.Ptr:
			f.Set(reflect.New(f.Type().Elem()))
		default:
			t.Fatalf("nonZeroConfig does not know how to fill Config.%s (kind %s); teach it", v.Type().Field(i).Name, f.Kind())
		}
	}
	return cfg
}
