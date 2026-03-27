# Synthetic dataset generator for Simple-Net training.
#
# Generates 128×128 grayscale images with a single bright "object"
# (blob) at a random position, plus the corresponding 8×8 heatmap
# ground truth label.
#
# The heatmap has a Gaussian peak centered at the grid cell
# corresponding to the object location.

import os
import math
import random
import numpy as np
import torch
from torch.utils.data import Dataset, DataLoader
from PIL import Image, ImageDraw, ImageFilter


class SyntheticDetectionDataset(Dataset):
    def __init__(self, num_samples=10000, img_size=128, hm_size=8,
                 min_obj_size=10, max_obj_size=40, sigma=1.0,
                 noise_level=20, seed=None):
        """
        Args:
            num_samples:   Number of images to generate per epoch
            img_size:      Input image size (128)
            hm_size:       Heatmap grid size (8)
            min_obj_size:  Minimum object diameter in pixels
            max_obj_size:  Maximum object diameter in pixels
            sigma:         Gaussian sigma for heatmap peak (in grid cells)
            noise_level:   Max background noise amplitude (0–255)
            seed:          Random seed for reproducibility (None = random)
        """
        self.num_samples = num_samples
        self.img_size = img_size
        self.hm_size = hm_size
        self.min_obj_size = min_obj_size
        self.max_obj_size = max_obj_size
        self.sigma = sigma
        self.noise_level = noise_level
        self.stride = img_size // hm_size 

        if seed is not None:
            random.seed(seed)
            np.random.seed(seed)

    def __len__(self):
        return self.num_samples

    def _generate_heatmap(self, cx, cy):
        hm = np.zeros((self.hm_size, self.hm_size), dtype=np.float32)
        gx = cx / self.stride
        gy = cy / self.stride

        for row in range(self.hm_size):
            for col in range(self.hm_size):
                dist_sq = (col + 0.5 - gx) ** 2 + (row + 0.5 - gy) ** 2
                hm[row, col] = math.exp(-dist_sq / (2 * self.sigma ** 2))

        return hm

    def _draw_circle(self, img_draw, cx, cy, radius, brightness):
        x0 = cx - radius
        y0 = cy - radius
        x1 = cx + radius
        y1 = cy + radius
        img_draw.ellipse([x0, y0, x1, y1], fill=brightness)

    def _draw_rectangle(self, img_draw, cx, cy, half_w, half_h, brightness):
        x0 = cx - half_w
        y0 = cy - half_h
        x1 = cx + half_w
        y1 = cy + half_h
        img_draw.rectangle([x0, y0, x1, y1], fill=brightness)

    def _draw_gaussian_blob(self, img_np, cx, cy, radius, brightness):
        for y in range(max(0, cy - radius * 2), min(self.img_size, cy + radius * 2)):
            for x in range(max(0, cx - radius * 2), min(self.img_size, cx + radius * 2)):
                dist_sq = (x - cx) ** 2 + (y - cy) ** 2
                val = brightness * math.exp(-dist_sq / (2 * (radius / 2) ** 2))
                img_np[y, x] = min(255, img_np[y, x] + int(val))
        return img_np

    def _generate_background(self):
        bg_type = random.choice(['noise', 'gradient', 'dark'])

        if bg_type == 'noise':
            bg = np.random.randint(0, self.noise_level,
                                   (self.img_size, self.img_size), dtype=np.uint8)
        elif bg_type == 'gradient':
            # Random direction gradient
            direction = random.choice(['horizontal', 'vertical', 'diagonal'])
            if direction == 'horizontal':
                ramp = np.linspace(0, self.noise_level, self.img_size, dtype=np.float32)
                bg = np.tile(ramp, (self.img_size, 1)).astype(np.uint8)
            elif direction == 'vertical':
                ramp = np.linspace(0, self.noise_level, self.img_size, dtype=np.float32)
                bg = np.tile(ramp.reshape(-1, 1), (1, self.img_size)).astype(np.uint8)
            else:
                x = np.linspace(0, 1, self.img_size)
                y = np.linspace(0, 1, self.img_size)
                xx, yy = np.meshgrid(x, y)
                bg = ((xx + yy) / 2 * self.noise_level).astype(np.uint8)
        else:
            bg = np.zeros((self.img_size, self.img_size), dtype=np.uint8)

        return bg

    def __getitem__(self, idx):
        obj_size = random.randint(self.min_obj_size, self.max_obj_size)
        margin = obj_size // 2 + 2
        cx = random.randint(margin, self.img_size - margin - 1)
        cy = random.randint(margin, self.img_size - margin - 1)
        brightness = random.randint(180, 255)
        img_np = self._generate_background()
        obj_type = random.choice(['circle', 'rectangle', 'blob'])

        if obj_type == 'circle':
            img_pil = Image.fromarray(img_np, mode='L')
            draw = ImageDraw.Draw(img_pil)
            self._draw_circle(draw, cx, cy, obj_size // 2, brightness)
            img_np = np.array(img_pil)

        elif obj_type == 'rectangle':
            img_pil = Image.fromarray(img_np, mode='L')
            draw = ImageDraw.Draw(img_pil)
            half_w = random.randint(obj_size // 3, obj_size // 2)
            half_h = random.randint(obj_size // 3, obj_size // 2)
            self._draw_rectangle(draw, cx, cy, half_w, half_h, brightness)
            img_np = np.array(img_pil)

        else:  
            img_np = self._draw_gaussian_blob(img_np, cx, cy,
                                               obj_size // 2, brightness)

        if random.random() < 0.3:
            img_pil = Image.fromarray(img_np.astype(np.uint8), mode='L')
            img_pil = img_pil.filter(ImageFilter.GaussianBlur(radius=1))
            img_np = np.array(img_pil)

        if random.random() < 0.2:
            noise_mask = np.random.random((self.img_size, self.img_size)) < 0.01
            img_np = np.where(noise_mask,
                              np.random.randint(100, 255, img_np.shape),
                              img_np).astype(np.uint8)
        heatmap = self._generate_heatmap(cx, cy)
        image_tensor = torch.from_numpy(img_np.astype(np.float32) / 255.0).unsqueeze(0)
        heatmap_tensor = torch.from_numpy(heatmap).unsqueeze(0)
        coords_tensor = torch.tensor([cx / self.img_size, cy / self.img_size],
                                      dtype=torch.float32)

        return image_tensor, heatmap_tensor, coords_tensor

class RealImageDataset(Dataset):
    def __init__(self, data_dir, img_size=128, hm_size=8, sigma=1.0):
        self.data_dir = data_dir
        self.img_size = img_size
        self.hm_size = hm_size
        self.sigma = sigma
        self.stride = img_size // hm_size

        # Load labels
        import csv
        self.samples = []
        labels_path = os.path.join(data_dir, 'labels.csv')

        if os.path.exists(labels_path):
            with open(labels_path, 'r') as f:
                reader = csv.reader(f)
                next(reader)  # skip header
                for row in reader:
                    img_name = row[0].strip()
                    cx = int(row[1])
                    cy = int(row[2])
                    self.samples.append((img_name, cx, cy))
        else:
            raise FileNotFoundError(f"Labels file not found: {labels_path}")

    def __len__(self):
        return len(self.samples)

    def _generate_heatmap(self, cx, cy):
        hm = np.zeros((self.hm_size, self.hm_size), dtype=np.float32)
        gx = cx / self.stride
        gy = cy / self.stride

        for row in range(self.hm_size):
            for col in range(self.hm_size):
                dist_sq = (col + 0.5 - gx) ** 2 + (row + 0.5 - gy) ** 2
                hm[row, col] = math.exp(-dist_sq / (2 * self.sigma ** 2))

        return hm

    def __getitem__(self, idx):
        img_name, cx, cy = self.samples[idx]
        img_path = os.path.join(self.data_dir, 'images', img_name)

        img = Image.open(img_path).convert('L')
        img = img.resize((self.img_size, self.img_size))
        img_np = np.array(img, dtype=np.float32) / 255.0

        heatmap = self._generate_heatmap(cx, cy)

        image_tensor = torch.from_numpy(img_np).unsqueeze(0)
        heatmap_tensor = torch.from_numpy(heatmap).unsqueeze(0)
        coords_tensor = torch.tensor([cx / self.img_size, cy / self.img_size],
                                      dtype=torch.float32)

        return image_tensor, heatmap_tensor, coords_tensor


def get_dataloaders(num_train=10000, num_val=1000, batch_size=32,
                    num_workers=4, seed=42):
    train_dataset = SyntheticDetectionDataset(
        num_samples=num_train,
        seed=seed
    )

    val_dataset = SyntheticDetectionDataset(
        num_samples=num_val,
        seed=seed + 1000 
    )

    train_loader = DataLoader(
        train_dataset,
        batch_size=batch_size,
        shuffle=True,
        num_workers=num_workers,
        pin_memory=True,
        drop_last=True
    )

    val_loader = DataLoader(
        val_dataset,
        batch_size=batch_size,
        shuffle=False,
        num_workers=num_workers,
        pin_memory=True
    )

    return train_loader, val_loader

# visualization
if __name__ == '__main__':
    import matplotlib
    matplotlib.use('Agg')  
    import matplotlib.pyplot as plt

    print("Generating test samples...")
    dataset = SyntheticDetectionDataset(num_samples=16, seed=42)
    fig, axes = plt.subplots(4, 4, figsize=(12, 12))
    fig.suptitle('Synthetic Training Samples', fontsize=14)

    for i in range(16):
        image, heatmap, coords = dataset[i]
        ax = axes[i // 4][i % 4]
        img_np = image.squeeze().numpy()
        hm_np = heatmap.squeeze().numpy()
        hm_upsampled = np.kron(hm_np, np.ones((16, 16)))
        ax.imshow(img_np, cmap='gray', vmin=0, vmax=1)
        ax.imshow(hm_upsampled, cmap='hot', alpha=0.3, vmin=0, vmax=1)
        cx = coords[0].item() * 128
        cy = coords[1].item() * 128
        ax.plot(cx, cy, 'g+', markersize=10, markeredgewidth=2)
        ax.set_title(f'({cx:.0f}, {cy:.0f})', fontsize=9)
        ax.axis('off')

    plt.tight_layout()
    plt.savefig('dataset_preview.png', dpi=100)
    print("Saved dataset_preview.png")
    print(f"\nDataset size: {len(dataset)}")
    img, hm, coords = dataset[0]
    print(f"Image shape:   {img.shape}")
    print(f"Heatmap shape: {hm.shape}")
    print(f"Coords shape:  {coords.shape}")
    print(f"Image range:   [{img.min():.3f}, {img.max():.3f}]")
    print(f"Heatmap range: [{hm.min():.3f}, {hm.max():.3f}]")

    train_loader, val_loader = get_dataloaders(
        num_train=100, num_val=20, batch_size=8, num_workers=0
    )
    print(f"\nTrain batches: {len(train_loader)}")
    print(f"Val batches:   {len(val_loader)}")
    batch_img, batch_hm, batch_coords = next(iter(train_loader))
    print(f"Batch image shape:   {batch_img.shape}")
    print(f"Batch heatmap shape: {batch_hm.shape}")
    print(f"Batch coords shape:  {batch_coords.shape}")