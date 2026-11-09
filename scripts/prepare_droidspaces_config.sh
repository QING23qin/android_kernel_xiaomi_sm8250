#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CONFIG_FILE="${1:-out_lmi/.config}"
OUT_DIR="${2:-$(dirname "$CONFIG_FILE")}"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[!] Config file not found: $CONFIG_FILE" >&2
    exit 1
fi

# These are the options required by the legacy DroidSpaces/container setup.
# Apply them to the generated .config, not to a defconfig fragment: the
# aptusitu-new branch uses vendor defconfig + Xiaomi config fragments.
"$ROOT_DIR/scripts/config" --file "$CONFIG_FILE" \
    -e SYSCTL \
    -e SYSVIPC \
    -e POSIX_MQUEUE \
    -e NAMESPACES \
    -e PID_NS \
    -e UTS_NS \
    -e IPC_NS \
    -e NET_NS \
    -e USER_NS \
    -e SECCOMP \
    -e SECCOMP_FILTER \
    -e CGROUPS \
    -e CGROUP_PIDS \
    -e CGROUP_DEVICE \
    -e MEMCG \
    -e CGROUP_SCHED \
    -e FAIR_GROUP_SCHED \
    -e CGROUP_FREEZER \
    -e CGROUP_NET_PRIO \
    -e DEVTMPFS \
    -e DEVTMPFS_MOUNT \
    -e OVERLAY_FS \
    -e TMPFS \
    -e TMPFS_POSIX_ACL \
    -e TMPFS_XATTR \
    -e VETH

echo "[*] Resolving Kconfig dependencies..."
make O="$OUT_DIR" ARCH=arm64 LLVM=1 LLVM_IAS=1 olddefconfig

required=(
    SYSCTL SYSVIPC POSIX_MQUEUE NAMESPACES
    PID_NS UTS_NS IPC_NS NET_NS USER_NS
    SECCOMP SECCOMP_FILTER
    CGROUPS CGROUP_PIDS CGROUP_DEVICE MEMCG
    CGROUP_SCHED FAIR_GROUP_SCHED CGROUP_FREEZER CGROUP_NET_PRIO
    DEVTMPFS DEVTMPFS_MOUNT OVERLAY_FS
    TMPFS TMPFS_POSIX_ACL TMPFS_XATTR VETH
)

echo "[*] Verifying effective DroidSpaces configuration..."
for symbol in "${required[@]}"; do
    if ! grep -qx "CONFIG_${symbol}=y" "$CONFIG_FILE"; then
        echo "[!] CONFIG_${symbol} did not survive olddefconfig" >&2
        grep -E "^#? CONFIG_${symbol}(=| )" "$CONFIG_FILE" || true
        exit 1
    fi
done

grep -E '^CONFIG_(SYSVIPC|POSIX_MQUEUE|PID_NS|UTS_NS|IPC_NS|NET_NS|USER_NS|SECCOMP_FILTER|CGROUP_PIDS|CGROUP_DEVICE|MEMCG|CGROUP_SCHED|CGROUP_FREEZER|CGROUP_NET_PRIO|DEVTMPFS|OVERLAY_FS|TMPFS_POSIX_ACL|TMPFS_XATTR|VETH)=y$' "$CONFIG_FILE"
echo "[+] DroidSpaces configuration verified."
