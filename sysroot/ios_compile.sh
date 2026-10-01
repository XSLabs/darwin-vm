#!/bin/bash
set -euo pipefail

export SRCDIR="${PWD}/ios_src"
export OUTDIR="${PWD}/ios_sysroot"
export OUTTGZ="ios_sysroot.tar.gz"

export DASH_VERS="v0.5.13.5"
export DASH_REPO="https://git.kernel.org/pub/scm/utils/dash/dash.git"

export BASH_VERS="bash-5.3"
export BASH_URL="https://ftp.gnu.org/gnu/bash/${BASH_VERS}.tar.gz"

export COREUTILS_VERS="coreutils-9.11"
export COREUTILS_URL="https://ftp.gnu.org/gnu/coreutils/${COREUTILS_VERS}.tar.xz"

export SOCAT_VERS="socat-1.8.1.3"
export SOCAT_URL="http://www.dest-unreach.org/socat/download/${SOCAT_VERS}.tar.gz"
export SOCAT_SHA256="06602ffd591e98c75b3dc1d66f0f19136cc666b0b2d95caad987d6ab2cb28097"

export DROPBEAR_VERS="dropbear-2026.94"
export DROPBEAR_URL="https://matt.ucc.asn.au/dropbear/releases/${DROPBEAR_VERS}.tar.bz2"

export PREFIX="/"

IOS_CROSS_HOST="arm64-apple-ios"
CLANG_IOS="$(xcrun -sdk iphoneos --find clang)"
CFLAGS_IOS="-isysroot $(xcrun -sdk iphoneos --show-sdk-path) -target arm64-apple-ios"
CFLAGS_MAC="-isysroot $(xcrun -sdk macosx --show-sdk-path)"

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

build_dash() {
  local DASH_NAME="dash"

  if [[ -f "${OUTDIR}/bin/sh" ]]; then
    echo "${DASH_NAME} already built"
    return
  fi

  echo "Building ${DASH_NAME}"

  get_git_src "${DASH_NAME}" "${DASH_REPO}" "${DASH_VERS}"
  cd "${SRCDIR}/${DASH_NAME}" || exit
  ./autogen.sh

  # We are always cross compiling
  sed -i.bak 's/cross_compiling=maybe/cross_compiling=yes/g' "${SRCDIR}/${DASH_NAME}/configure"
  sed -i.bak 's/cross_compiling=no/cross_compiling=yes/g' "${SRCDIR}/${DASH_NAME}/configure"

  cd "${SRCDIR}/${DASH_NAME}" || exit

  CC="${CLANG_IOS}" CFLAGS="${CFLAGS_IOS}" \
    "${SRCDIR}/${DASH_NAME}/configure" \
    --host="${IOS_CROSS_HOST}" --disable-nls --prefix="${PREFIX}" \
    --program-transform-name="s/dash/sh/"

  make
  make DESTDIR="${OUTDIR}" install
}

build_coreutils() {
  if [[ -f "${OUTDIR}/bin/ls" ]]; then
    echo "${COREUTILS_VERS} already built"
    return
  fi

  echo "Building ${COREUTILS_VERS}"

  get_tarball_src "${COREUTILS_VERS}" "${COREUTILS_URL}"

  cd "${SRCDIR}/${COREUTILS_VERS}" || exit

  CC="${CLANG_IOS}" CFLAGS="${CFLAGS_IOS}" \
    "${SRCDIR}/${COREUTILS_VERS}/configure" \
    --host="${IOS_CROSS_HOST}" --disable-nls --prefix="${PREFIX}" \
    ac_cv_func_clock_settime="no" \
    gl_cv_have_unlimited_file_name_length="no"

  make
  make DESTDIR="${OUTDIR}" install
}

build_bash() {
  if [[ -f "${OUTDIR}/bin/bash" ]]; then
    echo "${BASH_VERS} already built"
    return
  fi

  echo "Building ${BASH_VERS}"

  get_tarball_src "${BASH_VERS}" "${BASH_URL}"

  cd "${SRCDIR}/${BASH_VERS}" || exit

  CC="${CLANG_IOS}" CFLAGS="${CFLAGS_IOS}" CFLAGS_FOR_BUILD="${CFLAGS_MAC}" \
    "${SRCDIR}/${BASH_VERS}/configure" \
    --host="${IOS_CROSS_HOST}" --disable-nls --prefix="${PREFIX}" \
    --without-bash-malloc \
    bash_cv_sys_siglist="yes" \
    bash_cv_type_clock_t="yes" \
    ac_cv_type_uintmax_t="yes" \
    ac_cv_type_intmax_t="yes" \
    ac_cv_sizeof_intmax_t="yes" \
    bash_cv_type_sigset_t="yes" \
    bash_cv_type_socklen_t="yes" \
    ac_cv_func_getentropy="no" \
    bash_cv_termcap_lib="gnutermcap"

  make
  make DESTDIR="${OUTDIR}" install
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

  # iOS can't use system()
  sed -i '' 's|result = system(string);|fprintf(stderr, "no system\\n"); exit(1);|g' "${SRCDIR}/${SOCAT_VERS}/sycls.c"

  CC="${CLANG_IOS}" CFLAGS="${CFLAGS_IOS}" \
    "${SRCDIR}/${SOCAT_VERS}/configure" \
    ac_cv_type_uid_t="yes" \
    ac_cv_search_res_9_init="no" \
    ac_cv_header_resolv_h="no" \
    --disable-system --disable-sycls --disable-resolve \
    --host="${IOS_CROSS_HOST}" --build="arm64-darwin-macos" --prefix="${PREFIX}"

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

  CC="${CLANG_IOS}" CFLAGS="${CFLAGS_IOS}" LDFLAGS="${CFLAGS_IOS}" \
    "${SRCDIR}/${DROPBEAR_VERS}/configure" \
    ac_cv_type_uid_t="yes" \
    --disable-zlib \
    --host="${IOS_CROSS_HOST}" --build="arm64-darwin-macos" --prefix="${PREFIX}"

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

  if [[ -f "${OUTDIR}/bin/bashbug" ]]; then
    echo "rm bashbug"
    chmod +w "${OUTDIR}/bin/bashbug"
    rm "${OUTDIR}/bin/bashbug"
  fi

  if [[ -d "${OUTDIR}/share" ]]; then
    echo "rm share"
    rm -rf "${OUTDIR}/share"
  fi
}

main() {
  setup_dirs
  build_dash
  build_coreutils
  build_bash
  build_socat
  build_dropbear
  cleanup_sysroot
  echo "done!"
}

main "$@"
