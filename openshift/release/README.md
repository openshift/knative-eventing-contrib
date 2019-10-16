# Release creation

**Note 1** Run all scripts from the root of the repository.

**Note 2** The master branch in this repo is used as a stash for
openshift-specific files needed for CI. Those files are copied to release
branches which is where CI operates.

## Setting up your clone

**Note** Your clone must be in `$GOPATH/src/knative.dev/eventing-contrib` *not*
`github.com/knative/eventing-contrib` or `openshift/knative-eventing-contrib`

You must have remotes named "upstream" and "openshift" for the scripts
in this repo to work, like this:

```
git remote add openshift git@github.com:openshift/knative-eventing-contrib.git
git remote add upstream git@github.com:knative/eventing-contrib.git
```

## Branching

There are two branching cases:

1. Creating a branch based off an upstream release tag.
2. Make a branch follow upstream HEAD for continuous integration.

### Creating a branch based off an upstream tag

```bash
$ ./openshift/release/create-release-branch.sh vX.Y.Z release-vX.Y.Z
```

Creates and checks out branch "release-vX.Y.Z" based on tag "vX.Y.Z", adds
OpenShift specific files that we need to run CI on it.

### Updating a branch that follow upstream's HEAD

This is done via the nightly Jenkins job to create the release-next branch:

```bash
$ ./openshift/release/update-to-head.sh release-vX.Y.Z
```

Pull the latest master from upstream, rebase the current fixes on the
release-vX.Y.Z branch and update the Openshift specific files if necessary.

## Building image and docker files

On the release branch, build the images and docker files. If any are new/changed check them in.

```
make install
make generate-dockerfiles
```

## Push the branch to the openshift fork, e.g.
```
git push -v openshift refs/heads/release-vX.Y.Z\:refs/heads/release-vX.Y.Z
```

## Generate CI configuration

**Note**: use `knative-vX.Y.Z` not `release-vX.Y.Z` in this step only:
```
make BRANCH=knative-vX.Y.Z generate-ci-config
```
This creates `ci-operator-config_NN.yaml` files that you need to move
in the next step.

## CI setup in openshift/release

The remaining steps are done in a clone of `github.com:openshift/release`

1. Create a work branch, e.g. `aconway-release-090`

2. Move the generate CI config files from knative-eventing-contrib to
   the correct path in this repo, for example:
```
mv ../knative-eventing-contrib/ci-operator-config_41.yaml ci-operator/config/openshift/knative-eventing-contrib/openshift-knative-eventing-contrib-release-vX.Y.Z.yaml
mv ../knative-eventing-contrib/ci-operator-config_42.yaml ci-operator/config/openshift/knative-eventing-contrib/openshift-knative-eventing-contrib-release-vX.Y.Z__variant.yaml
```

3. Generate PROW files:
```
docker pull registry.svc.ci.openshift.org/ci/ci-operator-prowgen:latest
docker run -it -v "${PWD}/ci-operator:/ci-operator:z" registry.svc.ci.openshift.org/ci/ci-operator-prowgen:latest --from-dir /ci-operator/config --to-dir /ci-operator/jobs
```

4. Commit the generated files and create a PR to master.
   This will start a CI run, fix any problems you find.

5. Update this README if any of the steps are incorrect or out of date.

