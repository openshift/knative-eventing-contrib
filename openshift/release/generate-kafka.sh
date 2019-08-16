#!/usr/bin/env bash

source $(dirname $0)/resolve.sh

release=$1

#image_prefix="quay.io/openshift-knative/knative-eventing-contrib-"
output_file="openshift/release/knative-eventing-kafka-contrib-${release}.yaml"

if [ $release = "ci" ]; then
    image_prefix="image-registry.openshift-image-registry.svc:5000/knative-eventing/knative-eventing-contrib-"
    tag=""
else
    image_prefix="quay.io/openshift-knative/knative-eventing-contrib-"
    tag=$release
fi

# Apache Kafka Source
resolve_resources kafka/source/config kafka-src-resolved.yaml $image_prefix $release
cat kafka-src-resolved.yaml >> $output_file
rm kafka-src-resolved.yaml

# Apache Kafka Channel CCP
resolve_resources kafka/channel/config/provisioner kafka-ccp-resolved.yaml $image_prefix $release
cat kafka-ccp-resolved.yaml >> $output_file
rm kafka-ccp-resolved.yaml


# Apache Kafka Channel CRD
resolve_resources kafka/channel/config kafka-crd-resolved.yaml $image_prefix $release
cat kafka-crd-resolved.yaml >> $output_file
rm kafka-crd-resolved.yaml
