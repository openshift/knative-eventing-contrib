#!/usr/bin/env bash

export EVENTING_NAMESPACE="${EVENTING_NAMESPACE:-knative-eventing}"
export ZIPKIN_NAMESPACE=$EVENTING_NAMESPACE

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
  kubectl wait deployment --all --timeout=600s --for=condition=Available -n ${ZIPKIN_NAMESPACE} || return 1
}

function enable_eventing_tracing {
  header_text "Configuring tracing for Eventing"

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

function install_strimzi(){
  strimzi_version=`curl https://github.com/strimzi/strimzi-kafka-operator/releases/latest |  awk -F 'tag/' '{print $2}' | awk -F '"' '{print $1}' 2>/dev/null`
  header "Strimzi install"
  oc create namespace kafka
  curl -L "https://github.com/strimzi/strimzi-kafka-operator/releases/download/${strimzi_version}/strimzi-cluster-operator-${strimzi_version}.yaml" \
  | sed 's/namespace: .*/namespace: kafka/' \
  | oc -n kafka create -f -

  # Wait for the CRD we need to actually be active
  oc wait crd --timeout=-1s kafkas.kafka.strimzi.io --for=condition=Established

  header "Applying Strimzi Cluster file"
  oc -n kafka apply -f "https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/${strimzi_version}/examples/kafka/kafka-persistent.yaml"

  header "Waiting for Strimzi to become ready"
  oc wait kafka --all --timeout=-1s --for=condition=Ready -n kafka
}

function install_serverless(){
  header "Installing Serverless Operator"
  local operator_dir=/tmp/serverless-operator
  local failed=0
  git clone --branch release-1.12 https://github.com/openshift-knative/serverless-operator.git $operator_dir || return 1
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
  header "Installing Knative Eventing 0.17.2"

  oc apply -f https://raw.githubusercontent.com/openshift/knative-eventing/release-v0.17.2/openshift/release/knative-eventing-ci.yaml
  oc apply -f https://raw.githubusercontent.com/openshift/knative-eventing/release-v0.17.2/openshift/release/knative-eventing-mtbroker-ci.yaml

  # Wait for 5 pods to appear first
  timeout 900 '[[ $(oc get pods -n $EVENTING_NAMESPACE --no-headers | wc -l) -lt 5 ]]' || return 1
  wait_until_pods_running $EVENTING_NAMESPACE || return 1
}

function install_knative_kafka(){
  header "Installing Knative Kafka components"

  RELEASE_YAML="openshift/release/knative-eventing-kafka-contrib-ci.yaml"

  sed -i -e "s|registry.svc.ci.openshift.org/openshift/knative-.*:knative-eventing-sources-kafka-source-controller|${IMAGE_FORMAT//\$\{component\}/knative-eventing-sources-kafka-source-controller}|g"   ${RELEASE_YAML}
  sed -i -e "s|registry.svc.ci.openshift.org/openshift/knative-.*:knative-eventing-sources-kafka-source-adapter|${IMAGE_FORMAT//\$\{component\}/knative-eventing-sources-kafka-source-adapter}|g"         ${RELEASE_YAML}
  sed -i -e "s|registry.svc.ci.openshift.org/openshift/knative-.*:knative-eventing-sources-kafka-channel-controller|${IMAGE_FORMAT//\$\{component\}/knative-eventing-sources-kafka-channel-controller}|g" ${RELEASE_YAML}
  sed -i -e "s|registry.svc.ci.openshift.org/openshift/knative-.*:knative-eventing-sources-kafka-channel-dispatcher|${IMAGE_FORMAT//\$\{component\}/knative-eventing-sources-kafka-channel-dispatcher}|g" ${RELEASE_YAML}
  sed -i -e "s|registry.svc.ci.openshift.org/openshift/knative-.*:knative-eventing-sources-kafka-channel-webhook|${IMAGE_FORMAT//\$\{component\}/knative-eventing-sources-kafka-channel-webhook}|g"       ${RELEASE_YAML}

  cat ${RELEASE_YAML} \
  | sed 's/namespace: .*/namespace: knative-eventing/' \
  | sed 's/REPLACE_WITH_CLUSTER_URL/my-cluster-kafka-bootstrap.kafka:9092/' \
  | oc apply --filename -

  wait_until_pods_running $EVENTING_NAMESPACE || return 1
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

  go_test_e2e -timeout=90m -parallel=12 ./test/e2e \
    "$run_command" \
    $common_opts --dockerrepo "quay.io/openshift-knative" --tag "v0.17" || failed=$?

  return $failed
}
