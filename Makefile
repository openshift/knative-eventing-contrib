# This file is needed by kubebuilder but all functionality should exist inside
# the hack/ files.

CGO_ENABLED=0
GOOS=linux
CORE_IMAGES=$(shell find ./cmd -mindepth 1 -maxdepth 1 -type d)

all: generate manifests test verify
	
# Run tests
test: generate manifests verify
	go test ./pkg/... ./cmd/... -coverprofile cover.out

# Deploy default
deploy: manifests
	kustomize build config/default | ko apply -f /dev/stdin

# Generate manifests e.g. CRD, RBAC etc.
manifests:
	./hack/update-manifests.sh

# Generate code
generate: deps
	./hack/update-codegen.sh

# Dep ensure
deps:
	./hack/update-deps.sh

# Verify
verify: verify-codegen verify-manifests

# Verify codegen
verify-codegen:
	./hack/verify-codegen.sh

# Verify manifests
verify-manifests:
	./hack/verify-manifests.sh

# Install core images
install:
	go install $(CORE_IMAGES)
.PHONY: install

# Run E2E tests on OpenShift
test-e2e:
	./openshift/e2e-tests-openshift.sh
.PHONY: test-e2e

# Generate Dockerfiles for images used by ci-operator. The files need to be committed manually.
generate-dockerfiles:
	./openshift/ci-operator/generate-dockerfiles.sh openshift/ci-operator/knative-images $(CORE_IMAGES)
.PHONY: generate-dockerfiles
