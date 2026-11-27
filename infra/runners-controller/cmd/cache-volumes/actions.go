package main

import (
	"context"
	"errors"
	"os"
	"strings"
	"sync"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
)

var errUnknownCaller = errors.New("not a runner pod on this node")

// runnerPods resolves a GitHub Actions cache request's source address to the
// live runner Pod on this node. Cache clients cannot add headers, so the
// address is the only proof; buildx and job containers egress as the Pod.
type runnerPods struct {
	kube            kubernetes.Interface
	namespace, node string
	mu              sync.Mutex
	byIP            map[string]cachevolumes.ActionsCaller
	listed          time.Time
}

func (p *runnerPods) caller(ctx context.Context, ip string) (cachevolumes.ActionsCaller, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	caller, ok := p.byIP[ip]
	// A Pod's address is reused only after its sandbox is gone, which takes far
	// longer than a listing lives.
	if ok && time.Since(p.listed) < 5*time.Second {
		return caller, nil
	}
	if time.Since(p.listed) < time.Second {
		if ok {
			return caller, nil
		}
		return cachevolumes.ActionsCaller{}, errUnknownCaller
	}
	pods, err := p.kube.CoreV1().Pods(p.namespace).List(ctx, metav1.ListOptions{
		LabelSelector: "tuist.dev/runner=true",
		FieldSelector: "spec.nodeName=" + p.node,
	})
	if err != nil {
		return cachevolumes.ActionsCaller{}, err
	}
	p.byIP = map[string]cachevolumes.ActionsCaller{}
	for _, pod := range pods.Items {
		if pod.Status.PodIP != "" && pod.Status.Phase == corev1.PodRunning && pod.DeletionTimestamp == nil && pod.Spec.NodeName == p.node {
			p.byIP[pod.Status.PodIP] = cachevolumes.ActionsCaller{PodName: pod.Name, PodUID: string(pod.UID)}
		}
	}
	p.listed = time.Now()
	if caller, ok = p.byIP[ip]; ok {
		return caller, nil
	}
	return cachevolumes.ActionsCaller{}, errUnknownCaller
}

// agentToken reads the agent's projected ServiceAccount token, which kubelet
// rotates in place, for every request.
func agentToken(path string) func(context.Context) (string, error) {
	return func(context.Context) (string, error) {
		token, err := os.ReadFile(path)
		return strings.TrimSpace(string(token)), err
	}
}
