.PHONY: build test format dist
export GOWORK=off

build:
	go build -trimpath -o bin/tuist-labels ./cmd/tuist-labels

test:
	go test -race -count=1 ./...

format:
	gofmt -w cmd

dist:
	@for os in darwin linux windows; do for arch in arm64 amd64; do \
		suffix=""; [ "$$os" != windows ] || suffix=.exe; \
		CGO_ENABLED=0 GOOS=$$os GOARCH=$$arch go build -trimpath -o dist/$$os-$$arch/tuist-labels$$suffix ./cmd/tuist-labels || exit 1; \
	done; done
