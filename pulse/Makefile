# The arguments for building images.
CARGO_PROFILE ?=
FEATURES ?=
TARGET_DIR ?=
TARGET ?=
BUILD_BIN ?= pulse
BUILD_PACKAGE ?= $(if $(filter pulse,$(strip $(BUILD_BIN))),cmd)
BUILD_PACKAGE_OPT = $(if $(strip $(BUILD_PACKAGE)),-p ${BUILD_PACKAGE})
CARGO_BUILD_OPTS := --locked
IMAGE_REGISTRY ?= docker.io
IMAGE_NAMESPACE ?= pulse
IMAGE_TAG ?= latest
BUILDX_MULTI_PLATFORM_BUILD ?= false
BUILDX_BUILDER_NAME ?= gtbuilder
BASE_IMAGE ?= ubuntu
OUTPUT_DIR := $(shell if [ "$(RELEASE)" = "true" ]; then echo "release"; elif [ ! -z "$(CARGO_PROFILE)" ]; then echo "$(CARGO_PROFILE)" ; else echo "debug"; fi)
SQLNESS_OPTS ?=

# The arguments for running integration tests.
ETCD_VERSION ?= v3.5.9
ETCD_IMAGE ?= quay.io/coreos/etcd:${ETCD_VERSION}
RETRY_COUNT ?= 3
NEXTEST_OPTS := --retries ${RETRY_COUNT} --features pg_kvbackend,mysql_kvbackend
BUILD_JOBS ?= $(shell which nproc 1>/dev/null && expr $$(nproc) / 2) # If nproc is not available, we don't set the build jobs.
ifeq ($(BUILD_JOBS), 0) # If the number of cores is less than 2, set the build jobs to 1.
  BUILD_JOBS := 1
endif

ifneq ($(strip $(BUILD_JOBS)),)
	NEXTEST_OPTS += --build-jobs=${BUILD_JOBS}
endif

ifneq ($(strip $(BUILD_JOBS)),)
	SQLNESS_OPTS += --jobs ${BUILD_JOBS}
endif

ifneq ($(strip $(CARGO_PROFILE)),)
	CARGO_BUILD_OPTS += --profile ${CARGO_PROFILE}
endif

ifneq ($(strip $(FEATURES)),)
	CARGO_BUILD_OPTS += --features ${FEATURES}
endif

ifneq ($(strip $(TARGET_DIR)),)
	CARGO_BUILD_OPTS += --target-dir ${TARGET_DIR}
endif

ifneq ($(strip $(TARGET)),)
	CARGO_BUILD_OPTS += --target ${TARGET}
endif

ifneq ($(strip $(BUILD_BIN)),)
	CARGO_BUILD_OPTS += --bin ${BUILD_BIN}
endif

ifneq ($(strip $(RELEASE)),)
	CARGO_BUILD_OPTS += --release
endif

ifeq ($(BUILDX_MULTI_PLATFORM_BUILD), all)
	BUILDX_MULTI_PLATFORM_BUILD_OPTS := --platform linux/amd64,linux/arm64 --push
else ifeq ($(BUILDX_MULTI_PLATFORM_BUILD), amd64)
	BUILDX_MULTI_PLATFORM_BUILD_OPTS := --platform linux/amd64 --push
else ifeq ($(BUILDX_MULTI_PLATFORM_BUILD), arm64)
	BUILDX_MULTI_PLATFORM_BUILD_OPTS := --platform linux/arm64 --push
else
	BUILDX_MULTI_PLATFORM_BUILD_OPTS := -o type=docker
endif

ifneq ($(strip $(CARGO_BUILD_EXTRA_OPTS)),)
	CARGO_BUILD_OPTS += ${CARGO_BUILD_EXTRA_OPTS}
endif

##@ Build

.PHONY: build
build: ## Build debug version pulse.
	cargo ${CARGO_EXTENSION} build ${BUILD_PACKAGE_OPT} ${CARGO_BUILD_OPTS}

.PHONY: clean
clean: ## Clean the project.
	cargo clean

.PHONY: fmt
fmt: ## Format all the Rust code.
	cargo fmt --all

.PHONY: fmt-toml
fmt-toml: ## Format all TOML files.
	taplo format

.PHONY: check-toml
check-toml: ## Check all TOML files.
	taplo format --check

.PHONY: docker-image-buildx
docker-image-buildx: multi-platform-buildx ## Build docker image by buildx.
	docker buildx build --builder ${BUILDX_BUILDER_NAME} \
	  --build-arg="CARGO_PROFILE=${CARGO_PROFILE}" \
	  --build-arg="FEATURES=${FEATURES}" \
	  --build-arg="OUTPUT_DIR=${OUTPUT_DIR}" \
	  -f docker/buildx/${BASE_IMAGE}/Dockerfile \
	  -t ${IMAGE_REGISTRY}/${IMAGE_NAMESPACE}/pulse:${IMAGE_TAG} ${BUILDX_MULTI_PLATFORM_BUILD_OPTS} .

.PHONY: multi-platform-buildx
multi-platform-buildx: ## Create buildx multi-platform builder.
	docker buildx inspect ${BUILDX_BUILDER_NAME} || docker buildx create --name ${BUILDX_BUILDER_NAME} --driver docker-container --bootstrap --use

##@ Test
.PHONY: test
test: nextest ## Run unit and integration tests.
	cargo nextest run ${NEXTEST_OPTS}

.PHONY: nextest
nextest: ## Install nextest tools.
	cargo --list | grep nextest || cargo install cargo-nextest --locked

.PHONY: sqlness-test
sqlness-test: ## Run sqlness test.
	cargo sqlness bare ${SQLNESS_OPTS}

RUNS ?= 1
FUZZ_TARGET ?= fuzz_alter_table
.PHONY: fuzz
fuzz: ## Run fuzz test ${FUZZ_TARGET} (requires a nightly toolchain).
	cargo +nightly fuzz run ${FUZZ_TARGET} --fuzz-dir tests-fuzz -D -s none -- -runs=${RUNS}

.PHONY: fuzz-ls
fuzz-ls: ## List all fuzz targets (requires a nightly toolchain).
	cargo +nightly fuzz list --fuzz-dir tests-fuzz

.PHONY: check
check: ## Cargo check all the targets.
	cargo check --workspace --all-targets --all-features

.PHONY: clippy
clippy: ## Check clippy rules.
	cargo clippy --workspace --all-targets --all-features -- -D warnings

.PHONY: fix-clippy
fix-clippy: ## Fix clippy violations.
	cargo clippy --workspace --all-targets --all-features --fix

.PHONY: check-udeps
check-udeps: ## Check unused dependencies.
	cargo shear

.PHONY: fix-udeps
fix-udeps: ## Remove unused dependencies automatically.
	cargo shear --fix

.PHONY: fmt-check
fmt-check: ## Check code format.
	cargo fmt --all -- --check
	python3 scripts/check-snafu.py
	python3 scripts/check-super-imports.py

.PHONY: start-etcd
start-etcd: ## Start single node etcd for testing purpose.
	docker run --rm -d --network=host -p 2379-2380:2379-2380 ${ETCD_IMAGE}

.PHONY: stop-etcd
stop-etcd: ## Stop single node etcd for testing purpose.
	docker stop $$(docker ps -q --filter ancestor=${ETCD_IMAGE})

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# https://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display help messages.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
