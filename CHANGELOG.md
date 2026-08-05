# Changelog

Semua perubahan penting pada project ini dicatat di file ini.
Format mengikuti [Keep a Changelog](https://keepachangelog.com/), versi mengikuti [Semantic Versioning](https://semver.org/).

---

## [1.0.0] - Initial Release (Build in Progress)

### Ditambahkan
- **Config/Inputs.mqh** — Seluruh parameter input terpusat (entry, filter, recovery, exit, risk, dashboard, logging, eksekusi) beserta enum bersama (`ENUM_ENTRY_MODE`, `ENUM_RECOVERY_MODE`, `ENUM_TRADE_DIRECTION`, `ENUM_TRADE_STATE`).
- **Core/Utils.mqh** — Helper function bersama: normalisasi lot, konversi poin↔harga, parser custom lot sequence, cek jam sesi, deskripsi retcode MT5, deteksi retcode yang layak di-retry.
- **Core/Logger.mqh** — Logging terstruktur ke Experts tab dan file CSV (`Time, Symbol, Ticket, Layer, Action, Price, Lot, Profit, Floating, Retcode, Description`).
- **Core/SessionManager.mqh** — Filter jam trading (session hour range), termasuk dukungan range overnight.
- **Indicators/SMAEngine.mqh** — Wrapper indikator SMA dengan lifecycle handle yang aman.
- **Indicators/EMAFilter.mqh** — Wrapper EMA untuk dua kebutuhan: deteksi cross (fast/slow) dan trend bias (harga vs EMA tunggal).
- **Indicators/ATRFilter.mqh** — Wrapper ATR + gate volatilitas (blok entry jika ATR terlalu rendah/tinggi).
- **Indicators/TrendFilter.mqh** — Agregator EMA200 + SMA200 + Multi-Timeframe menjadi satu keputusan konfirmasi arah.
- **Core/SignalEngine.mqh** — Mesin sinyal entry final: menggabungkan entry mode, trend filter, ATR, spread, sesi, dan candle body menjadi satu sinyal terkonfirmasi per bar closed.
- **Core/TradeEngine.mqh** — Satu-satunya modul yang memanggil `OrderSend()`. Menangani open/close/modify posisi dengan retry logic untuk error transient (Requote, Off Quotes, Timeout, dll), serta encode/parse nomor layer via comment order.
- **Core/PositionManager.mqh** — Single source of truth untuk posisi & layer aktif; dibangun ulang dari data live terminal setiap tick (mendukung recovery state setelah restart terminal).
- **Core/RiskEngine.mqh** — Seluruh guard risiko: Max Daily Loss, Max Floating Loss, Max Drawdown, Max Total Lot, Max Layers, Max Consecutive Losses, Free Margin Guard, Margin Level Guard.
- **Core/RecoveryEngine.mqh** — Orkestrator siklus hedge-recovery penuh: buka posisi awal, buka layer recovery (arah berlawanan, lot membesar), Individual TP, Basket TP, Break Even, Trailing Stop, dan respons terhadap Emergency Close dari RiskEngine.
- **Core/Dashboard.mqh** — Panel info on-chart (state, trend, ATR, spread, sesi, layer, recovery mode, total lot, floating, equity, balance, margin level).
- **README.md** — Dokumentasi struktur project, instalasi, ringkasan parameter, dan rencana pengujian.

### Belum Selesai (In Progress)
- **GoldHedgeRecovery.mq5** — Main EA entry point (`OnInit`, `OnTick`, `OnDeinit`) yang menyatukan seluruh modul di atas. **Project belum bisa di-compile sampai file ini selesai.**

### Catatan
- Dirancang khusus untuk akun **Hedging** (bukan Netting) di MetaTrader 5.
- Default parameter dikalibrasi untuk modal kecil (contoh: modal demo $10, base lot 0.01).
- Belum pernah diuji di Strategy Tester — checklist pengujian tersedia di `README.md`.

---

## Rencana Versi Berikutnya (belum dirilis)
- Penambahan opsi input manual event/news filter (menunggu kebutuhan lebih lanjut).
- Potensi penambahan tombol reset di Dashboard untuk clear status "Paused (Consecutive Losses)" tanpa restart EA.
