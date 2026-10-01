#!/bin/bash
set -euo pipefail

export SRCDIR="${PWD}/macos_src"
export OUTDIR="${PWD}/macos_sysroot"
export OUTTGZ="macos_sysroot.tar.gz"

export SOCAT_VERS="socat-1.8.1.3"
export SOCAT_URL="http://www.dest-unreach.org/socat/download/${SOCAT_VERS}.tar.gz"
export SOCAT_SHA256="06602ffd591e98c75b3dc1d66f0f19136cc666b0b2d95caad987d6ab2cb28097"

export DROPBEAR_VERS="dropbear-2026.94"
export DROPBEAR_URL="https://matt.ucc.asn.au/dropbear/releases/${DROPBEAR_VERS}.tar.bz2"

export PREFIX="/"

setup_dirs() {
  mkdir -p "${SRCDIR}"
  mkdir -p "${OUTDIR}"
}

# get_git_src
# Argument 1: the project name
# Argument 2: the project repo URL
# Argument 3: which tag/ branch to checkout
get_git_src() {
  local PROJECT_NAME="${1}"
  local PROJECT_REPO="${2}"
  local PROJECT_VERS="${3}"
  if [[ -d "${SRCDIR}/${PROJECT_NAME}" ]]; then
    return
  fi

  cd "${SRCDIR}" || exit
  git clone --depth 1 --branch "${PROJECT_VERS}" "${PROJECT_REPO}" "${PROJECT_NAME}"
}

# get_tarball_src
# Argument 1: the project name + version (eg. "coreutils-9.11")
# Argument 2: the project URL (eg. "https://ftp.gnu.org/gnu/coreutils/coreutils-9.11.tar.xz")
get_tarball_src() {
  local tarfile
  local PROJECT_VERSION="${1}"
  local PROJECT_URL="${2}"
  if [[ -d "${SRCDIR}/${PROJECT_VERSION}" ]]; then
    return
  fi

  cd "${SRCDIR}" || exit

  tarfile=$(basename "${PROJECT_URL}")
  if [[ ! -f "${tarfile}" ]]; then
    wget "${PROJECT_URL}"
  else
    echo "${tarfile} already exists, skipping download"
  fi

  if [[ ! -f "${tarfile}" ]]; then
    echo "missing ${tarfile}"
    exit 1
  fi

  tar -xf "${tarfile}"
}

build_socat() {
  local downloaded_file_hash

  if [[ -f "${OUTDIR}/bin/socat" ]]; then
    echo "${SOCAT_VERS} already built"
    return
  fi

  echo "Building ${SOCAT_VERS}"

  get_tarball_src "${SOCAT_VERS}" "${SOCAT_URL}"

  downloaded_file_hash=$(sha256 -q "${SRCDIR}/${SOCAT_VERS}.tar.gz")

  if [[ "${SOCAT_SHA256}" != "${downloaded_file_hash}" ]]; then
    echo "${SRCDIR}/${SOCAT_VERS}.tar.gz hash doesn't match"
    echo "got      ${downloaded_file_hash}"
    echo "expected ${SOCAT_SHA256}"
    exit 1
  fi

  # note that socat won't install correctly unless built in-tree
  cd "${SRCDIR}/${SOCAT_VERS}" || exit

  "${SRCDIR}/${SOCAT_VERS}/configure" \
    ac_cv_search_res_9_init="no" \
    ac_cv_header_resolv_h="no" \
    --disable-readline --disable-openssl --disable-resolve \
    --prefix="${PREFIX}"

  make
  make DESTDIR="${OUTDIR}" install
}

build_dropbear() {
  if [[ -f "${OUTDIR}/sbin/dropbear" ]]; then
    echo "${DROPBEAR_VERS} already built"
    return
  fi

  echo "Building ${DROPBEAR_VERS}"

  get_tarball_src "${DROPBEAR_VERS}" "${DROPBEAR_URL}"

  cd "${SRCDIR}/${DROPBEAR_VERS}" || exit

  sed -i '' 's|#define DROPBEAR_SVR_LOCALSTREAMFWD 1|#define DROPBEAR_SVR_LOCALSTREAMFWD 0|g' "${SRCDIR}/${DROPBEAR_VERS}/src/default_options.h"
  sed -i '' 's|#define DROPBEAR_SVR_DROP_PRIVS DROPBEAR_SVR_MULTIUSER|#define DROPBEAR_SVR_DROP_PRIVS 0|g' "${SRCDIR}/${DROPBEAR_VERS}/src/default_options.h"
  sed -i '' 's|#define DEBUG_TRACE 0|#define DEBUG_TRACE 5|g' "${SRCDIR}/${DROPBEAR_VERS}/src/default_options.h"

  "${SRCDIR}/${DROPBEAR_VERS}/configure" \
    --prefix="${PREFIX}"

  make
  make DESTDIR="${OUTDIR}" install
}

# remove anything we don't need at runtime
cleanup_sysroot() {
  echo "cleaning sysroot"

  if [[ -z "${OUTDIR}" ]]; then
    echo "outdir is null, skipping clean"
    exit 1
  fi

  if [[ -d "${OUTDIR}/share" ]]; then
    echo "rm share"
    rm -rf "${OUTDIR}/share"
  fi
}

main() {
  setup_dirs
  build_socat
  build_dropbear
  cleanup_sysroot
  echo "done!"
}

main "$@"
