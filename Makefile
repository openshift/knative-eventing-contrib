# This file is needed by kubebuilder but all functionality should exist inside
# the hack/ files.

CGO_ENABLED=0
GOOS=linux
# Ignore errors if there are no images.
CORE_IMAGES=$(shell find ./cmd -mindepth 1 -maxdepth 1 -type d 2> /dev/null)
TEST_IMAGES=$(shell find ./test/test_images -mindepth 1 -maxdepth 1 -type d 2> /dev/null) $(shell find ./vendor/knative.dev/eventing/test/test_images -mindepth 1 -maxdepth 1 -type d 2> /dev/null) 

# Guess location of openshift/release repo. NOTE: override this if it is not correct.
OPENSHIFT=${CURDIR}/../../github.com/openshift/release

LOCAL_IMAGES=\
	kafka-source-adapter kafka-source-controller \
	kafka-channel-controller kafka-channel-dispatcher kafka-channel-webhook \

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

# Build and install commands.
install:
	for img in $(CORE_IMAGES); do go install $$img; done
	go build -o $(GOPATH)/bin/kafka-source-controller ./kafka/source/cmd/controller
	go build -o $(GOPATH)/bin/kafka-source-adapter ./kafka/source/cmd/receive_adapter
	go build -o $(GOPATH)/bin/kafka-channel-controller ./kafka/channel/cmd/channel_controller
	go build -o $(GOPATH)/bin/kafka-channel-dispatcher ./kafka/channel/cmd/channel_dispatcher
	go build -o $(GOPATH)/bin/kafka-channel-webhook ./kafka/channel/cmd/webhook
source.adapter: install

test-install:
	for img in $(TEST_IMAGES); do go install $$img; done
.PHONY: test-install

# Run E2E tests on OpenShift
test-e2e:
	./openshift/e2e-tests.sh
.PHONY: test-e2e

# Generate Dockerfiles for images used by ci-operator. The files need to be committed manually.
generate-dockerfiles:
	./openshift/ci-operator/generate-dockerfiles.sh openshift/ci-operator/knative-images $(CORE_IMAGES) $(LOCAL_IMAGES)
	./openshift/ci-operator/generate-dockerfiles.sh openshift/ci-operator/knative-test-images $(TEST_IMAGES)
.PHONY: generate-dockerfiles

# Update CI configuration and PROW files in the openshift/release repository.
# NOTE: This makes changes to files in the $(OPENSHIFT) directory, outside this repository
update-ci:
	sh ./openshift/ci-operator/update-ci.sh $(OPENSHIFT) $(CORE_IMAGES) $(LOCAL_IMAGES)
.PHONY: update-ci

generate-kafka:
	./openshift/release/generate-kafka.sh $(RELEASE)
.PHONY: generate-kafka
