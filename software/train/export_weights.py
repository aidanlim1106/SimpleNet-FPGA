import os
import torch
import numpy as np


def int8_to_hex(val):
    """Convert signed int8 to 2-digit hex (two's complement)."""
    return f"{val & 0xFF:02X}"


def int16_to_hex(val):
    """Convert signed int16 to 4-digit hex (two's complement)."""
    return f"{val & 0xFFFF:04X}"


def export_weights():
    quantized = torch.load('quantized_model.pth', map_location='cpu')

    # Create output directory
    out_dir = os.path.join('..', '..', 'weights')
    os.makedirs(out_dir, exist_ok=True)

    layer_names = ['conv1', 'conv2', 'conv3', 'conv4']
    all_biases = []
    shifts = []

    for name in layer_names:
        data = quantized[name]
        weights = data['weights']     # Shape: (cout, cin, 3, 3)
        biases = data['biases']       # Shape: (cout,)
        shift = data['shift']

        # ---- Export weights ----
        # Flatten in order: cout → cin → row → col
        # This matches how the FPGA reads them sequentially
        weight_file = os.path.join(out_dir, f'{name}_weights.mem')
        with open(weight_file, 'w') as f:
            f.write(f"// {name} weights: shape {weights.shape}\n")
            f.write(f"// Order: output_ch, input_ch, row, col\n")
            for cout in range(weights.shape[0]):
                for cin in range(weights.shape[1]):
                    for kr in range(3):
                        for kc in range(3):
                            val = int(weights[cout, cin, kr, kc])
                            f.write(int8_to_hex(val) + "\n")

        count = weights.shape[0] * weights.shape[1] * 9
        print(f"{name}: {count} weights → {weight_file}")

        # Collect biases
        for b in biases:
            all_biases.append(int(b))

        shifts.append(shift)

    # ---- Export all biases in one file ----
    bias_file = os.path.join(out_dir, 'all_biases.mem')
    with open(bias_file, 'w') as f:
        f.write(f"// All biases: {len(all_biases)} total\n")
        f.write(f"// Order: conv1 (4), conv2 (8), conv3 (16), conv4 (1)\n")
        for b in all_biases:
            f.write(int16_to_hex(b) + "\n")
    print(f"Biases: {len(all_biases)} → {bias_file}")

    # ---- Export shift values ----
    shift_file = os.path.join(out_dir, 'layer_shifts.mem')
    with open(shift_file, 'w') as f:
        f.write(f"// Right-shift per layer for re-quantization\n")
        for s in shifts:
            f.write(f"{s:02X}\n")
    print(f"Shifts: {len(shifts)} → {shift_file}")

    print("\nDone! Weight files are in the 'weights/' directory.")
    print("These get loaded into FPGA BRAM via $readmemh().")


if __name__ == '__main__':
    export_weights()