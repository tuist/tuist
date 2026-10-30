//go:build linux

package main

import (
	"context"
	"fmt"
	"strconv"
	"time"

	"github.com/tuist/tuist/infra/kura-controller/internal/diskallocator"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/fields"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
)

func clusterInventory(node, namespace string) (func() ([]diskallocator.Volume, error), error) {
	config, err := rest.InClusterConfig()
	if err != nil {
		return nil, err
	}
	client, err := kubernetes.NewForConfig(config)
	if err != nil {
		return nil, err
	}
	return inventoryReader(client, node, namespace), nil
}

func inventoryReader(client kubernetes.Interface, node, namespace string) func() ([]diskallocator.Volume, error) {
	var cached []diskallocator.Volume
	var expires time.Time
	return func() ([]diskallocator.Volume, error) {
		if time.Now().Before(expires) {
			return cached, nil
		}
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		pods, err := client.CoreV1().Pods(namespace).List(ctx, metav1.ListOptions{FieldSelector: fields.OneTermEqualSelector("spec.nodeName", node).String()})
		if err != nil {
			return nil, err
		}
		// Three bounded lists avoid two GETs per replica exhausting client-go's
		// rate limit and the inventory deadline on a populated node.
		claims, err := client.CoreV1().PersistentVolumeClaims(namespace).List(ctx, metav1.ListOptions{})
		if err != nil {
			return nil, err
		}
		pvs, err := client.CoreV1().PersistentVolumes().List(ctx, metav1.ListOptions{})
		if err != nil {
			return nil, err
		}
		volumes, err := inventoryVolumes(pods.Items, claims.Items, pvs.Items, namespace)
		if err != nil {
			return nil, err
		}
		cached, expires = volumes, time.Now().Add(5*time.Second)
		return volumes, nil
	}
}

func inventoryVolumes(pods []corev1.Pod, claims []corev1.PersistentVolumeClaim, pvs []corev1.PersistentVolume, namespace string) ([]diskallocator.Volume, error) {
	claimsByName := map[string]corev1.PersistentVolumeClaim{}
	for _, claim := range claims {
		claimsByName[claim.Name] = claim
	}
	pvsByName := map[string]corev1.PersistentVolume{}
	for _, pv := range pvs {
		pvsByName[pv.Name] = pv
	}
	var volumes []diskallocator.Volume
	for _, pod := range pods {
		floorValue := pod.Annotations["kura.tuist.dev/disk-floor-bytes"]
		if floorValue == "" || pod.Status.Phase == corev1.PodSucceeded || pod.Status.Phase == corev1.PodFailed {
			continue
		}
		floor, err := strconv.ParseUint(floorValue, 10, 64)
		if err != nil {
			return nil, err
		}
		ceiling, err := strconv.ParseUint(pod.Annotations["kura.tuist.dev/disk-ceiling-bytes"], 10, 64)
		if err != nil {
			return nil, err
		}
		for _, volume := range pod.Spec.Volumes {
			if volume.Name != "data" || volume.PersistentVolumeClaim == nil {
				continue
			}
			claim, ok := claimsByName[volume.PersistentVolumeClaim.ClaimName]
			if !ok {
				return nil, fmt.Errorf("missing PVC for %s", pod.Name)
			}
			if claim.Spec.VolumeName == "" {
				continue
			}
			pv, ok := pvsByName[claim.Spec.VolumeName]
			if !ok || pv.Spec.ClaimRef == nil || pv.Spec.ClaimRef.UID != claim.UID || pv.Spec.ClaimRef.Namespace != namespace || pv.Spec.ClaimRef.Name != claim.Name {
				return nil, fmt.Errorf("PV ownership mismatch for %s", pod.Name)
			}
			path := ""
			if pv.Spec.HostPath != nil {
				path = pv.Spec.HostPath.Path
			}
			if pv.Spec.Local != nil {
				path = pv.Spec.Local.Path
			}
			if path == "" {
				return nil, fmt.Errorf("shared disk requires a local PV for %s", pod.Name)
			}
			volumes = append(volumes, diskallocator.Volume{ID: string(pod.UID), Path: path, Floor: floor, Ceiling: ceiling})
		}
	}
	return volumes, nil
}
