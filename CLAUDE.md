# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
make build    # build layer.zip inside Docker (requires Docker on x86_64 host)
make test     # run integration test — unzips layer and runs test/index.py inside the Lambda container
make publish  # publish layer to AWS (configure config.sh first)
make check    # list published layer ARNs per configured region
make clean    # remove layer/ and layer.zip
```

## Architecture

This repo produces an AWS Lambda layer with `git` and `ssh` binaries for the **Python 3.12 / Amazon Linux 2023** runtime.

### Build pipeline

`build.sh` (host) → Docker container running `public.ecr.aws/lambda/python:3.12` → `build_layer.sh` (inside container) → `layer.zip`

`build_layer.sh` is the core script. It runs entirely inside the Lambda runtime image to guarantee binary compatibility. Key steps:
1. Installs `git`, `openssh-clients`, `patchelf`, `zip`, `findutils` via `dnf`
2. Copies binaries to a staging directory
3. Creates a `bin/git` wrapper script and renames the ELF to `bin/git.real` — necessary because git's compiled-in exec-path (`/usr/libexec/git-core`) doesn't exist in Lambda; the wrapper sets `GIT_EXEC_PATH=/opt/libexec/git-core`
4. Copies `/usr/libexec/git-core/` helpers to `libexec/git-core/`
5. Collects all shared library deps via `ldd` (transitive), copies them to `lib/`, recreates SONAME symlinks
6. Runs `patchelf --set-rpath /opt/lib` on all ELF binaries so the dynamic linker finds bundled libs at runtime without `LD_LIBRARY_PATH`
7. Verifies no "not found" in `ldd` output, then zips

### Layer structure (maps to `/opt/` in Lambda)

```
bin/git              # wrapper script (sets GIT_EXEC_PATH, execs git.real)
bin/git.real         # actual git ELF, RPATH=/opt/lib
bin/ssh              # ELF, RPATH=/opt/lib
bin/git-receive-pack, bin/git-upload-pack, bin/git-upload-archive  # wrapper scripts
lib/                 # bundled shared libs (libcurl, libssl, libcrypto, libpcre2, …)
libexec/git-core/    # git subcommand helpers (git-remote-https, etc.)
etc/ssh/             # ssh_config, moduli (optional)
```

Lambda automatically adds `/opt/bin` to `PATH`, so `git` and `ssh` are immediately available to function code.

### Configuration (`config.sh`)

All variables consumed by `build.sh`, `publish.sh`, and `check.sh`:

| Variable | Default | Notes |
|---|---|---|
| `LAYER_NAME` | `git-lambda-al2023` | Lambda layer name |
| `BUILD_IMAGE` | `public.ecr.aws/lambda/python:3.12` | Must be AL2023-based |
| `PUBLISH_REGIONS` | `us-east-1` | Comma-separated or `"all"` |
| `LAYER_PRINCIPAL` | `public` | `public`, `none`, account ID, or org ID (`o-…`) |
| `S3_STAGING_BUCKET` | _(empty)_ | Required only if `layer.zip` > 50 MB |
| `AWS_ACCOUNT_ID` | _(empty)_ | Derived from STS if blank |

### Publishing

`publish.sh` uploads the layer zip (directly via `--zip-file` if ≤ 50 MB, else via S3), then calls `add-layer-version-permission` based on `LAYER_PRINCIPAL`. Regions run in parallel (`xargs -P 8`). Each region emits its full ARN on completion.
