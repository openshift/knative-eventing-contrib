#!/bin/bash
# A script that will update the mapping file in github.com/openshift/release

set -e

fail() { echo; echo "$*"; exit 1; }

# Deduce X.Y.Z version from branch name
BRANCH=$(git rev-parse --abbrev-ref HEAD)
VERSION=$(echo $BRANCH | sed -E 's/^.*(v[0-9]+\.[0-9]+\.[0-9]+|next)|.*/\1/')
test -n "$VERSION" || fail "'$BRANCH' is not a release branch"
VER=$(echo $VERSION | sed 's/\./_/;s/\.[0-9]\+$//') # X_Y form of version


# Set up variables for important locations in the openshift/release repo.
OPENSHIFT=$(realpath "$1"); shift
test -d "$OPENSHIFT/.git" || fail "'$OPENSHIFT' is not a git repo"
MIRROR="$OPENSHIFT/core-services/image-mirroring/knative/mapping_knative_${VER}_quay"
CONFIGDIR=$OPENSHIFT/ci-operator/config/openshift/knative-eventing-contrib
test -d "$CONFIGDIR" || fail "'$CONFIGDIR' is not a directory"

# Generate CI config files
CONFIG=$CONFIGDIR/openshift-knative-eventing-contrib-release-$VERSION

CURDIR=$(dirname $0)
$CURDIR/generate-ci-config.sh knative-$VERSION 4.6 > ${CONFIG}__46.yaml

# Append missing lines to the mirror file.
[ -n "$(tail -c1 $MIRROR)" ] && echo >> $MIRROR # Make sure there's a newline
for IMAGE in $*; do
    NAME=knative-eventing-sources-$(basename $IMAGE | sed 's/_/-/')
    echo "Adding $NAME to mirror file"
    LINE="registry.svc.ci.openshift.org/openshift/knative-$VERSION:$NAME quay.io/openshift-knative/$NAME:$VERSION"
    # Add $LINE if not already present
    grep -q "^$LINE\$" $MIRROR || echo "$LINE"  >> $MIRROR
done

# Switch to openshift/release to generate PROW files

cd $OPENSHIFT
echo "Generating PROW files in $OPENSHIFT"
make jobs
make ci-operator-config
echo "==== Changes made to $OPENSHIFT ===="
git status
echo "==== Commit changes to $OPENSHIFT and create a PR"
