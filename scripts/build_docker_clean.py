#!/usr/bin/env python3
import subprocess
import sys
import os
import time

DOCKER = "/Applications/Docker.app/Contents/Resources/bin/docker"
IMAGE = "ghcr.io/cirruslabs/flutter:3.24.5"
REPO_ROOT = "/Users/azaanmac/Documents/Clipy"

def run_cmd(cmd, check=True):
    print(f"--> {' '.join(cmd)}")
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    print(p.stdout)
    if check and p.returncode != 0:
        raise RuntimeError(f"Command failed with code {p.returncode}: {p.stdout}")
    return p.stdout.strip()

def main():
    print("=== Starting Techuboard Clean Docker Build ===")
    
    # 1. Clean existing build container if any
    run_cmd([DOCKER, "rm", "-f", "techu_builder"], check=False)

    # 2. Create container
    print("Creating container...")
    cid = run_cmd([
        DOCKER, "create",
        "--name", "techu_builder",
        "-e", "TECHUBOARD_ALLOW_DEBUG_SIGNING=1",
        IMAGE,
        "sleep", "3600"
    ])
    print(f"Created: {cid}")

    try:
        # 3. Start container
        print("Starting container...")
        run_cmd([DOCKER, "start", "techu_builder"])

        # 4. Create destination directories
        print("Preparing workspace directories...")
        run_cmd([DOCKER, "exec", "techu_builder", "mkdir", "-p", "/workspace/vendor/common-relay"])

        # 5. Copy source code (only ~5MB)
        print("Copying techuboard_android source...")
        run_cmd([DOCKER, "cp", os.path.join(REPO_ROOT, "techuboard_android"), "techu_builder:/workspace/techuboard_android"])

        print("Copying common-relay dart source...")
        run_cmd([DOCKER, "cp", os.path.join(REPO_ROOT, "vendor", "common-relay", "dart"), "techu_builder:/workspace/vendor/common-relay/dart"])

        # 6. Run flutter pub get
        print("Running flutter pub get...")
        run_cmd([DOCKER, "exec", "-w", "/workspace/techuboard_android", "techu_builder", "flutter", "pub", "get"])

        # 7. Run flutter build apk
        print("Building release APK...")
        # Use Popen to stream logs in real time
        build_proc = subprocess.Popen(
            [DOCKER, "exec", "-w", "/workspace/techuboard_android", "techu_builder", "flutter", "build", "apk", "--release"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True
        )
        for line in build_proc.stdout:
            sys.stdout.write(line)
            sys.stdout.flush()
        build_proc.wait()
        if build_proc.returncode != 0:
            raise RuntimeError(f"flutter build apk failed with returncode {build_proc.returncode}")

        # 8. Copy output APK
        dest_apk = os.path.join(REPO_ROOT, "Techu Complete Versions", "Android", "Techuboard-Android-v1.0.apk")
        os.makedirs(os.path.dirname(dest_apk), exist_ok=True)
        print(f"Copying built APK to {dest_apk}...")
        run_cmd([DOCKER, "cp", "techu_builder:/workspace/techuboard_android/build/app/outputs/flutter-apk/app-release.apk", dest_apk])

        print(f"=== BUILD SUCCESSFUL! APK size: {os.path.getsize(dest_apk)} bytes ===")
    finally:
        print("Cleaning up container...")
        run_cmd([DOCKER, "rm", "-f", "techu_builder"], check=False)

if __name__ == "__main__":
    main()
