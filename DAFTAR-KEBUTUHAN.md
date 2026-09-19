# Daftar Kebutuhan PWKU Server 1.5.5

## Komputer host untuk panduan VirtualBox

- Windows 10/11 64-bit.
- VirtualBox 7.x.
- RAM minimal 12 GB; rekomendasi 16 GB.
- Ruang kosong minimal 25 GB; VDI virtual disetel 50 GB dinamis.
- CPU virtualization (Intel VT-x/AMD-V) aktif di BIOS/UEFI.
- OpenSSH Client Windows untuk installer sekali klik.

## VM VirtualBox pada panduan awal

- Ubuntu Server 20.04.6 LTS 64-bit.
- RAM 6144 MB.
- 1 vCPU untuk kompatibilitas/stabilitas.
- Disk VDI 50 GB, LVM aktif.
- Network NAT dan Cable Connected.
- OpenSSH Server aktif.

## Port NAT VirtualBox

| Fungsi | Host | Guest |
|---|---:|---:|
| SSH | 127.0.0.1:2223 | 22 |
| Panel web | 127.0.0.1:8081 | 8080 |
| Client PW | 127.0.0.1:29001 | 29000 |

## VM Proxmox yang sedang diuji

- Ubuntu Server 20.04.6, 6 core, RAM 8 GiB, disk SCSI VirtIO 100 GiB.
- NIC VirtIO pada bridge `vmbr0`; VM uji menggunakan `192.168.30.10/24`.
- Akses langsung dari Windows melalui SSH port 22, panel port 8080, dan
  gateway game port 29000. Tidak memakai port forwarding VirtualBox.
- Snapshot dan disk thin memerlukan ruang fisik yang cukup pada host Proxmox.

## Paket Ubuntu yang diminta langsung

```text
binutils
file
openssl
ca-certificates
curl
rsync
unzip
lvm2
libc6:i386
libstdc++6:i386
libgcc-s1:i386
zlib1g:i386
libncurses5:i386
libssl1.1:i386
libstdc++5:i386
libpcre3:i386
libxml2:i386
pax-utils
openjdk-8-jre-headless
mariadb-server
mariadb-client
openssh-server
```

APT memasang dependensi transitifnya secara otomatis. Salinan 209 paket `.deb`
dari instalasi teruji tersedia dalam `ubuntu-debs-20.04.tar.gz`.

## File khusus PW

- `Perfect_World_Server_1.5.5.tar.gz`: daemon, konfigurasi, dan data server.
- `web.tar.gz`: panel pemain/admin dan worker pengelolaan.
- `client-data.tar.gz`: `gshop.data`, `elements.data`, dan `tasks.data`.
- `support/db.sql`: 8 tabel dan 19 stored procedure autentikasi.
- `support/libtask.so`: ELF32 khusus `gamed/gs`, SHA-256
  `d82e92e97b1fe3a77c4929281d7b250bef9af81169f308165b429e14e8dfaa07`.
- `libpcre.so.0`: dibuat sebagai symlink privat ke library PCRE i386 yang
  tersedia; library sistem tidak ditimpa.

## Layanan hasil instalasi

- `mariadb.service`
- `ssh.service`
- `pw155-game.service`
- `pw155-web.service`
- `pw155-game-control.service`
- `pw155-character-sync.timer`
- `pw155-monitor.timer`
- `pw155-map-control.path`
- `pw155-map-status.timer`
- `pw155-db-backup.timer`

Daemon game: `logservice`, `authd`, `uniquenamed`, `gamedbd`, `gacd`,
`gfactiond`, `gdeliveryd`, `glinkd`, `gs01`, dan `is61`.

## Catatan keamanan

- MariaDB hanya listen pada loopback guest.
- Daemon internal hanya listen pada loopback; hanya `glinkd:29000` yang bind ke
  interface guest.
- Password database dibuat acak dan disimpan mode `0600` di guest.
- Port host memakai `127.0.0.1`, sehingga tidak langsung terbuka ke LAN.
