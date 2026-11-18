//go:build !kuraborrowed

package driver

import (
	"context"
	"fmt"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// The shipping driver serves ceiling-backed volumes only. Borrowed units are
// compiled only into their qualification fixtures (-tags kuraborrowed).
const borrowedUnitsBuild = false

func validateBorrowedRecord(r *ThinVolume) error {
	if r.BorrowedUnits || r.UnitPhase != "" || r.UnitOperation != nil || childVolumeIDPattern.MatchString(r.VolumeID) {
		return fmt.Errorf("borrowed volume records require the experimental driver build")
	}
	return nil
}

func (d *Driver) prepareBorrowedParent(_ context.Context, r *ThinVolume) error {
	return validateBorrowedRecord(r)
}

func (d *Driver) restoreBorrowedChildren(context.Context, *ThinVolume) error { return nil }

func (d *Driver) unpublishBorrowedChildren(context.Context, *ThinVolume) error { return nil }

func (d *Driver) deleteDetachedBorrowedChildren(context.Context, *ThinVolume) error { return nil }

func (d *Driver) ChangeBorrowedUnit(context.Context, BorrowedRequest) (*ThinSnapshot, error) {
	return nil, status.Error(codes.Unimplemented, "borrowed units require the experimental driver build")
}
