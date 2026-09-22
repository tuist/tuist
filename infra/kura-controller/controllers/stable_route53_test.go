package controllers

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/route53"
	r53types "github.com/aws/aws-sdk-go-v2/service/route53/types"
)

type fakeRoute53 struct {
	checks  []r53types.HealthCheck
	records []r53types.ResourceRecordSet
	created int
	reads   int
	deleted []string
	err     error
}

func (f *fakeRoute53) ListResourceRecordSets(_ context.Context, _ *route53.ListResourceRecordSetsInput, _ ...func(*route53.Options)) (*route53.ListResourceRecordSetsOutput, error) {
	f.reads++
	return &route53.ListResourceRecordSetsOutput{ResourceRecordSets: f.records}, f.err
}
func (f *fakeRoute53) ListHealthChecks(context.Context, *route53.ListHealthChecksInput, ...func(*route53.Options)) (*route53.ListHealthChecksOutput, error) {
	return &route53.ListHealthChecksOutput{HealthChecks: f.checks}, f.err
}
func (f *fakeRoute53) CreateHealthCheck(_ context.Context, input *route53.CreateHealthCheckInput, _ ...func(*route53.Options)) (*route53.CreateHealthCheckOutput, error) {
	f.created++
	check := r53types.HealthCheck{Id: aws.String("box-check"), CallerReference: input.CallerReference, HealthCheckConfig: input.HealthCheckConfig}
	f.checks = append(f.checks, check)
	return &route53.CreateHealthCheckOutput{HealthCheck: &check}, f.err
}
func (f *fakeRoute53) DeleteHealthCheck(_ context.Context, input *route53.DeleteHealthCheckInput, _ ...func(*route53.Options)) (*route53.DeleteHealthCheckOutput, error) {
	f.deleted = append(f.deleted, aws.ToString(input.HealthCheckId))
	return &route53.DeleteHealthCheckOutput{}, f.err
}

func TestStableHealthChecksSharedAndCollectedOnlyAfterLastReference(t *testing.T) {
	ctx := context.Background()
	api := &fakeRoute53{}
	p := &Route53StableDNS{api: api, zone: "ZCACHE", owner: "staging"}
	first, err := p.EnsureHealthCheck(ctx, "203.0.113.20")
	if err != nil {
		t.Fatal(err)
	}
	// A fresh provider models a restart; adoption cannot depend on local memory.
	restarted := &Route53StableDNS{api: api, zone: p.zone, owner: p.owner}
	second, err := restarted.EnsureHealthCheck(ctx, "203.0.113.20")
	if err != nil || first != second || api.created != 1 {
		t.Fatal("accounts on one box did not share a check across restart")
	}
	cfg := api.checks[0].HealthCheckConfig
	if cfg.Type != r53types.HealthCheckTypeTcp || aws.ToInt32(cfg.Port) != 443 || aws.ToInt32(cfg.RequestInterval) != 30 {
		t.Fatal("expected plain TCP health check")
	}
	foreign := r53types.HealthCheck{Id: aws.String("foreign"), CallerReference: aws.String("another-owner")}
	api.checks = append(api.checks, foreign)
	api.records = []r53types.ResourceRecordSet{{HealthCheckId: aws.String(first)}}
	if err := p.collectHealthChecks(ctx, map[string]bool{}); err != nil {
		t.Fatal(err)
	}
	if len(api.deleted) != 0 {
		t.Fatal("deleted a provider-referenced check")
	}
	api.records = nil
	if err := p.collectHealthChecks(ctx, map[string]bool{first: true}); err != nil {
		t.Fatal(err)
	}
	if len(api.deleted) != 0 {
		t.Fatal("deleted a check referenced by pending controller state")
	}
	if err := p.collectHealthChecks(ctx, map[string]bool{}); err != nil {
		t.Fatal(err)
	}
	if len(api.deleted) != 1 || api.deleted[0] != first {
		t.Fatalf("did not collect only our orphan: %v", api.deleted)
	}
}

func TestStableRecordObservationDistinguishesRegionsAndReadFailures(t *testing.T) {
	api := &fakeRoute53{records: []r53types.ResourceRecordSet{
		{Name: aws.String("acme.cache.tuist.dev."), Type: r53types.RRTypeA, SetIdentifier: aws.String("ca-east")},
		{Name: aws.String("acme.cache.tuist.dev."), Type: r53types.RRTypeA, SetIdentifier: aws.String("eu-west"), Region: r53types.ResourceRecordSetRegionEuWest3, HealthCheckId: aws.String("check"), ResourceRecords: []r53types.ResourceRecord{{Value: aws.String("203.0.113.20")}}},
	}}
	p := &Route53StableDNS{api: api, zone: "zone", owner: "staging"}
	record, err := p.Record(context.Background(), "acme.cache.tuist.dev", "eu-west")
	if err != nil || record == nil || record.Target != "203.0.113.20" || record.AWSRegion != "eu-west-3" {
		t.Fatalf("wrong regional record: %+v %v", record, err)
	}
	record, err = p.Record(context.Background(), "acme.cache.tuist.dev", "us-east")
	if err != nil || record != nil {
		t.Fatal("another region prevented observing withdrawal")
	}
	api.err = errors.New("AWS unavailable")
	if _, err := p.Record(context.Background(), "acme.cache.tuist.dev", "us-east"); err == nil {
		t.Fatal("read error interpreted as absence")
	}
}

func TestStableRecordSnapshotIsSharedAndFailsClosedWhenExpired(t *testing.T) {
	api := &fakeRoute53{records: []r53types.ResourceRecordSet{
		{Name: aws.String("acme.cache.tuist.dev."), Type: r53types.RRTypeA, SetIdentifier: aws.String("eu-west")},
		{Name: aws.String("other.cache.tuist.dev."), Type: r53types.RRTypeA, SetIdentifier: aws.String("ca-east")},
	}}
	p := &Route53StableDNS{api: api, zone: "zone", owner: "staging", recordTTL: 10 * time.Second}
	for _, key := range [][2]string{{"acme.cache.tuist.dev", "eu-west"}, {"other.cache.tuist.dev", "ca-east"}} {
		record, err := p.Record(context.Background(), key[0], key[1])
		if err != nil || record == nil {
			t.Fatalf("missing record %v: %v", key, err)
		}
	}
	if api.reads != 1 {
		t.Fatal("fleet reads did not share a snapshot")
	}
	p.recordsAt = time.Now().Add(-11 * time.Second)
	api.err = errors.New("AWS unavailable")
	if _, err := p.Record(context.Background(), "acme.cache.tuist.dev", "eu-west"); err == nil {
		t.Fatal("expired snapshot masked provider failure")
	}
	api.err, api.records = nil, nil
	record, err := p.Record(context.Background(), "acme.cache.tuist.dev", "eu-west")
	if err != nil || record != nil {
		t.Fatal("withdrawal was not observed after refreshing")
	}
}
