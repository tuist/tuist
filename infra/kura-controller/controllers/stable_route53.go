package controllers

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/route53"
	r53types "github.com/aws/aws-sdk-go-v2/service/route53/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

type route53API interface {
	ListResourceRecordSets(context.Context, *route53.ListResourceRecordSetsInput, ...func(*route53.Options)) (*route53.ListResourceRecordSetsOutput, error)
	ListHealthChecks(context.Context, *route53.ListHealthChecksInput, ...func(*route53.Options)) (*route53.ListHealthChecksOutput, error)
	CreateHealthCheck(context.Context, *route53.CreateHealthCheckInput, ...func(*route53.Options)) (*route53.CreateHealthCheckOutput, error)
	DeleteHealthCheck(context.Context, *route53.DeleteHealthCheckInput, ...func(*route53.Options)) (*route53.DeleteHealthCheckOutput, error)
}

type Route53StableDNS struct {
	api              route53API
	zone, owner      string
	healthMu         sync.Mutex
	healthReferences map[string]string
	recordMu         sync.Mutex
	recordTTL        time.Duration
	recordsAt        time.Time
	records          map[string]*StableDNSRecord
}

func NewRoute53StableDNS(ctx context.Context, zone, owner string) (*Route53StableDNS, error) {
	if zone == "" || owner == "" {
		return nil, fmt.Errorf("Route53 requires a zone and unique cluster owner")
	}
	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion("us-east-1"))
	if err != nil {
		return nil, err
	}
	return &Route53StableDNS{api: route53.NewFromConfig(cfg), zone: zone, owner: owner, recordTTL: 10 * time.Second}, nil
}

func (p *Route53StableDNS) healthPrefix() string {
	hash := sha256.Sum256([]byte(p.zone + "/" + p.owner))
	return fmt.Sprintf("kura-%x-", hash[:8])
}

func (p *Route53StableDNS) healthChecks(ctx context.Context) ([]r53types.HealthCheck, error) {
	var checks []r53types.HealthCheck
	input := &route53.ListHealthChecksInput{}
	for {
		page, err := p.api.ListHealthChecks(ctx, input)
		if err != nil {
			return nil, err
		}
		checks = append(checks, page.HealthChecks...)
		if !page.IsTruncated {
			return checks, nil
		}
		input.Marker = page.NextMarker
	}
}

func (p *Route53StableDNS) EnsureHealthCheck(ctx context.Context, target string) (string, error) {
	p.healthMu.Lock()
	defer p.healthMu.Unlock()
	hash := sha256.Sum256([]byte(target + ":443"))
	prefix := p.healthPrefix() + fmt.Sprintf("%x", hash[:12])
	checks, err := p.healthChecks(ctx)
	if err != nil {
		return "", err
	}
	for _, check := range checks {
		ref := aws.ToString(check.CallerReference)
		if ref == prefix || strings.HasPrefix(ref, prefix+"-") {
			cfg := check.HealthCheckConfig
			if cfg == nil || aws.ToString(cfg.IPAddress) != target || aws.ToInt32(cfg.Port) != 443 || cfg.Type != r53types.HealthCheckTypeTcp {
				return "", fmt.Errorf("owned health check %s has unexpected configuration", aws.ToString(check.Id))
			}
			return aws.ToString(check.Id), nil
		}
	}
	// AWS retains deleted caller references for days. A new incarnation needs
	// a nonce, but ambiguous create retries must retain the same reference.
	if p.healthReferences == nil {
		p.healthReferences = map[string]string{}
	}
	reference := p.healthReferences[target]
	if reference == "" {
		var nonce [8]byte
		if _, err := rand.Read(nonce[:]); err != nil {
			return "", err
		}
		reference = prefix + fmt.Sprintf("-%x", nonce)
		p.healthReferences[target] = reference
	}
	output, err := p.api.CreateHealthCheck(ctx, &route53.CreateHealthCheckInput{
		CallerReference: aws.String(reference), HealthCheckConfig: &r53types.HealthCheckConfig{
			IPAddress: aws.String(target), Port: aws.Int32(443), Type: r53types.HealthCheckTypeTcp,
			RequestInterval: aws.Int32(30), FailureThreshold: aws.Int32(3),
		},
	})
	if err != nil {
		var conflict *r53types.HealthCheckAlreadyExists
		if errors.As(err, &conflict) {
			delete(p.healthReferences, target)
		}
		return "", err
	}
	return aws.ToString(output.HealthCheck.Id), nil
}

// One bounded zone snapshot serves the fleet's readiness reads. Per-instance
// polling otherwise exceeds Route53's account-wide request limit. Expired or
// failed observations never fall back to stale data, particularly on withdrawal.
func (p *Route53StableDNS) Record(ctx context.Context, host, setID string) (*StableDNSRecord, error) {
	p.recordMu.Lock()
	defer p.recordMu.Unlock()
	if time.Since(p.recordsAt) >= p.recordTTL {
		records := map[string]*StableDNSRecord{}
		input := &route53.ListResourceRecordSetsInput{HostedZoneId: aws.String(p.zone)}
		for {
			page, err := p.api.ListResourceRecordSets(ctx, input)
			if err != nil {
				return nil, err
			}
			for _, record := range page.ResourceRecordSets {
				if record.Type != r53types.RRTypeA {
					continue
				}
				value := &StableDNSRecord{AWSRegion: string(record.Region), HealthCheckID: aws.ToString(record.HealthCheckId)}
				if len(record.ResourceRecords) == 1 {
					value.Target = aws.ToString(record.ResourceRecords[0].Value)
				}
				records[strings.TrimSuffix(aws.ToString(record.Name), ".")+"/"+aws.ToString(record.SetIdentifier)] = value
			}
			if !page.IsTruncated {
				break
			}
			input.StartRecordName, input.StartRecordType, input.StartRecordIdentifier = page.NextRecordName, page.NextRecordType, page.NextRecordIdentifier
		}
		p.records, p.recordsAt = records, time.Now()
	}
	return p.records[host+"/"+setID], nil
}

// Health checks are shared across account records and have no instance owner.
// This sweep discovers even a check created just before a controller crash.
// Provider records AND persisted instance intent retain it until external-dns
// has caught up. Other environments' checks never match this caller prefix.
func (p *Route53StableDNS) collectHealthChecks(ctx context.Context, inUse map[string]bool) error {
	p.healthMu.Lock()
	defer p.healthMu.Unlock()
	input := &route53.ListResourceRecordSetsInput{HostedZoneId: aws.String(p.zone)}
	for {
		page, err := p.api.ListResourceRecordSets(ctx, input)
		if err != nil {
			return err
		}
		for _, record := range page.ResourceRecordSets {
			inUse[aws.ToString(record.HealthCheckId)] = true
		}
		if !page.IsTruncated {
			break
		}
		input.StartRecordName, input.StartRecordType, input.StartRecordIdentifier = page.NextRecordName, page.NextRecordType, page.NextRecordIdentifier
	}
	checks, err := p.healthChecks(ctx)
	if err != nil {
		return err
	}
	for _, check := range checks {
		if strings.HasPrefix(aws.ToString(check.CallerReference), p.healthPrefix()) && !inUse[aws.ToString(check.Id)] {
			if _, err := p.api.DeleteHealthCheck(ctx, &route53.DeleteHealthCheckInput{HealthCheckId: check.Id}); err != nil {
				return err
			}
			// Retain references through stale list responses after a successful
			// create, but never reuse one after its check was collected.
			for target, reference := range p.healthReferences {
				if reference == aws.ToString(check.CallerReference) {
					delete(p.healthReferences, target)
				}
			}
		}
	}
	return nil
}

type StableHealthCollector struct {
	Reconciler *KuraInstanceReconciler
	Provider   *Route53StableDNS
	Namespace  string
}

func (*StableHealthCollector) NeedLeaderElection() bool { return true }
func (c *StableHealthCollector) Start(ctx context.Context) error {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
			if err := c.collect(ctx); err != nil {
				log.FromContext(ctx).Error(err, "collect stable DNS health checks")
			}
		}
	}
}
func (c *StableHealthCollector) collect(ctx context.Context) error {
	r := c.Reconciler
	r.stableDNSMu.Lock()
	defer r.stableDNSMu.Unlock()
	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	reader := r.APIReader
	if reader == nil {
		reader = r.Client
	}
	instances := &kurav1alpha1.KuraInstanceList{}
	if err := reader.List(ctx, instances, client.InNamespace(c.Namespace)); err != nil {
		return err
	}
	inUse := map[string]bool{}
	for _, instance := range instances.Items {
		if state := instance.Status.StableEndpoint; state != nil {
			inUse[state.HealthCheckID] = true
		}
	}
	return c.Provider.collectHealthChecks(ctx, inUse)
}
