# Pocket Browser AI — Android MVP

Browser Flutter satu tab + agent foreground pada **WebView yang sama** tempat Anda login. Source implementasi, fixture lokal, pengujian mock, dan workflow APK tersedia. Tidak memerlukan backend.

## Status jujur

- Host pengembangan: Termux Android ARM64; Dart 3.12.2 tersedia. Flutter binary, Java, Gradle dan Android SDK tidak tersedia.
- Build desktop Android resmi bukan toolchain native Termux. Tidak dilakukan instalasi binary Linux acak atau percobaan build berulang.
- Pemeriksaan yang benar-benar dijalankan dicatat di [`docs/VALIDATION.md`](docs/VALIDATION.md).
- **Belum ada APK hasil build atau pengujian Android WebView nyata.** Source sudah di-push dengan izin pengguna ke repo private `anzmage/pocket-browser-ai`. Dua dispatch build dan satu dispatch diagnostik runner gagal `startup_failure` sebelum job berjalan; tidak ada log kompilasi/artifact. Lihat `docs/VALIDATION.md` untuk bukti. Penyebab spesifik perlu diperiksa dari pesan error pada halaman Actions GitHub; jangan mengasumsikan build berhasil atau billing pasti penyebabnya.

## Build dari HP (GitHub Actions)

Repository proyek ini sudah tersedia di https://github.com/anzmage/pocket-browser-ai (private). Tidak perlu membuatnya ulang. Workflow ada di `.github/workflows/android.yml`; `runner-check.yml` adalah diagnostik satu perintah tanpa setup/dependency untuk memastikan runner dapat mulai.

Langkah berikut untuk menyiapkan salinan di repository lain: seluruh isi direktori ini harus menjadi **root repository**, bukan direktori `browserx` di atasnya.

1. Buat repository GitHub pribadi kosong melalui browser HP, tanpa README tambahan. Tidak perlu memasukkan API key atau GitHub Actions secret AI.
2. Dari Termux, ganti `OWNER/REPO` dengan repository milik Anda. Perintah berikut adalah contoh **opsional untuk repository baru**; jangan menimpa remote proyek yang sudah ada:

   ```bash
   cd ~/browserx/pocket_browser_ai
   git init -b main
   git add .
   git status --short
   git commit -m "Implement Pocket Browser AI MVP"
   git remote add origin git@github.com:OWNER/REPO.git
   git push -u origin main
   ```

   Gunakan autentikasi GitHub SSH yang Anda miliki, atau URL HTTPS dengan credential manager/`gh auth login`. Jangan menaruh access token dalam remote URL atau source. Jangan commit `.checks`, `.dart_tool`, `.env`, atau `node_modules` (sudah di-ignore).
3. Di GitHub mobile browser: **Actions → Android debug APK**. Push ke `main` memicu workflow; untuk menjalankan lagi pilih **Run workflow**. Jika Actions belum aktif, aktifkan dahulu. Artifact hanya muncul bila analyze, test, dan build semuanya lolos.
4. Buka run yang hijau → **Artifacts → pocket-browser-ai-debug**. Unduh ZIP, ekstrak `pocket-browser-ai-debug.apk`, lalu install melalui file manager. Izinkan instalasi dari sumber tersebut bila Android meminta. Android minimum **7.0 / API 24**; gunakan Android System WebView yang diperbarui.
5. Artifact berakhir setelah 14 hari. Simpan APK di HP. `SHA256SUMS` tersedia. Debug key runner bersifat sementara: build berikutnya bisa ditolak sebagai update jika signing key berbeda. Untuk MVP, uninstall/reinstall akan menghapus sesi/key; ekspor key ke password manager Anda sebelum uninstall. Jangan berharap migrasi sesi browser.

GitHub CLI sudah dipasang di HP ini. Bila belum login, jalankan sendiri `gh auth login --hostname github.com --git-protocol https --web` dan ikuti login browser. Jangan kirim token/login code ke percakapan. Upload source tetap memerlukan persetujuan Anda.

Jika memakai GitHub CLI di HP yang sudah terautentikasi:

```bash
gh run list --workflow android.yml
gh run watch
gh run download --name pocket-browser-ai-debug --dir ~/downloads/pocket-apk
```

Workflow dipin ke **Flutter 3.35.7 / Java 17 / Ubuntu 24.04**, Gradle 8.12 (checksum), AGP 8.9.1, Kotlin 2.1.0. Dependency aplikasi dan lockfile ikut disertakan. Gradle wrapper berasal dari repository resmi Gradle. Android SDK/NDK yang dibutuhkan diunduh tool Flutter/Gradle pada runner. Tidak ada key AI di workflow atau APK.

### Build pada host Linux yang kompatibel (bukan Termux native)

```bash
flutter --version  # gunakan 3.35.7
flutter pub get --enforce-lockfile
flutter analyze --fatal-infos
flutter test
npm ci --ignore-scripts
npm test
flutter build apk --debug --target-platform android-arm64,android-arm
```

Jangan menganggap `flutter` Linux ARM64 dapat dijalankan langsung di Android/Bionic. Source Flutter yang dipakai untuk analisis lokal bukan instalasi engine/build yang berfungsi.

## Konfigurasi provider

Di ikon roda gigi:

- **Base URL**: default `https://api.deepseek.com`. Bisa diganti, misalnya `https://api.openai.com/v1`, atau endpoint penuh `https://provider.example/custom/chat/completions`. Jika belum diakhiri `/chat/completions`, suffix ditambahkan.
- **API key**: masukkan dari UI, bukan source. Seluruh konfigurasi disimpan lewat `flutter_secure_storage`, Android Keystore + encrypted shared preferences. Android backup aplikasi dinonaktifkan. Key tidak dicatat ke log/riwayat.
- **Model ID**: default `deepseek-v4-pro`, dipilih untuk memprioritaskan kemampuan agent dibanding biaya/kecepatan. Ini pilihan di antara model DeepSeek, bukan klaim model paling andal secara universal. Model/endpoint tetap dapat diganti. Konfigurasi tersimpan yang sudah ada tidak ditimpa; ubah melalui UI bila perlu. Key tetap kosong sampai Anda mengisinya sendiri; gunakan key baru bila key lama pernah dibagikan di chat.
- **Batas langkah**: 15 default, dapat diubah 1–50.
- **Test connection**: mengirim Chat Completions kecil, tanpa halaman. Bisa dikenakan biaya provider. Verifikasi ini hanya membuktikan respons teks, bukan kepatuhan model pada JSON/agent.
- **Simpan** setelah mengubah konfigurasi. Key kosong tidak valid.

Adapter mengirim `model`, `messages`, `stream:false` dan membaca `choices[0].message.content`. Tidak mengirim `tools`, `response_format`, parameter vendor khusus, atau mengasumsikan structured output. Model harus dapat mengikuti instruksi satu JSON action. Respons Markdown, aksi tak dikenal, field tambahan, tipe salah dan snapshot usang ditolak. Provider dengan protokol non-Chat-Completions tidak didukung. Endpoint AI **wajib HTTPS**, tanpa query/userinfo; redirect ditolak agar key tidak diteruskan ke host lain. TLS tidak pernah di-bypass. Error body provider tidak ditampilkan karena dapat memuat data sensitif.

## Cara pakai

1. Buka alamat HTTP/HTTPS melalui address bar. Tanpa skema akan memakai HTTPS. HTTP didukung untuk website, **bukan endpoint AI**; koneksinya tidak terenkripsi.
2. Login **manual** di WebView. Cookie/session milik aplikasi ini, bukan Chrome. Tidak mengambil cookie Chrome, tidak menghapus cookie saat startup, tidak menyalin cookie ke provider. Persistensi mengikuti kebijakan website dan Android WebView. Cookie sesi tidak dijanjikan bertahan setelah proses dimatikan.
3. Buka panel chat, isi tujuan singkat tanpa password/OTP/key, lalu **Run**. Konteks halaman terpilih akan dikirim ke provider Anda.
4. Periksa riwayat langkah. Aksi dijalankan satu per iterasi. Snapshot baru diambil sebelum request dan setelah aksi; perubahan halaman bukan otomatis bukti tugas berhasil.
5. Untuk keamanan MVP, **semua click/type/select/navigate/back meminta konfirmasi satu-per-aksi**. Bahkan input/select bisa menyebabkan autosave. Ini sengaja lebih konservatif daripada menebak label tombol mana yang berbahaya. Periksa transaksi, penghapusan, penerima pesan dan perubahan penting sebelum menyetujui. Tolak jika ragu.
6. **Stop** membatalkan request HTTP dan mencegah aksi lanjutan. Aksi/click atau request website yang sudah terkirim tidak dapat dibatalkan atau di-rollback. **Take over** melakukan Stop dan mengembalikan kendali manual. Ketuk Run sesudah selesai manual untuk memulai loop baru dari snapshot baru; tidak melanjutkan antrean lama.
7. Saat agent aktif, sentuhan halaman diblokir agar tidak berlomba dengan agent. Tombol Stop/Take over tetap tersedia walaupun panel chat ditutup. Tutup/buka panel tidak membuat ulang controller WebView. Tombol Back Android: hentikan agent dahulu, lalu tutup chat, lalu history WebView, lalu konfirmasi keluar.
8. `ask_user` menghentikan loop. Lakukan langkah manual atau ubah instruksi dengan tujuan + jawaban yang diperlukan, lalu Run lagi. Riwayat bukan percakapan tak terbatas; tujuan dan delapan hasil langkah terakhir digunakan dalam satu run.
9. Aplikasi tidak aktif/foreground → agent berhenti. Tidak ada background service.

## Uji cepat fixture di HP

Ikon lab membuka fixture bawaan tanpa akun sungguhan. Jika form berada di bawah layar, scroll manual terlebih dahulu atau minta agent scroll. Hanya elemen pada viewport yang diobservasi.

1. Buka fixture → chat → instruksi: **“Isi Nama tampilan dengan Pocket, pilih Warna biru, klik Tampilkan hasil, lalu periksa hasil. Jangan isi Password atau OTP.”**
2. Run → izinkan masing-masing pengisian/pilihan/click. Jika perlu, izinkan scroll biasa (scroll tidak membutuhkan dialog).
3. Verifikasi langsung teks **`Hasil: Pocket / biru`** dan counter **Input/change** bertambah. Model menerima penanda `[field]` untuk nilai form yang terpantul di teks, bukan nilai mentah. Karena itu verifikasi visual Anda tetap penting.
4. Coba instruksi scroll/tunggu berulang → **Stop** di tengah request/langkah → pastikan tidak ada aksi baru. Lalu **Take over**, tutup chat, ubah input atau tekan tombol manual.
5. Run lagi: harus menggunakan snapshot baru. Coba tombol nonaktif, Password/OTP, dan link skema eksternal: agent harus menolak/berhenti; isi sensitif hanya manual. Reload fixture untuk mereset demo.

Tombol “Simpan perubahan demo” hanya mengubah teks lokal, tetapi tetap memerlukan konfirmasi. Tidak ada transaksi sungguhan pada fixture.

## Arsitektur

- `lib/browser/browser_controller.dart`: satu WebView, navigasi, history/loading, kebijakan skema.
- `assets/observer.js` + `page_observer.dart`: fixed JS, DOM viewport, maksimal 6.000 karakter teks / 70 elemen / label 180 karakter / 60 opsi, snapshot ID dan fingerprint.
- `action_executor.dart`: validasi snapshot/elemen + JS tetap dengan `jsonEncode` parameter, native HTTP/HTTPS/back/wait. Tidak ada `execute_javascript` dari model.
- `lib/ai/openai_provider.dart`: request HTTPS, timeout, abort, respons terbatas 256 KiB, tanpa log body/key.
- `lib/core/agent_loop.dart`: observe → AI → validate → konfirmasi → execute → settle → observe; 45 detik batas request/observe, 12 detik batas execute/settle, 5 menit dialog konfirmasi, wait maksimum 5 detik, maksimal 2 retry AI. Aksi yang mungkin sudah mengubah data **tidak diulang otomatis** saat gagal/timeout. Tiga iterasi tanpa perubahan menghentikan loop.
- `lib/core/models.dart`: parsing JSON ketat, allowlist aksi, URL dan redaksi tambahan.
- `lib/settings/`, `lib/ui/`: secure settings, browser, panel instruksi/riwayat.
- `tool/core_checks.dart`, `test/core_test.dart`: provider/page mock tanpa biaya API. Pemeriksaan yang sama bisa dijalankan `bash tool/check_core.sh` di Termux dari checkout bersih tanpa Flutter (hanya butuh Dart).
- `tool/observer.test.cjs`: DOM fixture melalui jsdom. Layout disimulasikan; bukan pengganti WebView/emulator nyata.

Snapshot diikat ke ID, URL lengkap internal, revision MutationObserver/input/change, referensi objek DOM dan signature elemen. Snapshot dikonsumsi satu kali. Perubahan halaman/elemen selama request atau dialog konfirmasi menyebabkan **fail closed**; Run lagi untuk mengamati ulang. Tidak otomatis mengklik elemen lain dengan ID yang mirip. Tidak ada jaminan atomisitas terhadap semua event asynchronous atau halaman berbahaya.

## Privasi, keamanan, dan batasan

- Teks website adalah data tidak tepercaya, bukan instruksi system. Policy ini ada di prompt, tetapi prompt injection tidak dapat dijamin hilang; allowlist, validasi dan persetujuan manusia tetap diperlukan.
- Tidak membaca cookie, storage website, token dari hidden DOM, atau nilai password untuk dikirim ke model. Seluruh nilai form hanya dipakai **secara lokal** untuk menghapus nilai yang terpantul di teks; tidak ada field `value` dalam snapshot. Input password/hidden/file, OTP/payment/token/login yang terdeteksi ditandai manual. Hidden fields tidak dimasukkan.
- Query/fragment/userinfo URL tidak dikirim. Teks berbentuk bearer/key/token diredaksi. **Bukan DLP sempurna**: halaman dapat menampilkan data pribadi atau rahasia tanpa penanda yang dikenali, termasuk token pendek di path. Jangan menjalankan agent pada halaman yang tidak boleh dibagikan ke provider. Konteks halaman tidak dikirim sebelum Run; test koneksi tidak mengirim snapshot.
- Field password/OTP/CAPTCHA/login harus manual, bukan dipecahkan atau dilewati AI. Identifikasi field sensitif bersifat heuristik; persetujuan setiap aksi adalah lapisan tambahan, bukan pengganti kewaspadaan.
- Tidak mengekspos native JavaScript channel/bridge dengan akses filesystem, shell, cookie, atau secret. JS observer berada di realm halaman yang sama: website masih dapat mengubah/menipu DOM; bukan security sandbox untuk situs berbahaya.
- Tidak mengabaikan SSL error dan tidak bypass CAPTCHA, rate limit, atau proteksi website. `intent:`, `mailto:`, `tel:`, `javascript:`, arbitrary `file:` dan skema lain diblokir eksplisit, tidak diluncurkan otomatis. Asset fixture bawaan adalah satu-satunya pengecualian file lokal.
- Banyak OAuth, termasuk sebagian login Google, **melarang embedded WebView**. Tidak ada janji login Google/semua website bekerja. Popup/new-window, file upload/download khusus, permission kamera/lokasi, cross-origin iframe, shadow DOM tertutup, rich-text/contenteditable dan situs yang memerlukan trusted user gestures belum didukung. Tidak ada fingerprint spoofing untuk melewati larangan.
- Native value setter + input/change events membantu form modern, tetapi tidak menjamin kompatibilitas semua framework. Verifikasi hasil website secara visual.
- Snapshot hanya viewport dan konteks terbatas. Animasi/perubahan DOM terus-menerus bisa menyebabkan penolakan snapshot usang. Loading berkepanjangan dihentikan oleh timeout; Take over bila perlu.
- Riwayat dan tujuan hanya di memori, tidak disimpan ke disk; tampilan aksi tidak mencatat isi input. Data ringkas tetap dikirim ke provider yang Anda pilih; biaya, retensi dan pemrosesan mengikuti kebijakan provider.

## Referensi resmi

Versi/API diperiksa dari metadata dan source resmi package, source Flutter 3.35.7, template Android dan Gradle. Lihat [`docs/DEPENDENCIES.md`](docs/DEPENDENCIES.md). Tidak ada aplikasi/server lain yang diubah. Hanya repository private proyek ini yang dibuat dan di-push setelah pengguna mengotorisasi proses build.
