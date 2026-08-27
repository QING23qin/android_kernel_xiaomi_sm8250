#!/bin/bash

# Exit on any error
set -e

if [ -z "$1" ]; then
    echo "[!] Error: No device specified."
    echo "Usage: $0 <device_name> [ksu] [miui|aosp]"
    exit 1
fi

DEVICE_NAME="$1"
DEFCONFIG="${DEVICE_NAME}_defconfig"
DEFCONFIG_PATH="arch/arm64/configs/${DEFCONFIG}"

if [ ! -f "$DEFCONFIG_PATH" ]; then
    echo "[!] Error: Defconfig not found at $DEFCONFIG_PATH"
    exit 1
fi

ENABLE_KSU=0
TARGET_OS="both"
shift
for arg in "$@"; do
    case "$arg" in
        ksu) ENABLE_KSU=1 ;;
        miui) TARGET_OS="miui" ;;
        aosp) TARGET_OS="aosp" ;;
    esac
done

KERNEL_DIR="$(pwd)"
TOOLCHAIN_BIN="$HOME/zyc-clang/bin"
export PATH="${TOOLCHAIN_BIN}:${PATH}"
export ARCH="arm64"
export SUBARCH="arm64"
export CCACHE_DIR="$HOME/.cache/ccache_mikernel"
export CCACHE_EXEC=$(command -v ccache)
if [ -z "$CCACHE_EXEC" ]; then
    echo "[!] ccache not found!"
    exit 1
fi
export USE_CCACHE=1
export CROSS_COMPILE="aarch64-linux-gnu-"
export CROSS_COMPILE_ARM32="arm-linux-gnueabi-"

clang --version || { echo "[!] Clang not found"; exit 1; }
mkdir -p "$CCACHE_DIR"

if [ "$ENABLE_KSU" -eq 1 ]; then
    echo "==========================================="
    echo " [*] Initializing KernelSU (ReSukiSU) Setup"
    echo "==========================================="
    curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash
    echo "[+] KernelSU setup finished."
fi

echo "==========================================="
echo " [*] Initializing Baseband-guard Setup"
echo "==========================================="
wget -O- https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh | bash
sed -i '/^config LSM$/,/^help$/{ /^[[:space:]]*default/ { /baseband_guard/! s/selinux/selinux,baseband_guard/ } }' security/Kconfig

echo "==========================================="
echo " [*] Initializing AnyKernel3 Workspace"
echo "==========================================="
rm -rf anykernel
git clone https://github.com/AstideLabs/AnyKernel3 -b kona --single-branch --depth=1 anykernel
sed -i "s/^device\.name1=.*/device.name1=${DEVICE_NAME}/" anykernel/anykernel.sh

# DroidSpaces cgroup-v2 compatibility:
# the container cgroup is used as the cgroup-namespace root and intentionally
# contains the monitor process. Apply the namespace-root mixable patch before
# either target is configured/built.
DROIDSPACES_CGROUP_PATCH="patches/droidspaces-cgroupns-root-mixable.patch"
if [ -f "$DROIDSPACES_CGROUP_PATCH" ]; then
    echo "[*] Applying DroidSpaces cgroup namespace root compatibility patch..."
    if ! patch -p1 --forward < "$DROIDSPACES_CGROUP_PATCH"; then
        if grep -q 'return cgrp == current_cgns_cgroup_dfl();' kernel/cgroup/cgroup.c; then
            echo "[+] DroidSpaces cgroup compatibility patch is already applied."
        else
            echo "[!] Failed to apply DroidSpaces cgroup compatibility patch"
            exit 1
        fi
    fi
fi

build_target() {
    local OS_TYPE=$1
    echo "==========================================="
    echo " Starting Kernel Compilation for ${DEVICE_NAME} (Target: $OS_TYPE)"
    echo "==========================================="

    local OUT_DIR="${KERNEL_DIR}/out_${OS_TYPE}"
    local MAKE_OPTS=(
        -j"$(nproc)"
        O="${OUT_DIR}"
        ARCH="${ARCH}"
        SUBARCH="${SUBARCH}"
        LLVM=1
        LLVM_IAS=1
        CC="ccache clang"
        HOSTCC="ccache clang"
        CROSS_COMPILE="${CROSS_COMPILE}"
        CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32}"
    )

    echo "[*] Cleaning ${OUT_DIR}..."
    rm -rf "${OUT_DIR}"
    mkdir -p "${OUT_DIR}"

    local DTS_SOURCE="arch/arm64/boot/dts/vendor/qcom"
    local DTS_BACKUP=".dts.bak.${OS_TYPE}"

    if [ "$OS_TYPE" == "miui" ]; then
        echo "[*] Applying MIUI DTS patches..."
        cp -a "${DTS_SOURCE}" "${DTS_BACKUP}"
        sed -i 's/<154>/<1537>/g' ${DTS_SOURCE}/dsi-panel-j1s* || true
        sed -i 's/<154>/<1537>/g' ${DTS_SOURCE}/dsi-panel-j2* || true
        sed -i 's/<155>/<1544>/g' ${DTS_SOURCE}/dsi-panel-j3s-37-02-0a-dsc-video.dtsi || true
        sed -i 's/<155>/<1545>/g' ${DTS_SOURCE}/dsi-panel-j11-38-08-0a-fhd-cmd.dtsi || true
        sed -i 's/<155>/<1546>/g' ${DTS_SOURCE}/dsi-panel-k11a-38-08-0a-dsc-cmd.dtsi || true
        sed -i 's/<155>/<1546>/g' ${DTS_SOURCE}/dsi-panel-l11r-38-08-0a-dsc-cmd.dtsi || true
        sed -i 's/<70>/<695>/g' ${DTS_SOURCE}/dsi-panel-j11-38-08-0a-fhd-cmd.dtsi || true
        sed -i 's/<70>/<695>/g' ${DTS_SOURCE}/dsi-panel-j3s-37-02-0a-dsc-video.dtsi || true
        sed -i 's/<70>/<695>/g' ${DTS_SOURCE}/dsi-panel-k11a-38-08-0a-dsc-cmd.dtsi || true
        sed -i 's/<70>/<695>/g' ${DTS_SOURCE}/dsi-panel-l11r-38-08-0a-dsc-cmd.dtsi || true
        sed -i 's/<71>/<710>/g' ${DTS_SOURCE}/dsi-panel-j1s* || true
        sed -i 's/<71>/<710>/g' ${DTS_SOURCE}/dsi-panel-j2* || true
        sed -i 's/\/\/ mi,mdss-dsi-pan-enable-smart-fps/mi,mdss-dsi-pan-enable-smart-fps/g' ${DTS_SOURCE}/dsi-panel* || true
        sed -i 's/\/\/ mi,mdss-dsi-smart-fps-max_framerate/mi,mdss-dsi-smart-fps-max_framerate/g' ${DTS_SOURCE}/dsi-panel* || true
        sed -i 's/\/\/ qcom,mdss-dsi-pan-enable-smart-fps/qcom,mdss-dsi-pan-enable-smart-fps/g' ${DTS_SOURCE}/dsi-panel* || true
        sed -i 's/qcom,mdss-dsi-qsync-min-refresh-rate/\/\/qcom,mdss-dsi-qsync-min-refresh-rate/g' ${DTS_SOURCE}/dsi-panel* || true
    fi

    echo "[*] Making defconfig: ${DEFCONFIG}..."
    make "${MAKE_OPTS[@]}" "${DEFCONFIG}"

    echo "[*] Injecting Baseband-guard configuration..."
    scripts/config --file "${OUT_DIR}/.config" -e BBG

    if [ "$ENABLE_KSU" -eq 1 ]; then
        scripts/config --file "${OUT_DIR}/.config" -e KSU -e THREAD_INFO_IN_TASK -e KSU_SUSFS
    fi

    if [ "$OS_TYPE" == "miui" ]; then
        scripts/config --file "${OUT_DIR}/.config" \
            --set-str STATIC_USERMODEHELPER_PATH /system/bin/micd \
            -e PERF_CRITICAL_RT_TASK -e SF_BINDER -e OVERLAY_FS -e MIGT -e MIGT_ENERGY_MODEL \
            -e MIHW -e PACKAGE_RUNTIME_INFO -e BINDER_OPT -e KPERFEVENTS -e PERF_HUMANTASK \
            -d LTO_CLANG -e LTO_NONE -d SHADOW_CALL_STACK -e XIAOMI_MIUI -d MI_MEMORY_SYSFS \
            -d TASK_DELAY_ACCT -e MIUI_ZRAM_MEMORY_TRACKING -e PERF_HELPER -e BOOTUP_RECLAIM \
            -e MI_RECLAIM -e RTMM -e MILLET_CGROUP -e MILLET_SIG -e MILLET_BINDER \
            -e MILLET_PKG -e MILLET_BINDER_GKI -e MILLET_CORE -e MILLET_HS -e BINDER_PRIO \
            -d REKERNEL -d REKERNEL_NETWORK
    fi

    if [ "$OS_TYPE" == "aosp" ]; then
        scripts/config --file "${OUT_DIR}/.config" -e REKERNEL -e REKERNEL_NETWORK
    fi

    # These are runtime-visible options. Force them after every defconfig/injection
    # and keep IKCONFIG enabled so the exact kernel can be inspected after flashing.
    if [ "$DEVICE_NAME" == "lmi" ]; then
        echo "[*] Forcing DroidSpaces runtime configuration..."
        scripts/config --file "${OUT_DIR}/.config" \
            -e CGROUPS \
            -e CGROUP_PIDS \
            -e CGROUP_DEVICE \
            -e CGROUP_SCHED \
            -e FAIR_GROUP_SCHED \
            -e PID_NS \
            -e UTS_NS \
            -e IPC_NS \
            -e NET_NS \
            -e SECCOMP \
            -e SECCOMP_FILTER \
            -e DEVTMPFS \
            -e DEVTMPFS_MOUNT \
            -e OVERLAY_FS \
            -e VETH \
            -e IKCONFIG \
            -e IKCONFIG_PROC
    fi

    echo "[*] Updating config (make olddefconfig)..."
    make "${MAKE_OPTS[@]}" olddefconfig

    if [ "$DEVICE_NAME" == "lmi" ]; then
        echo "[*] Verifying final DroidSpaces .config before compilation..."
        for symbol in CGROUPS CGROUP_PIDS CGROUP_DEVICE CGROUP_SCHED FAIR_GROUP_SCHED PID_NS UTS_NS IPC_NS NET_NS SECCOMP SECCOMP_FILTER DEVTMPFS DEVTMPFS_MOUNT OVERLAY_FS VETH IKCONFIG IKCONFIG_PROC; do
            grep -q "^CONFIG_${symbol}=y$" "${OUT_DIR}/.config" || {
                echo "[!] CONFIG_${symbol} is not enabled after olddefconfig"
                exit 1
            }
        done
        grep -E '^CONFIG_(CGROUPS|CGROUP_PIDS|CGROUP_DEVICE|CGROUP_SCHED|FAIR_GROUP_SCHED|PID_NS|UTS_NS|IPC_NS|NET_NS|SECCOMP|SECCOMP_FILTER|DEVTMPFS|DEVTMPFS_MOUNT|OVERLAY_FS|VETH|IKCONFIG|IKCONFIG_PROC)=y$' "${OUT_DIR}/.config"
    fi

    echo "[*] Building kernel..."
    make "${MAKE_OPTS[@]}"

    if [ "$OS_TYPE" == "miui" ]; then
        echo "[*] Restoring DTS backups..."
        rm -rf "${DTS_SOURCE}"
        mv "${DTS_BACKUP}" "${DTS_SOURCE}"
    fi

    echo "==========================================="
    if [ -f "${OUT_DIR}/arch/arm64/boot/Image" ]; then
        KERNEL_IMAGE="${OUT_DIR}/arch/arm64/boot/Image"
        echo "[+] $OS_TYPE Build Successful!"
        echo "[+] Kernel Image path: ${KERNEL_IMAGE}"

        # Verify the kernel build products, but do not confuse an IKCONFIG
        # extraction failure with a bad kernel. Linux 4.19 arm64 Android Image
        # packaging can remove the embedded IKCONFIG marker from Image even
        # though the running-kernel configuration is present in vmlinux.
        if [ -f "${OUT_DIR}/vmlinux" ]; then
            echo "[*] Extracting IKCONFIG from vmlinux..."
            if scripts/extract-ikconfig "${OUT_DIR}/vmlinux" > "${OUT_DIR}/.vmlinux_config" 2> "${OUT_DIR}/.ikconfig_error"; then
                echo "[+] IKCONFIG successfully extracted from vmlinux."
                for symbol in CGROUP_PIDS CGROUP_DEVICE PID_NS UTS_NS IPC_NS NET_NS SECCOMP_FILTER DEVTMPFS OVERLAY_FS VETH; do
                    grep -q "^CONFIG_${symbol}=y$" "${OUT_DIR}/.vmlinux_config" || {
                        echo "[!] CONFIG_${symbol} is missing from vmlinux IKCONFIG"
                        exit 1
                    }
                done
                echo "[+] vmlinux contains all required DroidSpaces CONFIG options."
            else
                echo "[!] vmlinux IKCONFIG extraction failed; showing diagnostic:"
                cat "${OUT_DIR}/.ikconfig_error" || true
                echo "[*] Checking CONFIG_IKCONFIG in final .config instead."
                grep -E '^CONFIG_IKCONFIG(_PROC)?=y$' "${OUT_DIR}/.config"
            fi
        fi

        sha256sum "${KERNEL_IMAGE}" > "${OUT_DIR}/Image.sha256"
        sha256sum "${KERNEL_IMAGE}"

        echo "[*] Packaging to AnyKernel3 ($OS_TYPE)..."
        rm -rf anykernel/kernels/*
        mkdir -p "anykernel/kernels/${OS_TYPE}/"
        cp "${KERNEL_IMAGE}" "anykernel/kernels/${OS_TYPE}/"
        cp "${OUT_DIR}/arch/arm64/boot/dtb" "anykernel/kernels/${OS_TYPE}/"
        if [ -f "${OUT_DIR}/arch/arm64/boot/dtbo.img" ]; then
            cp "${OUT_DIR}/arch/arm64/boot/dtbo.img" "anykernel/kernels/${OS_TYPE}/"
        fi

        local KSU_ZIP_STR="NoKernelSU"
        if [ "$ENABLE_KSU" -eq 1 ]; then KSU_ZIP_STR="ReSukiSU-SuSFS"; fi
        local GIT_COMMIT_ID=$(git rev-parse --short=8 HEAD 2>/dev/null || echo "unknown")
        local OS_UPPER=$(echo "$OS_TYPE" | tr '[:lower:]' '[:upper:]')
        local ZIP_FILENAME="APTKernel_${OS_UPPER}_${DEVICE_NAME}_${KSU_ZIP_STR}_$(date +'%Y%m%d_%H%M%S')_anykernel3_${GIT_COMMIT_ID}.zip"
        echo "[*] Zipping $ZIP_FILENAME ..."
        pushd anykernel > /dev/null
        zip -r9 "$ZIP_FILENAME" ./* -x .git .gitignore out/ ./*.zip > /dev/null
        mv "$ZIP_FILENAME" ../
        popd > /dev/null
        echo "[+] $OS_TYPE kernel binaries successfully packed into: $ZIP_FILENAME"
    else
        echo "[-] $OS_TYPE Build Failed. Kernel Image not found."
        exit 1
    fi
}

if [ "$TARGET_OS" == "aosp" ] || [ "$TARGET_OS" == "both" ]; then build_target "aosp"; fi
if [ "$TARGET_OS" == "miui" ] || [ "$TARGET_OS" == "both" ]; then build_target "miui"; fi

echo "==========================================="
echo "[*] ccache stats:"
ccache -s
echo "[+] All requested builds completed!"