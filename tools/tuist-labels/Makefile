.PHONY: setup assets build test format serve dist
export GOWORK=off

setup:
	mix deps.get
	npm ci --ignore-scripts
	$(MAKE) assets build

assets:
	npm run build

build:
	go build -trimpath -o bin/tuist-labels ./cmd/tuist-labels

serve:
	mix phx.server

test:
	mix test
	go test -race -count=1 ./...

format:
	mix format
	gofmt -w cmd
	npm run format

dist:
	@for os in darwin linux windows; do for arch in arm64 amd64; do \
		suffix=""; [ "$$os" != windows ] || suffix=.exe; \
		CGO_ENABLED=0 GOOS=$$os GOARCH=$$arch go build -trimpath -o dist/$$os-$$arch/tuist-labels$$suffix ./cmd/tuist-labels || exit 1; \
	done; done
