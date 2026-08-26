#!/bin/bash
set -e

# Normalize the DroidSpaces-required options in the device defconfig.
# Kconfig defconfigs can contain duplicate entries; when a later
# '# CONFIG_FOO is not set' remains, it can override an earlier CONFIG_FOO=y.
# Remove every existing occurrence first, then append one authoritative value.

DEVICE="${1:-lmi}"
CONFIG_FILE="arch/arm64/configs/${DEVICE}_defconfig"

if [ ! -f "${CONFIG_FILE}" ]; then
    echo "[!] Defconfig not found: ${CONFIG_FILE}"
    exit 1
fi

# Linux 4.19 / DroidSpaces legacy-kernel requirements.
# Keep this list limited to options supported by this tree and required by
# DroidSpaces; do not blindly enable unrelated Docker-only options.
declare -A CONFIGS=(
    [SYSCTL]=y
    [SYSVIPC]=y
    [POSIX_MQUEUE]=y
    [NAMESPACES]=y
    [PID_NS]=y
    [UTS_NS]=y
    [IPC_NS]=y
    [NET_NS]=y
    [SECCOMP]=y
    [SECCOMP_FILTER]=y
    [CGROUPS]=y
    [CGROUP_DEVICE]=y
    [CGROUP_PIDS]=y
    [MEMCG]=y
    [CGROUP_SCHED]=y
    [FAIR_GROUP_SCHED]=y
    [CGROUP_FREEZER]=y
    [CGROUP_NET_PRIO]=y
    [DEVTMPFS]=y
    [OVERLAY_FS]=y
    [TMPFS_POSIX_ACL]=y
    [TMPFS_XATTR]=y
    [FW_LOADER]=y
    [FW_LOADER_USER_HELPER]=y
    [FW_LOADER_COMPRESS]=y
    [VETH]=y
    [BRIDGE]=y
    [BRIDGE_NETFILTER]=y
    [NETFILTER]=y
    [NETFILTER_ADVANCED]=y
    [NF_CONNTRACK]=y
    [IP_NF_IPTABLES]=y
    [IP_NF_FILTER]=y
    [NF_NAT]=y
    [IP_NF_TARGET_MASQUERADE]=y
    [NETFILTER_XT_TARGET_MASQUERADE]=y
    [NETFILTER_XT_TARGET_TCPMSS]=y
    [NETFILTER_XT_MATCH_ADDRTYPE]=y
    [NF_CONNTRACK_NETLINK]=y
    [NF_NAT_REDIRECT]=y
    [IP_ADVANCED_ROUTER]=y
    [IP_MULTIPLE_TABLES]=y
    [USER_NS]=y
)

# Some legacy kernels use CONFIG_FOO=n rather than '# CONFIG_FOO is not set'.
for symbol in "${!CONFIGS[@]}"; do
    sed -i -E "/^CONFIG_${symbol}=.*/d; /^# CONFIG_${symbol} is not set$/d" "${CONFIG_FILE}"
done

{
    echo
    echo "# DroidSpaces legacy-kernel configuration (normalized by CI)"
    for symbol in "${!CONFIGS[@]}"; do
        echo "CONFIG_${symbol}=${CONFIGS[$symbol]}"
    done
} >> "${CONFIG_FILE}"

echo "[+] Normalized DroidSpaces config in ${CONFIG_FILE}"

# Print the effective entries so CI logs make configuration regressions obvious.
for symbol in "${!CONFIGS[@]}"; do
    grep -E "^CONFIG_${symbol}=" "${CONFIG_FILE}" | tail -n 1
done
