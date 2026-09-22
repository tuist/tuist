// Package cachevolumes journals private snapshot clones. The server owns cache
// identity, generations, publication and analytics; the agent fences writers.
package cachevolumes

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sync"
	"time"
)

var component = regexp.MustCompile(`^[a-zA-Z0-9-]{1,128}$`)
var scopePattern = regexp.MustCompile(`^[a-f0-9]{64}$`)
var idPattern = regexp.MustCompile(`^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$`)

type Identity struct {
	ID         string `json:"id"`
	Account    int64  `json:"account_id"`
	Scope      string `json:"scope"`
	ParentID   string `json:"parent_id"`
	CanPublish bool   `json:"can_publish"`
	UID        int    `json:"uid"`
}
type Slot struct {
	Identity
	PodUID        string    `json:"pod_uid"`
	PodName       string    `json:"pod_name"`
	State         string    `json:"state"`
	Warm          bool      `json:"warm"`
	AttachMS      int64     `json:"attach_ms"`
	SizeBytes     *int64    `json:"size_bytes"`
	CapacityBytes *int64    `json:"capacity_bytes"`
	UsedAt        time.Time `json:"used_at"`
}

// Backend owns storage operations and must make every operation restart-safe.
// Seal and Delete may run only once both teardown fences have passed.
type Backend interface {
	Attach(Slot, string) error
	Measure(Slot, string) (int64, int64, error)
	Seal(Slot, string) error
	Delete(Slot, string) error
}
type leaseLock struct {
	mu    sync.Mutex
	users int
}
type Store struct {
	mu       sync.Mutex
	locks    map[string]*leaseLock
	root     *os.Root
	path     string
	backend  Backend
	MaxSlots int
}

func Open(path string, backend Backend) (*Store, error) {
	if err := os.MkdirAll(path, 0700); err != nil {
		return nil, err
	}
	root, err := os.OpenRoot(path)
	if err != nil {
		return nil, err
	}
	for _, dir := range []string{"state", "pods"} {
		if err := root.MkdirAll(dir, 0755); err != nil {
			root.Close()
			return nil, err
		}
	}
	return &Store{root: root, path: path, backend: backend, MaxSlots: 100, locks: map[string]*leaseLock{}}, nil
}
func (s *Store) Close() error { return s.root.Close() }
func (s *Store) activePath(slot Slot) string {
	return filepath.Join(s.path, "pods", slot.PodUID, slot.Scope)
}
func (s *Store) slots() ([]Slot, error) {
	dir, err := s.root.Open("state")
	if err != nil {
		return nil, err
	}
	defer dir.Close()
	names, err := dir.Readdirnames(-1)
	if err != nil {
		return nil, err
	}
	slots := []Slot{}
	for _, name := range names {
		if filepath.Ext(name) != ".json" {
			continue
		}
		b, err := s.root.ReadFile("state/" + name)
		if os.IsNotExist(err) {
			continue
		}
		if err != nil {
			return nil, err
		}
		var slot Slot
		if err = json.Unmarshal(b, &slot); err != nil {
			return nil, err
		}
		if !valid(slot.Identity, slot.PodName, slot.PodUID) || name != slot.ID+".json" {
			return nil, errors.New("invalid cache journal")
		}
		slots = append(slots, slot)
	}
	return slots, nil
}
func valid(identity Identity, pod, uid string) bool {
	return idPattern.MatchString(identity.ID) && identity.Account > 0 && scopePattern.MatchString(identity.Scope) && component.MatchString(pod) && component.MatchString(uid) && (identity.ParentID == "" || idPattern.MatchString(identity.ParentID)) && identity.UID >= 0
}
func (s *Store) save(slot Slot) error {
	b, err := json.Marshal(slot)
	if err != nil {
		return err
	}
	name := "state/" + slot.ID + ".json"
	f, err := s.root.OpenFile(name+".tmp", os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	_, err = f.Write(b)
	if err == nil {
		err = f.Sync()
	}
	closeErr := f.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	if err = s.root.Rename(name+".tmp", name); err != nil {
		return err
	}
	dir, err := s.root.Open("state")
	if err != nil {
		return err
	}
	defer dir.Close()
	return dir.Sync()
}

// Serialize one lease without blocking unrelated attachment behind a flatten.
func (s *Store) lock(id string) func() {
	s.mu.Lock()
	lock := s.locks[id]
	if lock == nil {
		lock = &leaseLock{}
		s.locks[id] = lock
	}
	lock.users++
	s.mu.Unlock()
	lock.mu.Lock()
	return func() {
		lock.mu.Unlock()
		s.mu.Lock()
		lock.users--
		if lock.users == 0 {
			delete(s.locks, id)
		}
		s.mu.Unlock()
	}
}
func (s *Store) Acquire(identity Identity, pod, uid string) (bool, error) {
	if !valid(identity, pod, uid) {
		return false, errors.New("invalid identity")
	}
	unlock := s.lock(identity.ID)
	defer unlock()
	s.mu.Lock()
	slot, err := s.allocate(identity, pod, uid)
	s.mu.Unlock()
	if err != nil {
		return false, err
	}
	if slot.State == "active" {
		return slot.Warm, nil
	}
	return s.attach(slot)
}
func (s *Store) allocate(identity Identity, pod, uid string) (Slot, error) {
	slots, err := s.slots()
	if err != nil {
		return Slot{}, err
	}
	active, perPod := 0, 0
	for _, slot := range slots {
		if slot.ID == identity.ID {
			if slot.PodUID != uid || slot.Scope != identity.Scope || slot.State == "deleted" || slot.State == "sealed" {
				return Slot{}, errors.New("lease mismatch")
			}
			return slot, nil
		}
		if slot.State == "allocated" || slot.State == "active" {
			active++
			if slot.PodUID == uid {
				perPod++
			}
		}
	}
	if active >= s.MaxSlots || perPod >= 8 {
		return Slot{}, errors.New("cache capacity reached")
	}
	slot := Slot{Identity: identity, PodName: pod, PodUID: uid, State: "allocated", Warm: identity.ParentID != "", UsedAt: time.Now().UTC()}
	// Persist the remote resource identity before creating it. A lost response or
	// restart resumes exactly this clone; it never reformats an exposed filesystem.
	if err = s.save(slot); err != nil {
		return Slot{}, err
	}
	return slot, nil
}
func (s *Store) attach(slot Slot) (bool, error) {
	start := time.Now()
	if err := s.root.MkdirAll("pods/"+slot.PodUID+"/"+slot.Scope, 0755); err != nil {
		return false, err
	}
	if err := s.backend.Attach(slot, s.activePath(slot)); err != nil {
		return false, err
	}
	slot.State = "active"
	slot.AttachMS = time.Since(start).Milliseconds()
	if used, capacity, err := s.backend.Measure(slot, s.activePath(slot)); err == nil {
		slot.SizeBytes, slot.CapacityBytes = &used, &capacity
	}
	return slot.Warm, s.save(slot)
}

// Reporter returns hold/wait, seal, keep, delete, or forget. A remote delete
// decision NEVER overrides the local writer fence.
type Reporter func(Slot, bool) (string, error)

func (s *Store) Reconcile(gone func(string, string) (bool, error), report Reporter) error {
	slots, err := s.slots()
	if err != nil {
		return err
	}
	var failures []error
	for _, slot := range slots {
		if err := s.reconcileCurrent(slot.ID, gone, report); err != nil {
			failures = append(failures, fmt.Errorf("%s: %w", slot.ID, err))
		}
	}
	return errors.Join(failures...)
}
func (s *Store) reconcileCurrent(id string, gone func(string, string) (bool, error), report Reporter) error {
	unlock := s.lock(id)
	defer unlock()
	data, err := s.root.ReadFile("state/" + id + ".json")
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	var slot Slot
	if err := json.Unmarshal(data, &slot); err != nil {
		return err
	}
	return s.reconcileSlot(slot, gone, report)
}
func (s *Store) reconcileSlot(slot Slot, gone func(string, string) (bool, error), report Reporter) error {
	done, err := gone(slot.PodName, slot.PodUID)
	if err != nil {
		return err
	}
	if slot.State == "allocated" && !done {
		return nil
	}
	// An incomplete allocation can never become a published snapshot.
	if slot.State == "allocated" && done {
		if err = s.backend.Delete(slot, s.activePath(slot)); err != nil {
			return err
		}
		slot.State = "deleted"
		if err = s.save(slot); err != nil {
			return err
		}
	}
	if slot.State == "active" {
		if used, capacity, err := s.backend.Measure(slot, s.activePath(slot)); err == nil {
			slot.SizeBytes, slot.CapacityBytes = &used, &capacity
		}
	}
	action, err := report(slot, done)
	if err != nil {
		return err
	}
	if !done {
		return s.save(slot)
	}
	switch action {
	case "seal":
		if slot.State != "active" || !slot.CanPublish {
			return errors.New("invalid seal decision")
		}
		if err = s.backend.Seal(slot, s.activePath(slot)); err != nil {
			return err
		}
		slot.State = "sealed"
	case "delete":
		if err = s.backend.Delete(slot, s.activePath(slot)); err != nil {
			return err
		}
		slot.State = "deleted"
	case "forget":
		if slot.State != "deleted" {
			return errors.New("cannot forget live storage")
		}
		return s.root.Remove("state/" + slot.ID + ".json")
	case "hold", "wait", "keep":
	default:
		return errors.New("invalid cache decision")
	}
	return s.save(slot)
}

// Clean scratch files only after both pod teardown fences and after all block
// mounts for that pod have been detached. Never traverse a live mount.
func (s *Store) CleanPods(gone func(string) (bool, error)) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	slots, err := s.slots()
	if err != nil {
		return err
	}
	mounted := map[string]bool{}
	for _, slot := range slots {
		if slot.State == "active" || slot.State == "allocated" {
			mounted[slot.PodUID] = true
		}
	}
	dir, err := s.root.Open("pods")
	if err != nil {
		return err
	}
	defer dir.Close()
	names, err := dir.Readdirnames(-1)
	if err != nil {
		return err
	}
	for _, uid := range names {
		if !component.MatchString(uid) || mounted[uid] {
			continue
		}
		done, err := gone(uid)
		if err != nil {
			return err
		}
		if done {
			if err := s.root.RemoveAll("pods/" + uid); err != nil {
				return err
			}
		}
	}
	return nil
}
