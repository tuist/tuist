package guest

import (
	"reflect"
	"testing"
)

func TestCacheBinds(t *testing.T) {
	mod, build := cacheDigest("~/go/pkg/mod"), cacheDigest("~/.cache/go-build")
	tests := []struct {
		name     string
		manifest string
		want     []CacheBind
	}{
		{
			name:     "two paths under their digests, sorted by target",
			manifest: `{"version":1,"paths":{"~/go/pkg/mod":"` + mod + `","~/.cache/go-build":"` + build + `"}}`,
			want: []CacheBind{
				{Spelling: "~/.cache/go-build", Source: build, Target: "/home/user/.cache/go-build"},
				{Spelling: "~/go/pkg/mod", Source: mod, Target: "/home/user/go/pkg/mod"},
			},
		},
		{
			name:     "one path keeps data",
			manifest: `{"version":1,"paths":{"~/.gradle/caches":"data"}}`,
			want:     []CacheBind{{Spelling: "~/.gradle/caches", Source: "data", Target: "/home/user/.gradle/caches"}},
		},
		{
			name:     "data claimed twice counts for neither",
			manifest: `{"version":1,"paths":{"~/a":"data","~/b":"data","~/go/pkg/mod":"` + mod + `"}}`,
			want:     []CacheBind{{Spelling: "~/go/pkg/mod", Source: mod, Target: "/home/user/go/pkg/mod"}},
		},
		{
			name:     "a digest of another spelling is not trusted",
			manifest: `{"version":1,"paths":{"~/.ssh":"` + mod + `"}}`,
		},
		{
			name: "absolute, escaping and bare home spellings are skipped",
			manifest: `{"version":1,"paths":{"/usr/local/go":"` + cacheDigest("/usr/local/go") +
				`","~/../root":"` + cacheDigest("~/../root") + `","~/":"` + cacheDigest("~/") + `","~/x/../../etc":"` + cacheDigest("~/x/../../etc") + `"}}`,
		},
		{name: "another version", manifest: `{"version":2,"paths":{"~/go/pkg/mod":"` + mod + `"}}`},
		{name: "not json", manifest: `data`},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := CacheBinds([]byte(tt.manifest), "/home/user"); !reflect.DeepEqual(got, tt.want) {
				t.Fatalf("CacheBinds() = %#v, want %#v", got, tt.want)
			}
		})
	}
}
