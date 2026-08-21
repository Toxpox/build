# T3 Gemstone O1 Armbian Upstream Çözüm Planı

## Amaç

Bu belge, `t3-gem-o1` dalının `armbian/build` upstream kabul yoluna hazırlanması için gereken düzeltmeleri, önerilen uygulama sırasını ve doğrulama kriterlerini tanımlar.

Mevcut dal derleme seviyesinde önemli kontrollerden geçmektedir:

- Board config validator başarılıdır.
- Armbian ShellCheck başarılıdır.
- Resmi `dts-check` başarılıdır.
- `vendor` çekirdeğiyle minimal imaj üretimi başarılıdır.
- DTB ve PCIe Gen3 overlay imajda bulunmaktadır.
- Overlay, `fdtoverlay` ile taban DTB üzerine başarıyla uygulanmaktadır.
- U-Boot, kernel, initrd, TI Rogue GPU paketleri ve remoteproc firmware dosyaları imajda bulunmaktadır.

Buna rağmen aşağıdaki maddeler tamamlanmadan build PR'ı upstream kabulüne hazır sayılmamalıdır.

## Öncelik ve PR sırası

1. `armbian.github.io` asset PR'ını hazırla ve birleştir.
2. SD ve eMMC için dinamik boot aygıtı düzeltmesini uygula.
3. Desteklenmeyen ICM-20948 DTS düğümünü kaldır veya gerçek sürücü desteğini ekle.
4. `vendor-rt` hedefini destekle ya da geçici olarak kaldır.
5. Yeniden üretilebilirlik ve metadata temizliğini tamamla.
6. Dalı güncel `upstream/main` üzerine rebase et.
7. Yazılım ve gerçek donanım kabul matrisini çalıştır.
8. Assetlerin upstream ana dalına ulaştığını doğruladıktan sonra `armbian/build` PR'ını aç.

---

## 1. Board asset CI engelini kaldır

### Sorun

Armbian board-assets workflow'u aşağıdaki dosyaları `armbian/armbian.github.io` deposunun `main` dalında aramaktadır:

- `board-images/t3-gem-o1.png`
- `board-vendor-logos/t3gemstone-logo.png`

Dosyalar yerel asset dalında mevcut ve validator'dan geçmektedir, fakat upstream URL'leri şu anda `404` döndürmektedir. Build PR'ı asset PR'ından önce açılırsa CI başarısız olur.

### Çözüm

1. `armbian.github.io` dalını güncel upstream üzerine rebase et.
2. Yalnız iki asset dosyasını içeren bir PR aç.
3. Asset validator sonucunu PR açıklamasına ekle.
4. Asset PR'ının birleştirilmesini bekle.
5. Raw GitHub URL'lerinin `200` döndürdüğünü doğrula.

### Doğrulama

```bash
cd /home/toxpox/Masaüstü/T3/build/armbian.github.io

scripts/validate-board-assets.sh \
  board-images/t3-gem-o1.png \
  board-vendor-logos/t3gemstone-logo.png

for url in \
  https://raw.githubusercontent.com/armbian/armbian.github.io/main/board-images/t3-gem-o1.png \
  https://raw.githubusercontent.com/armbian/armbian.github.io/main/board-vendor-logos/t3gemstone-logo.png
do
  curl -fsSIL "$url" | head -n 1
done
```

### Kabul kriteri

Her iki upstream URL'si de `HTTP 200` döndürmelidir.

---

## 2. SD ve eMMC boot aygıtını dinamik hale getir

### Sorun

Genel K3 boot script'i aygıt numarasını sabit kullanmaktadır:

```text
config/bootscripts/boot-k3.cmd:1  bootpart=1:1
config/bootscripts/boot-k3.cmd:3  finduuid=part uuid ${boot} 1:2 uuid
```

T3 vendor U-Boot ise gerçek boot kaynağına göre aşağıdaki seçimi yapmaktadır:

- SD kart: `mmcdev=1`
- eMMC: `mmcdev=0`

`envboot`, eMMC üzerindeki `uEnv.txt` dosyasını yüklese bile içe aktarılan `uenvcmd`, kernel ve rootfs için MMC1'i kullanmaktadır. Bu nedenle eMMC'den başlatılan Armbian kurulumu yanlış aygıta yönelir. SD kart takılı değilse Armbian boot yolu başarısız olur. Ardından çalışan vendor fallback yolu da Armbian dosya düzenini kullanmamaktadır.

### Önerilen çözüm

T3 için kullanılan `uEnv.txt` boot yolunda hem boot bölümü hem root bölümü, `board_late_init()` tarafından belirlenen `${mmcdev}` üzerinden çalışma anında oluşturulmalıdır.

Tercih sırası:

1. Değişikliğin tüm TI K3 kartlarında güvenli olduğu kanıtlanabiliyorsa genel `boot-k3.cmd` dinamik hale getirilmelidir.
2. Genel değişiklik diğer kartlar için riskliyse T3'e özel bir boot script oluşturulmalı ve `config/boards/t3-gem-o1.csc` içinden `BOOTSCRIPT` bu dosyaya yönlendirilmelidir.
3. Alternatif olarak T3 U-Boot patch'i, `uenvcmd` çalışmadan önce `bootpart` ve rootfs UUID aramasını `${mmcdev}` üzerinden hazırlamalıdır.

Çözüm aşağıdaki davranışı sağlamalıdır:

| Boot kaynağı | `mmcdev` | Boot bölümü | Root bölümü |
|---|---:|---|---|
| eMMC | 0 | `0:1` | `0:2` |
| SD | 1 | `1:1` | `1:2` |

Sabit `1:1` ve `1:2` değerleri T3 boot yolunda kalmamalıdır.

### Yazılım doğrulaması

U-Boot varsayılan environment çıktısında aşağıdaki akış denetlenmelidir:

1. `board_late_init()` doğru `mmcdev` değerini seçer.
2. `envboot` aynı aygıttan `uEnv.txt` yükler.
3. `uenvcmd` boot bölümünü `${mmcdev}:1` olarak ayarlar.
4. `finduuid` root bölümünü `${mmcdev}:2` üzerinden bulur.
5. `bootcmd_ti_mmc`, kernel, DTB, overlay ve initrd dosyalarını aynı aygıttan yükler.

### Donanım kabul testi

| Senaryo | SD | eMMC | Beklenen sonuç |
|---|---|---|---|
| SD boot | Armbian | boş veya farklı sistem | Rootfs SD'den açılır |
| eMMC boot | çıkarılmış | Armbian | Rootfs eMMC'den açılır |
| eMMC boot, SD takılı | başka imaj | Armbian | Rootfs yine eMMC'den açılır |
| SD boot, eMMC dolu | Armbian | başka imaj | Rootfs yine SD'den açılır |

Her senaryoda seri konsol logunda seçilen `mmcdev`, yüklenen boot bölümü ve root `PARTUUID` kaydedilmelidir.

### Kabul kriteri

Dört senaryo da kullanıcı müdahalesi olmadan doğru aygıttan açılmalıdır.

---

## 3. ICM-20948 DTS düğümünü düzelt

### Sorun

Aşağıdaki düğüm kernelin tanımadığı bir compatible kullanmaktadır:

```dts
imu@3 {
    compatible = "invensense,icm20948";
    reg = <3>;
    spi-max-frequency = <7000000>;
};
```

Dosya:

```text
patch/kernel/archive/k3-6.18/dt/k3-am67a-t3-gem-o1.dts:806-810
```

TI Linux 6.18 ağacında:

- `invensense,icm20948` binding'i yoktur.
- Bu compatible ile eşleşen kernel sürücüsü yoktur.
- `spidev_dt_ids` tablosunda bu compatible yoktur.
- Board'a özel `driver_override` veya userspace binding servisi yoktur.

Sonuç olarak düğüm DTB içinde bulunsa da bir kernel sürücüsüne bağlanmaz ve `/dev/spidev0.3` oluşturmaz. `dts-check` başarısı yalnız sözdizimi ve mevcut schema kontrollerini gösterir, cihazın çalıştığını göstermez.

### Önerilen çözüm

Upstream Armbian PR'ı için en güvenli çözüm:

1. `imu@3` düğümünü DTS'den kaldır.
2. PR ve commit mesajlarında ICM-20948 desteğinin henüz bulunmadığını açıkça belirt.
3. Daha sonra gerçek bir Linux IIO sürücüsü ve DT binding upstream olduğunda ayrı bir değişiklikle düğümü yeniden ekle.

Kullanıcı alanından SPI erişimi zorunluysa sahte compatible üzerinden otomatik `spidev` bağlamaya çalışılmamalıdır. Açıkça belgelenmiş ve güvenlik sınırları belirlenmiş bir `driver_override` yaklaşımı ayrı bir board paketi olarak değerlendirilebilir. Bu seçenek, Armbian upstream DTS için ikinci tercihtir.

### Doğrulama

```bash
KERNEL=cache/sources/linux-kernel-worktree/6.18__k3__arm64

grep -RIn 'invensense,icm20948' \
  "$KERNEL/Documentation/devicetree/bindings" \
  "$KERNEL/drivers"

grep -RIn 'invensense,icm20948' \
  patch/kernel/archive/k3-6.18/dt
```

### Kabul kriteri

Şunlardan biri gerçekleşmelidir:

- Desteklenmeyen düğüm DTS'den tamamen kaldırılmıştır.
- Ya da compatible için gerçek binding, sürücü, kernel config ve donanım testi mevcuttur.

---

## 4. `vendor-rt` hedefini tutarlı hale getir

### Sorun

Board config iki kernel hedefini ilan etmektedir:

```text
KERNEL_TARGET="vendor,vendor-rt"
KERNEL_TEST_TARGET="vendor"
```

Ancak T3 çevre birimleri için eklenen seçenekler yalnız `linux-k3-vendor.config` dosyasındadır:

```text
CONFIG_BT_HCIUART_RTL=y
CONFIG_RTW88=m
CONFIG_RTW88_8822CS=m
CONFIG_HDC2010=m
CONFIG_IIO_ST_PRESS=m
```

`linux-k3-vendor-rt.config` bu seçenekleri içermemektedir ve `vendor-rt` imajı doğrulanmamıştır. Kullanıcı `vendor-rt` seçtiğinde ilan edilen kart özelliklerinin bir bölümü kaybolabilir.

### Önerilen çözüm

İki geçerli seçenek vardır.

#### Seçenek A: RT desteğini şimdilik kaldır

İlk upstream kabulü için daha düşük riskli seçenektir:

```bash
KERNEL_TARGET="vendor"
KERNEL_TEST_TARGET="vendor"
```

RT desteği daha sonra tam imaj ve donanım testleriyle ayrı PR olarak eklenebilir.

#### Seçenek B: RT desteğini tamamla

1. Gerekli seçenekleri `linux-k3-vendor-rt.config` içine ekle.
2. Seçenek bağımlılıklarını `rewrite-kernel-config` ile çöz.
3. `vendor-rt` DTB ve imaj üretimini çalıştır.
4. Wi-Fi, Bluetooth, HDC2010, LPS22DF, GPU ve remoteproc için donanım testi yap.
5. `KERNEL_TEST_TARGET` değerine `vendor-rt` eklemeyi değerlendir.

Board'a özel seçeneklerin ortak K3 config'lerine eklenmesinin diğer K3 kartlar üzerindeki etkisi PR açıklamasında gerekçelendirilmelidir. Mümkün olan sürücüler modül olarak tutulmalıdır.

### Doğrulama

```bash
./compile.sh dts-check BOARD=t3-gem-o1 BRANCH=vendor-rt

./compile.sh build \
  BOARD=t3-gem-o1 \
  BRANCH=vendor-rt \
  RELEASE=trixie \
  BUILD_MINIMAL=yes \
  BUILD_DESKTOP=no \
  KERNEL_CONFIGURE=no
```

### Kabul kriteri

- `vendor-rt` kaldırılmıştır, veya
- `vendor-rt` imajı başarıyla üretilmiş ve aynı donanım özellikleriyle doğrulanmıştır.

---

## 5. Yeniden üretilebilirlik ve metadata temizliği

### 5.1 Overlay içindeki `__TIMESTAMP__`

Dosya:

```text
patch/kernel/archive/k3-6.18/dt/k3-am67a-t3-gem-o1-pcie-link-speed-3.dtso:24
```

`__TIMESTAMP__` derleme zamanını DTBO içine gömer. Bu, aynı kaynaktan farklı binary çıktı üretebilir.

Öneri:

- Timestamp özelliğini kaldır.
- Overlay görünürlüğü gerekiyorsa sabit bir boolean veya sabit sürüm metni kullan.

Örnek:

```dts
overlays {
    k3-am67a-t3-gem-o1-pcie-link-speed-3;
};
```

### 5.2 Board maintainer

`BOARD_MAINTAINER=""` validator açısından geçerlidir ve `.csc` statüsüyle uyumludur. Buna rağmen PR'da bakım sorumlusu belirtilmesi kabul ihtimalini artırır.

Öneri:

- Bir Armbian kullanıcı adı bakım sorumluluğunu üstleniyorsa merkezi maintainer akışına kaydedilmesini talep et.
- Bakım taahhüdü yoksa `.csc` uzantısını koru. Board'u `.conf` olarak sunma.

### 5.3 Patch sıralaması

Aynı dizinde birden fazla `0001-*` patch bulunmaktadır. Armbian patch motoru dosya adına göre deterministik çalışsa da yeni T3 Makefile patch'inin benzersiz bir sıra numarası kullanması incelemeyi kolaylaştırır.

Öneri:

- T3 patch'ini mevcut sıra ile çakışmayacak bir numaraya taşı.
- Yeniden adlandırmadan sonra patch sırasını ve kernel derlemesini tekrar doğrula.

### 5.4 Commit imzaları ve mesajlar

Son T3 commit'lerinin tamamında `Signed-off-by` bulunması tercih edilmelidir. Armbian CI şu anda bunu zorunlu kılmasa bile kernel/U-Boot tarzı değişikliklerde DCO uyumunu açık hale getirir.

Öneri:

- Commit mesajlarındaki donanım çalışma iddialarını yalnız yeniden üretilebilir test kanıtlarıyla koru.
- Özellikle ICM-20948 için mevcut olmayan sürücü veya `spidev` cihazı iddiasını kaldır.
- Gerekirse interaktif rebase ile commit mesajlarını düzelt ve `Signed-off-by` ekle.

---

## 6. Upstream rebase

### Durum

Dal, denetim sırasında `upstream/main` dalının 59 commit gerisinde ve 7 commit ilerisindeydi. Geçici worktree üzerinde yapılan deneme rebase'i çakışmasız tamamlandı.

### Çözüm

Düzeltmeler tamamlandıktan sonra son kez güncel upstream üzerine rebase et:

```bash
git fetch upstream main
git rebase upstream/main
```

Force push gerekiyorsa uzak dal geçmişini koruyacak şekilde kullan:

```bash
git push --force-with-lease origin t3-gem-o1
```

### Kabul kriteri

```bash
git rev-list --left-right --count upstream/main...HEAD
```

Çıktının sol tarafı `0` olmalıdır.

---

## 7. Zorunlu yazılım doğrulama matrisi

Düzeltmelerden sonra aşağıdaki kontroller yeniden çalıştırılmalıdır.

### Board config

```bash
python3 tools/validate-board-config.py config/boards/t3-gem-o1.csc
```

Beklenen: exit `0`.

### ShellCheck

```bash
bash lib/tools/shellcheck.sh
```

Beklenen: error ve critical yok.

### DTS kontrolü

```bash
./compile.sh dts-check BOARD=t3-gem-o1 BRANCH=vendor
```

Beklenen: exit `0`.

### Minimal imaj

```bash
./compile.sh build \
  BOARD=t3-gem-o1 \
  BRANCH=vendor \
  RELEASE=trixie \
  BUILD_MINIMAL=yes \
  BUILD_DESKTOP=no \
  KERNEL_CONFIGURE=no
```

Beklenen: exit `0` ve yeni imaj dosyası.

### İmaj içerik kontrolü

En az aşağıdakiler doğrulanmalıdır:

- `/boot/tiboot3.bin`
- `/boot/tispl.bin`
- `/boot/u-boot.img`
- `/boot/Image`
- `/boot/uInitrd`
- `/boot/dtb/ti/k3-am67a-t3-gem-o1.dtb`
- `/boot/dtb/ti/k3-am67a-t3-gem-o1-pcie-link-speed-3.dtbo`
- TI Rogue DKMS modülü, userspace kütüphaneleri ve firmware
- J722S remoteproc firmware dosyaları ve symlink'leri
- RTL8822CS firmware
- `blacklist-powervr.conf`

### Overlay kompozisyonu

```bash
fdtoverlay \
  -i k3-am67a-t3-gem-o1.dtb \
  -o combined.dtb \
  k3-am67a-t3-gem-o1-pcie-link-speed-3.dtbo

fdtget combined.dtb /bus@f0000/pcie@2900000 max-link-speed
```

Gerçek PCIe node yolu oluşturulan DTB üzerinden doğrulanmalıdır. Beklenen değer `3` olmalıdır.

---

## 8. Donanım kabul matrisi

Build başarısı tek başına upstream kart desteğini doğrulamaz. En az aşağıdaki donanım kontrolleri kaydedilmelidir.

| Alan | Kontrol | Beklenen sonuç |
|---|---|---|
| Boot | SD boot | Armbian doğru SD rootfs ile açılır |
| Boot | eMMC boot, SD çıkarılmış | Armbian doğru eMMC rootfs ile açılır |
| Ethernet | İki portta DHCP ve trafik | Link kararlı, paket kaybı yok |
| Wi-Fi | RTL8822CS tarama ve bağlantı | Firmware yüklenir, bağlantı kurulur |
| Bluetooth | UART HCI attach ve cihaz tarama | HCI aygıtı aktif olur |
| GPU | `pvrsrvkm` yükleme | `powervr` ile çakışma olmaz |
| Remoteproc | R5F ve C7x başlatma | Firmware bulunur ve core'lar başlar |
| Basınç sensörü | LPS22DF IIO | IIO aygıtı ve ölçüm kanalları görünür |
| Sıcaklık/nem | HDC2010 IIO | IIO aygıtı görünür |
| PCIe Gen2 | Overlay kapalı | M.2 aygıt kararlı enumerate olur |
| PCIe Gen3 | Overlay açık | Uyumlu kart Gen3 hızında enumerate olur |
| USB | USB 2/3 portları | Aygıt algılanır ve veri aktarır |
| Reboot | Soğuk boot ve yeniden başlatma | En az 10 döngü hatasız tamamlanır |

ICM-20948 düğümü kaldırılırsa bu cihaz ilk upstream kabul matrisine dahil edilmemelidir.

---

## 9. Build PR kontrol listesi

Build PR açılmadan önce:

- [ ] Asset PR birleştirildi ve iki raw URL `200` döndürüyor.
- [ ] SD boot doğru aygıttan çalışıyor.
- [ ] eMMC boot, SD çıkarılmışken doğru aygıttan çalışıyor.
- [ ] eMMC boot sırasında takılı SD kart rootfs seçimini değiştirmiyor.
- [ ] Desteklenmeyen ICM-20948 DTS düğümü kaldırıldı veya gerçek sürücü eklendi.
- [ ] `vendor-rt` kaldırıldı veya eksiksiz doğrulandı.
- [ ] `__TIMESTAMP__` kaldırıldı.
- [ ] Board validator başarılı.
- [ ] ShellCheck başarılı.
- [ ] Resmi `dts-check` başarılı.
- [ ] Temiz ortamda minimal vendor imajı üretildi.
- [ ] İmaj içeriği doğrulandı.
- [ ] Donanım test logları PR açıklamasına eklendi.
- [ ] Dal güncel `upstream/main` üzerine rebase edildi.
- [ ] `git status` temiz.

## Nihai kabul tanımı

T3 Gemstone O1 entegrasyonu ancak aşağıdaki koşullar birlikte sağlandığında Armbian upstream'e hazır kabul edilmelidir:

1. Build PR CI'ı dış asset eksikliği nedeniyle başarısız olmamalıdır.
2. Aynı imaj SD ve eMMC'den doğru rootfs seçimiyle açılmalıdır.
3. DTS yalnız gerçekten desteklenen cihazları ilan etmelidir.
4. İlan edilen her kernel hedefi üretilmiş ve test edilmiş olmalıdır.
5. Resmi Armbian kontrolleri ve temiz imaj üretimi başarılı olmalıdır.
6. Temel kart işlevleri gerçek donanım üzerinde kanıtlanmalıdır.
