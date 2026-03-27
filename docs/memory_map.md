# DDR3 Memory Map

## Hardware

- **Chip**: DDR3L (1.35V), 16-bit data bus
- **Total Capacity**: 256 MB (addresses 0x0000000 to 0x0FFFFFF)
- **MIG UI Data Width**: 128 bits (16 bytes per transaction)
- **MIG UI Clock**: ~81.25 MHz

## Address Layout

| Region | Start Address | End Address | Size | Purpose |
|--------|--------------|-------------|------|---------|
| Frame Buffer 0 | `0x000_0000` | `0x009_5FFF` | 614,400 B | Display frame A |
| Frame Buffer 1 | `0x010_0000` | `0x019_5FFF` | 614,400 B | Display frame B |
| CNN Input | `0x020_0000` | `0x020_3FFF` | 16,384 B | 128x128 grayscale |
| Reserved | `0x020_4000` | `0x0FF_FFFF` | ~254 MB | Unused |

## Frame Buffer Format

- Resolution: 640 x 480
- Pixel format: RGB565 (16 bits per pixel)
- Row-major order: pixel address = (row x 640 + col) x 2
- Frame size: 640 x 480 x 2 = 614,400 bytes

## CNN Input Format

- Resolution: 128 x 128
- Pixel format: 8-bit grayscale
- Row-major order: pixel address = row x 128 + col
- Frame size: 128 x 128 x 1 = 16,384 bytes

## CNN Internal Buffers (BRAM, not DDR3)

The CNN pipeline uses internal ping-pong BRAM buffers rather than DDR3
for intermediate layer results. This avoids DDR3 bandwidth contention.

| Buffer | Size | Contents |
|--------|------|----------|
| buf_a | 16,384 B | Input image / even layer results |
| buf_b | 16,384 B | Odd layer results |

Layer data layout within each buffer:

| Layer Output | Dimensions | Address Formula |
|-------------|------------|-----------------|
| Layer 1: 64x64x4 | 16,384 B | `{ch[1:0], y[5:0], x[5:0]}` |
| Layer 2: 32x32x8 | 8,192 B | `{ch[2:0], y[4:0], x[4:0]}` |
| Layer 3: 16x16x16 | 4,096 B | `{ch[3:0], y[3:0], x[3:0]}` |
| Layer 4: 8x8x1 | 64 B | `{ch[0], y[2:0], x[2:0]}` |

## Double Buffering

Camera writes to one frame buffer while display reads from the other.
They swap on vertical sync boundaries. This prevents tearing.
