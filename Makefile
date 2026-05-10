#!/usr/bin/make -f

###############################################################################
###                           Module & Versioning                           ###
###############################################################################

VERSION ?= $(shell echo $(shell git describe --tags --always) | sed 's/^v//')
TMVERSION := $(shell go list -m github.com/cometbft/cometbft | sed 's:.* ::')
COMMIT := $(shell git log -1 --format='%H')

###############################################################################
###                          Directories & Binaries                         ###
###############################################################################

BINDIR ?= $(GOPATH)/bin
BUILDDIR ?= $(CURDIR)/build
EXAMPLE_BINARY := infinited

###############################################################################
###                              Repo Info                                  ###
###############################################################################

HTTPS_GIT := git@github.com:deep-thought-labs/infinite.git
DOCKER := $(or $(shell command -v docker 2>/dev/null),docker)

# Chain-upgrade system tests (tests/systemtests/chainupgrade): legacy binary is always taken from
# GitHub Releases for SYSTEMTEST_LEGACY_TAG (`make build-legacy-systemtest-binary`; alias: `build-v05`).
# No git checkout / local compile of the tag. Release assets are Linux-only; on macOS use `make test-system-docker`.
SYSTEMTEST_LEGACY_TAG ?= v0.2.0
SYSTEMTEST_LEGACY_REPO ?= deep-thought-labs/infinite
SYSTEMTEST_LEGACY_ASSET_LINUX_AMD64 ?= infinite_Linux_x86_64.tar.gz
SYSTEMTEST_LEGACY_ASSET_LINUX_ARM64 ?= infinite_Linux_ARM64.tar.gz
SYSTEMTEST_LEGACY_CHECKSUM_FILE ?= checksums.txt

# Prebuilt image for faster local Docker system tests (see tests/systemtests/docker/Dockerfile).
SYSTEMTEST_DOCKER_IMAGE ?= infinite-systemtest-env:local
# Named volumes: persist Go module + build cache between `test-system-docker-reuse` runs.
SYSTEMTEST_DOCKER_GOMOD_VOLUME ?= infinite-systemtest-gomod
SYSTEMTEST_DOCKER_GOCACHE_VOLUME ?= infinite-systemtest-gocache

export GO111MODULE = on

# Root `go.mod` directive — drives Docker golang:${GO_MOD_VERSION}-trixie (see test-system-docker*).
GO_MOD_VERSION ?= $(shell sed -n '/^go /s/^go //p' "$(CURDIR)/go.mod" 2>/dev/null | head -n1)

###############################################################################
###                            Submodule Settings                           ###
###############################################################################

# infinited is a separate module under ./infinited
INFINITED_DIR      := infinited
INFINITED_MAIN_PKG := ./cmd/infinited

###############################################################################
###                        Build & Install infinited                         ###
###############################################################################

# process build tags
build_tags = netgo

ifeq (cleveldb,$(findstring cleveldb,$(COSMOS_BUILD_OPTIONS)))
  build_tags += gcc
endif
ifeq (rocksdb,$(findstring rocksdb,$(COSMOS_BUILD_OPTIONS)))
  build_tags += gcc
  build_tags += rocksdb
endif
build_tags += $(BUILD_TAGS)
build_tags := $(strip $(build_tags))

# process linker flags

ldflags = -X github.com/cosmos/cosmos-sdk/version.Name=infinite \
          -X github.com/cosmos/cosmos-sdk/version.AppName=$(EXAMPLE_BINARY) \
          -X github.com/cosmos/cosmos-sdk/version.Version=$(VERSION) \
          -X github.com/cosmos/cosmos-sdk/version.Commit=$(COMMIT) \
          -X github.com/cometbft/cometbft/version.TMCoreSemVer=$(TMVERSION)

# DB backend selection
ifeq (cleveldb,$(findstring cleveldb,$(COSMOS_BUILD_OPTIONS)))
  ldflags += -X github.com/cosmos/cosmos-sdk/types.DBBackend=cleveldb
endif
ifeq (rocksdb,$(findstring rocksdb,$(COSMOS_BUILD_OPTIONS)))
  ldflags += -X github.com/cosmos/cosmos-sdk/types.DBBackend=rocksdb
endif

# add build tags to linker flags
whitespace := $(subst ,, )
comma := ,
build_tags_comma_sep := $(subst $(whitespace),$(comma),$(build_tags))
ldflags += -X "github.com/cosmos/cosmos-sdk/version.BuildTags=$(build_tags_comma_sep)"

ifeq (,$(findstring nostrip,$(COSMOS_BUILD_OPTIONS)))
  ldflags += -w -s
endif
ldflags += $(LDFLAGS)
ldflags := $(strip $(ldflags))

ifeq (staticlink,$(findstring staticlink,$(COSMOS_BUILD_OPTIONS)))
  ldflags += -linkmode external -extldflags '-static'
endif

BUILD_FLAGS := -tags "$(build_tags)" -ldflags '$(ldflags)'
# check for nostrip option
ifeq (,$(findstring nostrip,$(COSMOS_BUILD_OPTIONS)))
  BUILD_FLAGS += -trimpath
endif

# check if no optimization option is passed
# used for remote debugging
ifneq (,$(findstring nooptimization,$(COSMOS_BUILD_OPTIONS)))
  BUILD_FLAGS += -gcflags "all=-N -l"
endif

# Build into $(BUILDDIR)
build: go.sum
	@mkdir -p "$(BUILDDIR)"
	@echo "🏗️  Building infinited to $(BUILDDIR)/$(EXAMPLE_BINARY) ..."
	@echo "BUILD_FLAGS: $(BUILD_FLAGS)"
	@cd "$(INFINITED_DIR)" && CGO_ENABLED="1" \
	  go build $(BUILD_FLAGS) -o "$(BUILDDIR)/$(EXAMPLE_BINARY)" $(INFINITED_MAIN_PKG)

# Cross-compile for Linux AMD64
build-linux:
	GOOS=linux GOARCH=amd64 $(MAKE) build

# Cross-compilation builds for releases
# NOTE: These require CGO_ENABLED=1 for cryptographic functions (secp256k1)
# For best cross-compilation support, use GoReleaser or build on native platforms
# These commands work best when building for the same OS (e.g., Linux to Linux, macOS to macOS)

build-cross-linux-amd64:
	@echo "🏗️  Building binary for Linux AMD64 (requires cross-compilation tools)..."
	@echo "⚠️  Note: Cross-compilation with CGO from macOS to Linux may require additional setup"
	@mkdir -p "$(BUILDDIR)"
	@cd "$(INFINITED_DIR)" && CGO_ENABLED=1 GOOS=linux GOARCH=amd64 \
	  go build $(BUILD_FLAGS) -o "$(BUILDDIR)/infinited-linux-amd64" $(INFINITED_MAIN_PKG)

build-cross-linux-arm64:
	@echo "🏗️  Building binary for Linux ARM64 (requires cross-compilation tools)..."
	@mkdir -p "$(BUILDDIR)"
	@cd "$(INFINITED_DIR)" && CGO_ENABLED=1 GOOS=linux GOARCH=arm64 \
	  go build $(BUILD_FLAGS) -o "$(BUILDDIR)/infinited-linux-arm64" $(INFINITED_MAIN_PKG)

build-cross-darwin-amd64:
	@echo "🏗️  Building binary for macOS Intel..."
	@mkdir -p "$(BUILDDIR)"
	@cd "$(INFINITED_DIR)" && CGO_ENABLED=1 GOOS=darwin GOARCH=amd64 \
	  go build $(BUILD_FLAGS) -o "$(BUILDDIR)/infinited-darwin-amd64" $(INFINITED_MAIN_PKG)

build-cross-darwin-arm64:
	@echo "🏗️  Building binary for macOS Apple Silicon..."
	@mkdir -p "$(BUILDDIR)"
	@cd "$(INFINITED_DIR)" && CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 \
	  go build $(BUILD_FLAGS) -o "$(BUILDDIR)/infinited-darwin-arm64" $(INFINITED_MAIN_PKG)

build-cross-windows-amd64:
	@echo "🏗️  Building binary for Windows AMD64 (requires cross-compilation tools)..."
	@echo "⚠️  Note: Cross-compilation to Windows from macOS/Linux may require additional setup"
	@mkdir -p "$(BUILDDIR)"
	@cd "$(INFINITED_DIR)" && CGO_ENABLED=1 GOOS=windows GOARCH=amd64 \
	  go build $(BUILD_FLAGS) -o "$(BUILDDIR)/infinited-windows-amd64.exe" $(INFINITED_MAIN_PKG)

# Simple build from infinited directory (works reliably)
# Use this when you need to build manually and can change to the infinited directory
build-from-infinited:
	@echo "🏗️  Building from infinited directory..."
	@echo "💡 Tip: Run 'cd infinited && go build ./cmd/infinited' for direct control"
	@mkdir -p "$(BUILDDIR)"
	@cd "$(INFINITED_DIR)" && go build $(BUILD_FLAGS) -o "$(BUILDDIR)/infinited" $(INFINITED_MAIN_PKG)

# Install into $(BINDIR)
install: go.sum
	@echo "🚚  Installing infinited to $(BINDIR) ..."
	@echo "BUILD_FLAGS: $(BUILD_FLAGS)"
	@cd "$(INFINITED_DIR)" && CGO_ENABLED="1" \
	  go install $(BUILD_FLAGS) $(INFINITED_MAIN_PKG)

# Default & all target
.PHONY: all build build-linux install build-cross-linux-amd64 build-cross-linux-arm64 \
        build-cross-darwin-amd64 build-cross-darwin-arm64 build-cross-windows-amd64 \
        build-from-infinited
all: build

###############################################################################
###                          Tools & Dependencies                           ###
###############################################################################

go.sum: go.mod
	echo "Ensure dependencies have not been modified ..." >&2
	go mod verify
	go mod tidy

vulncheck:
	@go install golang.org/x/vuln/cmd/govulncheck@latest
	@$(shell go env GOPATH)/bin/govulncheck ./...

###############################################################################
###                           Tests & Simulation                            ###
###############################################################################

PACKAGES_NOSIMULATION=$(shell go list ./... | grep -v '/simulation')
PACKAGES_UNIT := $(shell go list ./... | grep -v '/tests/e2e$$' | grep -v '/simulation')
PACKAGES_INFINITED := $(shell cd infinited && go list ./... | grep -v '/simulation')
COVERPKG_EVM  := $(shell go list ./... | grep -v '/tests/e2e$$' | grep -v '/simulation' | paste -sd, -)
COVERPKG_ALL  := $(COVERPKG_EVM)
COVERPKG_INFINITED := $(shell cd infinited && go list ./... | grep -v '/simulation' | paste -sd, -)
COMMON_COVER_ARGS := -timeout=15m -covermode=atomic
# Infinite fork: precompile integration suites under `tests/integration/precompiles` often exceed 15m with `-race`
# on cold CI runners; wider timeout applies only to those two coverage targets (see test-unit-cover-*-precompiles).
COMMON_COVER_ARGS_PRECOMPILE_INTEGRATION := -timeout=25m -covermode=atomic

# Granular coverage blocks: root module vs `tests/integration`, `infinited` vs `infinited/tests/integration`,
# and within each integration tree a split between `tests/integration/precompiles/*` and the rest.
# Infinite fork: six blocks isolate heavyweight precompile suites for clearer CI attribution and timeouts.
# CI runs each block in a separate job (see .github/workflows/test.yml).
PACKAGES_EVM_CORE := $(shell go list ./... | grep -v '/tests/e2e$$' | grep -v '/simulation' | grep -v '/tests/integration')
PACKAGES_EVM_INTEGRATION := $(shell go list ./... | grep '/tests/integration' | grep -v '/tests/integration/precompiles')
PACKAGES_EVM_INTEGRATION_PRECOMPILES := $(shell go list ./... | grep '/tests/integration/precompiles')
PACKAGES_INFINITED_CORE := $(shell cd infinited && go list ./... | grep -v '/simulation' | grep -v '/tests/integration')
PACKAGES_INFINITED_INTEGRATION := $(shell cd infinited && go list ./... | grep '/tests/integration' | grep -v '/tests/integration/precompiles')
PACKAGES_INFINITED_INTEGRATION_PRECOMPILES := $(shell cd infinited && go list ./... | grep '/tests/integration/precompiles')

COVERAGE_EVM_CORE := coverage_evm_core.txt
COVERAGE_EVM_INTEGRATION := coverage_evm_integration.txt
COVERAGE_EVM_INTEGRATION_PRECOMPILES := coverage_evm_integration_precompiles.txt
COVERAGE_INFINITED_CORE := coverage_infinited_core.txt
COVERAGE_INFINITED_INTEGRATION := coverage_infinited_integration.txt
COVERAGE_INFINITED_INTEGRATION_PRECOMPILES := coverage_infinited_integration_precompiles.txt

# test-report-* LHS may `cd infinited`; anchor RHS to repo root so `go run` and logs/* resolve consistently.
GO_TEST_REPORT_PKG := $(CURDIR)/scripts/cmd/go-test-report

# Shared `go test` recipes (identical flags to test-unit-cover-*). test-report-* appends -json and pipes to go-test-report.
# Must follow PACKAGES_* and COVERAGE_* (immediate := expansion).
CMD_COVER_EVM_CORE := go test -race -tags=test -mod=readonly $(COMMON_COVER_ARGS) -coverpkg=$(COVERPKG_ALL) -coverprofile=$(COVERAGE_EVM_CORE) $(PACKAGES_EVM_CORE)
CMD_COVER_EVM_INTEGRATION := go test -race -tags=test -mod=readonly $(COMMON_COVER_ARGS) -coverpkg=$(COVERPKG_ALL) -coverprofile=$(COVERAGE_EVM_INTEGRATION) $(PACKAGES_EVM_INTEGRATION)
CMD_COVER_EVM_INTEGRATION_PRECOMPILES := go test -race -tags=test -mod=readonly $(COMMON_COVER_ARGS_PRECOMPILE_INTEGRATION) -coverpkg=$(COVERPKG_ALL) -coverprofile=$(COVERAGE_EVM_INTEGRATION_PRECOMPILES) $(PACKAGES_EVM_INTEGRATION_PRECOMPILES)
CMD_COVER_INFINITED_CORE := cd $(INFINITED_DIR) && go test -race -tags=test -mod=readonly $(COMMON_COVER_ARGS) -coverpkg=$(COVERPKG_INFINITED) -coverprofile=../$(COVERAGE_INFINITED_CORE) $(PACKAGES_INFINITED_CORE)
CMD_COVER_INFINITED_INTEGRATION := cd $(INFINITED_DIR) && go test -race -tags=test -mod=readonly $(COMMON_COVER_ARGS) -coverpkg=$(COVERPKG_INFINITED) -coverprofile=../$(COVERAGE_INFINITED_INTEGRATION) $(PACKAGES_INFINITED_INTEGRATION)
CMD_COVER_INFINITED_INTEGRATION_PRECOMPILES := cd $(INFINITED_DIR) && go test -race -tags=test -mod=readonly $(COMMON_COVER_ARGS_PRECOMPILE_INTEGRATION) -coverpkg=$(COVERPKG_INFINITED) -coverprofile=../$(COVERAGE_INFINITED_INTEGRATION_PRECOMPILES) $(PACKAGES_INFINITED_INTEGRATION_PRECOMPILES)

TEST_PACKAGES := ./...
TEST_TARGETS := test-unit test-evmd test-unit-cover test-race

test-unit: ARGS=-timeout=15m
test-unit: TEST_PACKAGES=$(PACKAGES_UNIT)
test-unit: run-tests

test-race: ARGS=-race
test-race: TEST_PACKAGES=$(PACKAGES_UNIT)
test-race: run-tests

test-infinited: ARGS=-timeout=15m
test-infinited:
	@cd infinited && go test -race -tags=test -mod=readonly $(ARGS) $(EXTRA_ARGS) $(PACKAGES_INFINITED)

# Full local coverage: six blocks (parallel-safe as prerequisites of merge) then merge + filter + summary.
test-unit-cover: test-unit-cover-merge

test-unit-cover-evm-core:
	@echo "🔍 Coverage block: evm core (root module, excluding tests/integration)..."
	@$(CMD_COVER_EVM_CORE)

test-unit-cover-evm-integration:
	@echo "🔍 Coverage block: evm integration (root tests/integration/*, excluding precompiles subtree)..."
	@$(CMD_COVER_EVM_INTEGRATION)

test-unit-cover-evm-integration-precompiles:
	@echo "🔍 Coverage block: evm integration precompiles (root tests/integration/precompiles/*)..."
	@$(CMD_COVER_EVM_INTEGRATION_PRECOMPILES)

test-unit-cover-infinited-core:
	@echo "🔍 Coverage block: infinited core (excluding tests/integration)..."
	@$(CMD_COVER_INFINITED_CORE)

test-unit-cover-infinited-integration:
	@echo "🔍 Coverage block: infinited integration (infinited/tests/integration/*, excluding precompiles subtree)..."
	@$(CMD_COVER_INFINITED_INTEGRATION)

test-unit-cover-infinited-integration-precompiles:
	@echo "🔍 Coverage block: infinited integration precompiles (infinited/tests/integration/precompiles/*)..."
	@$(CMD_COVER_INFINITED_INTEGRATION_PRECOMPILES)

# Enriched report: same `go test` recipe as test-unit-cover-* plus -json and scripts/cmd/go-test-report (writes logs/*.log).
test-report-evm-core:
	@echo "📋 Report block: evm core (same recipe as test-unit-cover-evm-core)..."
	@bash -o pipefail -c '$(CMD_COVER_EVM_CORE) -json 2>&1 | ( cd "$(CURDIR)" && go run "$(GO_TEST_REPORT_PKG)" -log test-report-evm-core -tee=false -jsonl-out logs/test-report-evm-core.jsonl )'

test-report-evm-integration:
	@echo "📋 Report block: evm integration (same recipe as test-unit-cover-evm-integration)..."
	@bash -o pipefail -c '$(CMD_COVER_EVM_INTEGRATION) -json 2>&1 | ( cd "$(CURDIR)" && go run "$(GO_TEST_REPORT_PKG)" -log test-report-evm-integration -tee=false -jsonl-out logs/test-report-evm-integration.jsonl )'

test-report-evm-integration-precompiles:
	@echo "📋 Report block: evm integration precompiles (same recipe as test-unit-cover-evm-integration-precompiles)..."
	@bash -o pipefail -c '$(CMD_COVER_EVM_INTEGRATION_PRECOMPILES) -json 2>&1 | ( cd "$(CURDIR)" && go run "$(GO_TEST_REPORT_PKG)" -log test-report-evm-integration-precompiles -tee=false -jsonl-out logs/test-report-evm-integration-precompiles.jsonl )'

test-report-infinited-core:
	@echo "📋 Report block: infinited core (same recipe as test-unit-cover-infinited-core)..."
	@bash -o pipefail -c '$(CMD_COVER_INFINITED_CORE) -json 2>&1 | ( cd "$(CURDIR)" && go run "$(GO_TEST_REPORT_PKG)" -log test-report-infinited-core -tee=false -jsonl-out logs/test-report-infinited-core.jsonl )'

test-report-infinited-integration:
	@echo "📋 Report block: infinited integration (same recipe as test-unit-cover-infinited-integration)..."
	@bash -o pipefail -c '$(CMD_COVER_INFINITED_INTEGRATION) -json 2>&1 | ( cd "$(CURDIR)" && go run "$(GO_TEST_REPORT_PKG)" -log test-report-infinited-integration -tee=false -jsonl-out logs/test-report-infinited-integration.jsonl )'

test-report-infinited-integration-precompiles:
	@echo "📋 Report block: infinited integration precompiles (same recipe as test-unit-cover-infinited-integration-precompiles)..."
	@bash -o pipefail -c '$(CMD_COVER_INFINITED_INTEGRATION_PRECOMPILES) -json 2>&1 | ( cd "$(CURDIR)" && go run "$(GO_TEST_REPORT_PKG)" -log test-report-infinited-integration-precompiles -tee=false -jsonl-out logs/test-report-infinited-integration-precompiles.jsonl )'

test-report-all: test-report-evm-core test-report-evm-integration test-report-evm-integration-precompiles test-report-infinited-core test-report-infinited-integration test-report-infinited-integration-precompiles
	@echo "📋 All six report blocks completed."

test-unit-cover-merge: test-unit-cover-evm-core test-unit-cover-evm-integration test-unit-cover-evm-integration-precompiles test-unit-cover-infinited-core test-unit-cover-infinited-integration test-unit-cover-infinited-integration-precompiles
	@echo "🔀 Merging coverage blocks into coverage.txt..."
	@echo "mode: atomic" > coverage.txt
	@grep -h -v '^mode:' $(COVERAGE_EVM_CORE) $(COVERAGE_EVM_INTEGRATION) $(COVERAGE_EVM_INTEGRATION_PRECOMPILES) $(COVERAGE_INFINITED_CORE) $(COVERAGE_INFINITED_INTEGRATION) $(COVERAGE_INFINITED_INTEGRATION_PRECOMPILES) >> coverage.txt
	@echo "🧹 Filtering ignored files from coverage.txt..."
	@grep -v -E '/cmd/|/client/|/proto/|/testutil/|/mocks/|/test_.*\.go:|\.pb\.go:|\.pb\.gw\.go:|/x/[^/]+/module\.go:|/scripts/|/ibc/testing/|/version/|\.md:|\.pulsar\.go:' coverage.txt > tmp_coverage.txt && mv tmp_coverage.txt coverage.txt
	@echo "📊 Coverage summary:"
	@go tool cover -func=coverage.txt

test: test-unit

test-all:
	@echo "🔍 Running evm module tests..."
	@go test -race -tags=test -mod=readonly -timeout=15m $(PACKAGES_NOSIMULATION)
	@echo "🔍 Running infinited module tests..."
	# Infinite fork: infinited includes heavy integration suites that can (a) exceed 15m on cold caches with `-race`,
	# and (b) deadlock/flake when multiple integration packages run concurrently (shared ports/processes).
	# Run the infinited module tests serially (`-p=1`) and with a wider timeout to reduce spurious failures.
	@cd infinited && go test -p=1 -race -tags=test -mod=readonly -timeout=30m $(PACKAGES_INFINITED)

run-tests:
ifneq (,$(shell which tparse 2>/dev/null))
	go test -race -tags=test -mod=readonly -json $(ARGS) $(EXTRA_ARGS) $(TEST_PACKAGES) | tparse
else
	go test -race -tags=test -mod=readonly $(ARGS) $(EXTRA_ARGS) $(TEST_PACKAGES)
endif


test-scripts:
	@echo "Running scripts tests"
	@pytest -s -vv ./scripts

test-solidity:
	@echo "Beginning solidity tests..."
	./scripts/run-solidity-tests.sh

.PHONY: run-tests test test-all $(TEST_TARGETS) \
	test-unit-cover-evm-core test-unit-cover-evm-integration test-unit-cover-evm-integration-precompiles \
	test-unit-cover-infinited-core test-unit-cover-infinited-integration test-unit-cover-infinited-integration-precompiles \
	test-unit-cover-merge \
	test-report-evm-core test-report-evm-integration test-report-evm-integration-precompiles \
	test-report-infinited-core test-report-infinited-integration test-report-infinited-integration-precompiles \
	test-report-all

benchmark:
	@go test -race -tags=test -mod=readonly -bench=. $(PACKAGES_NOSIMULATION)

.PHONY: benchmark

###############################################################################
###                                Linting                                  ###
###############################################################################
golangci_lint_cmd=golangci-lint
golangci_version=v2.10.1

# Pin matches dependency of DavidAnson/markdownlint-cli2-action@v16 (.github/workflows/lint.yml).
markdownlint_cli2_version=0.13.0

lint: lint-go lint-python lint-contracts lint-md

lint-go:
	@echo "--> Running linter"
	@go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@$(golangci_version)
	@$(shell go env GOPATH)/bin/golangci-lint run --timeout=15m

lint-python:
	@echo "--> Checking Python linters..."
	@if command -v pylint >/dev/null 2>&1; then \
		echo "  ✓ pylint found, running Python linter..."; \
		find . -name "*.py" -type f -not -path "*/node_modules/*" -not -path "*/lib/*" -not -path "*/tests/evm-tools-compatibility/*" | xargs pylint || true; \
	else \
		echo "  ⚠️  pylint not installed - Python linting skipped"; \
		echo "     To install: pip install pylint (optional, for code quality)"; \
	fi
	@if command -v flake8 >/dev/null 2>&1; then \
		echo "  ✓ flake8 found, running Python style checker..."; \
		flake8 || true; \
	else \
		echo "  ⚠️  flake8 not installed - Python style checking skipped"; \
		echo "     To install: pip install flake8 (optional, for code quality)"; \
	fi

lint-contracts:
	@echo "--> Checking Solidity linter..."
	@if command -v solhint >/dev/null 2>&1; then \
		echo "  ✓ solhint found, running Solidity linter..."; \
		solhint contracts/**/*.sol || true; \
	else \
		echo "  ⚠️  solhint not installed - Solidity linting skipped"; \
		echo "     To install: npm install -g solhint@v5.0.5 (optional, for contract code quality)"; \
		echo "     Note: Not required to build the binary, only for contract development"; \
	fi

lint-md:
	@echo "--> Running markdownlint (markdownlint-cli2 $(markdownlint_cli2_version), same pin as GitHub Actions markdownlint-cli2-action@v16)..."
	@if ! command -v npx >/dev/null 2>&1; then \
		echo "  npx not found; install Node.js to run markdownlint (https://nodejs.org/)"; \
		exit 1; \
	fi
	npx --yes markdownlint-cli2@$(markdownlint_cli2_version) "**/*.md"

lint-fix:
	@go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@$(golangci_version)
	@$(shell go env GOPATH)/bin/golangci-lint run --timeout=15m --fix

lint-fix-contracts:
	solhint --fix contracts/**/*.sol

.PHONY: lint lint-fix lint-contracts lint-go lint-md lint-python

format: format-go format-python format-shell

format-go:
	find . -name '*.go' -type f -not -path "./vendor*" -not -path "*.git*" -not -path "./client/docs/statik/statik.go" -not -name '*.pb.go' -not -name '*.pb.gw.go' -not -name '*.pulsar.go' | xargs gofumpt -w -l

format-python: format-isort format-black

format-black:
	find . -name '*.py' -type f -not -path "*/node_modules/*" | xargs black

format-isort:
	find . -name '*.py' -type f -not -path "*/node_modules/*" | xargs isort

format-shell:
	shfmt -l -w .

.PHONY: format format-go format-python format-black format-isort format-go

###############################################################################
###                                Protobuf                                 ###
###############################################################################

protoVer=0.18.1
protoImageName=ghcr.io/cosmos/proto-builder:$(protoVer)
protoImage=$(DOCKER) run --rm -v "$(CURDIR):/workspace" --workdir /workspace --user 0 $(protoImageName)

protoLintVer=0.44.0
protoLinterImage=yoheimuta/protolint
protoLinter=$(DOCKER) run --rm -v "$(CURDIR):/workspace" --workdir /workspace --user 0 $(protoLinterImage):$(protoLintVer)

# ------
# NOTE: If you are experiencing problems running these commands, try deleting
#       the docker images and execute the desired command again.
#
proto-all: proto-format proto-lint proto-gen

proto-gen:
	@echo "generating implementations from Protobuf files"
	@$(protoImage) sh ./scripts/generate_protos.sh
	@$(protoImage) sh ./scripts/generate_protos_pulsar.sh

proto-format:
	@echo "formatting Protobuf files"
	@$(protoImage) find ./ -name *.proto -exec clang-format -i {} \;

proto-lint:
	@echo "linting Protobuf files"
	@$(protoImage) buf lint --error-format=json
	@$(protoLinter) lint ./proto

proto-check-breaking:
	@echo "checking Protobuf files for breaking changes"
	@$(protoImage) buf breaking --against $(HTTPS_GIT)#branch=main

.PHONY: proto-all proto-gen proto-format proto-lint proto-check-breaking

###############################################################################
###                                Releasing                                ###
###############################################################################

PACKAGE_NAME:=github.com/cosmos/evm
GOLANG_CROSS_VERSION  = v1.22
GOPATH ?= '$(HOME)/go'
release-dry-run:
	@echo "Getting CometBFT version..."
	@echo "TMVERSION=$(TMVERSION)"
	@echo "ℹ️  GoReleaser mostrará el progreso de cada build..."
	docker run \
		--rm \
		--privileged \
		--platform linux/amd64 \
		-e CGO_ENABLED=1 \
		-e TMVERSION=$(TMVERSION) \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-v `pwd`:/go/src/$(PACKAGE_NAME) \
		-v ${GOPATH}/pkg:/go/pkg \
		-w /go/src/$(PACKAGE_NAME) \
		ghcr.io/goreleaser/goreleaser-cross:${GOLANG_CROSS_VERSION} \
		--clean --skip validate --skip publish --snapshot

# Release dry-run solo para Linux (más rápido para desarrollo)
# NOTE: Linux ARM64 builds may fail on Mac M1 with Docker emulation
#       This is expected - ARM64 builds work correctly in GitHub Actions (Ubuntu native)
release-dry-run-linux:
	@echo "Getting CometBFT version..."
	@echo "TMVERSION=$(TMVERSION)"
	@echo "ℹ️  Compilando solo para Linux (amd64 y arm64)..."
	@echo "⚠️  Nota: Builds ARM64 pueden fallar en Mac M1 con Docker emulado"
	@echo "          Esto es normal - ARM64 funciona correctamente en GitHub Actions"
	@echo "ℹ️  GoReleaser mostrará el progreso de cada build..."
	docker run \
		--rm \
		--privileged \
		--platform linux/amd64 \
		-e CGO_ENABLED=1 \
		-e TMVERSION=$(TMVERSION) \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-v `pwd`:/go/src/$(PACKAGE_NAME) \
		-v ${GOPATH}/pkg:/go/pkg \
		-w /go/src/$(PACKAGE_NAME) \
		ghcr.io/goreleaser/goreleaser-cross:${GOLANG_CROSS_VERSION} \
		--clean --skip validate --skip publish --snapshot \
		--config .goreleaser.linux-only.yml

release:
	@if [ ! -f ".release-env" ]; then \
		echo "\033[91m.release-env is required for release\033[0m";\
		exit 1;\
	fi
	@echo "Getting CometBFT version..."
	@echo "TMVERSION=$(TMVERSION)"
	docker run \
		--rm \
		--privileged \
		--platform linux/amd64 \
		-e CGO_ENABLED=1 \
		-e TMVERSION=$(TMVERSION) \
		--env-file .release-env \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-v `pwd`:/go/src/$(PACKAGE_NAME) \
		-v ${GOPATH}/pkg:/go/pkg \
		-w /go/src/$(PACKAGE_NAME) \
		ghcr.io/goreleaser/goreleaser-cross:${GOLANG_CROSS_VERSION} \
		release --clean --skip validate

.PHONY: release-dry-run release-dry-run-linux release

###############################################################################
###                        Compile Solidity Contracts                       ###
###############################################################################

# Install the necessary dependencies, compile the solidity contracts found in the
# Cosmos EVM repository and then clean up the contracts data.
contracts-all: contracts-compile contracts-clean

# Clean smart contract compilation artifacts, dependencies and cache files
contracts-clean:
	@echo "Cleaning up the contracts directory..."
	@python3 ./scripts/compile_smart_contracts/compile_smart_contracts.py --clean

# Compile the solidity contracts found in the Cosmos EVM repository.
contracts-compile:
	@echo "Compiling smart contracts..."
	@python3 ./scripts/compile_smart_contracts/compile_smart_contracts.py --compile

# Add a new solidity contract to be compiled
contracts-add:
	@echo "Adding a new smart contract to be compiled..."
	@python3 ./scripts/compile_smart_contracts/compile_smart_contracts.py --add $(CONTRACT)

###############################################################################
###                                Localnet                                 ###
###############################################################################

localnet-build-env:
	$(MAKE) -C contrib/images evmd-env

localnet-build-nodes:
	$(DOCKER) run --rm -v $(CURDIR)/.testnets:/data cosmos/evmd \
			  testnet init-files --validator-count 4 -o /data --starting-ip-address 192.168.10.2 --keyring-backend=test --chain-id=local-4221 --use-docker=true
	docker compose up -d

localnet-stop:
	docker compose down

# localnet-start will run a 4-node testnet locally. The nodes are
# based off the docker images in: ./contrib/images/simd-env
localnet-start: localnet-stop localnet-build-env localnet-build-nodes


test-rpc-compat:
	@./tests/jsonrpc/scripts/run-compat-test.sh

test-rpc-compat-stop:
	cd tests/jsonrpc && docker compose down

.PHONY: localnet-start localnet-stop localnet-build-env localnet-build-nodes test-rpc-compat test-rpc-compat-stop test-system test-system-docker test-system-docker-build test-system-docker-reuse build-legacy-systemtest-binary build-v05 mocks

test-system: build-legacy-systemtest-binary build
	mkdir -p ./tests/systemtests/binaries/
	cp "$(BUILDDIR)/$(EXAMPLE_BINARY)" ./tests/systemtests/binaries/evmd
	cd tests/systemtests/Counter && forge build
	$(MAKE) -C tests/systemtests test

# Run system tests in Linux container (recommended on macOS when legacy artifacts are Linux-only).
# Image tag golang:$(GO_MOD_VERSION)-trixie follows root go.mod; override GO_MOD_VERSION only if needed.
# Base image must ship glibc >= the release legacy binary (e.g. v0.2.0 may require GLIBC_2.38+);
# bookworm (2.36) is too old — use trixie (Debian 13) or newer.
# Do not pin --platform linux/amd64 on Apple Silicon: QEMU user-mode breaks CometBFT P2P SecretConnection
# (chacha20poly1305: message authentication failed), numPeers=0, timeout waiting for node start.
#
# Ephemeral run: installs apt + Foundry on every invocation (slow). For local iteration, prefer:
#   make test-system-docker-build   # once (or when Dockerfile / toolchain changes)
#   make test-system-docker-reuse   # fast: same image + persisted Go mod/build caches
test-system-docker:
	@if [ -z "$(GO_MOD_VERSION)" ]; then echo "ERROR: empty GO_MOD_VERSION (could not read go directive from go.mod)" >&2; exit 1; fi
	@echo "🐳 Running system tests in Linux container (ephemeral; apt + Foundry each run); Go $(GO_MOD_VERSION) ..."
	@$(DOCKER) run --rm \
		-v "$(CURDIR):/workspace" \
		-w /workspace \
		-e GOTOOLCHAIN=auto \
		-e SYSTEMTEST_LEGACY_TAG="$(SYSTEMTEST_LEGACY_TAG)" \
		-e SYSTEMTEST_LEGACY_REPO="$(SYSTEMTEST_LEGACY_REPO)" \
		-e SYSTEMTEST_LEGACY_ASSET_LINUX_AMD64="$(SYSTEMTEST_LEGACY_ASSET_LINUX_AMD64)" \
		-e SYSTEMTEST_LEGACY_ASSET_LINUX_ARM64="$(SYSTEMTEST_LEGACY_ASSET_LINUX_ARM64)" \
		-e SYSTEMTEST_LEGACY_CHECKSUM_FILE="$(SYSTEMTEST_LEGACY_CHECKSUM_FILE)" \
		"golang:$(GO_MOD_VERSION)-trixie" bash -lc '\
			set -euo pipefail; \
			apt-get update -qq; \
			apt-get install -y --no-install-recommends build-essential git make curl ca-certificates jq tar xz-utils python3; \
			export PATH="/usr/local/go/bin:$$PATH"; \
			if ! command -v go >/dev/null 2>&1; then echo "ERROR: go not found inside container"; exit 1; fi; \
			go version; \
			curl -fsSL https://foundry.paradigm.xyz | bash; \
			/root/.foundry/bin/foundryup; \
			export PATH="/root/.foundry/bin:$$PATH"; \
			make test-system \
		'

# Build reusable system-test image (apt + Foundry baked in). Rebuild when tests/systemtests/docker/Dockerfile changes.
test-system-docker-build:
	@if [ -z "$(GO_MOD_VERSION)" ]; then echo "ERROR: empty GO_MOD_VERSION (could not read go directive from go.mod)" >&2; exit 1; fi
	@echo "🐳 Building $(SYSTEMTEST_DOCKER_IMAGE) (Go $(GO_MOD_VERSION)) ..."
	@$(DOCKER) build --build-arg "GO_VERSION=$(GO_MOD_VERSION)" -t "$(SYSTEMTEST_DOCKER_IMAGE)" -f tests/systemtests/docker/Dockerfile tests/systemtests/docker

# Run system tests using prebuilt image + named volumes for Go module and build caches.
test-system-docker-reuse:
	@echo "🐳 Running system tests with $(SYSTEMTEST_DOCKER_IMAGE) (cached toolchain + Go caches)..."
	@$(DOCKER) run --rm \
		-v "$(CURDIR):/workspace" \
		-v "$(SYSTEMTEST_DOCKER_GOMOD_VOLUME):/go/pkg/mod" \
		-v "$(SYSTEMTEST_DOCKER_GOCACHE_VOLUME):/root/.cache/go-build" \
		-w /workspace \
		-e GOTOOLCHAIN=auto \
		-e GOMODCACHE=/go/pkg/mod \
		-e GOCACHE=/root/.cache/go-build \
		-e SYSTEMTEST_LEGACY_TAG="$(SYSTEMTEST_LEGACY_TAG)" \
		-e SYSTEMTEST_LEGACY_REPO="$(SYSTEMTEST_LEGACY_REPO)" \
		-e SYSTEMTEST_LEGACY_ASSET_LINUX_AMD64="$(SYSTEMTEST_LEGACY_ASSET_LINUX_AMD64)" \
		-e SYSTEMTEST_LEGACY_ASSET_LINUX_ARM64="$(SYSTEMTEST_LEGACY_ASSET_LINUX_ARM64)" \
		-e SYSTEMTEST_LEGACY_CHECKSUM_FILE="$(SYSTEMTEST_LEGACY_CHECKSUM_FILE)" \
		-e TEST_ARGS="$(TEST_ARGS)" \
		"$(SYSTEMTEST_DOCKER_IMAGE)" \
		bash -lc 'set -euo pipefail; export PATH="/usr/local/go/bin:$$PATH"; go version; forge --version; make test-system TEST_ARGS="$$TEST_ARGS"'

# Download legacy chain-upgrade binary from GitHub Releases only (matches .goreleaser archive names).
# Installs to tests/systemtests/binaries/v0.2/evmd (pre-upgrade line vs current-branch binary).
build-legacy-systemtest-binary:
	@set -e; \
	case "$$(uname -s)" in \
		Darwin) \
			echo ""; \
			echo "ERROR: Legacy release artifacts are Linux-only. On macOS run:"; \
			echo "  make test-system-docker"; \
			echo "(or run system tests on a Linux host)."; \
			echo ""; \
			exit 1 ;; \
	esac; \
	mkdir -p ./tests/systemtests/binaries/v0.2; \
	target="./tests/systemtests/binaries/v0.2/evmd"; \
	asset=""; \
	case "$$(uname -m)" in \
		x86_64|amd64) asset="$(SYSTEMTEST_LEGACY_ASSET_LINUX_AMD64)" ;; \
		aarch64|arm64) asset="$(SYSTEMTEST_LEGACY_ASSET_LINUX_ARM64)" ;; \
		*) echo "ERROR: Unsupported machine for legacy download: $$(uname -m)"; exit 1 ;; \
	esac; \
	base_url="https://github.com/$(SYSTEMTEST_LEGACY_REPO)/releases/download/$(SYSTEMTEST_LEGACY_TAG)"; \
	tmpdir=$$(mktemp -d); \
	trap 'rm -rf "$$tmpdir"' EXIT; \
	echo "⬇️  Downloading legacy $$asset ($(SYSTEMTEST_LEGACY_TAG))..."; \
	curl -fsSL "$$base_url/$(SYSTEMTEST_LEGACY_CHECKSUM_FILE)" -o "$$tmpdir/checksums.txt"; \
	curl -fsSL "$$base_url/$$asset" -o "$$tmpdir/archive.tar.gz"; \
	expected=$$(awk -v a="$$asset" '{ \
		name=$$2; sub(/^\*/, "", name); \
		if (name == a) { print $$1; exit } \
	}' "$$tmpdir/checksums.txt"); \
	if [ -z "$$expected" ]; then \
		echo "ERROR: No checksum line for $$asset in $(SYSTEMTEST_LEGACY_CHECKSUM_FILE)."; \
		exit 1; \
	fi; \
	actual=$$(shasum -a 256 "$$tmpdir/archive.tar.gz" | awk '{print $$1}'); \
	if [ "$$expected" != "$$actual" ]; then \
		echo "ERROR: SHA256 mismatch for $$asset (expected $$expected, got $$actual)."; \
		exit 1; \
	fi; \
	tar -xzf "$$tmpdir/archive.tar.gz" -C "$$tmpdir"; \
	if [ -f "$$tmpdir/infinited" ]; then cp "$$tmpdir/infinited" "$$target"; \
	elif [ -f "$$tmpdir/evmd" ]; then cp "$$tmpdir/evmd" "$$target"; \
	else \
		echo "ERROR: Archive $$asset did not contain infinited or evmd at top level."; \
		exit 1; \
	fi; \
	chmod +x "$$target"; \
	echo "✅ Legacy binary ready at $$target"

# Deprecated alias — prefer build-legacy-systemtest-binary.
build-v05: build-legacy-systemtest-binary

mocks:
	@echo "--> generating mocks"
	@go get github.com/vektra/mockery/v2
	@go generate ./...
	@make format-go

###############################################################################
###                              D2 Diagrams                                ###
###############################################################################

D2_THEME=300
D2_DARK_THEME=200
D2_LAYOUT=tala

D2_ENV_VARS=D2_THEME=$(D2_THEME) \
	    D2_DARK_THEME=$(D2_DARK_THEME) \
	    D2_LAYOUT=$(D2_LAYOUT)

.PHONY: d2check d2watch d2gen d2gen-all

d2check:
	@echo "🔍 checking if d2 is installed..."
	@which d2 > /dev/null 2>&1 || { \
		echo "🔴 d2 is not installed, see installation docs: https://d2lang.com/tour/install/"; \
		exit 1; \
	}
	@echo "🟢 d2 is installed"
	@echo "🔍 checking if $(D2_LAYOUT) layout is installed..."
	@d2 layout | grep $(D2_LAYOUT) > /dev/null 2>&1 || { \
		echo "🔴 $(D2_LAYOUT) layout is not installed, see docs: https://d2lang.com/tour/layouts/"; \
		exit 1; \
	}
	@echo "🟢 $(D2_LAYOUT) layout is installed"

d2watch: d2check
	@if [ -z "$(FILE)" ]; then \
		echo "🔴 missing required parameter FILE, the correct usage is: make d2watch FILE=path/to/file.d2"; \
		exit 1; \
	fi
	@if [ ! -f "$(FILE)" ]; then \
		echo "🔴 file $(FILE) does not exist"; \
		exit 1; \
	fi
	@echo "🔄 watching $(FILE) for changes..."
	@dir=$$(dirname "$(FILE)"); \
	basename=$$(basename "$(FILE)" .d2); \
	svgfile="$$dir/$$basename.svg"; \
	printf "📊 generating $$svgfile from $(FILE)... "; \
	$(D2_ENV_VARS) d2 --watch "$(FILE)" "$$svgfile"

d2gen: d2check
	@if [ -z "$(FILE)" ]; then \
		echo "🔴 missing required parameter FILE, the correct usage is: make d2gen FILE=path/to/file.d2"; \
		exit 1; \
	fi
	@if [ ! -f "$(FILE)" ]; then \
		echo "🔴 file $(FILE) does not exist"; \
		exit 1; \
	fi
	@dir=$$(dirname "$(FILE)"); \
	basename=$$(basename "$(FILE)" .d2); \
	svgfile="$$dir/$$basename.svg"; \
	printf "📊 generating $$svgfile from $(FILE)... "; \
	$(D2_ENV_VARS) d2 "$(FILE)" "$$svgfile" > /dev/null 2>&1 && echo "done ✅" || echo "failed ❌";

d2gen-all: d2check
	@echo "🟢 generating svg files for all d2 diagrams..."
	@find . -name "*.d2" -type f | while read d2file; do \
		dir=$$(dirname "$$d2file"); \
		basename=$$(basename "$$d2file" .d2); \
		svgfile="$$dir/$$basename.svg"; \
		printf "📊 generating $$svgfile from $$d2file... "; \
		$(D2_ENV_VARS) d2 "$$d2file" "$$svgfile" > /dev/null 2>&1 && echo "done ✅" || echo "failed ❌"; \
	done
	@echo "✅ svg files generated for all d2 diagrams"
