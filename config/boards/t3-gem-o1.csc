# T3 Gemstone O1 Texas Instruments AM67A quad core 4GB LPDDR4 32GB eMMC USB3 PCIe 4TOPS

BOARD_NAME="T3 Gemstone O1"
BOARD_VENDOR="t3gemstone"
BOARDFAMILY="k3-t3"
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
PACKAGE_LIST_BOARD="bluez"
KERNEL_TARGET="vendor,vendor-rt"
KERNEL_TEST_TARGET="vendor"
ATF_PLAT="k3"
ATF_BOARD="lite"
OPTEE_ARGS=""
OPTEE_PLATFORM="k3-am62x"
# J722S carries the same Rogue GPU as BeagleY-AI; TI ships it under the AM62P name.
TI_DEBPKGS_FALLBACK_SUITES=("noble" "jammy")
TI_PACKAGES+=(
	"ti-img-rogue-driver-am62p-dkms"
	"ti-img-rogue-umlibs-am62p"
	"ti-img-rogue-tools-am62p"
	"ti-img-rogue-firmware-am62p"
)

function post_family_tweaks__t3_gem_o1_remoteproc_firmware() {
	declare src="${SRC}/cache/sources/ti-linux-firmware/ti-ipc/j722s"
	if [[ ! -d "${src}" ]]; then
		display_alert "$BOARD" "ti-ipc/j722s missing, skipping remoteproc firmware" "wrn"
		return 0
	fi

	display_alert "$BOARD" "Installing remoteproc firmware" "info"
	mkdir -p "${SDCARD}/lib/firmware/ti-ipc/j722s"
	run_host_command_logged cp -v "${src}"/* "${SDCARD}/lib/firmware/ti-ipc/j722s/"

	declare -A fw_map=(
		[j722s-mcu-r5f0_0-fw]="ipc_echo_test_mcu2_0_release_strip.xer5f"
		[j722s-main-r5f0_0-fw]="ipc_echo_test_mcu3_0_release_strip.xer5f"
		[j722s-c71_0-fw]="ipc_echo_test_c7x_1_release_strip.xe71"
		[j722s-c71_1-fw]="ipc_echo_test_c7x_2_release_strip.xe71"
	)
	declare name
	for name in "${!fw_map[@]}"; do
		declare target="ti-ipc/j722s/${fw_map[$name]}"
		if [[ ! -f "${SDCARD}/lib/firmware/${target}" ]]; then
			display_alert "$BOARD" "Firmware missing, symlink skipped: ${target}" "wrn"
			continue
		fi
		ln -sfn "${target}" "${SDCARD}/lib/firmware/${name}"
	done
}

function post_family_tweaks__t3_gem_o1_bluetooth_firmware() {
	# armbian-firmware ships a generic rtl8822cs_config.bin that asks for a
	# 2 Mbaud link with hardware flow control. The module on this board is
	# wired to UART6 without working RTS/CTS at that rate, so the very first
	# firmware download command times out:
	#
	#   Bluetooth: hci0: RTL: cfg_sz 73, total sz 40777
	#   Bluetooth: hci0: command 0xfc20 tx timeout
	#   Bluetooth: hci0: RTL: download fw command failed (-110)
	#
	# ti-linux-firmware carries the board-specific pair, which selects
	# 1.5 Mbaud with flow control off and is what the vendor image uses.
	# Install it under /lib/firmware/updates, which the kernel searches
	# before /lib/firmware, so the generic file is shadowed rather than
	# overwritten and armbian-firmware upgrades stay non-destructive.
	declare src="${SRC}/cache/sources/ti-linux-firmware/rtl_bt"
	declare name
	for name in rtl8822cs_fw.bin rtl8822cs_config.bin; do
		if [[ ! -f "${src}/${name}" ]]; then
			display_alert "$BOARD" "ti-linux-firmware ${name} missing, Bluetooth may not come up" "wrn"
			return 0
		fi
	done

	display_alert "$BOARD" "Installing board-specific RTL8822CS Bluetooth firmware" "info"
	mkdir -p "${SDCARD}/lib/firmware/updates/rtl_bt"
	run_host_command_logged cp -v "${src}/rtl8822cs_fw.bin" "${src}/rtl8822cs_config.bin" \
		"${SDCARD}/lib/firmware/updates/rtl_bt/"
}

function post_family_tweaks__t3_gem_o1_blacklist_powervr() {
	display_alert "$BOARD" "Blacklisting mainline powervr, TI pvrsrvkm drives the GPU" "info"
	mkdir -p "${SDCARD}/etc/modprobe.d"
	cat <<- 'EOF' > "${SDCARD}/etc/modprobe.d/blacklist-powervr.conf"
		blacklist powervr
	EOF
}

function pre_umount_final_image__zzz_t3_gem_o1_pcie_gen2() {
	# The vendor DTS runs PCIe0 at Gen3, but the onboard M.2 slot (DX-M1) does
	# not enumerate at Gen3 on current hardware; it does at Gen2. The vendor
	# kernel ships a Gen2 overlay for exactly this, so apply it by default and
	# leave the line editable for anyone with a card that trains at Gen3. The
	# TI U-Boot env applies every entry in name_overlays via get_overlay_mmc
	# (load ${bootdir}/dtb/${overlay}; fdt apply).
	local uenv="${MOUNT}/boot/uEnv.txt"

	if [[ ! -f "${uenv}" ]]; then
		display_alert "$BOARD" "Missing ${uenv}; cannot set PCIe overlay" "wrn"
		return 0
	fi

	if grep -q 'name_overlays' "${uenv}"; then
		return 0
	fi

	cat <<- 'EOF' >> "${uenv}"

	# Device-tree overlays applied by U-Boot at boot. Space-separated, each path
	# is relative to /boot/dtb/. The base DTB asks for PCIe Gen3 (8.0 GT/s); the
	# overlay below caps the M.2 slot at Gen2 (5.0 GT/s), which is what the
	# onboard DX-M1 enumerates at. Remove it to try Gen3 with a card that trains
	# reliably. The vendor kernel builds many more overlays into /boot/dtb/ti/.
	name_overlays=ti/k3-am67a-t3-gem-o1-pcie-link-speed-2.dtbo
	EOF
}

