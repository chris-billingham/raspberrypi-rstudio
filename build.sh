#!/bin/bash
#
# Build an RStudio docker image.

readonly script_name=$(basename "$0")

# Account name prefix for docker image tags.
readonly DOCKERHUB_USER='arturklauser'

# Print usage message with error and exit.
function usage() {
  if [ "$#" != 0 ]; then
    (
      echo "$1"
      echo
    ) >&2
  fi
  cat - >&2 << END_USAGE
Usage: $script_name <debian-version> <stage>
         debian-version: stretch ..... Debian version 9
                         buster ...... Debian version 10
                         bullseye .... Debian version 11
         stage: build-env ......... create build environment
                server-deb ........ build server Debian package
                desktop-deb ....... build desktop Debian package
                server ............ create server runtime environment
                rstudio-version ... print rstudio version
END_USAGE
  exit 1
}

# Print standardized timestamp.
function timestamp() {
  date -u +'%Y-%m-%dT%H:%M:%SZ'
}

# Return minimum of two numeric inputs.
function min() {
  if [[ "$1" -lt "$2" ]]; then
    echo "$1"
  else
    echo "$2"
  fi
}

function main() {
  if [[ "${script_name}" =~ buildx ]]; then
    cat << EOF
==============================================================================
Note that this buildx.sh script depends on the experimental Docker support for
the _buildx_ plugin. Unless you know what you're doing, use build.sh instead.
==============================================================================

EOF
  fi

  if [[ "$#" != 2 ]]; then
    usage "Invalid number ($#) of command line arguments."
  fi

  # Define build environment.
  readonly DEBIAN_VERSION="$1"
  readonly BUILD_STAGE="$2"

  # Define RStudio source code version to use and the package release tag.
  case "${DEBIAN_VERSION}" in
    'stretch')
      # As of 2019-04-06 v1.1.463 is the latest version 1.1 tag.
      # Rstudio v1.2 doesn't compile on Stretch since it needs QT 5.10 but
      # Stretch only provides QT 5.7.1. QT provided by RStudio is x86 binary
      # only.
      readonly VERSION_MAJOR=1
      readonly VERSION_MINOR=1
      readonly VERSION_PATCH=463
      readonly PACKAGE_RELEASE="4~r2r.${DEBIAN_VERSION}"
      ;;
    'buster')
      # As of 2021-02-06 v1.4.1103 is the latest version 1.4 tag.
      readonly VERSION_MAJOR=1
      readonly VERSION_MINOR=4
      readonly VERSION_PATCH=1103
      readonly PACKAGE_RELEASE="1~r2r.${DEBIAN_VERSION}"
      ;;
    'bullseye')
      # As of 2021-02-06 v1.4.1103 is the latest version 1.4 tag.
      readonly VERSION_MAJOR=1
      readonly VERSION_MINOR=4
      readonly VERSION_PATCH=1103
      readonly PACKAGE_RELEASE="1~r2r.${DEBIAN_VERSION}"
      ;;
    *)
      usage "Unsupported Debian version '${DEBIAN_VERSION}'"
      ;;
  esac

  readonly VERSION_TAG=${VERSION_MAJOR}.${VERSION_MINOR}.${VERSION_PATCH}

  # Define image tag and dockerfile depending on requested build stage.
  case "${BUILD_STAGE}" in
    'build-env' | 'server-deb' | 'desktop-deb' | 'server')
      readonly IMAGE_NAME="${DOCKERHUB_USER}/raspberrypi-rstudio-${BUILD_STAGE}"
      readonly DOCKERFILE="docker/Dockerfile.${BUILD_STAGE}"
      ;;
    'rstudio-version')
      echo "${VERSION_TAG}"
      exit 0
      ;;
    *)
      usage "Unsupported build stage '${BUILD_STAGE}'"
      ;;
  esac

  echo "Start building at $(timestamp) ..."

  # Parallelism is no greater than number of available CPUs and max 2.
  readonly NPROC=$(nproc 2> /dev/null)
  # Travis: There is a 50 minute job time limit. The aarch64 VM has 32 CPUs.
  # Make use of them to stay within the job time limit.
  if [ "$TRAVIS" = 'true' ]; then
    readonly BUILD_PARALLELISM=$(min '8' "${NPROC}")
  else
    readonly BUILD_PARALLELISM=$(min '2' "${NPROC}")
  fi

  # If we're running on real or simulated ARM we comment out the cross-build
  # lines.
  readonly ARCH=$(uname -m)
  if [[ ${ARCH} =~ (arm|aarch64) || "${script_name}" =~ buildx ]]; then
    # shellcheck disable=SC2016
    readonly CROSS_BUILD_FIX='s/^(.*cross-build-.*)/# $1/'
  else
    readonly CROSS_BUILD_FIX=''
  fi

  # Build the docker image.
  (for i in {0..100}; do
    sleep 1
    echo "Still building ... ($i min)"
    sleep 59
  done) &
  pid=$!
  # Get current commit SHA. Works also on --depth=1 shallow clones.
  ref="$(git log --pretty=format:'%H' HEAD^!)"
  set -x
  time \
    perl -pe "${CROSS_BUILD_FIX}" "${DOCKERFILE}" \
    | docker build \
      --build-arg DEBIAN_VERSION="${DEBIAN_VERSION}" \
      --build-arg VERSION_TAG="${VERSION_TAG}" \
      --build-arg VERSION_MAJOR="${VERSION_MAJOR}" \
      --build-arg VERSION_MINOR="${VERSION_MINOR}" \
      --build-arg VERSION_PATCH="${VERSION_PATCH}" \
      --build-arg PACKAGE_RELEASE="${PACKAGE_RELEASE}" \
      --build-arg BUILD_PARALLELISM="${BUILD_PARALLELISM}" \
      --build-arg TRAVIS="${TRAVIS}" \
      --build-arg VCS_REF="${ref}" \
      --build-arg BUILD_DATE="$(timestamp)" \
      -t "${IMAGE_NAME}:${VERSION_TAG}-${DEBIAN_VERSION}" \
      -

  set +x
  kill $pid

  echo "Done building at $(timestamp)"
}

main "$@"
