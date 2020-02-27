#!/bin/sh 

source $(dirname $0)/../vendor/knative.dev/test-infra/scripts/e2e-tests.sh

set -x

function run_e2e_tests(){
  header "Running tests"
  echo "The E2E test suite is currently empty"
  oc version
  return 1
}

failed=0

run_e2e_tests || failed=1

(( failed )) && exit 1

success
