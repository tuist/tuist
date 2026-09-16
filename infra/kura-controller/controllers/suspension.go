package controllers

import (
	"context"
	"fmt"
	"hash/fnv"
	"sort"
	"strings"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/log"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

const (
	suspendedPhase  = "Suspended"
	suspendingPhase = "Suspending"

	// volumeWipedAnnotation marks a retained data volume whose content was
	// deleted after the last pod on it stopped. Only an unscheduled pod leaves
	// it in place: once a pod is scheduled onto the volume it may write, and
	// the marker is removed.
	volumeWipedAnnotation = "kura.tuist.dev/volume-wiped-at"

	wipeJobComponent      = "kura-volume-wipe"
	suspensionRequeueTime = 10 * time.Second
)

// reconcileSuspended converges a suspended instance: its StatefulSet scaled to
// zero and every retained data volume emptied. Nothing that addresses the
// instance is touched, which is the point of suspending rather than deleting:
// the client and peer Services keep their pod selectors, the Ingresses and
// DNSEndpoints keep publishing the hosts, and the peer TLS material and egress
// class stay allocated, so a return only has to start pods.
//
// Emptying a volume in place, rather than deleting the claim, keeps it bound to
// the machine it was carved on, so the returning pods schedule onto volumes
// that already exist instead of waiting for new ones to be provisioned. The
// content still goes: an archived account's cache is discarded either way, and
// capacity accounting counts an archived instance as holding nothing.
//
// Once converged the instance leaves the periodic requeue. A suspended
// instance only has to react to its spec changing, and every one that stayed
// in the heartbeat would add a reconcile to each pass over the namespace.
func (r *KuraInstanceReconciler) reconcileSuspended(ctx context.Context, instance *kurav1alpha1.KuraInstance) (ctrl.Result, error) {
	if err := r.scaleStatefulSetToZero(ctx, instance); err != nil {
		return ctrl.Result{}, err
	}
	pods, err := r.instancePods(ctx, instance)
	if err != nil {
		return ctrl.Result{}, err
	}
	// A pod still stopping may have been scheduled after the volume was last
	// emptied, so its marker cannot be trusted by the pass that wipes.
	if err := r.clearWipedMarkersForScheduledPods(ctx, instance, pods); err != nil {
		return ctrl.Result{}, err
	}

	emptied := false
	message := fmt.Sprintf("waiting for %d pods to stop", len(pods))
	if len(pods) == 0 {
		emptied, message, err = r.emptyRetainedVolumes(ctx, instance)
		if err != nil {
			return ctrl.Result{}, err
		}
	}

	now := metav1.NewTime(time.Now().UTC())
	instance.Status.Phase = suspendingPhase
	if emptied {
		instance.Status.Phase = suspendedPhase
	}
	instance.Status.ObservedImage = ""
	instance.Status.ReadyReplicas = 0
	instance.Status.Message = message
	instance.Status.LastReconciledAt = &now
	instance.Status.ObservedGeneration = instance.Generation
	instance.Status.RolloutHealth = nil
	instance.Status.PeerRoles = nil
	if err := r.Status().Update(ctx, instance); err != nil {
		return ctrl.Result{}, err
	}

	log.FromContext(ctx).Info("reconciled suspended Kura instance", "phase", instance.Status.Phase, "message", message)
	if !emptied {
		return ctrl.Result{RequeueAfter: suspensionRequeueTime}, nil
	}
	r.forgetPodSamples(instance)
	return ctrl.Result{}, nil
}

func (r *KuraInstanceReconciler) scaleStatefulSetToZero(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	sts := &appsv1.StatefulSet{}
	if err := r.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, sts); err != nil {
		if apierrors.IsNotFound(err) {
			return nil
		}
		return err
	}
	if sts.Spec.Replicas != nil && *sts.Spec.Replicas == 0 {
		return nil
	}
	before := sts.DeepCopy()
	sts.Spec.Replicas = ptr(int32(0))
	return r.Patch(ctx, sts, client.MergeFrom(before))
}

// emptyRetainedVolumes runs one wipe Job per data volume that is not marked
// empty, and reports true once none is left holding content. A volume whose
// wipe failed is released instead: the cache is discarded all the same, and the
// return provisions a fresh volume wherever there is room.
func (r *KuraInstanceReconciler) emptyRetainedVolumes(ctx context.Context, instance *kurav1alpha1.KuraInstance) (bool, string, error) {
	claims, err := r.dataVolumeClaims(ctx, instance)
	if err != nil {
		return false, "", err
	}
	pending := []string{}
	for i := range claims {
		claim := &claims[i]
		if claim.DeletionTimestamp != nil {
			pending = append(pending, claim.Name)
			continue
		}
		if claimWiped(claim) {
			continue
		}
		done, err := r.wipeVolume(ctx, instance, claim)
		if err != nil {
			return false, "", err
		}
		if !done {
			pending = append(pending, claim.Name)
		}
	}
	if len(pending) > 0 {
		return false, fmt.Sprintf("emptying retained volumes: %s", strings.Join(pending, ", ")), nil
	}
	return true, fmt.Sprintf("suspended with %d empty retained volumes", len(claims)), nil
}

func (r *KuraInstanceReconciler) wipeVolume(ctx context.Context, instance *kurav1alpha1.KuraInstance, claim *corev1.PersistentVolumeClaim) (bool, error) {
	job := &batchv1.Job{}
	err := r.Get(ctx, types.NamespacedName{Name: wipeJobName(instance, claim.Name), Namespace: instance.Namespace}, job)
	if apierrors.IsNotFound(err) {
		job = wipeJob(instance, claim.Name)
		if err := controllerutil.SetControllerReference(instance, job, r.Scheme); err != nil {
			return false, err
		}
		if err := r.Create(ctx, job); err != nil && !apierrors.IsAlreadyExists(err) {
			return false, err
		}
		log.FromContext(ctx).Info("emptying retained Kura data volume", "pvc", claim.Name, "job", job.Name)
		return false, nil
	}
	if err != nil {
		return false, err
	}
	outcome, err := r.settleWipeJob(ctx, job)
	return outcome == wipeSucceeded, err
}

type wipeOutcome int

const (
	wipeRunning wipeOutcome = iota
	wipeSucceeded
	wipeReleased
)

// settleWipeJob records a finished wipe on its volume and removes the Job. A
// volume whose wipe failed may be half emptied, which is worse than full or
// empty for a store that is about to be opened on it, so it is released.
func (r *KuraInstanceReconciler) settleWipeJob(ctx context.Context, job *batchv1.Job) (wipeOutcome, error) {
	claim := &corev1.PersistentVolumeClaim{}
	claimName := wipeJobClaimName(job)
	claimErr := r.Get(ctx, types.NamespacedName{Name: claimName, Namespace: job.Namespace}, claim)
	if claimErr != nil && !apierrors.IsNotFound(claimErr) {
		return wipeRunning, claimErr
	}
	claimExists := claimErr == nil

	switch {
	case jobConditionTrue(job, batchv1.JobComplete):
		if claimExists && !claimWiped(claim) {
			before := claim.DeepCopy()
			if claim.Annotations == nil {
				claim.Annotations = map[string]string{}
			}
			claim.Annotations[volumeWipedAnnotation] = time.Now().UTC().Format(time.RFC3339)
			if err := r.Patch(ctx, claim, client.MergeFrom(before)); err != nil {
				return wipeRunning, err
			}
		}
		return wipeSucceeded, r.deleteJob(ctx, job)
	case jobConditionTrue(job, batchv1.JobFailed):
		log.FromContext(ctx).Info("releasing a retained Kura data volume that could not be emptied", "pvc", claimName, "job", job.Name)
		if claimExists {
			if err := r.reclaimDataVolume(ctx, claim); err != nil {
				return wipeRunning, err
			}
			if err := r.Delete(ctx, claim); err != nil && !apierrors.IsNotFound(err) {
				return wipeRunning, err
			}
		}
		return wipeReleased, r.deleteJob(ctx, job)
	default:
		return wipeRunning, nil
	}
}

// settleWipeJobsBeforeResume holds a returning instance's StatefulSet at zero
// while a wipe it started while suspended is still deleting. Starting a pod on
// a volume mid-delete would open a store with an arbitrary part of its files
// missing.
func (r *KuraInstanceReconciler) settleWipeJobsBeforeResume(ctx context.Context, instance *kurav1alpha1.KuraInstance) (bool, error) {
	jobs := &batchv1.JobList{}
	if err := r.List(ctx, jobs, client.InNamespace(instance.Namespace), client.MatchingLabels(wipeJobLabels(instance))); err != nil {
		return false, err
	}
	inProgress := false
	for i := range jobs.Items {
		outcome, err := r.settleWipeJob(ctx, &jobs.Items[i])
		if err != nil {
			return false, err
		}
		inProgress = inProgress || outcome != wipeSucceeded
	}
	return inProgress, nil
}

func wipeJobClaimName(job *batchv1.Job) string {
	for _, volume := range job.Spec.Template.Spec.Volumes {
		if volume.PersistentVolumeClaim != nil {
			return volume.PersistentVolumeClaim.ClaimName
		}
	}
	return ""
}

func wipeJobLabels(instance *kurav1alpha1.KuraInstance) map[string]string {
	return map[string]string{
		"app.kubernetes.io/name":       wipeJobComponent,
		"app.kubernetes.io/instance":   instance.Name,
		"app.kubernetes.io/managed-by": "kura-controller",
	}
}

func (r *KuraInstanceReconciler) deleteJob(ctx context.Context, job *batchv1.Job) error {
	if err := r.Delete(ctx, job, client.PropagationPolicy(metav1.DeletePropagationBackground)); err != nil && !apierrors.IsNotFound(err) {
		return err
	}
	return nil
}

func jobConditionTrue(job *batchv1.Job, conditionType batchv1.JobConditionType) bool {
	for _, condition := range job.Status.Conditions {
		if condition.Type == conditionType && condition.Status == corev1.ConditionTrue {
			return true
		}
	}
	return false
}

// wipeJob deletes everything on one data volume. It runs on the instance's own
// image, which the volume's machine pulled for the pods that just stopped, and
// schedules wherever the volume's node affinity puts it. Its pods are labelled
// apart from the instance's selector so nothing mistakes one for a replica.
func wipeJob(instance *kurav1alpha1.KuraInstance, claimName string) *batchv1.Job {
	podLabels := wipeJobLabels(instance)
	return &batchv1.Job{
		ObjectMeta: metav1.ObjectMeta{
			Name:      wipeJobName(instance, claimName),
			Namespace: instance.Namespace,
			Labels:    podLabels,
		},
		Spec: batchv1.JobSpec{
			BackoffLimit: ptr(int32(2)),
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{Labels: podLabels},
				Spec: corev1.PodSpec{
					RestartPolicy:      corev1.RestartPolicyNever,
					EnableServiceLinks: ptr(false),
					NodeSelector:       nodeSelector(instance),
					Tolerations:        instance.Spec.Tolerations,
					Containers: []corev1.Container{{
						Name:            "wipe",
						Image:           instance.Spec.Image,
						ImagePullPolicy: corev1.PullIfNotPresent,
						Command:         []string{"/bin/sh", "-c", "find /var/cache/kura -mindepth 1 -delete"},
						Resources: corev1.ResourceRequirements{
							Requests: corev1.ResourceList{
								corev1.ResourceCPU:    resource.MustParse("10m"),
								corev1.ResourceMemory: resource.MustParse("32Mi"),
							},
						},
						VolumeMounts: []corev1.VolumeMount{{Name: "data", MountPath: "/var/cache/kura"}},
					}},
					Volumes: []corev1.Volume{{
						Name: "data",
						VolumeSource: corev1.VolumeSource{PersistentVolumeClaim: &corev1.PersistentVolumeClaimVolumeSource{
							ClaimName: claimName,
						}},
					}},
				},
			},
		},
	}
}

func wipeJobName(instance *kurav1alpha1.KuraInstance, claimName string) string {
	ordinal := claimName[strings.LastIndex(claimName, "-")+1:]
	name := fmt.Sprintf("%s-wipe-%s", instance.Name, ordinal)
	if len(name) <= 63 {
		return name
	}
	hash := fnv.New32a()
	_, _ = hash.Write([]byte(claimName))
	suffix := fmt.Sprintf("-wipe-%s-%x", ordinal, hash.Sum32())
	return strings.TrimRight(instance.Name[:63-len(suffix)], "-") + suffix
}

func (r *KuraInstanceReconciler) dataVolumeClaims(ctx context.Context, instance *kurav1alpha1.KuraInstance) ([]corev1.PersistentVolumeClaim, error) {
	claims := &corev1.PersistentVolumeClaimList{}
	if err := r.List(ctx, claims, client.InNamespace(instance.Namespace), client.MatchingLabels(selectorLabels(instance))); err != nil {
		return nil, err
	}
	dataPrefix := fmt.Sprintf("data-%s-", instance.Name)
	out := []corev1.PersistentVolumeClaim{}
	for i := range claims.Items {
		if strings.HasPrefix(claims.Items[i].Name, dataPrefix) {
			out = append(out, claims.Items[i])
		}
	}
	sort.Slice(out, func(a, b int) bool { return out[a].Name < out[b].Name })
	return out, nil
}

// reconcileWipedVolumes carries a returning instance's empty volumes: it
// removes the marker from a volume once a pod is scheduled on it, and releases
// an empty volume whose pod the scheduler cannot place.
//
// Nothing reserves room on a machine for a suspended instance, so the machine
// its volume is bound to may have filled up in the meantime. An empty volume
// costs nothing to give up, and releasing it lets the StatefulSet recreate the
// claim wherever the scheduler finds room. That return is slower, since the
// volume is provisioned again and the customer DNS record follows the primary
// to its new box, but it is the one that can finish. A volume without the
// marker may hold cache and is never released for a scheduling failure.
func (r *KuraInstanceReconciler) reconcileWipedVolumes(ctx context.Context, instance *kurav1alpha1.KuraInstance, pods []corev1.Pod) error {
	if err := r.clearWipedMarkersForScheduledPods(ctx, instance, pods); err != nil {
		return err
	}
	for i := range pods {
		pod := &pods[i]
		if pod.DeletionTimestamp != nil || pod.Spec.NodeName != "" || !podUnschedulable(pod) {
			continue
		}
		claim := &corev1.PersistentVolumeClaim{}
		if err := r.Get(ctx, types.NamespacedName{Name: "data-" + pod.Name, Namespace: pod.Namespace}, claim); err != nil {
			if apierrors.IsNotFound(err) {
				continue
			}
			return err
		}
		if !claimWiped(claim) {
			continue
		}
		log.FromContext(ctx).Info("releasing an empty Kura data volume whose machine cannot take its pod", "pod", pod.Name, "pvc", claim.Name)
		if err := r.releaseNodeLocalVolume(ctx, pod); err != nil {
			return err
		}
	}
	return nil
}

func (r *KuraInstanceReconciler) clearWipedMarkersForScheduledPods(ctx context.Context, instance *kurav1alpha1.KuraInstance, pods []corev1.Pod) error {
	for i := range pods {
		pod := &pods[i]
		if pod.Spec.NodeName == "" {
			continue
		}
		claim := &corev1.PersistentVolumeClaim{}
		if err := r.Get(ctx, types.NamespacedName{Name: "data-" + pod.Name, Namespace: instance.Namespace}, claim); err != nil {
			if apierrors.IsNotFound(err) {
				continue
			}
			return err
		}
		if _, ok := claim.Annotations[volumeWipedAnnotation]; !ok {
			continue
		}
		before := claim.DeepCopy()
		delete(claim.Annotations, volumeWipedAnnotation)
		if err := r.Patch(ctx, claim, client.MergeFrom(before)); err != nil {
			return err
		}
	}
	return nil
}

func podUnschedulable(pod *corev1.Pod) bool {
	for _, condition := range pod.Status.Conditions {
		if condition.Type == corev1.PodScheduled {
			return condition.Status == corev1.ConditionFalse && condition.Reason == corev1.PodReasonUnschedulable
		}
	}
	return false
}

func claimWiped(claim *corev1.PersistentVolumeClaim) bool {
	return claim.Annotations[volumeWipedAnnotation] != ""
}
