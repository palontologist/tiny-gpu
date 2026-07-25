# tiny-gpu Carrier Board — Authoritative Pin/Ball Maps (from datasheets)

These maps were extracted from the official datasheets and are the reference for
rebuilding the schematic symbols + verifying the PCB after re-running Trace with
**real KiCad libraries** (not AI-invented footprints).

> CRITICAL: The original Trace-generated board is NON-FUNCTIONAL. Every IC footprint
> was generated with pads named by *net* (e.g. "DDR_DQ0") instead of real ball/pin
> coordinates, and most physical balls/pins are MISSING:
>   - XC7A100T FGG484 (FPGA): 207 pads present, should be 484
>   - MT41K256M16 BGA-96 (DDR3) x8: 51 pads each, should be 96
>   - SiI9022A QFN-72 (HDMI): 26 pads present, should be 72 + EP
> Fix = use real library footprints + symbols whose pin `number` = real ball/pin coord.

## 1. SiI9022A / SiI9022ACNU — 72-pin QFN (10x10 mm, 0.5 mm pitch, EP)
Source: Lattice SiI9022A/SiI9024A Data Sheet, Figure 5.3 + "Ball and Pin Descriptions"
(DS rev E.01). **This is the part the original design got 100% wrong.**

| QFN pin | Signal | Type | Notes |
|---|---|---|---|
| 1  | CSCL   | I/O (open-drain) | Local I2C clock — 4.7 kΩ pullup to IOVCC |
| 2  | CSDA   | I/O (open-drain) | Local I2C data — 4.7 kΩ pullup to IOVCC |
| 3  | IOVCC  | Pwr | I/O supply: 1.8 V **or** 3.3 V (sets I/O threshold via IO_SEL) |
| 4  | D23    | In  | Video input data bit 23 (24-bit single-edge mode) |
| 5  | CVCC12 | Pwr | Digital core 1.2 V (also pins 12,26,42,47,53) |
| 6  | D22    | In  | Video data bit 22 |
| 7  | D21    | In  | Video data bit 21 |
| 8  | D20    | In  | Video data bit 20 |
| 9  | D19    | In  | Video data bit 19 |
| 10 | D18    | In  | Video data bit 18 |
| 11 | D17    | In  | Video data bit 17 |
| 12 | CVCC12 | Pwr | Digital core 1.2 V |
| 13 | D16    | In  | Video data bit 16 |
| 14 | D15    | In  | Video data bit 15 |
| 15 | D14    | In  | Video data bit 14 |
| 16 | D13    | In  | Video data bit 13 |
| 17 | D12    | In  | Video data bit 12 |
| 18 | D11    | In  | Video data bit 11 |
| 19 | D10    | In  | Video data bit 10 |
| 20 | D9     | In  | Video data bit 9 |
| 21 | IOVCC  | Pwr | I/O supply |
| 22 | IDCK   | In  | Input data clock (pixel clock) |
| 23 | D8     | In  | Video data bit 8 |
| 24 | D7     | In  | Video data bit 7 |
| 25 | D6     | In  | Video data bit 6 |
| 26 | CVCC12 | Pwr | Digital core 1.2 V |
| 27 | D5     | In  | Video data bit 5 |
| 28 | D4     | In  | Video data bit 4 |
| 29 | D3     | In  | Video data bit 3 |
| 30 | D2     | In  | Video data bit 2 |
| 31 | D1     | In  | Video data bit 1 |
| 32 | D0     | In  | Video data bit 0 |
| 33 | DE     | In  | Data enable |
| 34 | HSYNC  | In  | Horizontal sync |
| 35 | VSYNC  | In  | Vertical sync |
| 36 | SPDIF  | In  | S/PDIF audio (optional) |
| 37 | SD3    | In  | I2S data 3 (optional) |
| 38 | MCLK   | In  | Audio master clock (optional) |
| 39 | SD2    | In  | I2S data 2 (optional) |
| 40 | SD1    | In  | I2S data 1 (optional) |
| 41 | SD0    | In  | I2S data 0 (optional) |
| 42 | CVCC12 | Pwr | Digital core 1.2 V |
| 43 | CGND   | Gnd | Digital core GND |
| 44 | WS     | In  | I2S word select (optional) |
| 45 | SCK    | In  | I2S serial clock (optional) |
| 46 | IOVCC  | Pwr | I/O supply |
| 47 | CVCC12 | Pwr | Digital core 1.2 V |
| 48 | DSDA   | I/O (open-drain) | DDC data to HDMI connector — 1.8–2.2 kΩ pullup |
| 49 | DSCL   | I/O (open-drain) | DDC clock to HDMI connector — 1.8–2.2 kΩ pullup |
| 50 | CEC_D  | I/O | Local CEC (to CPU, optional) |
| 51 | RESET# | In  | Reset, active LOW (from FPGA) |
| 52 | INT    | Out | Interrupt (to FPGA) |
| 53 | CVCC12 | Pwr | Digital core 1.2 V |
| 54 | HPD    | In  | Hot-plug detect (from HDMI connector) — 10 kΩ pulldown to GND |
| 55 | RSVDL  | In  | Must be tied LOW |
| 56 | EXT_SWING | In | R (4.3 kΩ ±1% w/ term, or 5.1 kΩ) to GND sets TMDS swing |
| 57 | IOGND  | Gnd | I/O GND |
| 58 | TXC-   | Out | TMDS clock − (to HDMI connector) |
| 59 | TXC+   | Out | TMDS clock + (to HDMI connector) |
| 60 | AVCC12 | Pwr | Analog/TMDS 1.2 V (also pin 66) |
| 61 | TX0-   | Out | TMDS data lane 0 − |
| 62 | TX0+   | Out | TMDS data lane 0 + |
| 63 | AGND   | Gnd | Analog GND |
| 64 | TX1-   | Out | TMDS data lane 1 − |
| 65 | TX1+   | Out | TMDS data lane 1 + |
| 66 | AVCC12 | Pwr | Analog/TMDS 1.2 V |
| 67 | TX2-   | Out | TMDS data lane 2 − |
| 68 | TX2+   | Out | TMDS data lane 2 + |
| 69 | IO_SEL | In  | Tie to GND = 3.3 V I/O; tie to 1.8 V = 1.8 V I/O |
| 70 | VDDQ   | In  | Must be tied LOW |
| 71 | CEC_A  | I/O | HDMI CEC (to connector) |
| 72 | CI2CA  | In  | I2C addr select — 4.7 kΩ to IO_SEL level |
| EP | GND    |     | Exposed pad — MUST connect to board GND plane |

Power summary for the redesign:
- 1.2 V rail (CVCC12 + AVCC12, pins 5,12,26,42,47,53,60,66) ← from AP2112K-1.2 (as originally planned).
- IOVCC (pins 3,21,46): choose 3.3 V **or** 1.8 V. NOTE: if 3.3 V, the FPGA bank driving
  D0–D23/IDCK/DE/HSYNC/VSYNC must be a 3.3 V-capable **HR** bank (Artix-7 HP banks 14/15
  only support ≤1.8 V VCCO). IO_SEL must match (GND for 3.3 V).
- GND: CGND(43), IOGND(57), AGND(63), EP all to GND.
- RSVDL(55) and VDDQ(70) tie LOW; CI2CA(72) 4.7 kΩ to IO_SEL.

## 2. MT41K256M16TW-107:P — DDR3L x16, 96-ball FBGA (8x14 mm, "TW")
Source: Micron 4Gb_DDR3L DS, Table 4 / Figure 13. Use the **real KiCad BGA-96
footprint** (with 96 ball-named pads). Net→ball mapping is the standard x16 assignment
in the Micron DS; verify each lane against Figure 13 when routing. Signal set per device:

- Data: DQ[15:0], LDQS/LDQS# (lower byte strobe), UDQS/UDQS# (upper byte strobe),
  LDM (lower byte mask), UDM (upper byte mask)
- Address: A[14:0], A12/BC# (on-the-fly burst chop), BA[2:0]
- Command: CK/CK#, CKE, CS#, RAS#, CAS#, WE#, ODT, RESET#
- Reference: VREFCA, ZQ (external 240 Ω ±1% to VSSQ)
- Power: VDD, VDDQ (1.35 V), VSS, VSSQ
- x16 has two byte lanes; terminate unused upper byte (UDQS→GND via 1 kΩ,
  UDQS#→VDD via 1 kΩ, UDM→VDD, DQ[15:8]→VSS/VDD/VREF or float) if only lower byte used.

> The original design placed 8× x16 parts = 128 DQ. See the 128-bit feasibility note
> in section 4 before committing the FPGA bank plan.

## 3. XC7A100T-2FGG484I — Artix-7, 484-ball FGG484 (0.95 mm pitch)
Source: AMD/Xilinx UG475 (7 Series Packaging and Pinout). Use the **real KiCad
BGA-484 footprint** (484 ball-named pads A1–U21). The schematic symbol pin `number`
must equal the ball coordinate (e.g. "K11"), NOT the net name.

Required ball groups to assign (per UG475 FGG484 table):
- VCCINT, VCCAUX, VCCBRAM, VCCO_0/14/15/34/35 (power per bank)
- GND (many balls)
- VREF (per bank using DDR/SSTL), ZQ (per bank using DCI/ODT)
- Configuration: TCK, TMS, TDI, TDO, PROG_B, INIT_B, CCLK, DONE, M[2:0], DOUT_CSO_B,
  DIN_D0 (SPI flash master mode)
- User I/O banks for: DDR3 (data/addr/cmd), HDMI video input, TMDS-side config I2C,
  HDMI control (HPD/INT/RESET)

## 4. Artix-7 bank plan & resolution (RESOLVED)

### 4.1 Hard constraint: only TWO HP banks on FGG484
XC7A100T-2FGG484I user I/O banks (Xilinx UG475/UG471):
- **HP banks 14, 15** — VCCO ≤ 1.8 V. Optimized for memory (SSTL15/DCI). MIG places
  the DDR interface here. ~50 I/O each → **~96–100 usable I/O total for DDR**.
- **HR banks 34, 35** — VCCO ≤ 3.3 V. For general I/O (HDMI video input, etc.).
- Bank 0 — dedicated configuration I/O.

### 4.2 The 128-bit plan does NOT fit
DDR3 pin budget (address/command shared across all chips, fly-by topology):

| Width | x16 chips | DQ | DQS | DM | addr/cmd | total I/O |
|---|---|---|---|---|---|---|
| 16-bit | 1 | 16 | 4 | 2 | 27 | 49 |
| 32-bit | 2 | 32 | 8 | 4 | 27 | 71 |
| 48-bit | 3 | 48 | 12 | 6 | 27 | 93 |
| 64-bit | 4 | 64 | 16 | 8 | 27 | 115  ❌ (>~100) |
| 128-bit | 8 | 128 | 32 | 16 | 27 | 203  ❌ |

Two HP banks (~100 I/O) cannot host 64-bit, let alone 128-bit. **Resolution: use a
32-bit DDR3L interface (2× MT41K256M16TW).** This needs ~71 I/O, fits banks 14+15
with ~25 pins to spare. (16-bit/1 chip is even safer if 512 MB is enough; 48-bit is
tight but possible.)

> Capacity impact: 2× 4 Gb = 1 GB (was 4 GB at 128-bit). Fine for a GPU framebuffer demo.
> If >1 GB is required, move to a larger package (e.g. FGG676, 4 HP banks) or Kintex.

### 4.3 Bank assignment
- **DDR3L (32-bit) → HP banks 14 + 15**, I/O std SSTL15, **VCCO = 1.5 V**. Add a
  dedicated VREF (from VCCO via divider) and ZQ (240 Ω ±1% to GND) per bank.
- **HDMI / SiI9022A video input (D[23:0], IDCK, DE, HSYNC, VSYNC) + control → HR
  banks 34 + 35**, VCCO = 3.3 V. SiI9022A IO_SEL tied to GND (selects 3.3 V I/O).
  (~35 FPGA pins; HR banks have ~100 I/O — plenty of room.)
- **Configuration / JTAG → Bank 0** + dedicated config pins (master SPI flash).

### 4.4 Power-rail correction (was wrong in the original)
- FPGA DDR bank VCCO must be **1.5 V (SSTL15)**, NOT 1.35 V. DDR3L devices are
  1.5 V-tolerant, so the simplest fix is: **run both the DDR chips (VDD/VDDQ) and the
  FPGA VCCO_DDR at 1.5 V on a single 1.5 V rail** (DDR3L is 1.5 V-compatible).
  Alternatively keep DDR chips at 1.35 V and add a separate 1.5 V rail for the FPGA
  bank — more rails, more complexity. Original single 1.35 V "VCCO_DDR" rail is
  incorrect for the FPGA bank either way.
- Required rails: 1.0 V (VCCINT), 1.8 V (VCCAUX/VCCBRAM), 1.5 V (VCCO DDR bank +
  DDR VDD), 3.3 V (VCCO HR / IO, SiI9022A IOVCC), 1.2 V (SiI9022A CVCC12/AVCC12).
  Keep the original PG sequencing chain (U1→U2→U3→U4) but make U3 = 1.5 V, not 1.35 V.

### 4.5 Action items
- Reduce DDR3L from 8× to **2× MT41K256M16TW** (32-bit). Remove U7–U12.
- Change VCCO_DDR rail to **1.5 V** (U3 TPS62130: R7=350k/R8=100k → ~1.5 V;
  recompute FB divider: Vout = 0.8 × (1 + Rtop/Rbot); for 1.5 V, Rtop/Rbot ≈ 0.875,
  e.g. R7=350k, R8=400k).
- Assign DDR nets to HP banks 14/15 and HDMI nets to HR banks 34/35 per §4.3.
- Re-verify against Xilinx UG475 (FGG484 ball→bank map) and UG586 (MIG) when
  rebuilding the FPGA symbol.

## 5. Correct KiCad library footprints to use (real packages)
- FPGA:   `Package_BGA:BGA-484_1.0mm_Pitch` (or the FGG484-specific 484-ball) — 484 pads
- DDR3:   `Package_BGA:BGA-96_1.0mm_Pitch` (x16, 96-ball) — 96 pads each
- HDMI:   `Package_DFN_QFN:QFN-72-1EP_10x10mm_P0.5mm_EP8x8mm` — 72 pins + EP
- Do NOT let any tool regenerate "footprints" from net-named symbol pins.
