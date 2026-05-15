#!/usr/bin/env python3
"""Integration test for the git-lambda-al2023 Lambda layer.

Run via test.sh, which mounts the unpacked layer at /opt and this file at /var/task.
Requires outbound internet access for the git clone test.
"""
import os
import shutil
import subprocess
import sys
import tempfile


def run(cmd, **kwargs):
    return subprocess.check_output(cmd, stderr=subprocess.STDOUT, text=True, **kwargs).strip()


def check(condition, msg):
    if not condition:
        print(f"FAIL: {msg}", file=sys.stderr)
        sys.exit(1)


def main():
    results = {}

    # 1. git binary is the one from the layer
    git_path = shutil.which("git")
    check(git_path == "/opt/bin/git", f"Expected /opt/bin/git on PATH, got {git_path}")
    results["git_path"] = git_path
    print(f"git path: {git_path}")

    # 2. git version
    git_version = run(["/opt/bin/git", "--version"])
    results["git_version"] = git_version
    print(git_version)

    # 3. ssh version
    ssh_version = run(["/opt/bin/ssh", "-V"])
    results["ssh_version"] = ssh_version
    print(ssh_version)

    # 4. ldd — no missing libraries
    env = {**os.environ, "LD_LIBRARY_PATH": "/opt/lib"}
    ldd_git = run(["ldd", "/opt/bin/git.real"], env=env)
    ldd_ssh = run(["ldd", "/opt/bin/ssh"], env=env)
    check("not found" not in ldd_git, f"git has missing libs:\n{ldd_git}")
    check("not found" not in ldd_ssh, f"ssh has missing libs:\n{ldd_ssh}")
    results["ldd_git_ok"] = True
    results["ldd_ssh_ok"] = True
    print("ldd git: OK")
    print("ldd ssh: OK")

    # 5. git exec-path points to our libexec
    exec_path = run(["/opt/bin/git", "--exec-path"])
    check(exec_path == "/opt/libexec/git-core", f"Expected /opt/libexec/git-core, got {exec_path}")
    results["git_exec_path"] = exec_path
    print(f"git --exec-path: {exec_path}")

    # 6. Functional test: HTTPS clone
    tmpdir = tempfile.mkdtemp(dir="/tmp")
    try:
        subprocess.check_call(
            ["/opt/bin/git", "clone", "--depth", "1",
             "https://github.com/mhart/aws4.git", tmpdir],
            timeout=60,
        )
        cloned = os.listdir(tmpdir)
        check(len(cloned) > 0, "git clone produced an empty directory")
        results["clone_ok"] = True
        results["cloned_files"] = len(cloned)
        print(f"git clone OK ({len(cloned)} items)")
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)

    print("\nAll checks passed.")
    for k, v in results.items():
        print(f"  {k}: {v}")


if __name__ == "__main__":
    main()
