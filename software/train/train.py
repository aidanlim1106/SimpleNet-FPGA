import torch
import torch.nn as nn
from torch.utils.data import DataLoader
from model import SimpleDetector
from dataset import SyntheticDetectionDataset


def train():
    # ---- Config ----
    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    epochs = 50
    batch_size = 64
    lr = 0.001
    print(f"Training on: {device}")

    # ---- Data ----
    train_dataset = SyntheticDetectionDataset(num_samples=10000, seed=42)
    val_dataset = SyntheticDetectionDataset(num_samples=1000, seed=99)

    train_loader = DataLoader(train_dataset, batch_size=batch_size, shuffle=True)
    val_loader = DataLoader(val_dataset, batch_size=batch_size)

    # ---- Model ----
    model = SimpleDetector().to(device)
    optimizer = torch.optim.Adam(model.parameters(), lr=lr)
    criterion = nn.MSELoss()

    print(f"\nModel parameters: {sum(p.numel() for p in model.parameters()):,}")
    print(f"Training samples: {len(train_dataset):,}")
    print(f"Validation samples: {len(val_dataset):,}\n")

    # ---- Training loop ----
    best_val_loss = float('inf')

    for epoch in range(epochs):
        # Train
        model.train()
        train_loss = 0.0
        for images, heatmaps in train_loader:
            images = images.to(device)
            heatmaps = heatmaps.to(device)

            optimizer.zero_grad()
            output = model(images)
            loss = criterion(output, heatmaps)
            loss.backward()
            optimizer.step()
            train_loss += loss.item()

        train_loss /= len(train_loader)

        # Validate
        model.eval()
        val_loss = 0.0
        correct = 0
        total = 0

        with torch.no_grad():
            for images, heatmaps in val_loader:
                images = images.to(device)
                heatmaps = heatmaps.to(device)

                output = model(images)
                val_loss += criterion(output, heatmaps).item()

                # Check if predicted max position matches target
                pred_flat = output.view(output.size(0), -1)
                target_flat = heatmaps.view(heatmaps.size(0), -1)
                pred_pos = pred_flat.argmax(dim=1)
                target_pos = target_flat.argmax(dim=1)
                correct += (pred_pos == target_pos).sum().item()
                total += output.size(0)

        val_loss /= len(val_loader)
        accuracy = 100.0 * correct / total

        print(f"Epoch {epoch+1:3d}/{epochs} | "
              f"Train Loss: {train_loss:.4f} | "
              f"Val Loss: {val_loss:.4f} | "
              f"Location Acc: {accuracy:.1f}%")

        # Save best model
        if val_loss < best_val_loss:
            best_val_loss = val_loss
            torch.save(model.state_dict(), 'trained_model.pth')

    print(f"\nTraining complete! Best val loss: {best_val_loss:.4f}")
    print("Model saved to: trained_model.pth")
    print("Next step: run quantize.py")


if __name__ == '__main__':
    train()