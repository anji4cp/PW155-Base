# Paket Instalasi PWKU Server 1.5.5

Folder ini berisi bahan untuk memasang server Perfect World 1.5.5 pada VM
Ubuntu. Panduan VirtualBox tersedia di bawah; konfigurasi Proxmox yang sedang
dipakai juga dirangkum di sini.

**Repo GitHub publik hanya berisi skrip dan dokumentasi.** ISO Ubuntu,
arsip server/client/web, cache paket, skema game, library pihak ketiga,
salinan client, dan backup tetap di folder lokal; semuanya sengaja tidak
diunggah. Clone GitHub saja belum merupakan paket instalasi lengkap.

Mulai dari [TUTORIAL-INSTALL-UBUNTU.md](TUTORIAL-INSTALL-UBUNTU.md).
Daftar teknis lengkap tersedia di [DAFTAR-KEBUTUHAN.md](DAFTAR-KEBUTUHAN.md).
Setelah server terpasang, ikuti
[TUTORIAL-KONEKSI-EDITOR.md](TUTORIAL-KONEKSI-EDITOR.md) untuk menghubungkan
Universal Data Studio melalui SSH. `SETUP-UNIVERSAL-EDITOR.cmd` menyiapkan
PuTTY/PSCP dan izin file server yang terbatas.

## Cara paling singkat

1. Pasang Ubuntu Server 20.04.6 di VirtualBox atau Proxmox dan aktifkan OpenSSH.
2. Untuk VirtualBox NAT, buat port forwarding sesuai tutorial. Untuk Proxmox
   bridge, catat IP VM yang dapat dijangkau dari Windows.
3. Klik dua kali `VERIFY-PACKAGE.cmd` untuk memeriksa keutuhan bahan.
4. Setelah Ubuntu selesai boot, klik dua kali `INSTALL-PW-SERVER.cmd`.
5. Masukkan alamat dan port SSH VM. Nilai bawaan `127.0.0.1:2223` hanya untuk
   VirtualBox NAT; pada Proxmox bridge gunakan IP VM dan port `22`.
6. Ketik password Ubuntu ketika diminta.
7. Tunggu sampai tulisan `INSTALASI PW 1.5.5 SELESAI` muncul.

Instalasi pertama biasanya memerlukan 15–40 menit, tergantung internet dan
kecepatan disk. Boot server berikutnya memerlukan sekitar 2–3 menit untuk memuat
daemon dan dua map.

## Hasil instalasi

- VirtualBox NAT sesuai tutorial: panel <http://127.0.0.1:8081>, gateway
  `127.0.0.1:29001`, SSH `127.0.0.1:2223`.
- Proxmox bridge: panel `http://IP-VM:8080`, gateway `IP-VM:29000`, dan SSH
  `IP-VM:22`. Contoh VM uji saat ini memakai `192.168.30.10`.
- Admin awal: `admin`
- Password admin awal: dibuat acak pada instalasi baru dan ditampilkan di
  akhir output installer. Catat sebelum menutup terminal.

Ganti password admin setelah login pertama. Database memakai password acak yang
hanya disimpan di guest Ubuntu dengan izin file terbatas.

## Isi penting

- `ubuntu-20.04.6-live-server-amd64.iso`: installer OS.
- `Perfect_World_Server_1.5.5.tar.gz`: binary dan data server.
- `web.tar.gz`: panel pemain/admin.
- `client-data.tar.gz`: data editor client.
- `ubuntu-debs-20.04.tar.gz`: cache 209 paket `.deb` dari instalasi yang diuji.
- `support/`: library kompatibilitas, skema SQL, unit systemd, dan alat operasi.
- `install-pw155.sh`: installer utama di Ubuntu.
- `INSTALL-PW-SERVER.cmd`: pengirim dan pemicu instalasi dari Windows.
- `images/`: tangkapan layar asli instalasi Ubuntu.
- `SHA256SUMS.txt`: checksum bahan utama.

Jika memakai clone GitHub, salin sendiri bahan yang sah ke nama/path di atas,
termasuk `support/db.sql` dan `support/libtask.so`, lalu jalankan
`VERIFY-PACKAGE.cmd`. Pemeriksaan checksum memang akan gagal selama bahan
tersebut belum lengkap atau tidak cocok dengan paket lokal yang diuji.

Cache `.deb` mengurangi unduhan ulang dan menjadi cadangan bila mirror lambat.
Koneksi internet tetap dianjurkan agar indeks dan pembaruan keamanan terbaru
dapat diambil.

Admin Panel menyediakan **Backup & download database**. Administrator dapat
membuat backup manual tanpa mematikan game, menyimpannya di VM/VPS, dan
mengunduh arsip yang sama ke laptop atau PC. Backup server dipertahankan selama
14 hari.

Admin Panel juga menyediakan **Rate & Item** untuk mengubah multiplier EXP,
mengaktifkan gold monster x2, dan mengirim **material biasa** berdasarkan ID
ke mailbox karakter. Hanya `MATERIAL_ESSENCE` dengan `proc_type=0` dari
`elements.data` baseline yang diizinkan; weapon/equipment dan kategori lain
ditolak. Status `mail-accepted` berarti surat diterima server, belum berarti
lampirannya sudah diambil. Periksa mailbox dan tas karakter setelah mengirim.

## Konfigurasi Proxmox yang diuji

VM 100 memakai Ubuntu Server 20.04.6, BIOS SeaBIOS, machine `i440fx`, SCSI
VirtIO, disk 100 GiB di `local-lvm`, 6 core, RAM 8 GiB, dan NIC VirtIO pada
bridge `vmbr0`. Sesuaikan sumber daya dengan host Anda; konfigurasi ini bukan
persyaratan minimum. Sebelum eksperimen data game, buat snapshot VM dan
pastikan ruang thin pool Proxmox cukup.

## Perintah sesudah instalasi

```bash
sudo /srv/pw155/tools/pw155-service.sh status
sudo /srv/pw155/tools/pw155-service.sh restart
sudo /srv/pw155/tools/pw155-service.sh stop
sudo bash /home/pwadmin/support/verify-install.sh
```
