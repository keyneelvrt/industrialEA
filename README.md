# Astra Industrial EA modifikasi v2.00 — Industrial-Grade Multi-Asset Expert Advisor

Laporan Proyek #2: Sains Manajemen
Departemen Ilmu Komputer dan Elektronika, FMIPA Universitas Gadjah Mada (2026)

* Penulis: Keyne Elvaretta
* NIM: 24/533391/PA/22572
* Mata Kuliah: Sains Manajemen
* Repositori: https://github.com/keyneelvrt/industrialEA

---

## Ringkasan Proyek

Proyek ini mengevaluasi performa sistem perdagangan algoritmik Astra Industrial EA v2.00 pada 10 instrumen finansial lintas 5 kelas aset:
* Forex Major: EURUSD, GBPUSD, USDJPY
* Indeks Saham: DE40 (DAX), USTEC (Nasdaq 100), JPN225 (Nikkei 225), HK50 (Hang Seng)
* Logam Mulia: XAGUSD (Silver)
* Kripto: BTCUSD (Bitcoin)
* Energi: USOIL (WTI Crude Oil)

Pengujian dilakukan menggunakan model simulasi Every Tick / 1-Minute OHLC berbasis data historis riil broker Exness kurun waktu 7 tahun (2019–2026) dengan History Quality 98%–100%.

---

## Manajemen Risiko & Parameter

1. Model Tanpa Leverage (1:1 Cash Equivalent Model).
2. Aturan Strict Institusional: No Martingale, No Grid Averaging, dan No High-Frequency Trading (HFT).
3. Bar-Close Execution Only: Eksekusi sinyal hanya pada pembentukan bar baru di timeframe H1.
4. Setelan Parameter Spesifik: Penggunaan InpAutoProfile=false dengan penguncian arah entri (Single-Directional Bias) serta rasio ATR Stop Loss & Take Profit kustom.
5. Circuit Breaker: Penutupan posisi otomatis jika Equity Drawdown mencapai 25%.

---

## Arsitektur Strategi Multi-Timeframe

* Layer 1 (Macro Filter): EMA 200 + ATR Directional Buffer (H4/D1) untuk penentu tren utama.
* Layer 2 (Signal Trigger): Keltner Channel Breakout (EMA 20 ± N x ATR) pada timeframe H1/H4.
* Layer 3 (Momentum Confirmation): RSI(14) Rebound Confirmation pada timeframe H1/H4.
* Layer 4 (Volatility Gate): ATR Volatility Filter (ATR > SMA-ATR-20) untuk menghindari kondisi pasar sideways.

---

## Hasil Pengujian Agregat 7 Tahun (2019–2026)

* Modal Awal Akumulasi: $100,000.00 ($10,000.00 per instrumen)
* Ekuitas Akhir Akumulasi: $114,191.00
* Total Net Profit: +$14,191.00 (+14.19% rata-rata return per instrumen)
* Success Rate: 100% (10 dari 10 instrumen membukukan profit positif)
* Rata-Rata Profit Factor: 1.21
* Aggregate Win Rate: 52.50% (1,884 Total Trades)
* Rata-Rata Max Equity Drawdown: 10.85% (Memenuhi batas toleransi < 25%–30%)

---

## Rekapitulasi Performa Instrumen

| Instrumen | Kategori | Net Profit ($) | Return (%) | Profit Factor | Win Rate (%) | Trades | Max DD (%) | Sharpe Ratio | 
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | 
| DE40 | Indeks Saham | +$6,804.22 | +68.04% | 1.40 | 46.36% | 343 | 12.42% | 3.55 | 
| EURUSDm | Forex Major | +$2,223.78 | +22.24% | 1.18 | 55.09% | 383 | 9.92% | 1.39 | 
| JPN225 | Indeks Saham | +$2,143.56 | +21.40% | 1.10 | 53.25% | 231 | 25.02% | 0.85 | 
| BTCUSDm | Kripto | +$951.70 | +9.52% | 1.23 | 45.78% | 83 | 11.23% | 1.87 | 
| HK50 | Indeks Saham | +$800.33 | +8.00% | 1.42 | 57.69% | 78 | 7.02% | 4.03 | 
| GBPUSDm | Forex Major | +$529.00 | +5.29% | 1.10 | 53.94% | 241 | 12.17% | 0.67 |
| USTECm | Indeks Saham | +$402.18 | +4.02% | 1.55 | 58.33% | 36 | 2.86% | 3.74 |
| XAGUSDm | Logam Mulia | +$170.00 | +1.70% | 1.06 | 60.34% | 174 | 6.34% | 0.30 | 
| USOILm | Energi | +$132.65 | +1.33% | 1.02 | 45.74% | 188 | 12.03% | 0.17 |
| USDJPYm | Forex Major | +$33.90 | +0.34% | 1.00 | 48.31% | 267 | 9.46% | 0.10 |

---

