module github.com/tuist/tuist/infra/vm-image-builder-bootstrap

go 1.25

require (
	github.com/tuist/tuist/infra/macos-host-bootstrap v0.0.0
	golang.org/x/crypto v0.31.0
	golang.org/x/term v0.27.0
)

require golang.org/x/sys v0.28.0 // indirect

replace github.com/tuist/tuist/infra/macos-host-bootstrap => ../macos-host-bootstrap
