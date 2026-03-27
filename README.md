# Simple-Net: FPGA Object Detection 

> Real-time single-class object detection running entirely on a Spartan-7 FPGA with no CPU, no software—pure hardware.

![Board](https://img.shields.io/badge/Board-Urbana%20S7-blue)
![FPGA](https://img.shields.io/badge/FPGA-XC7S50-purple)

## What Is This?

A complete hardware-only neural network designed to:
* **Capture** live video from an OV7670 camera.
* **Process** a custom 5-layer INT8 CNN at real-time speeds.
* **Detect** and draw a bounding box around objects.
* **Output** directly to HDMI — no PC or external processing required.

---

## Build Progress

| Phase | Milestone | Status |
| :--- | :--- | :--- |
| 0 | Clocking & Foundation | ✅ Complete |
| 1 | DDR3 Memory Hub | ✅ Complete |
| 2 | Camera Interface | ✅ Complete |
| 3 | HDMI Video Output | ✅ Complete |
| 4 | Downsampler | ✅ Complete |
| 5 | CNN Engine | ✅ Complete |
| 6 | Full Integration | ✅ Complete |

---

## Hardware Required

* **FPGA Board:** Real Digital Urbana Board (Spartan-7 XC7S50)
* **Camera:** OV7670 Camera Module (non-FIFO)
* **Display:** HDMI Monitor
* **Connection:** Micro-USB cable (for programming/power)

## Building

1.  Install **Vivado 2023.x** or later.
2.  Open your terminal/Vivado Tcl Console.
3.  Run: `vivado -source vivado/create_project.tcl`
4.  Generate bitstream.
5.  Program the board.

---

## Resource Usage Estimates

| Subsystem | DSP48 (of 120) | BRAM (of 338 KB) |
| :--- | :--- | :--- |
| DDR3 Controller | 0 | ~15 KB |
| Video Pipeline | 0 | ~40 KB |
| CNN Engine (INT8) | 70–90 | ~160 KB |
| **Free Margin** | **~30** | **~120 KB** |

---

## License

This project is licensed under the [MIT License](LICENSE).
