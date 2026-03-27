import torch
import numpy as np
from torch.utils.data import Dataset


class SyntheticDetectionDataset(Dataset):
    def __init__(self, num_samples=10000, img_size=128, seed=42):
        self.num_samples = num_samples
        self.img_size = img_size
        self.rng = np.random.RandomState(seed)

        # Pre-generate all samples for reproducibility
        self.samples = []
        for _ in range(num_samples):
            self.samples.append(self._generate_sample())

    def _generate_sample(self):
        img = np.zeros((self.img_size, self.img_size), dtype=np.float32)

        # Random rectangle size (20–50 pixels)
        w = self.rng.randint(20, 50)
        h = self.rng.randint(20, 50)

        # Random position (fully within image)
        x = self.rng.randint(0, self.img_size - w)
        y = self.rng.randint(0, self.img_size - h)

        # Draw white rectangle with slight noise
        brightness = self.rng.uniform(0.7, 1.0)
        img[y:y+h, x:x+w] = brightness

        # Add background noise
        noise = self.rng.normal(0, 0.05, img.shape).astype(np.float32)
        img = np.clip(img + noise, 0, 1)

        # Object center in image coordinates
        cx = x + w // 2
        cy = y + h // 2

        # Create 8×8 heatmap with Gaussian blob at center
        heatmap = np.zeros((8, 8), dtype=np.float32)
        hm_x = cx * 8 // self.img_size  # Scale to heatmap coords
        hm_y = cy * 8 // self.img_size

        # Place Gaussian
        for hy in range(8):
            for hx in range(8):
                dist_sq = (hx - hm_x) ** 2 + (hy - hm_y) ** 2
                heatmap[hy, hx] = np.exp(-dist_sq / 2.0)

        # Convert to tensors
        img_tensor = torch.from_numpy(img).unsqueeze(0)      # (1, 128, 128)
        hm_tensor = torch.from_numpy(heatmap).unsqueeze(0)   # (1, 8, 8)

        return img_tensor, hm_tensor

    def __len__(self):
        return self.num_samples

    def __getitem__(self, idx):
        return self.samples[idx]