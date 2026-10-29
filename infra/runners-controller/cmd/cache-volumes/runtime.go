package main

import (
	"context"
	"fmt"

	runtimeapi "k8s.io/cri-api/pkg/apis/runtime/v1"
)

// Kubelet's SubPath mount stays busy while our propagated child mount exists.
// The CRI writer fence lets us unmount it after the VM stops, so kubelet can
// finish deleting its directory. API pod absence alone is not a writer fence.
func runtimeGone(ctx context.Context, runtime runtimeapi.RuntimeServiceClient, uid string) (bool, error) {
	if runtime == nil {
		return false, fmt.Errorf("runtime teardown verifier unavailable")
	}
	sandboxes, err := runtime.ListPodSandbox(ctx, &runtimeapi.ListPodSandboxRequest{})
	if err != nil {
		return false, err
	}
	ids := map[string]bool{}
	for _, sandbox := range sandboxes.Items {
		if sandbox.Metadata == nil {
			return false, fmt.Errorf("runtime returned a sandbox without identity")
		}
		if sandbox.Metadata.GetUid() != uid {
			continue
		}
		ids[sandbox.Id] = true
		if sandbox.State != runtimeapi.PodSandboxState_SANDBOX_NOTREADY {
			return false, nil
		}
	}
	containers, err := runtime.ListContainers(ctx, &runtimeapi.ListContainersRequest{})
	if err != nil {
		return false, err
	}
	for _, container := range containers.Containers {
		if ids[container.PodSandboxId] || container.Labels["io.kubernetes.pod.uid"] == uid {
			if container.State != runtimeapi.ContainerState_CONTAINER_EXITED {
				return false, nil
			}
		}
	}
	return true, nil
}
