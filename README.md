# 🍎 Clean Mac

> macOS sistem temizleme aracı — basit, güvenli, etkili.

[![ShellCheck](https://img.shields.io/badge/ShellCheck-passing-brightgreen)](https://www.shellcheck.net/)
[![macOS](https://img.shields.io/badge/macOS-Ventura%20%7C%20Sonoma%20%7C%20Sequoia-blue)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

macOS'ta cache, log, geçici dosya, uygulama kalıntıları ve çöp kutusu gibi gereksiz verileri güvenle temizler. **İnteraktif terminal arayüzü** ve **modern web dashboard** ile kullanılabilir.

---

## ✨ Özellikler

- 🔍 Önce tarar, onayınızı bekler — sürpriz yok
- 📊 7 kategori ile esnek temizlik
- 🌐 Modern web dashboard (tek komutla başlat)
- 🛡️ Kritik sistem dosyalarına dokunmaz
- 🍎 Bash 3.2+ uyumlu (tüm macOS sürümleri)

---

## 🚀 Kurulum

```bash
git clone https://github.com/<username>/apple-cleanup.git
cd apple-cleanup
chmod +x clean_mac.sh
```

---

## 📖 Kullanım

### Terminal Arayüzü

```bash
# İnteraktif temizleme (önce tarar, sonra sorar)
bash clean_mac.sh

# Yardım
bash clean_mac.sh --help
```

### Web Dashboard

```bash
python3 web/server.py
# Tarayıcıda http://localhost:8080 adresini açın
```

---

## 📦 Kategoriler

| # | Kategori | Hedef | Not |
|---|---------|-------|-----|
| 1 | 📦 Kullanıcı Cache | `~/Library/Caches/*` | |
| 2 | 🖥️ Sistem Cache | `/Library/Caches/*` | sudo gerekir |
| 3 | 📂 Uygulama Kalıntıları | `~/Library/Application Support/` + `Preferences/` | İnteraktif seçim |
| 4 | 📋 Loglar | `~/Library/Logs/*` + `/Library/Logs/*` | |
| 5 | 🗃️ Geçici Dosyalar | `$TMPDIR` + user var/folders | |
| 6 | 🛠️ Geliştirici | Xcode DerivedData + kırık symlink'ler | İnteraktif seçim |
| 7 | 🗑️ Çöp Kutusu | `~/.Trash/*` | |

---

## 🏗️ Proje Yapısı

```
apple-cleanup/
├── clean_mac.sh        # Ana temizleme scripti
├── web/
│   ├── server.py       # Python web sunucusu
│   ├── index.html      # Dashboard arayüzü
│   ├── style.css       # Stiller
│   └── script.js       # Frontend mantığı
├── README.md
├── LICENSE
└── .gitignore
```

---

## 🔧 Web API

Web dashboard, `clean_mac.sh`'i JSON modunda çalıştırır:

```bash
# Tarama sonuçları
bash clean_mac.sh --scan-json

# Belirli kategorileri temizle
bash clean_mac.sh --clean-json 1,4,7

# Sistem durumu
bash clean_mac.sh --status-json
```

---

## ⚠️ Güvenlik Notları

- Script sadece cache, log ve geçici dosyaları siler
- macOS bu dosyaları gerektiğinde otomatik yeniden oluşturur
- `Downloads` klasörüne dokunulmaz
- Sistem Cache için `sudo` yetkisi gerekir (terminal modunda)
- Web dashboard üzerinden sudo gerektiren kategoriler atlanır

---

## 📄 Lisans

MIT License — detaylar için [LICENSE](LICENSE) dosyasına bakın.
