import sys
import math
import torch
import numpy as np
from model import SimpleDetector


def quantize_tensor(tensor, bits=8):
    """
    Quantize a float tensor to signed INT8.

    Returns:
        q_tensor: int8 numpy array
        scale: float (multiply by scale to get back to ~float)
    """
    max_val = tensor.abs().max().item()
    if max_val == 0:
        return np.zeros(tensor.shape, dtype=np.int8), 1.0

    scale = 127.0 / max_val
    q_tensor = torch.round(tensor * scale).clamp(-128, 127)

    return q_tensor.numpy().astype(np.int8), scale


def validate_quantization(quantized, model, num_samples=50):
    """
    Quick validation: compare float vs quantized peak locations.
    Simulates the integer arithmetic the FPGA will perform.
    """
    from dataset import SyntheticDetectionDataset

    model.eval()
    dataset = SyntheticDetectionDataset(num_samples=num_samples, seed=999)

    match_count = 0

    print(f"Validating quantization ({num_samples} samples)...")

    for idx in range(num_samples):
        image_float, _, coords = dataset[idx]
        image_float = image_float.unsqueeze(0)
        # Float model prediction
        with torch.no_grad():
            float_out = model(image_float).squeeze().numpy()
        float_peak = np.unravel_index(float_out.argmax(), float_out.shape)
        # Convert to uint8 as FPGA sees it
        act = (image_float.squeeze().numpy() * 255).astype(np.float32)
        if act.ndim == 2:
            act = act[np.newaxis, :, :]

        layer_names = ['conv1', 'conv2', 'conv3', 'conv4']
        for i, name in enumerate(layer_names):
            q = quantized[name]
            w = q['weights'].astype(np.float32)
            b = q['biases'].astype(np.float32)
            shift = q['shift']

            cout, cin, kh, kw = w.shape
            in_h, in_w = act.shape[1], act.shape[2]
            out_h, out_w = in_h // 2, in_w // 2

            out = np.zeros((cout, out_h, out_w), dtype=np.float32)

            for oc in range(cout):
                for oy in range(out_h):
                    for ox in range(out_w):
                        acc = float(b[oc])
                        for ic in range(cin):
                            for kr in range(3):
                                for kc in range(3):
                                    sy = oy * 2 + kr - 1
                                    sx = ox * 2 + kc - 1
                                    if 0 <= sy < in_h and 0 <= sx < in_w:
                                        px = act[ic, sy, sx]
                                    else:
                                        px = 0.0
                                    acc += px * w[oc, ic, kr, kc]

                        shifted = int(acc) >> shift
                        if i < 3:
                            shifted = max(0, min(255, shifted))
                        else:
                            shifted = max(0, min(255, shifted))

                        out[oc, oy, ox] = shifted

            act = out

        quant_peak = np.unravel_index(act.squeeze().argmax(),
                                       act.squeeze().shape)

        dist = math.sqrt((float_peak[0] - quant_peak[0]) ** 2 +
                         (float_peak[1] - quant_peak[1]) ** 2)
        if dist <= 1.0:
            match_count += 1

    rate = match_count / num_samples
    print(f"  Match rate (within 1 grid cell): {rate:.1%}")
    if rate < 0.7:
        print("  WARNING: Low match rate — shifts may need tuning")
    else:
        print("  GOOD: Quantization quality acceptable")

    return rate


def quantize_model():
    model = SimpleDetector()

    try:
        state_dict = torch.load('trained_model.pth', map_location='cpu')
        if 'model_state_dict' in state_dict:
            model.load_state_dict(state_dict['model_state_dict'])
        else:
            model.load_state_dict(state_dict)
    except FileNotFoundError:
        print("ERROR: trained_model.pth not found!")
        print("Run train.py first.")
        sys.exit(1)

    model.eval()

    layers = [
        ('conv1', model.conv1),
        ('conv2', model.conv2),
        ('conv3', model.conv3),
        ('conv4', model.conv4),
    ]

    quantized = {}
    print("=" * 50)
    print("  Simple-Net INT8 Quantization")
    print("=" * 50)
    print()

    total_weights = 0
    total_bytes = 0

    for name, layer in layers:
        w_quant, w_scale = quantize_tensor(layer.weight.data)
        b_float = layer.bias.data
        # Bias scale depends on input scale × weight scale
        b_max = b_float.abs().max().item()
        if b_max > 0:
            b_scale = 32767.0 / b_max
        else:
            b_scale = 1.0
        b_quant = torch.round(b_float * b_scale).clamp(-32768, 32767)
        b_quant = b_quant.numpy().astype(np.int16)

        # Compute output right-shift for re-quantization
        # We need to shift right to get back to UINT8 (0–255)
        # shift = log2(w_scale * input_scale)
        shift = max(0, int(np.round(np.log2(w_scale * 128))))

        quantized[name] = {
            'weights': w_quant,
            'biases': b_quant,
            'w_scale': w_scale,
            'b_scale': b_scale,
            'shift': shift,
        }

        n_weights = w_quant.size
        n_biases = b_quant.size
        total_weights += n_weights
        total_bytes += n_weights * 1 + n_biases * 2

        print(f"{name}:")
        print(f"  Weight shape: {w_quant.shape}")
        print(f"  Weight range: [{w_quant.min()}, {w_quant.max()}]")
        print(f"  Bias shape:   {b_quant.shape}")
        print(f"  Bias range:   [{b_quant.min()}, {b_quant.max()}]")
        print(f"  Right shift:  {shift}")
        print(f"  Quant error:  {np.mean((layer.weight.data.numpy() - w_quant / w_scale) ** 2):.2e} MSE")
        print()

    print("-" * 50)
    print(f"Total weights:  {total_weights}")
    print(f"Total storage:  {total_bytes} bytes ({total_bytes / 1024:.1f} KB)")
    print()

    try:
        validate_quantization(quantized, model)
    except ImportError:
        print("(Skipping validation — dataset.py not found)")
    except Exception as e:
        print(f"(Skipping validation — {e})")

    print()

    torch.save(quantized, 'quantized_model.pth')
    print("Saved: quantized_model.pth")
    print()
    print("Next step: python export_weights.py")


if __name__ == '__main__':
    quantize_model()