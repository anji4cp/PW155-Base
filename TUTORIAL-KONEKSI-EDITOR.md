# Tutorial Menghubungkan Universal Data Studio ke PWKU Server

Tutorial ini khusus **Universal Data Studio / Universal Data Editor** di folder
`Rodys_Angelica_Editor_SRC_V22`, bukan PW Data Studio. Editor mengirim file
melalui `PSCP` dan membuka console menggunakan `PuTTY`; tidak ada koneksi langsung
ke MariaDB.

> Nyalakan VM `PWKU-Server` hanya ketika akan menjalankan penyiapan, menguji
> koneksi, atau mengirim perubahan dari editor.

## Pengaturan koneksi

| Kolom editor | Nilai PWKU |
|---|---|
| Server | `127.0.0.1` |
| Port | `2223` |
| Login | `pwadmin` |
| Password | Password Ubuntu milik `pwadmin` |
| Config | `/srv/pw155/staging/pw155/gamed/config/` |

Alamat `127.0.0.1` hanya berlaku pada komputer Windows yang menjalankan VM.

## Cara cepat: penyiapan sekali klik

### Langsung dari pengaturan UDE (disarankan)

1. Buka `Settings > Server` di UDE.
2. Isi alamat IP server, port SSH, dan login sesuai server yang sedang disiapkan.
3. Klik `Install / Update Server Helper...`.
4. Terima fingerprint SSH jika diminta, lalu masukkan password SSH dan password
   `sudo` secara interaktif.
5. Tunggu tulisan `SERVER HELPER BERHASIL DIPASANG / DIPERBARUI`.
6. Simpan pengaturan, kemudian jalankan `Health Check`.

Tombol ini aman dijalankan ulang untuk memperbarui helper pada server lama maupun
menyiapkan server baru. Password tidak disimpan atau dimasukkan ke command line.

### Menggunakan installer terpisah

1. Nyalakan `PWKU-Server` dari VirtualBox dan tunggu sekitar 2–3 menit.
2. Klik dua kali `SETUP-UNIVERSAL-EDITOR.cmd` di folder `PWKU-Installer`.
3. Masukkan password Ubuntu ketika diminta oleh SSH dan `sudo`.
4. Tunggu tulisan `SETUP UNIVERSAL DATA STUDIO SELESAI`.

Skrip menyalin PuTTY/PSCP/Plink yang terpasang di Windows ke folder editor,
memasang helper deployment dengan allowlist file, serta memasang kontrol service
terbatas. Password tidak disimpan.

## Membuka editor

Jalankan:

`Universal data Editor.exe` dari folder editor UDE yang sudah Anda pasang.

Jika belum ada, build `Universal-data-Editor.csproj` dalam konfigurasi **Release**
dengan target **.NET Framework 4.8**.

## Mengisi menu Server

1. Klik panah pada tombol **Server** di toolbar kanan atas.
2. Pilih **Settings**, lalu buka tab **Server**.
3. Pada **Interaction with the server via SSH**, isi:

   - Server: `127.0.0.1`
   - Login: `pwadmin`
   - Port: `2223`
   - Password: password Ubuntu milik `pwadmin`

4. Pada **Paths**, isi Config:

   `/srv/pw155/staging/pw155/gamed/config/`

5. Klik tombol kecil di samping Config untuk mengisi path bawaan, lalu cocokkan:

| File | Path di server |
|---|---|
| elements.data | `/srv/pw155/staging/pw155/gamed/config/elements.data` |
| tasks.data | `/srv/pw155/staging/pw155/gamed/config/tasks.data` |
| gshopsev.data | `/srv/pw155/staging/pw155/gamed/config/gshopsev.data` |
| gshopsev1.data | `/srv/pw155/staging/pw155/gamed/config/gshopsev1.data` |
| gshopsev2.data | `/srv/pw155/staging/pw155/gamed/config/gshopsev2.data` |
| gshopsev3.data | Kosongkan; file tidak ada pada server PWKU |
| aipolicy.data | `/srv/pw155/staging/pw155/gamed/config/aipolicy.data` |
| npcgen.data (world) | `/srv/pw155/staging/pw155/gamed/config/world/npcgen.data` |
| npcgen.data (Celestial Vale) | `/srv/pw155/staging/pw155/gamed/config/a61/npcgen.data` |
| domain.sev | `/srv/pw155/staging/pw155/gdeliveryd/domain.sev` |
| domain2.sev | `/srv/pw155/staging/pw155/gdeliveryd/domain2.sev` |
| extra_drops.sev | `/srv/pw155/staging/pw155/gamed/config/extra_drops.sev` |

Editor hanya memiliki satu kolom `npcgen.data`. Gunakan path `world` untuk map
utama; ubah sementara ke `a61` ketika mengedit Celestial Vale.

6. Hilangkan centang **Use compression (7z) when sending files**. Versi baru
   memakai staging dan SHA-256 sendiri.
7. Isi **Restart GS command**:

   `sudo /srv/pw155/tools/pw155-ude-deploy restart`

8. Isi **Custom command**:

   `sudo /srv/pw155/tools/pw155-ude-deploy status`

9. Untuk **Action when clicking Server**, pilih **Open console (Putty)** pada
   pengujian pertama, lalu simpan pengaturan.

## Menguji koneksi

1. Buka menu **Server > Open console (Putty)**.
2. Pada koneksi pertama, setujui fingerprint hanya jika targetnya VM
   `PWKU-Server` pada `127.0.0.1:2223`.
3. Setelah prompt Ubuntu muncul, jalankan:

   ```bash
   sudo /srv/pw155/tools/pw155-ude-deploy status
   ```

4. Ketik `exit` untuk menutup console.

## Mengirim perubahan dengan aman

Versi baru menjalankan staging, checksum, backup, apply atomik, restart, dan
health check. Jika health check gagal, backup dipulihkan otomatis.

1. Buat backup VM atau file server.
2. Logout semua karakter dan tutup client.
3. Simpan hasil edit secara lokal.
4. Dari menu **Server**, pilih hanya file yang sesuai, misalnya **Safe deploy
   elements.data**, **Safe deploy tasks.data**, atau **Safe deploy
   gshopsev.data**.
5. Periksa target di dialog **Safe Deployment**, lalu klik **Backup & Deploy**.
6. Tunggu health check selesai; jangan menutup editor saat proses berjalan.
7. Buka **Server > Deployment History & Rollback** untuk melihat backup atau
   mengembalikan deployment lama.
8. Uji di dalam game. Pasang juga output
   client yang berpasangan bila jenis perubahan memerlukannya.

## Keamanan dan troubleshooting

- Jangan gunakan user `root` dan jangan membuka MariaDB port `3306`.
- Editor menyimpan password terenkripsi. Saat deploy, restart, rollback, atau
  health check memakai Plink/PSCP, password ditulis sementara ke file lokal acak
  dan segera dihapus setelah proses selesai. Console PuTTY tidak menerima
  password lewat command line; ketik password ketika PuTTY memintanya.
- Jika PuTTY tidak terbuka, pastikan `ssh\putty.exe`, `ssh\pscp.exe`, dan
  `ssh\plink.exe` berada
  di sebelah aplikasi; jalankan setup sekali klik lagi.
- Jika `Connection refused`, jalankan `Test-NetConnection 127.0.0.1 -Port 2223`
  dan periksa port forwarding VirtualBox ke guest port `22`.
- Jika `Permission denied`, jalankan kembali setup. Login SSH baru mungkin
  diperlukan setelah grup `pweditor` pertama kali ditambahkan.
- Jika NPC tidak berubah, periksa apakah path seharusnya `world` atau `a61`.
