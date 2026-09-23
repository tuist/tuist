package main

import (
	"context"
	"errors"
	"testing"

	"google.golang.org/grpc"
	runtimeapi "k8s.io/cri-api/pkg/apis/runtime/v1"
)

type testRuntime struct {
	runtimeapi.RuntimeServiceClient
	sandboxes  []*runtimeapi.PodSandbox
	containers []*runtimeapi.Container
	err        error
}

func (r testRuntime) ListPodSandbox(context.Context, *runtimeapi.ListPodSandboxRequest, ...grpc.CallOption) (*runtimeapi.ListPodSandboxResponse, error) {
	return &runtimeapi.ListPodSandboxResponse{Items: r.sandboxes}, r.err
}
func (r testRuntime) ListContainers(context.Context, *runtimeapi.ListContainersRequest, ...grpc.CallOption) (*runtimeapi.ListContainersResponse, error) {
	return &runtimeapi.ListContainersResponse{Containers: r.containers}, r.err
}

func TestRuntimeGoneRequiresStoppedSandboxAndContainers(t *testing.T) {
	for _, tc := range []struct {
		name      string
		runtime   testRuntime
		gone      bool
		wantError bool
	}{
		{name: "removed", gone: true},
		{name: "unavailable", runtime: testRuntime{err: errors.New("CRI unavailable")}, wantError: true},
		{name: "live sandbox", runtime: testRuntime{sandboxes: []*runtimeapi.PodSandbox{{Id: "s", Metadata: &runtimeapi.PodSandboxMetadata{Uid: "u"}, State: runtimeapi.PodSandboxState_SANDBOX_READY}}}},
		{name: "stopped sandbox", runtime: testRuntime{sandboxes: []*runtimeapi.PodSandbox{{Id: "s", Metadata: &runtimeapi.PodSandboxMetadata{Uid: "u"}, State: runtimeapi.PodSandboxState_SANDBOX_NOTREADY}}}, gone: true},
		{name: "live container after sandbox stop", runtime: testRuntime{sandboxes: []*runtimeapi.PodSandbox{{Id: "s", Metadata: &runtimeapi.PodSandboxMetadata{Uid: "u"}, State: runtimeapi.PodSandboxState_SANDBOX_NOTREADY}}, containers: []*runtimeapi.Container{{PodSandboxId: "s", State: runtimeapi.ContainerState_CONTAINER_RUNNING}}}},
		{name: "orphan running container", runtime: testRuntime{containers: []*runtimeapi.Container{{Labels: map[string]string{"io.kubernetes.pod.uid": "u"}, State: runtimeapi.ContainerState_CONTAINER_RUNNING}}}},
		{name: "created container", runtime: testRuntime{containers: []*runtimeapi.Container{{Labels: map[string]string{"io.kubernetes.pod.uid": "u"}, State: runtimeapi.ContainerState_CONTAINER_CREATED}}}},
		{name: "exited container", runtime: testRuntime{containers: []*runtimeapi.Container{{Labels: map[string]string{"io.kubernetes.pod.uid": "u"}, State: runtimeapi.ContainerState_CONTAINER_EXITED}}}, gone: true},
		{name: "replacement pod", runtime: testRuntime{sandboxes: []*runtimeapi.PodSandbox{{Metadata: &runtimeapi.PodSandboxMetadata{Uid: "replacement"}, State: runtimeapi.PodSandboxState_SANDBOX_READY}}}, gone: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			gone, err := runtimeGone(context.Background(), tc.runtime, "u")
			if gone != tc.gone || (err != nil) != tc.wantError {
				t.Fatalf("gone=%v err=%v", gone, err)
			}
		})
	}
}
