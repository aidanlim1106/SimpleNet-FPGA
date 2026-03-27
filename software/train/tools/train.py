# After training completes:
#   1. Run quantize.py to convert to INT8
#   2. Run export_weights.py to generate .mem files
#   3. Load .mem files into FPGA BRAM

import os
import sys
import time
import argparse
import datetime
import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
from torch.optim.lr_scheduler import CosineAnnealingLR

from model import SimpleDetector
from dataset import get_dataloaders, SyntheticDetectionDataset


def parse_args():
    parser = argparse.ArgumentParser(description='Train Simple-Net detector')
    parser.add_argument('--epochs', type=int, default=30,
                        help='Number of training epochs (default: 30)')
    parser.add_argument('--batch', type=int, default=32,
                        help='Batch size (default: 32)')
    parser.add_argument('--lr', type=float, default=1e-3,
                        help='Initial learning rate (default: 1e-3)')
    parser.add_argument('--weight-decay', type=float, default=1e-4,
                        help='Weight decay / L2 regularization (default: 1e-4)')
    parser.add_argument('--num-train', type=int, default=10000,
                        help='Number of training samples (default: 10000)')
    parser.add_argument('--num-val', type=int, default=1000,
                        help='Number of validation samples (default: 1000)')
    parser.add_argument('--workers', type=int, default=4,
                        help='DataLoader workers (default: 4)')
    parser.add_argument('--seed', type=int, default=42,
                        help='Random seed (default: 42)')
    parser.add_argument('--resume', type=str, default=None,
                        help='Path to checkpoint to resume from')
    parser.add_argument('--save-dir', type=str, default='checkpoints',
                        help='Directory to save checkpoints (default: checkpoints)')
    parser.add_argument('--save-every', type=int, default=5,
                        help='Save checkpoint every N epochs (default: 5)')

    parser.add_argument('--no-cuda', action='store_true',
                        help='Disable CUDA even if available')
    parser.add_argument('--quiet', action='store_true',
                        help='Reduce output verbosity')

    return parser.parse_args()


class HeatmapLoss(nn.Module):
    """
    Combined loss for heatmap-based detection.
    Components:
        1. MSE Loss: pixel-wise heatmap accuracy
        2. Peak Loss: penalizes distance between predicted
           and ground-truth peak locations
    """

    def __init__(self, mse_weight=1.0, peak_weight=0.5):
        super().__init__()
        self.mse_weight = mse_weight
        self.peak_weight = peak_weight
        self.mse_loss = nn.MSELoss()

    def _get_peak_coords(self, heatmap):
        """
        Extract (x, y) coordinates of the peak in each heatmap.
        Uses soft-argmax for differentiability.
        
        Args:
            heatmap: (B, 1, H, W) tensor
            
        Returns:
            coords: (B, 2) tensor of (x, y) in [0, 1] range
        """
        B, C, H, W = heatmap.shape
        flat = heatmap.view(B, -1)
        weights = torch.softmax(flat * 10.0, dim=-1)  
        weights = weights.view(B, 1, H, W)
        grid_y = torch.linspace(0, 1, H, device=heatmap.device).view(1, 1, H, 1).expand(B, 1, H, W)
        grid_x = torch.linspace(0, 1, W, device=heatmap.device).view(1, 1, 1, W).expand(B, 1, H, W)
        pred_x = (weights * grid_x).sum(dim=[2, 3]) 
        pred_y = (weights * grid_y).sum(dim=[2, 3]) 

        return torch.cat([pred_x, pred_y], dim=1)  

    def forward(self, pred_heatmap, gt_heatmap, gt_coords=None):
        # MSE loss on full heatmap
        mse = self.mse_loss(pred_heatmap, gt_heatmap)
        # Peak location loss
        if gt_coords is not None and self.peak_weight > 0:
            pred_coords = self._get_peak_coords(pred_heatmap)
            peak = self.mse_loss(pred_coords, gt_coords)
        else:
            peak = torch.tensor(0.0, device=pred_heatmap.device)

        total = self.mse_weight * mse + self.peak_weight * peak

        return total, mse, peak


def compute_detection_accuracy(pred_heatmap, gt_coords, threshold_pixels=16):
    B = pred_heatmap.shape[0]

    flat = pred_heatmap.view(B, -1)
    max_idx = flat.argmax(dim=1)
    pred_y = (max_idx // 8).float() / 8.0 + 0.5 / 8.0
    pred_x = (max_idx % 8).float() / 8.0 + 0.5 / 8.0
    dx = (pred_x - gt_coords[:, 0]) * 128.0
    dy = (pred_y - gt_coords[:, 1]) * 128.0
    dist = torch.sqrt(dx ** 2 + dy ** 2)

    correct = (dist < threshold_pixels).float().sum()
    accuracy = correct / B

    return accuracy.item()


def train_one_epoch(model, loader, criterion, optimizer, device, epoch, quiet=False):
    """Train for one epoch."""
    model.train()

    total_loss = 0.0
    total_mse = 0.0
    total_peak = 0.0
    total_acc = 0.0
    num_batches = 0

    for batch_idx, (images, heatmaps, coords) in enumerate(loader):
        images = images.to(device)
        heatmaps = heatmaps.to(device)
        coords = coords.to(device)

        pred = model(images)
        loss, mse, peak = criterion(pred, heatmaps, coords)
        optimizer.zero_grad()
        loss.backward()

        torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=5.0)

        optimizer.step()
        acc = compute_detection_accuracy(pred.detach(), coords)
        total_loss += loss.item()
        total_mse += mse.item()
        total_peak += peak.item()
        total_acc += acc
        num_batches += 1

        if not quiet and batch_idx % 50 == 0:
            print(f'  Epoch {epoch} [{batch_idx}/{len(loader)}] '
                  f'Loss: {loss.item():.4f} '
                  f'MSE: {mse.item():.4f} '
                  f'Peak: {peak.item():.4f} '
                  f'Acc: {acc:.2%}')

    return {
        'loss': total_loss / num_batches,
        'mse': total_mse / num_batches,
        'peak': total_peak / num_batches,
        'accuracy': total_acc / num_batches
    }


@torch.no_grad()
def validate(model, loader, criterion, device):
    """Run validation."""
    model.eval()

    total_loss = 0.0
    total_mse = 0.0
    total_peak = 0.0
    total_acc = 0.0
    num_batches = 0

    for images, heatmaps, coords in loader:
        images = images.to(device)
        heatmaps = heatmaps.to(device)
        coords = coords.to(device)

        pred = model(images)
        loss, mse, peak = criterion(pred, heatmaps, coords)

        acc = compute_detection_accuracy(pred, coords)
        total_loss += loss.item()
        total_mse += mse.item()
        total_peak += peak.item()
        total_acc += acc
        num_batches += 1

    return {
        'loss': total_loss / num_batches,
        'mse': total_mse / num_batches,
        'peak': total_peak / num_batches,
        'accuracy': total_acc / num_batches
    }


def save_checkpoint(model, optimizer, scheduler, epoch, metrics, path):
    """Save training checkpoint."""
    checkpoint = {
        'epoch': epoch,
        'model_state_dict': model.state_dict(),
        'optimizer_state_dict': optimizer.state_dict(),
        'scheduler_state_dict': scheduler.state_dict(),
        'metrics': metrics
    }
    torch.save(checkpoint, path)


def load_checkpoint(path, model, optimizer=None, scheduler=None):
    """Load training checkpoint."""
    checkpoint = torch.load(path, map_location='cpu')
    model.load_state_dict(checkpoint['model_state_dict'])

    if optimizer is not None and 'optimizer_state_dict' in checkpoint:
        optimizer.load_state_dict(checkpoint['optimizer_state_dict'])

    if scheduler is not None and 'scheduler_state_dict' in checkpoint:
        scheduler.load_state_dict(checkpoint['scheduler_state_dict'])

    return checkpoint.get('epoch', 0), checkpoint.get('metrics', {})


def count_parameters(model):
    """Count trainable parameters."""
    return sum(p.numel() for p in model.parameters() if p.requires_grad)


def main():
    args = parse_args()

    # setup
    timestamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    print("=" * 60)
    print("  Simple-Net Training")
    print(f"  {timestamp}")
    print("=" * 60)

    torch.manual_seed(args.seed)
    np.random.seed(args.seed)

    if args.no_cuda or not torch.cuda.is_available():
        device = torch.device('cpu')
    else:
        device = torch.device('cuda')
    print(f"Device: {device}")

    os.makedirs(args.save_dir, exist_ok=True)

    model = SimpleDetector().to(device)
    print(f"\nModel: SimpleDetector")
    print(f"Parameters: {count_parameters(model):,}")
    print(f"Architecture:")
    print(f"  Conv1: 1→4,   3×3, stride 2  (128→64)")
    print(f"  Conv2: 4→8,   3×3, stride 2  (64→32)")
    print(f"  Conv3: 8→16,  3×3, stride 2  (32→16)")
    print(f"  Conv4: 16→1,  3×3, stride 2  (16→8)")

    print(f"\nDataset:")
    print(f"  Training samples:   {args.num_train}")
    print(f"  Validation samples: {args.num_val}")
    print(f"  Batch size:         {args.batch}")

    train_loader, val_loader = get_dataloaders(
        num_train=args.num_train,
        num_val=args.num_val,
        batch_size=args.batch,
        num_workers=args.workers,
        seed=args.seed
    )

    criterion = HeatmapLoss(mse_weight=1.0, peak_weight=0.5)

    optimizer = optim.AdamW(
        model.parameters(),
        lr=args.lr,
        weight_decay=args.weight_decay
    )

    scheduler = CosineAnnealingLR(
        optimizer,
        T_max=args.epochs,
        eta_min=args.lr * 0.01  # min LR = 1% of initial
    )

    start_epoch = 0
    best_val_acc = 0.0

    if args.resume:
        print(f"\nResuming from: {args.resume}")
        start_epoch, prev_metrics = load_checkpoint(
            args.resume, model, optimizer, scheduler
        )
        start_epoch += 1  
        best_val_acc = prev_metrics.get('val_accuracy', 0.0)
        print(f"  Resumed at epoch {start_epoch}, best val acc: {best_val_acc:.2%}")

    print(f"\nTraining for {args.epochs - start_epoch} epochs...")
    print(f"  LR: {args.lr}, Weight Decay: {args.weight_decay}")
    print("-" * 60)

    for epoch in range(start_epoch, args.epochs):
        epoch_start = time.time()

        train_metrics = train_one_epoch(
            model, train_loader, criterion, optimizer, device,
            epoch, quiet=args.quiet
        )

        val_metrics = validate(model, val_loader, criterion, device)
        scheduler.step()
        current_lr = optimizer.param_groups[0]['lr']

        epoch_time = time.time() - epoch_start

        print(f'Epoch {epoch:3d}/{args.epochs} ({epoch_time:.1f}s) | '
              f'LR: {current_lr:.6f} | '
              f'Train Loss: {train_metrics["loss"]:.4f} Acc: {train_metrics["accuracy"]:.2%} | '
              f'Val Loss: {val_metrics["loss"]:.4f} Acc: {val_metrics["accuracy"]:.2%}')

        is_best = val_metrics['accuracy'] > best_val_acc
        if is_best:
            best_val_acc = val_metrics['accuracy']
            best_path = os.path.join(args.save_dir, 'best_model.pth')
            save_checkpoint(model, optimizer, scheduler, epoch,
                          {'val_accuracy': best_val_acc, **val_metrics}, best_path)
            print(f'  ★ New best model saved! Val Acc: {best_val_acc:.2%}')

        if (epoch + 1) % args.save_every == 0:
            ckpt_path = os.path.join(args.save_dir, f'checkpoint_epoch{epoch:03d}.pth')
            save_checkpoint(model, optimizer, scheduler, epoch,
                          {**train_metrics, **val_metrics}, ckpt_path)

    final_path = os.path.join(args.save_dir, 'final_model.pth')
    torch.save(model.state_dict(), final_path)
    print(f"\nFinal model saved: {final_path}")

    standard_path = 'trained_model.pth'
    torch.save(model.state_dict(), standard_path)
    print(f"Copied to: {standard_path}")

    print("\n" + "=" * 60)
    print("  Training Complete!")
    print(f"  Best validation accuracy: {best_val_acc:.2%}")
    print(f"  Final model: {final_path}")
    print(f"\n  Next steps:")
    print(f"    1. python quantize.py        # Convert to INT8")
    print(f"    2. python export_weights.py  # Generate .mem files")
    print(f"    3. Load .mem into FPGA BRAM")
    print("=" * 60)


if __name__ == '__main__':
    main()