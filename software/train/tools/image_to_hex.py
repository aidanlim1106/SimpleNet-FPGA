import sys
import numpy as np
from PIL import Image


def convert(input_path, output_path):
    # Load and resize to 128×128 grayscale
    img = Image.open(input_path).convert('L').resize((128, 128))
    pixels = np.array(img, dtype=np.uint8)

    with open(output_path, 'w') as f:
        f.write(f"// {input_path} converted to 128x128 grayscale\n")
        for row in range(128):
            for col in range(128):
                f.write(f"{pixels[row, col]:02X}\n")

    total = 128 * 128
    print(f"Converted: {input_path} → {output_path} ({total} pixels)")


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: python image_to_hex.py input.png output.hex")
        sys.exit(1)
    convert(sys.argv[1], sys.argv[2])