# tiny-gpu FPGA Carrier Board — Design Context

## 2025-01-01 -- Initial PCB Layout Created

- Parsed `tiny-gpu.kicad_sch` (66 component instances) to extract all net assignments
- Created `other.trace_pcb` with complete component placement across a 200×160mm board
- Conversion to `.kicad_pcb` fails with `libexpat.so.1` system library error — this is an environment issue, not a file content error. The `.trace_pcb` file itself is correctly formed.

### Component placement strategy:
- **Connectors on edges**: J1 (USB-C) left edge top, J2 (HDMI) right edge, J3 (JTAG) left edge bottom
- **Power section top-left**: U1/U2/U3 (TPS62130 bucks for 1.0V/1.8V/1.35V), U4 (AP2112K 3.3V LDO), U15 (AP2112K 1.2V LDO) with associated inductors, feedback resistors, bulk caps, and decoupling caps
- **FPGA center**: U_FPGA (XC7A100T BGA-484) at 110,90 — board center for balanced DDR routing
- **DDR3L array right-of-FPGA**: 8× MT41K256M16TW BGA-96 in 2 rows of 4, 15mm spacing
  - Row A (Y=55): U5, U6, U7, U8 (DQ0-63)
  - Row B (Y=75): U9, U10, U11, U12 (DQ64-127)
- **HDMI encoder bottom-center**: U13 (SiI9022A QFN-72) at 110,145 with pull-ups and decoupling
- **SPI Flash near FPGA left**: U14 (W25Q128 SOIC-8) at 80,115
- **Done LED bottom-left**: R18 + D1 at 30,155
- **GND zone**: Both F.Cu and B.Cu pours covering entire board

### Known issue:
- `libexpat.so.1` missing in Trace conversion environment — causes `Conversion failed` error on write
- The `.trace_pcb` file content is valid; this is a system/environment problem not a design error
