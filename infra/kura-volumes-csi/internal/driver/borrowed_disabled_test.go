//go:build !kuraborrowed

package driver

import (
	"context"
	"strings"
	"testing"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

func TestShippingDriverRefusesBorrowedUnits(t *testing.T) {
	e := newEnv(t)
	request := createRequest(mib)
	request.Parameters = map[string]string{"layout": ThinLayout, "borrowed_units": "v1"}
	_, err := e.d.CreateVolume(context.Background(), request)
	if status.Code(err) != codes.InvalidArgument || !strings.Contains(err.Error(), "experimental") {
		t.Fatalf("CreateVolume with borrowed units = %v, want an experimental-build refusal", err)
	}
	if _, err := e.d.ChangeBorrowedUnit(context.Background(), BorrowedRequest{}); status.Code(err) != codes.Unimplemented {
		t.Fatalf("ChangeBorrowedUnit = %v, want Unimplemented", err)
	}
	for _, record := range []ThinVolume{
		{VolumeID: "pvc-00000000-0000-0000-0000-000000000001", BorrowedUnits: true},
		{VolumeID: "pvc-00000000-0000-0000-0000-000000000001-unit-00000000-0000-0000-0000-000000000002", UnitPhase: "active"},
	} {
		if err := validateBorrowedRecord(&record); err == nil {
			t.Fatalf("shipping driver accepted borrowed record %+v", record)
		}
	}
}
