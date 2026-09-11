package main

import (
	"reflect"
	"testing"
)

func TestSplitNames(t *testing.T) {
	for _, tc := range []struct {
		input string
		want  []string
	}{
		{"", nil}, {" , \t,", nil}, {"kura-a, kura-b,,\tkura-c ", []string{"kura-a", "kura-b", "kura-c"}},
	} {
		if got := splitNames(tc.input); !reflect.DeepEqual(got, tc.want) {
			t.Fatalf("%q: got %v, want %v", tc.input, got, tc.want)
		}
	}
}
