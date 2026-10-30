package picos

import "testing"

// What pica_sh printed on the bench S5860 for a commit it refused, with its
// reason on the line before "Commit failed.".
const refusedCommit = `Synchronizing configuration...OK.
Welcome to PICOS
tuist@PICOS> 
Execute command: configure.
Entering configuration mode.
Execute command: set interface gigabit-ethernet te-1/1/31 speed 25000.
Execute command: commit
.
all 4 ports te-1/1/29, te-1/1/30, te-1/1/31, te-1/1/32 in one group set either 25G or 10G/1G
Commit failed.
`

func TestARefusedCommitKeepsItsReason(t *testing.T) {
	err := refusal(refusedCommit)
	if err == nil {
		t.Fatal("the refusal was not found")
	}
	if err.Line != "commit" {
		t.Fatalf("line = %q", err.Line)
	}
	if want := ".\nall 4 ports te-1/1/29, te-1/1/30, te-1/1/31, te-1/1/32 in one group set either 25G or 10G/1G\nCommit failed."; err.Output != want {
		t.Fatalf("output = %q, want %q", err.Output, want)
	}
}

func TestALineThatRanIsNoRefusal(t *testing.T) {
	if err := refusal("Execute command: commit\n.\nCommit OK.\nSave done.\n"); err != nil {
		t.Fatalf("refusal = %v", err)
	}
}
