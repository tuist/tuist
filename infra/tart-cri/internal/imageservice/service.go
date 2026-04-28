// Package imageservice implements CRI's ImageService — pull/list/
// remove of OCI images. Tart already speaks the OCI registry
// protocol (`tart pull` and `tart push`), so each method is a thin
// shim.
package imageservice

import (
	"context"

	runtimeapi "k8s.io/cri-api/pkg/apis/runtime/v1"

	"github.com/tuist/tuist/infra/tart-cri/internal/tart"
)

type Service struct {
	runtimeapi.UnimplementedImageServiceServer

	Tart *tart.Runtime
}

func New(t *tart.Runtime) *Service { return &Service{Tart: t} }

func (s *Service) PullImage(ctx context.Context, req *runtimeapi.PullImageRequest) (*runtimeapi.PullImageResponse, error) {
	image := req.GetImage().GetImage()
	if err := s.Tart.Pull(ctx, image); err != nil {
		return nil, err
	}
	return &runtimeapi.PullImageResponse{ImageRef: image}, nil
}

func (s *Service) ListImages(ctx context.Context, _ *runtimeapi.ListImagesRequest) (*runtimeapi.ListImagesResponse, error) {
	vms, err := s.Tart.List(ctx)
	if err != nil {
		return nil, err
	}
	// Tart's "image" surface is the same as its VM list — every
	// non-running VM is a clonable image. We deduplicate by Source.
	seen := map[string]struct{}{}
	images := []*runtimeapi.Image{}
	for _, vm := range vms {
		if vm.Source == "" {
			continue
		}
		if _, ok := seen[vm.Source]; ok {
			continue
		}
		seen[vm.Source] = struct{}{}
		images = append(images, &runtimeapi.Image{
			Id:          vm.Source,
			RepoTags:    []string{vm.Source},
			RepoDigests: []string{vm.Source},
			Size_:       uint64(vm.Size),
		})
	}
	return &runtimeapi.ListImagesResponse{Images: images}, nil
}

func (s *Service) ImageStatus(ctx context.Context, req *runtimeapi.ImageStatusRequest) (*runtimeapi.ImageStatusResponse, error) {
	image := req.GetImage().GetImage()
	vms, err := s.Tart.List(ctx)
	if err != nil {
		return nil, err
	}
	for _, vm := range vms {
		if vm.Source == image {
			return &runtimeapi.ImageStatusResponse{
				Image: &runtimeapi.Image{
					Id:          image,
					RepoTags:    []string{image},
					RepoDigests: []string{image},
					Size_:       uint64(vm.Size),
				},
			}, nil
		}
	}
	return &runtimeapi.ImageStatusResponse{}, nil
}

func (s *Service) RemoveImage(ctx context.Context, req *runtimeapi.RemoveImageRequest) (*runtimeapi.RemoveImageResponse, error) {
	if err := s.Tart.Delete(ctx, req.GetImage().GetImage()); err != nil {
		return nil, err
	}
	return &runtimeapi.RemoveImageResponse{}, nil
}

func (s *Service) ImageFsInfo(_ context.Context, _ *runtimeapi.ImageFsInfoRequest) (*runtimeapi.ImageFsInfoResponse, error) {
	// Kubelet uses this for image-disk eviction decisions. Returning
	// an empty response disables eviction; for production we'd query
	// `df` on Tart's image dir (~/.tart/cache/...).
	return &runtimeapi.ImageFsInfoResponse{}, nil
}
