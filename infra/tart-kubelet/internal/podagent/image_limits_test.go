package podagent

import "testing"

func TestParseImageCurrentSectors(t *testing.T) {
	tests := []struct {
		name string
		out  string
		want uint64
	}{
		{
			name: "plain limits",
			out:  "45056\t2097072\t274877906864\n",
			want: 2097072,
		},
		{
			name: "limits after a deprecation warning",
			out:  "hdiutil: WARNING: 'hdiutil resize ...' is deprecated. Please use 'diskutil image resize ...' instead.\n37797888\t62914560\t274877497264\n",
			want: 62914560,
		},
		{
			name: "limits followed by a trailing note",
			out:  "37797888\t62914560\t274877497264\nhdiutil: note: something 1 2 3\n",
			want: 62914560,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := parseImageCurrentSectors(tt.out)
			if err != nil {
				t.Fatalf("parseImageCurrentSectors: %v", err)
			}
			if got != tt.want {
				t.Fatalf("parseImageCurrentSectors = %d, want %d", got, tt.want)
			}
		})
	}
}

func TestParseImageCurrentSectorsRejectsOutputWithoutLimits(t *testing.T) {
	for _, out := range []string{
		"",
		"hdiutil: WARNING: 'hdiutil resize ...' is deprecated.\n",
		"45056\t2097072\n",
		"45056\t-1\t274877906864\n",
		"1 2 3 4\n",
	} {
		if got, err := parseImageCurrentSectors(out); err == nil {
			t.Errorf("parseImageCurrentSectors(%q) = %d, want an error", out, got)
		}
	}
}
