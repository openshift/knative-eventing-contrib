# This file is needed by kubebuilder but all functionality should exist inside
# the hack/ files.

CGO_ENABLED=0
GOOS=linux
CORE_IMAGES=$(shell find ./cmd -mindepth 1 -maxdepth 1 -type d)
# There may not be any test images so ignore errors
TEST_IMAGES=$(shell find ./test/test_images -mindepth 1 -maxdepth 1 -type d 2> /dev/null)
LOCAL_IMAGES=\
	kafka-source-adapter kafka-source-controller \
	kafka-channel-controller kafka-channel-dispatcher kafka-channel-webhook \
	camel-source-controller \
	github-receive-adapter github-source-controller

all: generate manifests test verify

# Run tests
test: generate manifests verify
	go test ./pkg/... ./cmd/... -coverprofile cover.out

# Deploy default
nndeploy: manifests
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

# Build and install commands.
install:
	go install $(CORE_IMAGES)
	go build -o $(GOPATH)/bin/kafka-source-controller ./kafka/source/cmd/controller
	go build -o $(GOPATH)/bin/kafka-source-adapter ./kafka/source/cmd/receive_adapter
	go build -o $(GOPATH)/bin/kafka-channel-controller ./kafka/channel/cmd/channel_controller
	go build -o $(GOPATH)/bin/kafka-channel-dispatcher ./kafka/channel/cmd/channel_dispatcher
	go build -o $(GOPATH)/bin/kafka-channel-webhook ./kafka/channel/cmd/webhook
	go build -o $(GOPATH)/bin/camel-source-controller ./camel/source/cmd/controller
	go build -o $(GOPATH)/bin/github-source-controller ./github/cmd/controller
	go build -o $(GOPATH)/bin/github-receive-adapter ./github/cmd/receive_adapter
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
	# Remove old images and re-generate, avoid stale images hanging around.
	rm -rf openshift/ci-operator/knative-images/*
	rm -rf openshift/ci-operator/knative-test-images/*
	./openshift/ci-operator/generate-dockerfiles.sh openshift/ci-operator/knative-images $(CORE_IMAGES) $(LOCAL_IMAGES)
	./openshift/ci-operator/generate-dockerfiles.sh openshift/ci-operator/knative-test-images $(TEST_IMAGES)
.PHONY: generate-dockerfiles

# Generates a ci-operator configuration for a specific branch.
generate-ci-config:
	./openshift/ci-operator/generate-ci-config.sh $(BRANCH) 4.1 > ci-operator-config_41.yaml
	./openshift/ci-operator/generate-ci-config.sh $(BRANCH) 4.2 > ci-operator-config_42.yaml
.PHONY: generate-ci-config

generate-kafka:
	./openshift/release/generate-kafka.sh $(RELEASE)
.PHONY: generate-kafka

generate-camel:
	./openshift/release/generate-camel.sh $(RELEASE)
.PHONY: generate-camel
