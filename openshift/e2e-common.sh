#!/usr/bin/env bash

export EVENTING_NAMESPACE="${EVENTING_NAMESPACE:-knative-eventing}"
export TEST_EVENTING_NAMESPACE=$EVENTING_NAMESPACE
export KNATIVE_DEFAULT_NAMESPACE=$EVENTING_NAMESPACE
export ZIPKIN_NAMESPACE=$EVENTING_NAMESPACE
export CONFIG_TRACING_CONFIG="test/config/config-tracing.yaml"
export STRIMZI_INSTALLATION_CONFIG_TEMPLATE="test/config/100-strimzi-cluster-operator-0.20.0.yaml"
export STRIMZI_INSTALLATION_CONFIG="$(mktemp)"
export KAFKA_INSTALLATION_CONFIG="test/config/100-kafka-ephemeral-triple-2.6.0.yaml"
export KAFKA_USERS_CONFIG="test/config/100-strimzi-users-0.20.0.yaml"
export KAFKA_PLAIN_CLUSTER_URL="my-cluster-kafka-bootstrap.kafka.svc.cluster.local:9092"
export KAFKA_TLS_CLUSTER_URL="my-cluster-kafka-bootstrap.kafka.svc.cluster.local:9093"
export KAFKA_SASL_CLUSTER_URL="my-cluster-kafka-bootstrap.kafka.svc.cluster.local:9094"
export KAFKA_TLS_CONFIG="test/config/config-kafka-tls.yaml"
export KAFKA_SASL_CONFIG="test/config/config-kafka-sasl.yaml"
export KAFKA_CRD_CONFIG_TEMPLATE_DIR="kafka/channel/config"
KAFKA_CLUSTER_URL=${KAFKA_PLAIN_CLUSTER_URL}

function scale_up_workers(){
  local cluster_api_ns="openshift-machine-api"

  oc get machineset -n ${cluster_api_ns} --show-labels

  # Get the name of the first machineset that has at least 1 replica
  local machineset
  machineset=$(oc get machineset -n ${cluster_api_ns} -o custom-columns="name:{.metadata.name},replicas:{.spec.replicas}" | grep " 1" | head -n 1 | awk '{print $1}')
  # Bump the number of replicas to 6 (+ 1 + 1 == 8 workers)
  oc patch machineset -n ${cluster_api_ns} "${machineset}" -p '{"spec":{"replicas":6}}' --type=merge
  wait_until_machineset_scales_up ${cluster_api_ns} "${machineset}" 6
}

# Waits until the machineset in the given namespaces scales up to the
# desired number of replicas
# Parameters: $1 - namespace
#             $2 - machineset name
#             $3 - desired number of replicas
function wait_until_machineset_scales_up() {
  echo -n "Waiting until machineset $2 in namespace $1 scales up to $3 replicas"
  for _ in {1..150}; do  # timeout after 15 minutes
    local available
    available=$(oc get machineset -n "$1" "$2" -o jsonpath="{.status.availableReplicas}")
    if [[ ${available} -eq $3 ]]; then
      echo -e "\nMachineSet $2 in namespace $1 successfully scaled up to $3 replicas"
      return 0
    fi
    echo -n "."
    sleep 6
  done
  echo - "Error: timeout waiting for machineset $2 in namespace $1 to scale up to $3 replicas"
  return 1
}

# Loops until duration (car) is exceeded or command (cdr) returns non-zero
function timeout() {
  SECONDS=0; TIMEOUT=$1; shift
  while eval $*; do
    sleep 5
    [[ $SECONDS -gt $TIMEOUT ]] && echo "ERROR: Timed out" && return 1
  done
  return 0
}

function install_tracing {
  deploy_zipkin
  enable_eventing_tracing
}

function deploy_zipkin {
  logger.info "Installing Zipkin in namespace ${ZIPKIN_NAMESPACE}"
  cat <<EOF | oc apply -f - || return $?
apiVersion: v1
kind: Service
metadata:
  name: zipkin
  namespace: ${ZIPKIN_NAMESPACE}
spec:
  type: NodePort
  ports:
  - name: http
    port: 9411
  selector:
    app: zipkin
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: zipkin
  namespace: ${ZIPKIN_NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: zipkin
  template:
    metadata:
      labels:
        app: zipkin
      annotations:
        sidecar.istio.io/inject: "false"
    spec:
      containers:
      - name: zipkin
        image: docker.io/openzipkin/zipkin:2.13.0
        ports:
        - containerPort: 9411
        env:
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: metadata.namespace
        resources:
          limits:
            memory: 1000Mi
          requests:
            memory: 256Mi
---
EOF

  logger.info "Waiting until Zipkin is available"
  oc wait deployment --all --timeout=600s --for=condition=Available -n ${ZIPKIN_NAMESPACE} || return 1
}

function enable_eventing_tracing {
  header "Configuring tracing for Eventing"

  cat <<EOF | oc apply -f - || return $?
apiVersion: v1
kind: ConfigMap
metadata:
  name: config-tracing
  namespace: ${EVENTING_NAMESPACE}
data:
  enable: "true"
  zipkin-endpoint: "http://zipkin.${ZIPKIN_NAMESPACE}.svc.cluster.local:9411/api/v2/spans"
  sample-rate: "1.0"
  debug: "true"
EOF
}

function create_auth_secrets() {
  create_tls_secrets
  create_sasl_secrets
}

function create_tls_secrets() {
  header "Creating TLS Kafka secret"
  STRIMZI_CRT=$(oc -n kafka get secret my-cluster-cluster-ca-cert --template='{{index .data "ca.crt"}}' | base64 --decode )
  TLSUSER_CRT=$(oc -n kafka get secret my-tls-user --template='{{index .data "user.crt"}}' | base64 --decode )
  TLSUSER_KEY=$(oc -n kafka get secret my-tls-user --template='{{index .data "user.key"}}' | base64 --decode )

  kubeocctl create secret --namespace knative-eventing generic strimzi-tls-secret \
    --from-literal=ca.crt="$STRIMZI_CRT" \
    --from-literal=user.crt="$TLSUSER_CRT" \
    --from-literal=user.key="$TLSUSER_KEY"
}

function create_sasl_secrets() {
  header "Creating SASL Kafka secret"
  STRIMZI_CRT=$(oc -n kafka get secret my-cluster-cluster-ca-cert --template='{{index .data "ca.crt"}}' | base64 --decode )
  SASL_PASSWD=$(oc -n kafka get secret my-sasl-user --template='{{index .data "password"}}' | base64 --decode )

  oc create secret --namespace knative-eventing generic strimzi-sasl-secret \
    --from-literal=ca.crt="$STRIMZI_CRT" \
    --from-literal=password="$SASL_PASSWD" \
    --from-literal=saslType="SCRAM-SHA-512" \
    --from-literal=user="my-sasl-user"
}

function install_strimzi(){
  header "Installing Kafka cluster"
  oc create namespace kafka || return 1
  sed 's/namespace: .*/namespace: kafka/' ${STRIMZI_INSTALLATION_CONFIG_TEMPLATE} > ${STRIMZI_INSTALLATION_CONFIG}
  oc apply -f "${STRIMZI_INSTALLATION_CONFIG}" -n kafka || return 1
  # Wait for the CRD we need to actually be active
  oc wait crd --timeout=900s kafkas.kafka.strimzi.io --for=condition=Established || return 1

  oc apply -f ${KAFKA_INSTALLATION_CONFIG} -n kafka
  oc wait kafka --all --timeout=900s --for=condition=Ready -n kafka || return 1

  # Create some Strimzi Kafka Users
  oc apply -f "${KAFKA_USERS_CONFIG}" -n kafka || return 1
}

function install_serverless(){
  header "Installing Serverless Operator"
  local operator_dir=/tmp/serverless-operator
  local failed=0
  git clone --branch release-1.11 https://github.com/openshift-knative/serverless-operator.git $operator_dir || return 1
  # unset OPENSHIFT_BUILD_NAMESPACE (old CI) and OPENSHIFT_CI (new CI) as its used in serverless-operator's CI
  # environment as a switch to use CI built images, we want pre-built images of k-s-o and k-o-i
  unset OPENSHIFT_BUILD_NAMESPACE
  unset OPENSHIFT_CI
  pushd $operator_dir

  INSTALL_EVENTING="false" ./hack/install.sh && header "Serverless Operator installed successfully" || failed=1
  popd
  return $failed
}

function install_knative_eventing(){
  header "Installing Knative Eventing 0.18.4"

  oc apply -f https://raw.githubusercontent.com/openshift/knative-eventing/release-v0.18.4/openshift/release/knative-eventing-ci.yaml || return 1
  oc apply -f https://raw.githubusercontent.com/openshift/knative-eventing/release-v0.18.4/openshift/release/knative-eventing-mtbroker-ci.yaml || return 1

  # Wait for 5 pods to appear first
  timeout 900 '[[ $(oc get pods -n $EVENTING_NAMESPACE --no-headers | wc -l) -lt 5 ]]' || return 1
  wait_until_pods_running $EVENTING_NAMESPACE || return 1
}

function install_knative_kafka {
  install_knative_kafka_channel || return 1
  install_knative_kafka_source || return 1
}

function install_knative_kafka_channel(){
  header "Installing Knative Kafka Channel"

  RELEASE_YAML="openshift/release/knative-eventing-kafka-channel-ci.yaml"

  sed -i -e "s|registry.svc.ci.openshift.org/openshift/knative-.*:knative-eventing-sources-kafka-channel-controller|${IMAGE_FORMAT//\$\{component\}/knative-eventing-sources-kafka-channel-controller}|g" ${RELEASE_YAML}
  sed -i -e "s|registry.svc.ci.openshift.org/openshift/knative-.*:knative-eventing-sources-kafka-channel-dispatcher|${IMAGE_FORMAT//\$\{component\}/knative-eventing-sources-kafka-channel-dispatcher}|g" ${RELEASE_YAML}
  sed -i -e "s|registry.svc.ci.openshift.org/openshift/knative-.*:knative-eventing-sources-kafka-channel-webhook|${IMAGE_FORMAT//\$\{component\}/knative-eventing-sources-kafka-channel-webhook}|g"       ${RELEASE_YAML}

  cat ${RELEASE_YAML} \
  | sed "s/REPLACE_WITH_CLUSTER_URL/${KAFKA_CLUSTER_URL}/" \
  | oc apply --filename -

  wait_until_pods_running $EVENTING_NAMESPACE || return 1
}

function install_knative_kafka_source(){
  header "Installing Knative Kafka Source"

  RELEASE_YAML="openshift/release/knative-eventing-kafka-source-ci.yaml"

  sed -i -e "s|registry.svc.ci.openshift.org/openshift/knative-.*:knative-eventing-sources-kafka-source-controller|${IMAGE_FORMAT//\$\{component\}/knative-eventing-sources-kafka-source-controller}|g"   ${RELEASE_YAML}
  sed -i -e "s|registry.svc.ci.openshift.org/openshift/knative-.*:knative-eventing-sources-kafka-source-adapter|${IMAGE_FORMAT//\$\{component\}/knative-eventing-sources-kafka-source-adapter}|g"         ${RELEASE_YAML}

  cat ${RELEASE_YAML} \
  | oc apply --filename -

  wait_until_pods_running $EVENTING_NAMESPACE || return 1
}

function uinstall_knative_kafka {
  uninstall_knative_kafka_channel
  uninstall_knative_kafka_source
}

function uninstall_knative_kafka_channel(){
  header "Uninstalling Knative Kafka Channel"

  RELEASE_YAML="openshift/release/knative-eventing-kafka-channel-ci.yaml"

  oc delete -f ${RELEASE_YAML} || return 1
}

function uninstall_knative_kafka_source(){
  header "InstalUninstallingling Knative Kafka Source"

  RELEASE_YAML="openshift/release/knative-eventing-kafka-source-ci.yaml"

  oc delete -f ${RELEASE_YAML} || return 1
}

function run_e2e_tests(){

  oc get ns ${TEST_EVENTING_NAMESPACE} 2>/dev/null || TEST_EVENTING_NAMESPACE="knative-eventing"
  sed "s/namespace: ${KNATIVE_DEFAULT_NAMESPACE}/namespace: ${TEST_EVENTING_NAMESPACE}/g" ${CONFIG_TRACING_CONFIG} | oc replace -f -
  local test_name="${1:-}"
  local run_command=""
  local failed=0
  local channels=messaging.knative.dev/v1beta1:KafkaChannel

  local common_opts=" -channels=$channels --kubeconfig $KUBECONFIG" ## --imagetemplate $TEST_IMAGE_TEMPLATE"
  if [ -n "$test_name" ]; then
      local run_command="-run ^(${test_name})$"
  fi

  go_test_e2e -tags=e2e,source -timeout=90m -parallel=12 ./test/e2e \
    "$run_command" \
    $common_opts --dockerrepo "quay.io/openshift-knative" --tag "v0.18" || failed=$?

  return $failed
}

function run_e2e_tls_tests(){
  header "Testing the consolidated channel with TLS"
  # Set the URL to the TLS listeners config
  cp ${KAFKA_TLS_CONFIG} "${KAFKA_CRD_CONFIG_TEMPLATE_DIR}/configmaps/kafka-config.yaml"
  KAFKA_CLUSTER_URL=${KAFKA_TLS_CLUSTER_URL}

  install_knative_kafka_channel || return 1

  oc get ns ${TEST_EVENTING_NAMESPACE} 2>/dev/null || TEST_EVENTING_NAMESPACE="knative-eventing"
  sed "s/namespace: ${KNATIVE_DEFAULT_NAMESPACE}/namespace: ${TEST_EVENTING_NAMESPACE}/g" ${CONFIG_TRACING_CONFIG} | oc replace -f -
  local test_name="${1:-}"
  local run_command=""
  local failed=0
  local channels=messaging.knative.dev/v1beta1:KafkaChannel

  local common_opts=" -channels=$channels --kubeconfig $KUBECONFIG" ## --imagetemplate $TEST_IMAGE_TEMPLATE"
  if [ -n "$test_name" ]; then
      local run_command="-run ^(${test_name})$"
  fi

  go_test_e2e -tags=e2e -timeout=90m -parallel=12 ./test/e2e \
    "$run_command" \
    $common_opts --dockerrepo "quay.io/openshift-knative" --tag "v0.18" || failed=$?

  uninstall_knative_kafka_channel || return 1

  return $failed
}

function run_e2e_sasl_tests(){
  header "Testing the consolidated channel with TLS"
  # Set the URL to the TLS listeners config
  cp ${KAFKA_SASL_CONFIG} "${KAFKA_CRD_CONFIG_TEMPLATE_DIR}/configmaps/kafka-config.yaml"
  KAFKA_CLUSTER_URL=${KAFKA_SASL_CLUSTER_URL}

  install_knative_kafka_channel || return 1

  oc get ns ${TEST_EVENTING_NAMESPACE} 2>/dev/null || TEST_EVENTING_NAMESPACE="knative-eventing"
  sed "s/namespace: ${KNATIVE_DEFAULT_NAMESPACE}/namespace: ${TEST_EVENTING_NAMESPACE}/g" ${CONFIG_TRACING_CONFIG} | oc replace -f -
  local test_name="${1:-}"
  local run_command=""
  local failed=0
  local channels=messaging.knative.dev/v1beta1:KafkaChannel

  local common_opts=" -channels=$channels --kubeconfig $KUBECONFIG" ## --imagetemplate $TEST_IMAGE_TEMPLATE"
  if [ -n "$test_name" ]; then
      local run_command="-run ^(${test_name})$"
  fi

  go_test_e2e -tags=e2e -timeout=90m -parallel=12 ./test/e2e \
    "$run_command" \
    $common_opts --dockerrepo "quay.io/openshift-knative" --tag "v0.18" || failed=$?

  uninstall_knative_kafka_channel || return 1

  return $failed
}
