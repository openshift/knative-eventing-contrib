#!/bin/bash

branch=${1-'knative-v0.8.1'}
openshift=${2-'4.3'}
promotion_disabled=${3-false}

cat <<EOF
tag_specification:
  cluster: https://api.ci.openshift.org
  name: '$openshift'
  namespace: ocp
promotion:
  additional_images:
    knative-eventing-contrib-src: src
  disabled: $promotion_disabled
  cluster: https://api.ci.openshift.org
  namespace: openshift
  name: $branch
base_images:
  base:
    name: '$openshift'
    namespace: ocp
    tag: base
build_root:
  project_image:
    dockerfile_path: openshift/ci-operator/build-image/Dockerfile
canonical_go_repository: knative.dev/eventing-contrib
binary_build_commands: make install
test_binary_build_commands: make test-install
tests:
- as: e2e-aws-ocp-${openshift//./}
  commands: "make test-e2e"
  openshift_installer_src:
    cluster_profile: aws
resources:
  '*':
    limits:
      memory: 4Gi
    requests:
      cpu: 100m
      memory: 200Mi
images:
EOF

core_images=$(find ./openshift/ci-operator/knative-images -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
for img in $core_images; do
  image_base=$(basename $img)
  to_image=$(echo ${image_base//_/-})
  cat <<EOF
- dockerfile_path: openshift/ci-operator/knative-images/$image_base/Dockerfile
  from: base
  inputs:
    bin:
      paths:
      - destination_dir: .
        source_path: /go/bin/$image_base
  to: knative-eventing-sources-$to_image
EOF
done

test_images=$(find ./openshift/ci-operator/knative-test-images -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
for img in $test_images; do
  image_base=$(basename $img)
  to_image=$(echo ${image_base//_/-})
  cat <<EOF
- dockerfile_path: openshift/ci-operator/knative-test-images/$image_base/Dockerfile
  from: base
  inputs:
    test-bin:
      paths:
      - destination_dir: .
        source_path: /go/bin/$image_base
  to: knative-eventing-sources-test-$to_image
EOF
done
