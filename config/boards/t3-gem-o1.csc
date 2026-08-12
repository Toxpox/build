# T3 Gemstone O1 Texas Instruments AM67A quad core 4GB LPDDR4 32GB eMMC USB3 PCIe 4TOPS

BOARD_NAME="T3 Gemstone O1"
BOARD_VENDOR="t3gemstone"
BOARDFAMILY="k3"
BOARD_MAINTAINER=""
INTRODUCED="2026"
BOOT_SOC="j722s"
BOOTCONFIG="am67a_t3_gem_o1_a53_defconfig"
TIBOOT3_BOOTCONFIG="am67a_t3_gem_o1_r5_defconfig"
TIBOOT3_FILE="tiboot3-j722s-hs-fs-evm.bin"
BOOTFS_TYPE="fat"
BOOT_FDT_FILE="ti/k3-am67a-t3-gem-o1.dtb"
DEFAULT_CONSOLE="serial"
SERIALCON="ttyS2"
# edge (mainline 7.2) is left out on purpose: the board DTS lives in
# patch/kernel/archive/k3-6.18/dt and there is no k3-7.2 patch dir yet, so an edge
# image would build without a board DTB at all.
KERNEL_TARGET="vendor,vendor-rt,vendor-edge"
KERNEL_TEST_TARGET="vendor"
ATF_PLAT="k3"
ATF_BOARD="lite"
OPTEE_ARGS=""
OPTEE_PLATFORM="k3-am62x"
# J722S carries the same Rogue GPU as BeagleY-AI; TI ships the packages under the AM62P name.
TI_DEBPKGS_FALLBACK_SUITES=("noble" "jammy")
TI_PACKAGES+=(
	"ti-img-rogue-driver-am62p-dkms"
	"ti-img-rogue-umlibs-am62p"
	"ti-img-rogue-tools-am62p"
	"ti-img-rogue-firmware-am62p"
)

# The official TI U-Boot tree the k3 family selects has no T3 defconfigs yet
# (checked against tag 12.00.00.07, branch ti-u-boot-2026.01 and u-boot master).
# Until T3 support lands upstream, build U-Boot from the vendor fork pinned to a
# verified commit. Runs after the family config so it wins over k3.conf.
function post_family_config__t3_gem_o1_uboot() {
	declare -g BOOTSOURCE="https://github.com/t3gemstone/u-boot"
	declare -g BOOTBRANCH="commit:b8410d78120ed91156f3ec7ede81bed004f8b46e"
	declare -g BOOTPATCHDIR="u-boot-t3-gem-o1"
	display_alert "T3 Gemstone O1: using vendor U-Boot fork" "${BOOTBRANCH}" "info"
}
