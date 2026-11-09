#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

DEVICE="${1:-lmi}"
shift || true
if [[ "$DEVICE" != "lmi" ]]; then
    echo "[!] This branch currently has a verified device config only for LMI." >&2
    echo "Usage: $0 lmi [--droidspaces|--no-droidspaces] [--clean]" >&2
    exit 2
fi

ENABLE_DROIDSPACES="${ENABLE_DROIDSPACES:-1}"
CLEAN_BUILD="${CLEAN_BUILD:-0}"
for arg in "$@"; do
    case "$arg" in
        --droidspaces) ENABLE_DROIDSPACES=1 ;;
        --no-droidspaces) ENABLE_DROIDSPACES=0 ;;
        --clean) CLEAN_BUILD=1 ;;
        *) echo "[!] Unknown argument: $arg" >&2; exit 2 ;;
    esac
done

OUT_DIR="$ROOT_DIR/out_lmi"
ARTIFACT_DIR="$OUT_DIR/artifacts"
TOOLCHAIN_BIN="${TOOLCHAIN_BIN:-$HOME/zyc-clang/bin}"

export PATH="$TOOLCHAIN_BIN:$PATH"
export ARCH=arm64
export SUBARCH=arm64
export CCACHE_DIR="${CCACHE_DIR:-$HOME/.cache/ccache_mikernel}"
export CCACHE_BASEDIR="$ROOT_DIR"
export CCACHE_COMPILERCHECK=content
export USE_CCACHE=1

for tool in make clang ccache aarch64-linux-gnu-gcc arm-linux-gnueabi-gcc; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "[!] Required tool not found: $tool" >&2
        exit 1
    }
done

clang --version
mkdir -p "$CCACHE_DIR"

if [[ "$CLEAN_BUILD" == "1" ]]; then
    echo "[*] Removing previous output directory..."
    rm -rf "$OUT_DIR"
fi
mkdir -p "$OUT_DIR"

MAKE_ARGS=(
    ARCH=arm64
    SUBARCH=arm64
    LLVM=1
    LLVM_IAS=1
    CC="ccache clang"
    HOSTCC="ccache clang"
    CROSS_COMPILE=aarch64-linux-gnu-
    CROSS_COMPILE_ARM32=arm-linux-gnueabi-
)

echo "==========================================="
echo "[*] Configuring LMI (vendor/kona-perf_defconfig)"
echo "==========================================="
make O="$OUT_DIR" "${MAKE_ARGS[@]}" vendor/kona-perf_defconfig

echo "[*] Merging SM8250 common and Xiaomi LMI config fragments..."
scripts/kconfig/merge_config.sh -m -O "$OUT_DIR" \
    "$OUT_DIR/.config" \
    arch/arm64/configs/vendor/xiaomi/sm8250-common.config \
    arch/arm64/configs/vendor/xiaomi/lmi.config

if [[ "$ENABLE_DROIDSPACES" == "1" ]]; then
    echo "[*] Enabling and validating DroidSpaces options..."
    chmod +x scripts/prepare_droidspaces_config.sh
    scripts/prepare_droidspaces_config.sh "$OUT_DIR/.config" "$OUT_DIR"
else
    echo "[*] DroidSpaces config normalization skipped."
    make O="$OUT_DIR" "${MAKE_ARGS[@]}" olddefconfig
fi

echo "[*] Verifying LMI board and DT overlay selection..."
for symbol in MACH_XIAOMI_LMI BOARD_XIAOMI BOARD_XIAOMI_SM8250 BOARD_LMI BUILD_ARM64_DT_OVERLAY; do
    grep -qx "CONFIG_${symbol}=y" "$OUT_DIR/.config" || {
        echo "[!] CONFIG_${symbol} is not enabled after config merge." >&2
        exit 1
    }
done

echo "[*] Final config summary:"
grep -E '^CONFIG_(MACH_XIAOMI_LMI|BOARD_XIAOMI|BOARD_XIAOMI_SM8250|BOARD_LMI|LOCALVERSION|PID_NS|UTS_NS|IPC_NS|NET_NS|CGROUP_PIDS|CGROUP_DEVICE|CGROUP_NET_PRIO|DEVTMPFS|OVERLAY_FS|TMPFS_POSIX_ACL|TMPFS_XATTR)=' "$OUT_DIR/.config" || true

echo "==========================================="
echo "[*] Building LMI kernel, DTBs and DTBO..."
echo "==========================================="
make -j"$(nproc)" O="$OUT_DIR" "${MAKE_ARGS[@]}"

KERNEL_IMAGE="$OUT_DIR/arch/arm64/boot/Image"
if [[ ! -s "$KERNEL_IMAGE" ]]; then
    echo "[!] Kernel Image was not generated." >&2
    exit 1
fi

rm -rf "$ARTIFACT_DIR"
mkdir -p "$ARTIFACT_DIR/dts"
cp "$KERNEL_IMAGE" "$ARTIFACT_DIR/Image"
cp "$OUT_DIR/.config" "$ARTIFACT_DIR/kernel.config"
[[ ! -s "$OUT_DIR/vmlinux" ]] || cp "$OUT_DIR/vmlinux" "$ARTIFACT_DIR/vmlinux"
[[ ! -s "$OUT_DIR/System.map" ]] || cp "$OUT_DIR/System.map" "$ARTIFACT_DIR/System.map"
[[ ! -s "$OUT_DIR/arch/arm64/boot/dtbo.img" ]] || cp "$OUT_DIR/arch/arm64/boot/dtbo.img" "$ARTIFACT_DIR/dtbo.img"

DTS_OUT="$OUT_DIR/arch/arm64/boot/dts/vendor/qcom"
if [[ ! -s "$DTS_OUT/lmi-sm8250-overlay.dtbo" ]]; then
    echo "[!] LMI DT overlay was not generated; check BOARD_LMI and DTS configuration." >&2
    exit 1
fi
if [[ ! -s "$OUT_DIR/arch/arm64/boot/dtbo.img" ]]; then
    echo "[!] dtbo.img was not generated." >&2
    exit 1
fi
if [[ -d "$DTS_OUT" ]]; then
    find "$DTS_OUT" -maxdepth 1 -type f \
        \( -name 'kona*.dtb' -o -name 'lmi*.dtb' -o -name 'lmi*.dtbo' \) \
        -exec cp -t "$ARTIFACT_DIR/dts" {} +
fi

if ! find "$ARTIFACT_DIR/dts" -maxdepth 1 -type f -print -quit | grep -q .; then
    echo "[!] No LMI/Kona device-tree output was found." >&2
    exit 1
fi

(
    cd "$ARTIFACT_DIR"
    sha256sum Image kernel.config > SHA256SUMS
    [[ ! -f dtbo.img ]] || sha256sum dtbo.img >> SHA256SUMS
)

COMMIT="$(git rev-parse --short=8 HEAD 2>/dev/null || echo unknown)"
BUILD_DATE="$(date -u +%Y%m%d-%H%M%S)"
PACKAGE="$ROOT_DIR/APTKernel_LMI_${BUILD_DATE}_${COMMIT}.tar.gz"
tar -czf "$PACKAGE" -C "$ARTIFACT_DIR" .

echo "==========================================="
echo "[+] Build completed."
echo "[+] Kernel image: $KERNEL_IMAGE"
echo "[+] Artifact package: $PACKAGE"
echo "[*] ccache statistics:"
ccache -s
