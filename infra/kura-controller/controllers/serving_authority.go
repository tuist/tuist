package controllers

import (
	"context"
	"encoding/json"
	"fmt"
	"reflect"
	"sync"
	"time"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	corev1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
)

const servingMode = "PositiveFenceV1"
const servingRollbackFloor = "kura.tuist.dev/serving-rollback-floor"

type servingHolder struct {
	InstanceUID string `json:"instance_uid"`
	PodUID      string `json:"pod_uid"`
	Incarnation string `json:"incarnation"`
	Host        string `json:"host"`
}
type servingGrant struct {
	Handover      *handoverIntent  `json:"handover,omitempty"`
	LastHandover  string           `json:"last_handover,omitempty"`
	Barrier       *handoverReceipt `json:"barrier,omitempty"`
	Epoch         uint64           `json:"epoch"`
	Holder        servingHolder    `json:"holder"`
	ExpiresMS     int64            `json:"expires_ms"`
	Phase         string           `json:"phase"`
	PodName       string           `json:"pod_name"`
	Reason        string           `json:"reason"`
	FenceEvidence string           `json:"fence_evidence,omitempty"`
}
type servingReport struct {
	RevokedEpoch uint64           `json:"revoked_epoch"`
	Observed     *servingGrant    `json:"observed"`
	Mutations    uint64           `json:"mutations"`
	Barrier      *handoverReceipt `json:"barrier"`
	Capability   string           `json:"capability"`
	Enabled      bool             `json:"enabled"`
	Identity     servingHolder    `json:"identity"`
	Epoch        uint64           `json:"epoch"`
	Valid        bool             `json:"valid"`
}

func fencedServing(instance *kurav1alpha1.KuraInstance) bool {
	return instance.Spec.ServingMode == servingMode || instance.Annotations[servingRollbackFloor] != ""
}

// This controller has its own worker queue and direct API client. Metrics,
// DNS, StatefulSet and volume operations cannot consume its worker budget.
// CAS on the grant is authoritative even during overlapping controller leaders.
type ServingAuthorityReconciler struct {
	client.Client
	RuntimeStatusClient RuntimeStatusClient
	Enabled             bool
}

func (r *ServingAuthorityReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).Named("kura-serving-authority").For(&kurav1alpha1.KuraInstance{}).
		WithOptions(controller.Options{MaxConcurrentReconciles: 32}).Complete(r)
}

func (r *ServingAuthorityReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	ctx, cancel := context.WithTimeout(ctx, 1800*time.Millisecond)
	defer cancel()
	result := ctrl.Result{RequeueAfter: 2 * time.Second}
	instance := &kurav1alpha1.KuraInstance{}
	if err := r.Get(ctx, req.NamespacedName, instance); err != nil {
		if apierrors.IsNotFound(err) {
			forgetServingMetrics(req.Namespace, req.Name)
		}
		return result, client.IgnoreNotFound(err)
	}
	if !fencedServing(instance) || instance.DeletionTimestamp != nil {
		forgetServingMetrics(req.Namespace, req.Name)
		return ctrl.Result{}, nil
	}
	if !r.Enabled {
		return result, nil
	} // No new grants, including renewals, with authority disabled.
	if instance.Annotations[servingRollbackFloor] == "" {
		before := instance.DeepCopy()
		if instance.Annotations == nil {
			instance.Annotations = map[string]string{}
		}
		instance.Annotations[servingRollbackFloor] = servingMode
		instance.Annotations["kura.tuist.dev/fenced-runtime-image"] = instance.Spec.Image
		return result, r.Patch(ctx, instance, client.MergeFromWithOptions(before, client.MergeFromWithOptimisticLock{}))
	}
	if err := r.ensureIdentity(ctx, instance); err != nil {
		return result, err
	}
	cm := &corev1.ConfigMap{}
	key := types.NamespacedName{Namespace: instance.Namespace, Name: instance.Name + "-serving"}
	err := r.Get(ctx, key, cm)
	if apierrors.IsNotFound(err) {
		if instance.Annotations["kura.tuist.dev/serving-authority-uid"] != "" {
			return result, fmt.Errorf("durable serving authority was removed; refusing epoch reset")
		}
		cm = &corev1.ConfigMap{ObjectMeta: metav1.ObjectMeta{Name: key.Name, Namespace: key.Namespace}, Data: map[string]string{}}
		if err := controllerutil.SetControllerReference(instance, cm, r.Scheme()); err != nil {
			return result, err
		}
		initial, _ := json.Marshal(servingGrant{Holder: servingHolder{InstanceUID: string(instance.UID)}, Phase: "Preparing", Reason: "Waiting for both fenced runtime incarnations"})
		cm.Data["grant"] = string(initial)
		return result, r.Create(ctx, cm)
	}
	if err != nil {
		return result, err
	}
	if uid := instance.Annotations["kura.tuist.dev/serving-authority-uid"]; uid == "" {
		before := instance.DeepCopy()
		instance.Annotations["kura.tuist.dev/serving-authority-uid"] = string(cm.UID)
		return result, r.Patch(ctx, instance, client.MergeFromWithOptions(before, client.MergeFromWithOptimisticLock{}))
	} else if uid != string(cm.UID) {
		return result, fmt.Errorf("serving authority identity changed; refusing epoch reset")
	}
	var grant servingGrant
	if err := json.Unmarshal([]byte(cm.Data["grant"]), &grant); err != nil {
		return result, err
	}
	if grant.Holder.InstanceUID != string(instance.UID) {
		return result, fmt.Errorf("serving authority instance UID mismatch")
	}
	pods := &corev1.PodList{}
	if err := r.List(ctx, pods, client.InNamespace(instance.Namespace), client.MatchingLabels(selectorLabels(instance))); err != nil {
		return result, err
	}
	helper := &KuraInstanceReconciler{Client: r.Client, Scheme: r.Scheme(), RuntimeStatusClient: r.RuntimeStatusClient}
	statusClient := r.RuntimeStatusClient
	if statusClient == nil {
		statusClient = defaultRuntimeStatusClient()
	}
	samples := map[string]runtimeStatus{}
	var probes sync.WaitGroup
	var samplesMu sync.Mutex
	for _, pod := range pods.Items {
		probes.Add(1)
		go func(pod corev1.Pod) {
			defer probes.Done()
			probeCtx, cancel := context.WithTimeout(ctx, time.Second)
			defer cancel()
			if sample, err := statusClient.Status(probeCtx, pod); err == nil {
				samplesMu.Lock()
				samples[pod.Name] = sample
				samplesMu.Unlock()
			}
		}(pod)
	}
	probes.Wait()
	observeAuthority(instance, grant, samples[grant.PodName].ServingAuthority)
	observeRecovery(instance)
	// Grants are already committed before they can reach this publication path.
	// A stale route never authorizes the old writer; its runtime fences locally.
	primary, routeErr := helper.fencedPrimary(ctx, instance, samples)
	if routeErr != nil {
		return result, routeErr
	}
	if err := helper.reconcileService(ctx, instance, primary); err != nil {
		return result, err
	}
	if err := helper.reconcileGRPCService(ctx, instance, primary); err != nil {
		return result, err
	}
	if err := helper.reconcileExternalService(ctx, instance, primary); err != nil {
		return result, err
	}
	holders := map[string]servingHolder{}
	for i := range pods.Items {
		pod := &pods.Items[i]
		sample, fresh := samples[pod.Name]
		report := sample.ServingAuthority
		if fresh && podReady(pod) && runtimeStatusServing(sample) && report.Enabled && report.Capability == "positive-fence-v1" && report.Identity.InstanceUID == string(instance.UID) && report.Identity.PodUID == string(pod.UID) && report.Identity.Host == pod.Spec.NodeName && report.Identity.Incarnation != "" {
			holders[pod.Name] = report.Identity
		}
	}
	before := cm.DeepCopy()
	now := time.Now().UnixMilli()
	switch grant.Phase {
	case "Preparing":
		// Both expected ordinals must be upgraded before the first public grant;
		// a mixed legacy writer cannot participate in fenced serving.
		if len(pods.Items) != int(replicas(instance)) || len(holders) != int(replicas(instance)) {
			return result, nil
		}
		candidate := instance.Name + "-0"
		holder, ok := holders[candidate]
		if !ok {
			return result, nil
		}
		grant = servingGrant{Epoch: 1, Holder: holder, PodName: candidate, Phase: "Serving", ExpiresMS: now + 15000, Reason: "Initial fenced activation"}
	case "Serving":
		sourceReport := samples[grant.PodName].ServingAuthority
		if sourceReport.Observed != nil && sourceReport.Observed.Epoch == grant.Epoch && !sourceReport.Valid {
			grant.Phase, grant.Reason = "Fencing", "Holder reports expired or refused authority; positive fencing required"
			break
		}
		handover := instance.Spec.PlannedHandover
		if handover != nil && handover.ID != "" && handover.ID != grant.LastHandover && now < grant.ExpiresMS-2000 {
			target, present := holders[handover.PodName]
			source, sourcePresent := holders[grant.PodName]
			if present && sourcePresent && source == grant.Holder && target.PodUID == handover.PodUID && target.Incarnation == handover.Incarnation && target.Host != grant.Holder.Host && samples[handover.PodName].BackfillInitialCycle == backfillCycleComplete {
				grant.Phase = "Quiescing"
				grant.ExpiresMS = now + 15000
				grant.Handover = &handoverIntent{ID: handover.ID, Destination: target, DestinationURL: renderPodNodeURL(instance, handover.PodName, instance.Namespace), SourceURL: renderPodNodeURL(instance, grant.PodName, instance.Namespace), DeadlineMS: now + 300000}
				grant.Reason = "Verifying named standby against every retained record and final feed position"
				break
			}
		}
		if holder, ok := holders[grant.PodName]; ok && holder == grant.Holder && now < grant.ExpiresMS-2000 {
			if grant.ExpiresMS-now > 10000 {
				return result, nil
			}
			grant.ExpiresMS = now + 15000
		} else {
			grant.Phase, grant.Reason = "Fencing", "Holder unavailable or expired; positive fencing required; asynchronous tail may be lost"
		}
	case "Quiescing":
		if grant.Handover == nil {
			return result, fmt.Errorf("missing handover intent")
		}
		source, fresh := samples[grant.PodName]
		if !fresh || source.ServingAuthority.Identity != grant.Holder || now >= grant.ExpiresMS-2000 {
			grant.Phase, grant.Reason = "Fencing", "Source lost during handover; positive fencing required"
			break
		}
		if now >= grant.Handover.DeadlineMS {
			grant.LastHandover, grant.Handover, grant.Phase, grant.Reason = grant.Handover.ID, nil, "Serving", "Handover preparation timed out; retained old primary"
			grant.ExpiresMS = now + 15000
			break
		}
		receipt := source.ServingAuthority.Barrier
		destinationReceipt := (*handoverReceipt)(nil)
		for _, sample := range samples {
			if sample.ServingAuthority.Identity == grant.Handover.Destination {
				destinationReceipt = sample.ServingAuthority.Barrier
			}
		}
		if receipt != nil && receipt.ID == grant.Handover.ID && receipt.Source == grant.Holder && receipt.Destination == grant.Handover.Destination && receipt.Digest != "" && reflect.DeepEqual(receipt, destinationReceipt) && source.ServingAuthority.Mutations == 0 {
			grant.Phase, grant.Barrier, grant.Reason = "Revoking", receipt, "Named retained-data barrier acknowledged; waiting for stopped-serving acknowledgment"
		} else if grant.ExpiresMS-now <= 10000 {
			grant.ExpiresMS = now + 15000
		} else {
			return result, nil
		}
	case "Revoking":
		source, fresh := samples[grant.PodName]
		report := source.ServingAuthority
		if !fresh || report.Identity != grant.Holder || report.Observed == nil || report.Observed.Epoch != grant.Epoch || report.Observed.Phase != "Revoking" || report.RevokedEpoch != grant.Epoch || report.Valid || report.Mutations != 0 {
			return result, nil
		}
		if grant.Handover == nil || grant.Barrier == nil {
			return result, fmt.Errorf("missing persisted handover barrier")
		}
		targetName := ""
		for name, holder := range holders {
			if holder == grant.Handover.Destination {
				targetName = name
			}
		}
		if targetName == "" || !reflect.DeepEqual(samples[targetName].ServingAuthority.Barrier, grant.Barrier) {
			return result, nil
		}
		if grant.Epoch == ^uint64(0) {
			return result, fmt.Errorf("serving epoch exhausted")
		}
		grant.LastHandover = grant.Handover.ID
		grant.Holder, grant.PodName, grant.Epoch, grant.ExpiresMS, grant.Phase, grant.Reason = grant.Handover.Destination, targetName, grant.Epoch+1, now+15000, "Serving", "Planned handover after named retained-data barrier and positive runtime revoke"
		grant.Handover = nil
	case "Fencing":
		promotion := instance.Spec.PrimaryPromotion
		if promotion == nil || promotion.PreviousEpoch != grant.Epoch || promotion.PreviousPodUID != grant.Holder.PodUID || promotion.PreviousIncarnation != grant.Holder.Incarnation || promotion.PreviousHost != grant.Holder.Host || promotion.FenceEvidence == "" {
			return result, nil
		}
		candidate, ok := holders[promotion.PodName]
		if !ok || candidate.PodUID != promotion.PodUID || candidate.Incarnation != promotion.Incarnation || candidate.Host == grant.Holder.Host {
			return result, nil
		}
		if grant.Epoch == ^uint64(0) {
			return result, fmt.Errorf("serving epoch exhausted")
		}
		grant = servingGrant{Epoch: grant.Epoch + 1, Holder: candidate, PodName: promotion.PodName, Phase: "Serving", ExpiresMS: now + 15000, Reason: "Positively fenced crash promotion; unreplicated tail may be missing", FenceEvidence: promotion.FenceEvidence}
	default:
		return result, fmt.Errorf("unknown serving phase %q", grant.Phase)
	}
	data, err := json.Marshal(grant)
	if err != nil {
		return result, err
	}
	cm.Data["grant"] = string(data)
	if err := r.Patch(ctx, cm, client.MergeFromWithOptions(before, client.MergeFromWithOptimisticLock{})); err != nil {
		return result, err
	}
	var previous servingGrant
	_ = json.Unmarshal([]byte(before.Data["grant"]), &previous)
	if previous.Phase != grant.Phase || previous.Epoch != grant.Epoch {
		ctrl.LoggerFrom(ctx).Info("serving authority transitioned", "from", previous.Phase, "to", grant.Phase, "epoch", grant.Epoch, "pod", grant.PodName, "reason", grant.Reason)
	}
	observeAuthority(instance, grant, samples[grant.PodName].ServingAuthority)
	return result, nil
}

func (r *ServingAuthorityReconciler) ensureIdentity(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	name := instance.Name + "-serving"
	objects := []client.Object{
		&corev1.ServiceAccount{ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: instance.Namespace}},
		&rbacv1.Role{ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: instance.Namespace}, Rules: []rbacv1.PolicyRule{{APIGroups: []string{""}, Resources: []string{"configmaps"}, ResourceNames: []string{name}, Verbs: []string{"get"}}}},
		&rbacv1.RoleBinding{ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: instance.Namespace}, RoleRef: rbacv1.RoleRef{APIGroup: rbacv1.GroupName, Kind: "Role", Name: name}, Subjects: []rbacv1.Subject{{Kind: "ServiceAccount", Name: name, Namespace: instance.Namespace}}},
	}
	for _, object := range objects {
		if err := controllerutil.SetControllerReference(instance, object, r.Scheme()); err != nil {
			return err
		}
		if err := r.Create(ctx, object); err != nil && !apierrors.IsAlreadyExists(err) {
			return err
		}
	}
	return nil
}

func (r *KuraInstanceReconciler) fencedPrimary(ctx context.Context, instance *kurav1alpha1.KuraInstance, samples map[string]runtimeStatus) (string, error) {
	cm := &corev1.ConfigMap{}
	reader := r.APIReader
	if reader == nil {
		reader = r.Client
	}
	if err := reader.Get(ctx, types.NamespacedName{Namespace: instance.Namespace, Name: instance.Name + "-serving"}, cm); err != nil {
		if apierrors.IsNotFound(err) {
			return "fenced-unavailable", nil
		}
		return "", err
	}
	var grant servingGrant
	if err := json.Unmarshal([]byte(cm.Data["grant"]), &grant); err != nil {
		return "", err
	}
	sample, fresh := samples[grant.PodName]
	if (grant.Phase != "Serving" && grant.Phase != "Quiescing") || grant.Holder.InstanceUID != string(instance.UID) || grant.ExpiresMS <= time.Now().UnixMilli()+2000 || !fresh || !sample.ServingAuthority.Valid || sample.ServingAuthority.Epoch != grant.Epoch || sample.ServingAuthority.Identity != grant.Holder {
		return "fenced-unavailable", nil
	}
	return grant.PodName, nil
}

type handoverIntent struct {
	ID             string        `json:"id"`
	Destination    servingHolder `json:"destination"`
	DestinationURL string        `json:"destination_url"`
	SourceURL      string        `json:"source_url"`
	DeadlineMS     int64         `json:"deadline_ms"`
}
type handoverReceipt struct {
	ID          string        `json:"id"`
	Source      servingHolder `json:"source"`
	Destination servingHolder `json:"destination"`
	Incarnation uint64        `json:"incarnation"`
	Head        uint64        `json:"head"`
	FrontierMS  uint64        `json:"frontier_ms"`
	Records     uint64        `json:"records"`
	Digest      string        `json:"digest"`
}
