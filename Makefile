# This file is needed by kubebuilder but all functionality should exist inside
# the hack/ files.

CGO_ENABLED=0
GOOS=linux
CORE_IMAGES=$(shell find ./cmd -mindepth 1 -maxdepth 1 -type d)
TEST_IMAGES=$(shell find ./test/test_images -mindepth 1 -maxdepth 1 -type d)

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
	go build -o $(GOPATH)/bin/kafka-source-controller ./contrib/kafka/cmd/controller
	go build -o $(GOPATH)/bin/kafka-source-adapter ./contrib/kafka/cmd/receive_adapter
	go build -o $(GOPATH)/bin/camel-source-controller ./contrib/camel/cmd/controller
source.adapter: install

test-install:
	for img in $(TEST_IMAGES); do \
		go install $$img ; \
	done
.PHONY: test-install

# Run E2E tests on OpenShift
test-e2e:
	./openshift/e2e-tests-openshift.sh
.PHONY: test-e2e

# Generate Dockerfiles for images used by ci-operator. The files need to be committed manually.
generate-dockerfiles:
	./openshift/ci-operator/generate-dockerfiles.sh openshift/ci-operator/knative-images $(CORE_IMAGES)
	./openshift/ci-operator/generate-dockerfiles.sh openshift/ci-operator/knative-images kafka-source-adapter
	./openshift/ci-operator/generate-dockerfiles.sh openshift/ci-operator/knative-images kafka-source-controller
	./openshift/ci-operator/generate-dockerfiles.sh openshift/ci-operator/knative-images camel-source-controller
	./openshift/ci-operator/generate-dockerfiles.sh openshift/ci-operator/knative-test-images $(TEST_IMAGES)
.PHONY: generate-dockerfiles

# Generates a ci-operator configuration for a specific branch.
generate-ci-config:
	./openshift/ci-operator/generate-ci-config.sh $(BRANCH) > ci-operator-config.yaml
.PHONY: generate-ci-config

# Generate an aggregated knative yaml file with replaced image references
generate-release:
	./openshift/release/generate-release.sh $(RELEASE)
.PHONY: generate-release

generate-kafka:
	./openshift/release/generate-kafka.sh $(RELEASE)
.PHONY: generate-release
