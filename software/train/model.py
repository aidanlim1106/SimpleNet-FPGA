import torch
import torch.nn as nn


class SimpleDetector(nn.Module):
    def __init__(self):
        super().__init__()

        # Layer 1: 128×128×1  → 64×64×4
        self.conv1 = nn.Conv2d(1, 4, kernel_size=3, stride=2, padding=1, bias=True)
        self.relu1 = nn.ReLU()

        # Layer 2: 64×64×4   → 32×32×8
        self.conv2 = nn.Conv2d(4, 8, kernel_size=3, stride=2, padding=1, bias=True)
        self.relu2 = nn.ReLU()

        # Layer 3: 32×32×8   → 16×16×16
        self.conv3 = nn.Conv2d(8, 16, kernel_size=3, stride=2, padding=1, bias=True)
        self.relu3 = nn.ReLU()

        # Layer 4: 16×16×16  → 8×8×1  (heatmap)
        self.conv4 = nn.Conv2d(16, 1, kernel_size=3, stride=2, padding=1, bias=True)
        # No ReLU on last layer — we want the raw heatmap

    def forward(self, x):
        """
        Args:
            x: (batch, 1, 128, 128) grayscale image, values 0.0–1.0
        Returns:
            heatmap: (batch, 1, 8, 8) detection heatmap
        """
        x = self.relu1(self.conv1(x))
        x = self.relu2(self.conv2(x))
        x = self.relu3(self.conv3(x))
        x = self.conv4(x)
        return x