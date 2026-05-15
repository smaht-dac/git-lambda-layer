#!/usr/bin/env bash
# Runs inside the Lambda Docker container during build.
# Installs git + openssh, collects shared library deps, patches RPATH, and zips everything to /out/layer.zip.
set -euo pipefail

dnf install -y git openssh-clients patchelf zip findutils 2>&1 | tail -3

echo "Bundling $(git --version), $(ssh -V 2>&1)"

STAGING=$(mktemp -d)
BINDIR="${STAGING}/bin"
LIBDIR="${STAGING}/lib"
mkdir -p "${BINDIR}" "${LIBDIR}" "${STAGING}/libexec/git-core" "${STAGING}/etc/ssh"

# ---- Binaries ----
for bin in git ssh ssh-add ssh-agent ssh-keygen ssh-keyscan scp; do
  cp "$(command -v "${bin}")" "${BINDIR}/${bin}"
done

# git's compiled-in exec-path is /usr/libexec/git-core, which is absent in Lambda.
# A wrapper sets GIT_EXEC_PATH before exec-ing the real binary.
mv "${BINDIR}/git" "${BINDIR}/git.real"
printf '#!/bin/sh\nexport GIT_EXEC_PATH=/opt/libexec/git-core\nexec /opt/bin/git.real "$@"\n' > "${BINDIR}/git"
chmod +x "${BINDIR}/git"

for link in git-receive-pack git-upload-archive git-upload-pack; do
  printf '#!/bin/sh\nexport GIT_EXEC_PATH=/opt/libexec/git-core\nexec /opt/bin/git.real %s "$@"\n' \
    "${link#git-}" > "${BINDIR}/${link}"
  chmod +x "${BINDIR}/${link}"
done

[ -d /usr/libexec/git-core ] && cp -a /usr/libexec/git-core/. "${STAGING}/libexec/git-core/"

# ---- Shared library dependencies ----
# ldd resolves the full transitive graph; shell scripts produce no output (stderr suppressed).
SKIP="libc\.so|libdl\.so|libpthread\.so|librt\.so|libm\.so|libutil\.so|linux-vdso|ld-linux|libgcc_s\.so"

DEPS=$(find "${STAGING}/bin" "${STAGING}/libexec" -type f \
  -exec ldd {} 2>/dev/null \; \
  | awk '/=>/ { print $3 }' | grep "^/" | grep -vE "${SKIP}" | sort -u)

for lib in ${DEPS}; do
  [ -f "${lib}" ] || continue
  real=$(readlink -f "${lib}")
  cp -n "${real}" "${LIBDIR}/"
  # ldd reports the SONAME path (e.g. libcurl.so.4), which is a symlink to the versioned file.
  # Recreate that symlink in LIBDIR so the dynamic linker finds it.
  [ "${lib}" != "${real}" ] && \
    ln -sf "$(basename "${real}")" "${LIBDIR}/$(basename "${lib}")" 2>/dev/null || true
done

# ---- Patch RPATH so binaries find /opt/lib at runtime ----
find "${STAGING}/bin" "${STAGING}/libexec" -type f | while read -r elf; do
  patchelf --set-rpath /opt/lib "${elf}" 2>/dev/null || true
done

# ---- Optional: ssh config skeleton ----
[ -f /etc/ssh/ssh_config ] && cp /etc/ssh/ssh_config "${STAGING}/etc/ssh/" || true
[ -f /etc/ssh/moduli ]     && cp /etc/ssh/moduli     "${STAGING}/etc/ssh/" || true

# ---- Verify: no missing libraries ----
for bin in git.real ssh; do
  ldd "${BINDIR}/${bin}" | grep -q "not found" && { echo "ERROR: missing libs for ${bin}"; exit 1; }
done
echo "Library resolution OK"

# ---- Package ----
cd "${STAGING}" && zip -yr /out/layer.zip .
echo "layer.zip: $(du -sh /out/layer.zip | cut -f1)"
