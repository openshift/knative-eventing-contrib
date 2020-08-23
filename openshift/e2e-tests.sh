
# shellcheck disable=SC1090
source "$(dirname "$0")/../vendor/knative.dev/test-infra/scripts/e2e-tests.sh"
source "$(dirname "$0")/e2e-common.sh"

set -x

export TEST_IMAGE_TEMPLATE="${IMAGE_FORMAT//\$\{component\}/knative-eventing-test-{{.Name}}}"

env

scale_up_workers || exit 1

failed=0

(( !failed )) && install_strimzi || failed=1

(( !failed )) && install_serverless || failed=1

#(( !failed )) && run_e2e_tests || failed=1

(( failed )) && dump_cluster_state

(( failed )) && exit 1

success