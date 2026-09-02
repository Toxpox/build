# T3 Gemstone O1: Vendor Kernel Entegrasyonu ve `.csc` → `.conf` Geçiş Planı

Bu belge iki hedefi kapsar:

1. `https://github.com/t3gemstone/linux` deposundaki `v6.12.24-ti-arm64-r43-t3-gem-o1` dalını Armbian build framework'üne bir kernel kaynağı olarak eklemek.
2. `config/boards/t3-gem-o1.csc` kartını topluluk (`csc`) statüsünden standart/desteklenen (`conf`) statüsüne taşımak.

Mevcut durum referansı: `ARMBIAN_UPSTREAM_FIX_PLAN.md` (bu belge onun yerine geçmez, onu tamamlar ve bazı maddelerini geçersiz kılar; bkz. bölüm 6).

---

## 0. Mevcut durumun özeti

Dal `t3-gem-o1` şu anda şöyle çalışıyor:

| Bileşen | Mevcut kaynak |
|---|---|
| Kernel | `TexasInstruments/ti-linux-kernel`, tag `12.00.00.07`, 6.18 (`k3` ailesi `vendor` dalı) |
| Board DTS | Armbian içinde patch olarak: `patch/kernel/archive/k3-6.18/dt/k3-am67a-t3-gem-o1*.dts*` |
| DTB Makefile kaydı | `patch/kernel/archive/k3-6.18/0001-arm64-dts-ti-build-T3-Gemstone-O1-DTBs.patch` |
| Kernel config | `config/kernel/linux-k3-vendor.config` (paylaşımlı K3 config'i, T3 seçenekleri buraya eklenmiş) |
| U-Boot | Board dosyası içinden `post_family_config` ile `t3gemstone/u-boot` commit `b8410d78` |
| Board statüsü | `.csc`, `BOARD_MAINTAINER=""` |

Bunun sonuçları:

- T3'e özel sürücü seçenekleri paylaşımlı `linux-k3-*.config` dosyalarını kirletiyor ve diğer TI K3 kartlarını etkiliyor.
- Board DTS'i Armbian ağacında bakılıyor; T3 tarafındaki DTS güncellemeleri elle kopyalanmak zorunda.
- Overlay'lerin yalnız biri (`pcie-link-speed-3`) mevcut; T3 kernelinde 34 adet overlay var.
- `.csc` statüsü resmi imaj üretimi ve resmi destek dışında kalıyor.

Doğrulanan vendor kernel gerçekleri (`v6.12.24-ti-arm64-r43-t3-gem-o1`, HEAD `6477c4a`, 2026-08-28):

- Kernel sürümü `6.12.24`.
- `arch/arm64/configs/t3_gem_o1_defconfig` mevcut (3167 satır) ve **`CONFIG_PREEMPT_RT=y` içeriyor**, yani vendor defconfig aslında RT'dir.
- `arch/arm64/boot/dts/ti/` içinde `k3-am67a-t3-gem-o1.dts`, `-pinmux.dtsi` ve 34 adet `.dtso` overlay var; hepsi ağacın `Makefile`'ına kayıtlı, `DTC_FLAGS_k3-am67a-t3-gem-o1 += -@` ayarlı.
- Vendor DTS'te `imu@3` düğümü `compatible = "invensense,icm20948-spidev"` kullanıyor ve bu string vendor kernelin `drivers/spi/spidev.c` dosyasına eklenmiş. Yani `spidev` bağlanması vendor kernelde gerçekten çalışır.
- Vendor DTS'te PCIe **varsayılan `max-link-speed = <3>`** (Gen3) ve düşürme için ayrı bir `k3-am67a-t3-gem-o1-pcie-link-speed-2.dtbo` overlay'i var. Bu, Armbian dalındaki mevcut mantığın **tersidir**.
- Defconfig'te `CONFIG_RTW88_8822CS=m`, `CONFIG_HDC2010=m`, `CONFIG_INV_ICM42600_*=m` gibi kart çevre birimleri zaten açık.

---

## 1. Hedef mimari

Andrew Davis'in `k3-beagle` ailesini ayırma yaklaşımının aynısı uygulanacak (bkz. commit `f5c484947`, "k3-beagle: Add config for BeagleBoard.org Linux and U-Boot"). Bu, upstream'de kabul görmüş ve emsal teşkil eden desendir.

Yeni yapı:

```text
config/sources/families/k3-t3.conf          # yeni aile, k3_common.inc'i source eder
config/kernel/linux-k3-t3-vendor.config     # T3 vendor kernel config (non-RT)
config/kernel/linux-k3-t3-vendor-rt.config  # opsiyonel, RT varyantı
patch/kernel/archive/k3-t3-6.12/            # yalnız gerekiyorsa; hedef: boş
config/boards/t3-gem-o1.conf                # .csc'den yeniden adlandırılmış
```

Kaldırılacaklar:

```text
patch/kernel/archive/k3-6.18/dt/k3-am67a-t3-gem-o1.dts
patch/kernel/archive/k3-6.18/dt/k3-am67a-t3-gem-o1-pinmux.dtsi
patch/kernel/archive/k3-6.18/dt/k3-am67a-t3-gem-o1-pcie-link-speed-3.dtso
patch/kernel/archive/k3-6.18/0001-arm64-dts-ti-build-T3-Gemstone-O1-DTBs.patch
config/kernel/linux-k3-vendor.config içindeki T3'e özel eklemeler (geri alınır)
```

Neden ayrı aile, `BOARDFAMILY="k3"` içinde `case` değil:

- `LINUXFAMILY` ayrı olunca kernel deb paketi `linux-image-vendor-k3-t3` olarak ayrışır, TI K3 paketleriyle çakışmaz.
- `LINUXCONFIG` otomatik olarak `linux-k3-t3-${BRANCH}` olur (`config/sources/common.conf:134`), paylaşımlı K3 config'i kirlenmez.
- `KERNELPATCHDIR` ayrışır, K3 6.18 patch'leri 6.12 ağacına uygulanmaya çalışılmaz.
- Upstream'de aynı gerekçeyle `k3-beagle` zaten ayrılmış durumda; inceleme sırasında tartışma çıkmaz.

---

## 2. Adım adım uygulama

### Adım 2.1 — `config/sources/families/k3-t3.conf` oluştur

Taslak (sürüm pinleri Adım 2.2'de doğrulanacak):

```bash
#
# SPDX-License-Identifier: GPL-2.0
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#

source "${BASH_SOURCE%/*}/include/k3_common.inc"

declare -g LINUXFAMILY="k3-t3" # Separate kernel package from the regular `k3` family
declare -g ATFSOURCE="https://github.com/TexasInstruments/arm-trusted-firmware"

case "${BRANCH}" in

	vendor | vendor-rt)

		declare -g KERNELSOURCE="https://github.com/t3gemstone/linux"
		declare -g KERNEL_MAJOR_MINOR="6.12"
		declare -g KERNELBRANCH="branch:v6.12.24-ti-arm64-r43-t3-gem-o1"
		declare -g KERNEL_DESCRIPTION="T3 Foundation (vendor) kernel"
		declare -g BOOTSOURCE="https://github.com/t3gemstone/u-boot"
		declare -g BOOTBRANCH="commit:b8410d78120ed91156f3ec7ede81bed004f8b46e"
		declare -g BOOTPATCHDIR="u-boot-t3-gem-o1"
		declare -g ATFBRANCH="tag:__DOGRULA__"
		declare -g OPTEE_BRANCH="tag:__DOGRULA__"
		declare -g TI_LINUX_FIRMWARE_BRANCH="tag:__DOGRULA__"
		declare -g UBOOT_HASH_EXTRA="ti-linux-firmware-__DOGRULA__"
		EXTRAWIFI="no"
		;;

esac
```

Notlar:

- `KERNELBRANCH` için dal yerine commit pinlemesi tercih edilebilir (`commit:6477c4a...`). Upstream Armbian'da `k3-beagle` dal pinlemesi kullandığı için dal kabul edilebilirdir, ancak yeniden üretilebilirlik açısından commit daha güçlüdür. **Karar: ilk PR'da `branch:` kullan, T3 tarafı dalı sabitlemeyi taahhüt etmiyorsa `commit:`'e geç.**
- `BOOTSOURCE`/`BOOTBRANCH`/`BOOTPATCHDIR` board dosyasındaki `post_family_config__t3_gem_o1_uboot()` fonksiyonundan buraya taşınır ve o fonksiyon silinir.

### Adım 2.2 — ATF / OP-TEE / ti-linux-firmware sürümlerini doğrula

`r43` etiketi T3'ün kendi revizyon numarasıdır, TI SDK sürümü değildir. Doğru üçlüyü vendor U-Boot ağacından çıkar:

```bash
cd /home/toxpox/Masaüstü/T3/build/build
git clone --filter=blob:none https://github.com/t3gemstone/u-boot /tmp/t3-uboot
cd /tmp/t3-uboot && git checkout b8410d78120ed91156f3ec7ede81bed004f8b46e

# U-Boot taban sürümü -> uyumlu ATF/OP-TEE aralığını belirler
head -5 Makefile
# binman girdileri -> beklenen ti-linux-firmware düzeni
grep -rn 'ti-fs-firmware\|ti-dm\|ti-linux-firmware' arch/arm/dts/k3-j722s*binman* | head
```

Ardından SYSFW/DM ABI uyumu için kernel tarafındaki remoteproc firmware beklentisini kontrol et:

```bash
cd /tmp/t3lin
git show HEAD:drivers/remoteproc/ti_k3_r5_remoteproc.c | grep -n 'VERSION\|ABI' | head
```

Kabul kriteri: `tiboot3.bin` üretimi başarılı, seri konsolda SYSFW/DM sürüm uyumsuzluğu uyarısı yok, R5F ve C7x remoteproc çekirdekleri `running` durumuna geçiyor.

Referans olarak `k3-beagle` ailesi 6.12 tabanlı vendor kernel ile `ATFBRANCH="tag:11.00.09"`, `OPTEE_BRANCH="tag:4.6.0"`, `TI_LINUX_FIRMWARE_BRANCH="tag:11.02.15"` kullanıyor. T3 6.12.24 de aynı nesildendir; bu üçlü başlangıç adayıdır ancak **test edilmeden yazılmamalıdır**.

`UBOOT_HASH_EXTRA` mutlaka ayarlanmalıdır: `artifact-uboot.sh` `TI_LINUX_FIRMWARE_BRANCH` değerini hash'lemez, aksi halde eski `tiboot3.bin` cache'ten yeniden kullanılır.

### Adım 2.3 — Kernel config'lerini üret

Vendor defconfig RT'dir, dolayısıyla iki ayrı config üretilir.

Non-RT `vendor`:

```bash
cd /tmp/t3lin
cp arch/arm64/configs/t3_gem_o1_defconfig /tmp/t3-nonrt-defconfig
scripts/config --file /tmp/t3-nonrt-defconfig \
  --disable CONFIG_PREEMPT_RT \
  --enable  CONFIG_PREEMPT
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
  KCONFIG_CONFIG=/tmp/t3-nonrt-defconfig olddefconfig
cp /tmp/t3-nonrt-defconfig \
  /home/toxpox/Masaüstü/T3/build/build/config/kernel/linux-k3-t3-vendor.config
```

RT `vendor-rt`:

```bash
cp /tmp/t3lin/arch/arm64/configs/t3_gem_o1_defconfig \
  /home/toxpox/Masaüstü/T3/build/build/config/kernel/linux-k3-t3-vendor-rt.config
```

Sonra Armbian'ın kendi normalize akışını çalıştır (satır sırası ve türetilmiş semboller CI ile uyumlu olsun diye):

```bash
./compile.sh rewrite-kernel-config BOARD=t3-gem-o1 BRANCH=vendor
./compile.sh rewrite-kernel-config BOARD=t3-gem-o1 BRANCH=vendor-rt
```

Armbian'ın gerektirdiği seçeneklerin açık olduğunu doğrula (en az):

```text
CONFIG_DEVTMPFS_MOUNT, CONFIG_CGROUPS, CONFIG_MEMCG, CONFIG_NAMESPACES,
CONFIG_SQUASHFS, CONFIG_OVERLAY_FS, CONFIG_ZRAM, CONFIG_ZSWAP,
CONFIG_EXT4_FS, CONFIG_BTRFS_FS, CONFIG_NFT_*, CONFIG_BPF_SYSCALL,
CONFIG_CC_CAN_LINK, CONFIG_DEBUG_INFO_BTF (armbian-config/systemd bağımlılıkları)
```

Kontrol:

```bash
for s in DEVTMPFS_MOUNT CGROUPS MEMCG NAMESPACES SQUASHFS OVERLAY_FS ZRAM ZSWAP EXT4_FS BTRFS_FS BPF_SYSCALL; do
  grep -H "CONFIG_${s}[= ]" config/kernel/linux-k3-t3-vendor.config || echo "EKSIK: ${s}"
done
```

### Adım 2.4 — Paylaşımlı K3 config'ini temizle

`config/kernel/linux-k3-vendor.config` içine T3 için eklenen seçenekler geri alınır:

```text
CONFIG_BT_HCIUART_RTL, CONFIG_RTW88, CONFIG_RTW88_8822CS,
CONFIG_HDC2010, CONFIG_IIO_ST_PRESS
```

Bunlar artık `linux-k3-t3-*.config` içinde yaşar. Böylece diğer TI K3 kartlarında gereksiz sürücü yükü ve regresyon riski kalmaz.

```bash
git log --oneline -- config/kernel/linux-k3-vendor.config
git revert --no-commit <T3-ekleme-commiti>   # ya da elle geri al
./compile.sh rewrite-kernel-config BOARD=beagley-ai BRANCH=vendor  # etkilenmediğini doğrula
```

### Adım 2.5 — Board DTS patch'lerini kaldır

Vendor kernel board DTS'ini, pinmux'unu ve 34 overlay'i zaten içerdiği için Armbian tarafındaki kopyalar silinir:

```bash
git rm patch/kernel/archive/k3-6.18/dt/k3-am67a-t3-gem-o1.dts \
       patch/kernel/archive/k3-6.18/dt/k3-am67a-t3-gem-o1-pinmux.dtsi \
       patch/kernel/archive/k3-6.18/dt/k3-am67a-t3-gem-o1-pcie-link-speed-3.dtso \
       patch/kernel/archive/k3-6.18/0001-arm64-dts-ti-build-T3-Gemstone-O1-DTBs.patch
```

`patch/kernel/archive/k3-t3-6.12/` dizini **oluşturulmaz** — hedef sıfır patch'tir. Bir patch gerekirse (ör. Debian toolchain'iyle derleme hatası), o patch upstream T3 deposuna gönderilir ve Armbian'da yalnız geçici olarak tutulur, dosya başlığında gerekçe ve upstream linki bulunur.

Bu adım, `ARMBIAN_UPSTREAM_FIX_PLAN.md` bölüm 3'teki (ICM-20948) ve 5.1'deki (`__TIMESTAMP__`) sorunları da otomatik olarak kapatır: her ikisi de silinen dosyalarda yaşıyordu.

### Adım 2.6 — Board dosyasını yeni aileye bağla ve PCIe mantığını düzelt

`config/boards/t3-gem-o1.csc` içinde:

```diff
-BOARDFAMILY="k3"
+BOARDFAMILY="k3-t3"
-BOOT_FDT_FILE="ti/k3-am67a-t3-gem-o1.dtb"
+BOOT_FDT_FILE="ti/k3-am67a-t3-gem-o1.dtb"   # değişmez, doğrula
```

`post_family_config__t3_gem_o1_uboot()` fonksiyonu silinir (aileye taşındı).

`pre_umount_final_image__zzz_t3_gem_o1_overlay_hint()` **tersine çevrilir**. Vendor DTS varsayılanı Gen3'tür; Gen2'ye düşürme overlay'i vardır:

```bash
	# Base DTB runs PCIe0 at Gen3. If the onboard M.2 card does not train at
	# Gen3, uncomment the Gen2 overlay below and reboot.
	#name_overlays=ti/k3-am67a-t3-gem-o1-pcie-link-speed-2.dtbo
```

**Karar gerekli:** DX-M1 kartı Gen3'te enumerate olmuyorsa varsayılan Gen2 olmalıdır. Bu durumda `name_overlays` satırı yorumsuz olarak yazılır ve gerekçesi PR'da donanım logu ile belgelenir. Donanım testi yapılmadan bu karar verilmemelidir.

Ayrıca ICM-20948 için:

```bash
# Vendor kernel binds this via the "invensense,icm20948-spidev" compatible
# added to drivers/spi/spidev.c; the node appears as /dev/spidev0.3.
```

Bu iddia şu komutla donanımda doğrulanmalıdır:

```bash
ls -l /dev/spidev0.3
```

### Adım 2.7 — `KERNEL_TARGET` netleştir

```bash
KERNEL_TARGET="vendor,vendor-rt"
KERNEL_TEST_TARGET="vendor"
```

`vendor-rt` yalnız Adım 2.3'teki RT config üretildikten **ve** RT imajı gerçek donanımda açıldıktan sonra bırakılır. Aksi halde `KERNEL_TARGET="vendor"` yapılır.

`edge` hedefi bu PR kapsamına alınmaz: T3 board DTS'i mainline'da yoktur.

---

## 3. `.csc` → `.conf` geçiş koşulları

Armbian'da uzantı yalnız bir etiket değildir; `lib/functions/configuration/main-config.sh:45` şunu yapar:

```bash
if [[ ${VENDOR} == "Armbian" ]] && [[ ${BOARD_TYPE} != "conf" || ... ]]; then
	# resmi vendor metadata (destek, gizlilik, hata bildirimi URL'leri) sıfırlanır
fi
```

Yani `.conf`, kartın resmi Armbian destek zincirine girmesi anlamına gelir. Bunun için aşağıdakiler **tamamlanmadan** yeniden adlandırma yapılmamalıdır.

### 3.1 Bakım sorumlusu (zorunlu)

- `BOARD_MAINTAINER="<github-kullanici-adi>"` doldurulur.
- Kişi Armbian maintainers veritabanına kaydedilir. Aksi halde saatlik çalışan `data-sync-maintainers.yml` iş akışı alanı tekrar `""` yapar ve `CODEOWNERS` üretimi kartı sahipsiz görür.
- Bakım sorumlusu 365 günden fazla hareketsiz kalırsa `CODEOWNERS`'tan düşürülür (`MAINTAINER_INACTIVE_DAYS: "365"`).

Doğrulama:

```bash
curl -fsSL https://github.armbian.com/maintainers.json | grep -i '<github-kullanici-adi>'
python3 tools/validate-board-config.py config/boards/t3-gem-o1.conf
```

Beklenen: `BOARD_MAINTAINER` uyarısı yok, exit `0`.

### 3.2 Board assetleri upstream'de (zorunlu)

`ARMBIAN_UPSTREAM_FIX_PLAN.md` bölüm 1 aynen geçerlidir:

```bash
for url in \
  https://raw.githubusercontent.com/armbian/armbian.github.io/main/board-images/t3-gem-o1.png \
  https://raw.githubusercontent.com/armbian/armbian.github.io/main/board-vendor-logos/t3gemstone-logo.png
do curl -fsSIL "$url" | head -n 1; done
```

Beklenen: iki adet `HTTP/2 200`.

### 3.3 Boot aygıtı davranışı (zorunlu)

`ARMBIAN_UPSTREAM_FIX_PLAN.md` bölüm 2'deki SD/eMMC dinamik `mmcdev` düzeltmesi tamamlanmış ve dört senaryonun tamamı geçmiş olmalıdır. `.csc` için "bilinen kısıt" sayılabilecek bu davranış, `.conf` için kabul edilemez.

### 3.4 Donanım kabul matrisi (zorunlu)

Her satır için seri konsol logu ve komut çıktısı PR'a eklenir.

| Özellik | Doğrulama komutu | Beklenen |
|---|---|---|
| Boot (SD) | `lsblk -o NAME,MOUNTPOINT` | rootfs `mmcblk1p2` |
| Boot (eMMC, SD yok) | aynı | rootfs `mmcblk0p2` |
| Ethernet | `ip -br a; ping -c3 1.1.1.1` | link up, yanıt var |
| Wi-Fi (RTW88 8822CS) | `nmcli dev wifi list` | AP listesi dolu |
| Bluetooth | `hciconfig -a; bluetoothctl scan on` | `hci0 UP`, cihaz görülüyor |
| USB3 | `lsusb -t` | 5000M port |
| PCIe / M.2 | `lspci -vv \| grep -i 'LnkSta'` | beklenen hız (Gen2 veya Gen3, 2.6'daki karara göre) |
| eMMC yazma | `dd if=/dev/zero of=/tmp/t bs=1M count=512 oflag=direct` | makul hız, hata yok |
| GPU (Rogue) | `dmesg \| grep -i pvr; glxinfo -B` veya `kmscube` | sürücü yüklü, render var |
| Remoteproc | `cat /sys/class/remoteproc/remoteproc*/state` | tümü `running` |
| HDC2010 | `sensors` veya `cat /sys/bus/iio/devices/iio:device*/name` | `hdc2010` |
| LPS22DF | aynı | `lps22df` |
| ICM-20948 | `ls -l /dev/spidev0.3` | cihaz mevcut |
| CAN | `ip link set can0 up type can bitrate 500000; candump can0` | arayüz up |
| UART konsol | seri terminal | login prompt |
| RTC | `hwclock -r`, reboot sonrası saat | saat korunuyor |
| Sıcaklık | `cat /sys/class/thermal/thermal_zone*/temp` | makul değerler |
| Overlay yükleme | `uEnv.txt` ile bir DSI overlay | `fdt` uygulanıyor, panel çalışıyor |
| Reboot / poweroff | `reboot`, `poweroff` | temiz, asılmadan |
| RT (vendor-rt seçilirse) | `uname -a \| grep -i rt; cyclictest -m -p90 -i200 -d0 -l100000` | RT kernel, kabul edilebilir max latency |

### 3.5 Dağıtım matrisi

`.conf` kartların desteklenen release'lerde açılması beklenir. En az `trixie` ve `noble` için minimal imaj üretilip açılmalıdır:

```bash
for rel in trixie noble; do
  ./compile.sh build BOARD=t3-gem-o1 BRANCH=vendor RELEASE=$rel \
    BUILD_MINIMAL=yes BUILD_DESKTOP=no KERNEL_CONFIGURE=no
done
```

Not: `TI_DEBPKGS_FALLBACK_SUITES=("noble" "jammy")` nedeniyle Rogue GPU paketleri trixie'de fallback ile geliyor; bu durum PR'da açıkça belirtilmelidir.

### 3.6 Yeniden adlandırma

Yukarıdaki 3.1–3.5 tamam olduğunda:

```bash
git mv config/boards/t3-gem-o1.csc config/boards/t3-gem-o1.conf
python3 tools/validate-board-config.py config/boards/t3-gem-o1.conf
grep -rn 't3-gem-o1\.csc' . --exclude-dir=.git   # kalan referans olmamalı
```

### 3.7 Kademeli alternatif (önerilen)

Tek PR'da hem yeni kernel ailesi hem `.conf` yükseltmesi istemek inceleme yükünü ve red riskini artırır. Önerilen sıra:

1. **PR-A**: asset'ler (`armbian.github.io`).
2. **PR-B**: `k3-t3` ailesi + T3 vendor kernel + patch temizliği + boot aygıtı düzeltmesi, kart **`.csc` kalır**.
3. **PR-C**: donanım kabul matrisi kanıtlarıyla `.csc` → `.conf` yükseltmesi ve `BOARD_MAINTAINER`.

PR-C'nin tek başına küçük ve kanıt yoğun olması kabul olasılığını belirgin biçimde artırır.

---

## 4. Doğrulama komut zinciri

Her adımdan sonra çalıştırılacak tam set:

```bash
cd /home/toxpox/Masaüstü/T3/build/build

# 1. Board config
python3 tools/validate-board-config.py config/boards/t3-gem-o1.*

# 2. Shell lint
bash lib/tools/shellcheck.sh

# 3. DTS kontrolü (yeni aile ile)
./compile.sh dts-check BOARD=t3-gem-o1 BRANCH=vendor

# 4. Kernel config normalize (diff üretmemeli)
./compile.sh rewrite-kernel-config BOARD=t3-gem-o1 BRANCH=vendor
git diff --exit-code config/kernel/linux-k3-t3-vendor.config

# 5. Minimal imaj
./compile.sh build BOARD=t3-gem-o1 BRANCH=vendor RELEASE=trixie \
  BUILD_MINIMAL=yes BUILD_DESKTOP=no KERNEL_CONFIGURE=no

# 6. Diğer K3 kartları etkilenmedi mi
./compile.sh dts-check BOARD=beagley-ai BRANCH=vendor
git diff --stat config/kernel/linux-k3-vendor.config
```

İmaj içerik kontrolü (loop mount sonrası):

```text
/boot/tiboot3.bin
/boot/tispl.bin
/boot/u-boot.img
/boot/uEnv.txt
/boot/dtb/ti/k3-am67a-t3-gem-o1.dtb
/boot/dtb/ti/k3-am67a-t3-gem-o1-*.dtbo        (34 overlay)
/boot/vmlinuz-6.12.24-*
/boot/initrd.img-6.12.24-*
/lib/firmware/ti-ipc/j722s/*
```

Overlay uygulanabilirlik testi:

```bash
fdtoverlay -i k3-am67a-t3-gem-o1.dtb -o /tmp/out.dtb \
  k3-am67a-t3-gem-o1-pcie-link-speed-2.dtbo && echo OK
```

---

## 5. Risk listesi

| Risk | Etki | Azaltma |
|---|---|---|
| 6.12.24 vendor kerneli TI SDK 12.00 firmware'i ile ABI uyumsuz | remoteproc / SYSFW hataları | Adım 2.2'de doğru `TI_LINUX_FIRMWARE_BRANCH` pinlenir, `UBOOT_HASH_EXTRA` ile cache kırılır |
| Vendor dal force-push edilir | yeniden üretilemez build | `commit:` pinlemesine geçilir |
| T3 defconfig'i Armbian gereksinimlerini karşılamaz | systemd/armbian-config bozulur | Adım 2.3'teki sembol kontrol listesi |
| RT config test edilmeden yayınlanır | kullanıcıda özellik kaybı | `vendor-rt` çıkarılır ya da tam test edilir |
| PCIe Gen3 varsayılanı DX-M1 ile eğitilmez | M.2 slot ölü | Gen2 overlay'i varsayılan yapılır, donanım logu ile gerekçelendirilir |
| `.conf` yükseltmesi bakım sorumlusu olmadan yapılır | kart çürür, upstream reddeder | 3.1 zorunlu ön koşuldur |
| Debian toolchain 6.12'yi derlemez | build hatası | Gerekirse minimum patch, upstream T3'e de gönderilir |

---

## 6. `ARMBIAN_UPSTREAM_FIX_PLAN.md` ile ilişki

| Eski madde | Yeni durum |
|---|---|
| 1. Board assetleri | Geçerli, değişmedi (PR-A) |
| 2. SD/eMMC boot aygıtı | Geçerli, değişmedi, `.conf` için zorunlu |
| 3. ICM-20948 DTS düğümü | **Kapandı**: vendor kernel `invensense,icm20948-spidev`'i `spidev.c` içinde destekliyor; DTS artık Armbian'da bakılmıyor |
| 4. `vendor-rt` tutarlılığı | Değişti: T3 defconfig'i zaten RT; artık non-RT varyantı türetiliyor (Adım 2.3) |
| 5.1 `__TIMESTAMP__` | **Kapandı**: dosya siliniyor (Adım 2.5) |
| 5.2 Board maintainer | Yükseldi: `.conf` için uyarı değil, zorunlu (3.1) |
| 5.3 Patch sıralaması | **Kapandı**: T3 patch'i siliniyor |
| 5.4 Commit imzaları | Geçerli, değişmedi |
| 6. Upstream rebase | Geçerli, değişmedi |
| 7–8. Doğrulama ve PR | Bölüm 4 ile genişletildi |

---

## 7. Kontrol listesi

- [ ] 2.2 ATF / OP-TEE / ti-linux-firmware sürümleri donanımda doğrulandı
- [ ] 2.1 `config/sources/families/k3-t3.conf` eklendi
- [ ] 2.3 `linux-k3-t3-vendor.config` (+ opsiyonel `-rt`) üretildi ve normalize edildi
- [ ] 2.4 `linux-k3-vendor.config` T3 eklemelerinden temizlendi, BeagleY-AI etkilenmedi
- [ ] 2.5 T3 DTS ve Makefile patch'leri kaldırıldı
- [ ] 2.6 Board dosyası `k3-t3` ailesine bağlandı, PCIe overlay mantığı düzeltildi
- [ ] 2.7 `KERNEL_TARGET` kararı verildi
- [ ] Bölüm 4 doğrulama zinciri temiz geçti
- [ ] 3.3 SD ve eMMC dört senaryosu geçti
- [ ] 3.4 Donanım kabul matrisi kanıtlarıyla dolduruldu
- [ ] 3.5 trixie ve noble imajları açıldı
- [ ] 3.1 `BOARD_MAINTAINER` atandı ve maintainers.json'da göründü
- [ ] 3.2 Asset URL'leri 200 döndürdü
- [ ] 3.6 `git mv` ile `.conf` yapıldı, kalan `.csc` referansı yok
- [ ] `upstream/main` üzerine rebase, `Signed-off-by` tam
