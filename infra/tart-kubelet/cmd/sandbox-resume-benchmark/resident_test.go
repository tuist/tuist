package main

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestResidentReplyMustMatchRequestAndState(t *testing.T) {
	for _, failure := range []string{"", "wrong_state", "error", "wrong_action", "invalid_pid"} {
		t.Run(failure, func(t *testing.T) {
			dir := t.TempDir()
			ctx, cancel := context.WithTimeout(t.Context(), time.Second)
			defer cancel()
			// A valid but stale reply must not acknowledge this transition.
			old, _ := json.Marshal(residentReply{ID: "old", Action: "resume", State: "running", PID: 42})
			if err := os.WriteFile(filepath.Join(dir, "resident-reply.json"), old, 0600); err != nil {
				t.Fatal(err)
			}
			server := make(chan error, 1)
			go func() {
				for {
					data, err := os.ReadFile(filepath.Join(dir, "resident-request.json"))
					if err == nil {
						var request map[string]string
						if err := json.Unmarshal(data, &request); err != nil {
							server <- err
							return
						}
						reply := residentReply{ID: request["id"], Action: request["action"], State: "running", PID: 123, APIMS: 2}
						switch failure {
						case "wrong_state":
							reply.State = "paused"
						case "error":
							reply.Error = "invalid transition"
						case "wrong_action":
							reply.Action = "pause"
						case "invalid_pid":
							reply.PID = 0
						}
						data, _ = json.Marshal(reply)
						err = os.WriteFile(filepath.Join(dir, "reply.tmp"), data, 0600)
						if err == nil {
							err = os.Rename(filepath.Join(dir, "reply.tmp"), filepath.Join(dir, "resident-reply.json"))
						}
						server <- err
						return
					}
					select {
					case <-ctx.Done():
						server <- ctx.Err()
						return
					case <-time.After(time.Millisecond):
					}
				}
			}()
			reply, err := residentCommand(ctx, dir, "resume")
			if (err != nil) != (failure != "") {
				t.Fatalf("reply=%+v err=%v", reply, err)
			}
			if failure == "" && reply.PID != 123 {
				t.Fatal("accepted stale acknowledgement")
			}
			if err := <-server; err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestResidentMissingReplyHonorsDeadline(t *testing.T) {
	ctx, cancel := context.WithTimeout(t.Context(), 20*time.Millisecond)
	defer cancel()
	if _, err := residentCommand(ctx, t.TempDir(), "pause"); err != context.DeadlineExceeded {
		t.Fatalf("unacknowledged pause: %v", err)
	}
}

func TestResidentCanceledRequestDoesNotPauseVM(t *testing.T) {
	dir := t.TempDir()
	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	if _, err := residentCommand(ctx, dir, "pause"); err != context.Canceled {
		t.Fatalf("canceled pause: %v", err)
	}
	if _, err := os.Stat(filepath.Join(dir, "resident-request.json")); !os.IsNotExist(err) {
		t.Fatal("published a canceled request")
	}
}

func TestResidentModeCannotPretendToReleaseCapacity(t *testing.T) {
	o := options{home: t.TempDir(), kubeletHome: t.TempDir(), source: "base", mode: "resident", memory: 8192, cpus: 8,
		cycles: 1, timeout: time.Minute, acquire: "reservation.sh", build: "build.sh"}
	t.Setenv("TUIST_RESIDENT_BENCHMARK", "")
	if err := o.validate(); err == nil {
		t.Fatal("resident mode accepted without opt-in runtime")
	}
	t.Setenv("TUIST_RESIDENT_BENCHMARK", "1")
	o.between = "ci-workload.sh"
	if err := o.validate(); err == nil {
		t.Fatal("resident pause accepted a released-capacity workload hook")
	}
	o.between = ""
	if err := o.validate(); err != nil {
		t.Fatal(err)
	}
}
