# git-lambda-layer

Pre-compiled `git` and `ssh` binaries packaged as an AWS Lambda layer for the **Python 3.12 runtime on Amazon Linux 2023**.

## Requirements

- Docker (x86_64 host)
- AWS CLI v2 configured with credentials that have:
  - `lambda:PublishLayerVersion`
  - `lambda:AddLayerVersionPermission`
  - `sts:GetCallerIdentity` (used to derive the account ID if `AWS_ACCOUNT_ID` is not set)
  - `s3:PutObject` on `S3_STAGING_BUCKET` (only if the layer zip exceeds 50 MB)

## Quick start

```bash
# 1. Edit config.sh — set PUBLISH_REGIONS, LAYER_PRINCIPAL, etc.

# 2. Build the layer zip
make build

# 3. Test locally (requires outbound internet for the git clone check)
make test

# 4. Publish to AWS
make publish

# 5. Verify the published ARNs
make check
```

## Configuration (`config.sh`)

| Variable | Default | Description |
|---|---|---|
| `LAYER_NAME` | `git-lambda-al2023` | Name of the Lambda layer |
| `BUILD_IMAGE` | `public.ecr.aws/lambda/python:3.12` | Docker image used for the build |
| `LAYER_ZIP` | `layer.zip` | Output filename |
| `PUBLISH_REGIONS` | `us-east-1` | Comma-separated regions, or `all` for all Lambda regions |
| `LAYER_PRINCIPAL` | `public` | `public`, `none`, an account ID, or an org ID (`o-…`) |
| `S3_STAGING_BUCKET` | _(empty)_ | S3 bucket for zips > 50 MB; leave blank to use direct upload |
| `AWS_ACCOUNT_ID` | _(empty)_ | Your account ID; derived from STS if blank |

### Cross-account sharing (`LAYER_PRINCIPAL`)

| Value | Effect |
|---|---|
| `public` | Any AWS account can use the layer ARN |
| `none` | Layer is private to your account |
| `123456789012` | Shared with that specific AWS account |
| `o-abc123def456` | Shared with your entire AWS Organization |

## Using the layer in a Lambda function

Add the layer ARN to your function. Because Lambda already puts `/opt/bin` on `PATH`, `git` and `ssh` are immediately available:

```python
import subprocess

def handler(event, context):
    result = subprocess.check_output(
        ["git", "clone", "--depth", "1", "https://github.com/example/repo.git", "/tmp/repo"],
        stderr=subprocess.STDOUT,
        text=True,
    )
    return result
```

### SSH remotes

Set `GIT_SSH_COMMAND` to avoid issues with `~/.ssh` not existing in the Lambda environment:

```python
import os, subprocess

env = {
    **os.environ,
    "GIT_SSH_COMMAND": (
        "ssh -o UserKnownHostsFile=/tmp/known_hosts "
        "-o StrictHostKeyChecking=no "
        "-i /tmp/id_rsa"
    ),
}
subprocess.check_call(["git", "clone", "git@github.com:example/repo.git", "/tmp/repo"], env=env)
```

## How the build works

The build runs entirely inside `public.ecr.aws/lambda/python:3.12` — the same image AWS uses for the Python 3.12 runtime — so every binary is compiled for and linked against the exact same Amazon Linux 2023 environment.

Key steps in `build.sh`:

1. Install `git`, `openssh`, and `patchelf` via `dnf`
2. Copy `git`, `ssh`, and the `git-core` helper binaries to a staging directory
3. Discover all shared library dependencies via `ldd` (two transitive passes)
4. Copy needed `.so` files to `staging/lib/` (glibc-family libs are excluded — they are guaranteed present in the Lambda runtime)
5. Use `patchelf --set-rpath /opt/lib` on every ELF binary so the dynamic linker finds the bundled libs at runtime without requiring `LD_LIBRARY_PATH`
6. Verify no "not found" entries remain in `ldd` output, then zip

## Layer structure

```
bin/
  git, ssh, ssh-add, ssh-agent, ssh-keygen, ssh-keyscan, scp
  git-receive-pack, git-upload-pack, git-upload-archive
lib/
  libcurl.so.4, libssl.so.3, libcrypto.so.3, libpcre2-8.so.0,
  libexpat.so.1, libnghttp2.so.14, libzstd.so.1, libssh2.so.1, …
libexec/git-core/
  git-remote-https, git-remote-http, git-credential-*, …
etc/ssh/
  ssh_config, moduli
```

## Published layer ARNs

| Region | Layer ARN |
|---|---|
| us-east-1 | _(fill in after `make publish`)_ |

## Architecture note

This layer targets **x86_64** only. If you need `arm64` (Graviton) Lambda functions, a separate build and publish is required.
