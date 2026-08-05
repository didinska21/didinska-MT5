# GoldHedgeRecovery EA

Expert Advisor untuk **MetaTrader 5 (MQL5)**, khusus simbol **XAUUSD**, dengan konsep:

> Initial Entry → Hedge Recovery (lawan arah, lot membesar) → Individual TP per posisi → Basket TP (tutup semua sekaligus)

Dirancang untuk akun **Hedging** (bukan Netting) — memungkinkan posisi BUY dan SELL aktif bersamaan di simbol yang sama.

---

## ⚠️ Peringatan Risiko

EA ini menggunakan metode **hedge recovery / martingale-style** (lot membesar tiap layer saat market melawan posisi). Ini **bukan strategi bebas risiko**. Pada kondisi market trending kuat searah dalam waktu lama, lot recovery bisa terus membesar sampai menyentuh limit risk engine dan memicu **emergency close** (posisi ditutup rugi). Selalu uji di akun **demo** terlebih dahulu, gunakan modal yang siap hilang, dan pahami setiap parameter sebelum live.

---

## 📁 Struktur Project

```
GoldHedgeRecovery/
├── GoldHedgeRecovery.mq5        # Main EA entry point
├── Config/
│   └── Inputs.mqh               # Semua parameter input + enum bersama
├── Core/
│   ├── TradeEngine.mqh          # Eksekusi order (open/close/modify) + retry logic
│   ├── SignalEngine.mqh         # Logika sinyal entry (cross / trend + filter)
│   ├── RecoveryEngine.mqh       # Logika hedge recovery & lot sizing
│   ├── RiskEngine.mqh           # Semua guard/limit risiko
│   ├── PositionManager.mqh      # Tracking posisi, layer, basket state
│   ├── Dashboard.mqh            # Panel info on-chart
│   ├── Logger.mqh               # Logging Experts tab + CSV
│   ├── SessionManager.mqh       # Filter jam sesi trading
│   └── Utils.mqh                # Helper function bersama (lot, harga, waktu, dll)
├── Indicators/
│   ├── SMAEngine.mqh            # Wrapper indikator SMA
│   ├── EMAFilter.mqh            # Wrapper indikator EMA + logika cross/trend
│   ├── ATRFilter.mqh            # Wrapper indikator ATR + filter volatilitas
│   └── TrendFilter.mqh          # Gabungan filter tren (EMA200/SMA200/MTF)
├── README.md                    # Dokumen ini
└── CHANGELOG.md                 # Riwayat perubahan versi
```

---

## 🚧 Status Pembangunan

| Fase | Modul | Status |
|---|---|---|
| 1 | `Inputs.mqh`, `Utils.mqh`, `Logger.mqh` | ✅ Selesai |
| 2 | `SMAEngine.mqh`, `EMAFilter.mqh`, `ATRFilter.mqh`, `TrendFilter.mqh` | ⏳ Belum |
| 3 | `SignalEngine.mqh` | ⏳ Belum |
| 4 | `TradeEngine.mqh` | ⏳ Belum |
| 5 | `PositionManager.mqh` | ⏳ Belum |
| 6 | `RecoveryEngine.mqh` | ⏳ Belum |
| 7 | `RiskEngine.mqh` | ⏳ Belum |
| 8 | `Dashboard.mqh`, `SessionManager.mqh` | ⏳ Belum |
| 9 | `GoldHedgeRecovery.mq5` (main) | ⏳ Belum |

> Dokumen ini akan diperbarui setiap fase baru selesai. Jangan compile project sebelum semua fase selesai — beberapa `#include` di fase awal mereferensikan file yang masih akan dibuat di fase berikutnya.

---

## 🔧 Instalasi

1. Buka **MetaEditor** (dari MT5: `Tools` → `MetaQuotes Language Editor`, atau tombol F4)
2. Di panel **Navigator** sebelah kiri, klik kanan folder `Experts` → `New Folder` → beri nama `GoldHedgeRecovery`
3. Copy seluruh isi folder project ini (pertahankan struktur sub-folder `Config/`, `Core/`, `Indicators/`) ke dalam folder `MQL5/Experts/GoldHedgeRecovery/` di data folder terminal kamu
   - Cara cepat cari data folder: MT5 → `File` → `Open Data Folder`
4. Di MetaEditor, buka `GoldHedgeRecovery.mq5`, klik **Compile** (F7)
5. Pastikan tidak ada error di tab **Errors** — hanya boleh 0 error, warning boleh diabaikan jika tidak kritikal
6. Kembali ke MT5, buka chart **XAUUSD**, drag EA `GoldHedgeRecovery` dari Navigator ke chart
7. Di tab **Common** pada dialog EA, centang **Allow Algo Trading**
8. Atur parameter di tab **Inputs** sesuai kebutuhan (lihat `Config/Inputs.mqh` untuk deskripsi tiap parameter)
9. Klik **OK**

---

## ⚙️ Ringkasan Parameter Penting

Semua parameter didefinisikan di `Config/Inputs.mqh` dengan deskripsi inline. Beberapa yang paling sering perlu disesuaikan:

| Parameter | Fungsi | Default |
|---|---|---|
| `InpBaseLot` | Lot posisi awal (layer 0) | 0.01 |
| `InpRecoveryMode` | Metode lot recovery (Fixed/Multiplier/Custom) | Multiplier |
| `InpRecoveryMultiplier` | Pengali lot tiap layer recovery | 2.0 |
| `InpRecoveryTriggerUSD` | Floating loss (USD) yang memicu layer recovery baru | 0.30 |
| `InpMaxLayers` | Batas maksimal jumlah layer (termasuk layer 0) | 5 |
| `InpBasketTPUSD` | Target profit (USD) untuk menutup seluruh basket sekaligus | 0.50 |
| `InpMaxFloatingLossUSD` | Batas floating loss sebelum emergency close | 4.0 |
| `InpMaxTotalLot` | Batas total lot seluruh layer aktif | 0.50 |

---

## 🧪 Rencana Pengujian

Sebelum live, disarankan menguji EA melalui skenario berikut di **Strategy Tester** MT5:

- [ ] Visual Backtest (amati perilaku entry/recovery/TP secara visual)
- [ ] Non-Visual Backtest (cek hasil statistik cepat)
- [ ] Optimization (cari kombinasi parameter terbaik dalam batas risk yang aman)
- [ ] Kondisi market Trending
- [ ] Kondisi market Sideways
- [ ] Kondisi volatilitas tinggi (news/event besar)
- [ ] Kondisi volatilitas rendah
- [ ] Restart terminal saat posisi masih terbuka (cek EA bisa re-attach state dengan benar)
- [ ] Simulasi terputus internet/VPS (cek tidak terjadi duplikasi order saat reconnect)
- [ ] Jalan di VPS selama beberapa hari nonstop

---

## 📜 Lisensi & Tanggung Jawab

Project ini dibuat untuk kebutuhan personal. Trading forex/gold mengandung risiko kehilangan modal. Penggunaan EA ini sepenuhnya tanggung jawab pengguna.
