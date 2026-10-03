# MenuBarHub 🟣

**MenuBarHub** adalah aplikasi menubar native macOS (Swift + WebKit) yang dirancang khusus untuk menyatukan aplikasi perpesanan dan media sosial dalam satu tempat dengan **efisiensi RAM maksimal** (sangat optimal untuk MacBook Air M1 8GB).

---

## 🚀 Mengapa MenuBarHub Dibuat?

Di mesin Mac dengan RAM 8GB (Unified Memory), membuka aplikasi berbasis Electron (seperti Franz, Ferdium, Rambox) atau membuka 7 tab media sosial sekaligus di browser biasa dapat menghabiskan **2,5 GB hingga 4 GB RAM**, yang menyebabkan *swap memory* membengkak dan menurunkan performa laptop.

**MenuBarHub menyelesaikan masalah ini dengan 5 pilar utama:**
1. **Ukuran Super Ringan (Biner Native ~160 KB)**: Dibangun murni dengan Swift dan WebKit bawaan sistem operasi macOS tanpa dependensi Chromium/Electron.
2. **Grace Period 1 Menit & Auto-Purge**: Tab media sosial yang tidak disentuh selama 1 menit otomatis dimatikan dari RAM (0 MB).
3. **Multi-Account Terisolasi (Isolated WKWebsiteDataStore)**: Login multi-akun tanpa risiko tertukar atau logout otomatis.
4. **Hybrid Routing**: Obrolan akun utama (Primary) langsung terhubung ke aplikasi native resmi untuk performa tercepat, sementara akun sekunder berjalan di dalam WebKit terisolasi.
5. **Built-in Media Tools**: Dilengkapi *Smart Auto-Scroll* dan *1-Click Video Downloader* dengan pilihan kualitas langsung ke folder `~/Downloads`.

---

## ✨ Fitur Unggulan

### 💬 1. Layanan yang Didukung
- **WhatsApp** (Native Routing / Isolated WebKit)
- **Telegram** (Engine WebK Ultra-Ringan / Native Routing)
- **Instagram** (Feed & Reels dengan Auto-Scroll & Downloader)
- **TikTok** (Feed Video dengan Auto-Scroll Otomatis & Downloader)
- **Facebook** (Feed & Video Downloader)
- **X (Twitter)** (Feed & Media Downloader)
- **Threads** (Feed & Video Downloader)

### 👥 2. Multi-Account Terisolasi (*Profile Pattern*)
Tersedia 4 ruang kerja profil mandiri:
- `Home` (Akun Utama)
- `Work` (Akun Pekerjaan)
- `Project X` (Akun Khusus Proyek)
- `Archive` (Akun Cadangan)

Setiap profil memiliki sesi login dan *cookies* mandiri sehingga tidak akan saling menimpa.

### 📥 3. 1-Click Video Downloader (Pilihan Kualitas)
- Tombol unduh video (`arrow.down.to.line.circle.fill`) muncul otomatis saat membuka tab media sosial (TikTok, Instagram, Facebook, Threads, X).
- Menyediakan menu pilihan kualitas:
  - 🌟 **High Quality (Original HD / Best)**
  - 📱 **Standard Quality (720p / Fast)**
  - 🎵 **Audio Track Only (M4A / MP3)**
  - 📂 **Buka Folder Downloads**
- Mengunduh langsung melalui `URLSession` native ke folder `~/Downloads/` lengkap dengan spanduk notifikasi macOS.

### 🎬 4. Smart Auto-Scroll untuk TikTok & Instagram Reels
- Dilengkapi pendeteksi durasi tayangan cerdas (*Loop & End Detector*).
- Begitu tayangan video TikTok atau Reel selesai, halaman otomatis berpindah (*scroll*) ke video berikutnya tanpa perlu disentuh manual.
- Tombol saklar Auto-Scroll (`arrow.down.circle.fill`) berwarna hijau aktif di bilah navigasi.

### 📌 5. Jendela Fleksibel (Resizable, Draggable & Pin)
- **Pin Mode**: Klik tombol Pin (`📌`) agar jendela tetap melayang di atas aplikasi lain (*Stay on Top*).
- **Draggable Header**: Saat dalam mode Pin, seret area bilah atas untuk memindahkan posisi jendela ke mana saja di layar.
- **Dual Grip Resize**: Tarik sudut kiri bawah atau kanan bawah untuk mengatur ukuran jendela secara bebas.
- **Zoom In / Out**: Atur persentase skala tampilan tiap layanan (50% hingga 250%).

### 🖱️ 6. Menu Klik Kanan Cepat (*Context Menu*)
Klik kanan pada ikon menubar untuk akses instan ke:
- Buka / Tutup Jendela
- Ganti Profil & Ganti Layanan Cepat
- Toggle Pin Mode
- Reset Ukuran Jendela Standar
- Pembersihan RAM Manual (*Free Inactive Memory*)
- Keluar Aplikasi (`Quit`)

---

## 🛠️ Cara Kompilasi & Menjalankan

### Persyaratan Sistem:
- macOS 12.0 (Monterey) atau yang lebih baru.
- Arsitektur Apple Silicon (M1/M2/M3/M4) atau Intel Mac.

### Kompilasi dari Kode Sumber:
```bash
git clone https://github.com/tog-got/menubar-hub.git
cd menubar-hub
./build.sh
```

### Memindahkan ke Folder Applications:
```bash
cp -r MenuBarHub.app /Applications/
open /Applications/MenuBarHub.app
```

---

## 📜 Lisensi
Open Source di bawah lisensi MIT. Bebas digunakan, dimodifikasi, dan didistribusikan.
