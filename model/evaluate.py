# filename: evaluate.py
# course: cs 471
# authors: kaden campbell, lundon dotson, kevin davis

"""
evaluate trained character classifier on held out chars74k test split

outputs:
    output/confusion_matrix.png    row normalized confusion matrix heatmap
    output/sample_predictions.png  grid of test images with predicted vs true labels
    console: overall accuracy plus bottom 10 per class recall
"""

import os

import numpy as np
import torch
import matplotlib.pyplot as plt
import seaborn as sns

from train import (
    CLASS_LABELS,
    CHECKPOINT_PATH,
    CharacterCNN,
    MODEL_DIR,
    NUM_CLASSES,
    device,
    get_dataloaders,
)


def load_model(path=CHECKPOINT_PATH):
    """load trained charactercnn from saved checkpoint
    raises if no checkpoint exists (caller forgot to run train.py)
    """
    if not os.path.exists(path):
        raise FileNotFoundError(f"No checkpoint at {path}. Run train.py first.")
    model = CharacterCNN()
    model.load_state_dict(torch.load(path, map_location="cpu"))
    model.eval()
    return model


def _collect_predictions(model):
    """run model over entire test set, return preds and labels as numpy arrays"""
    dev = device()
    model = model.to(dev)
    _, test_loader, _ = get_dataloaders()

    # accumulate per batch then concatenate at end
    # avoids holding full dataset on gpu at once
    all_preds, all_labels = [], []
    with torch.no_grad():
        for imgs, labels in test_loader:
            imgs = imgs.to(dev)
            preds = model(imgs).argmax(1).cpu().numpy()
            all_preds.append(preds)
            all_labels.append(labels.numpy())
    return np.concatenate(all_preds), np.concatenate(all_labels)


def _confusion_matrix(labels, preds, n_classes=NUM_CLASSES):
    """build n_classes x n_classes confusion matrix from prediction arrays
    cm[true, pred] counts how often true class was predicted as pred class
    diagonal entries are correct predictions
    """
    cm = np.zeros((n_classes, n_classes), dtype=np.int64)
    for t, p in zip(labels, preds):
        cm[t, p] += 1
    return cm


def evaluate(model=None):
    """compute overall accuracy and identify worst performing classes
    prints summary to console and returns raw arrays for downstream plotting
    """
    if model is None:
        model = load_model()
    preds, labels = _collect_predictions(model)

    acc = (preds == labels).mean()
    print(f"Test accuracy: {acc:.4f}  ({(preds == labels).sum()}/{len(labels)})")

    # per class recall: diagonal divided by row sum
    # row sum is total true instances of that class
    # diagonal is correct predictions for that class
    cm = _confusion_matrix(labels, preds)
    per_class = cm.diagonal() / cm.sum(axis=1).clip(min=1)

    # sort ascending and take 10 worst classes
    # gives quick view of model's weakest spots for slide bullets
    worst = np.argsort(per_class)[:10]
    print("\nLowest per-class recall:")
    for i in worst:
        print(f"  {CLASS_LABELS[i]!r:>4}  {per_class[i]:.3f}  "
              f"({cm[i, i]}/{cm[i].sum()})")

    return preds, labels, cm


def plot_confusion_matrix(model=None, save_path=None):
    """render row normalized confusion matrix as heatmap
    row normalization shows recall per class (independent of class size)
    off diagonal hot spots reveal which class pairs get confused
    """
    if model is None:
        model = load_model()
    _, _, cm = evaluate(model)

    # divide each row by its sum to get per class recall in [0, 1]
    # clip(min=1) avoids divide by zero on empty classes (shouldn't happen but defensive)
    cm_norm = cm.astype(float) / cm.sum(axis=1, keepdims=True).clip(min=1)

    fig, ax = plt.subplots(figsize=(14, 12))
    sns.heatmap(
        cm_norm, ax=ax, cmap="Blues", vmin=0, vmax=1, square=True,
        xticklabels=CLASS_LABELS, yticklabels=CLASS_LABELS,
        cbar_kws={"label": "Recall"},
    )
    ax.set_xlabel("Predicted")
    ax.set_ylabel("True")
    ax.set_title("Chars74K confusion matrix (row normalized)")
    plt.tight_layout()

    if save_path is None:
        save_path = os.path.join(MODEL_DIR, "confusion_matrix.png")
    fig.savefig(save_path, dpi=150)
    plt.close(fig)
    print(f"Saved {save_path}")


def show_sample_predictions(model=None, num_samples=16, save_path=None):
    """render grid of test images with predicted versus true labels
    correct predictions in green, incorrect in red
    useful for slides showing concrete model behavior
    """
    if model is None:
        model = load_model()
    dev = device()
    model = model.to(dev)
    # reuse get_dataloaders with batch_size as num_samples for one iter
    _, test_loader, _ = get_dataloaders(batch_size=num_samples)

    imgs, labels = next(iter(test_loader))
    with torch.no_grad():
        preds = model(imgs.to(dev)).argmax(1).cpu()

    # 4 column grid; rows determined by num_samples
    cols = 4
    rows = (num_samples + cols - 1) // cols
    fig, axes = plt.subplots(rows, cols, figsize=(cols * 2, rows * 2))
    for i, ax in enumerate(axes.flat):
        if i >= num_samples:
            ax.axis("off")
            continue
        ax.imshow(imgs[i].squeeze().numpy(), cmap="gray")
        true_c, pred_c = CLASS_LABELS[labels[i]], CLASS_LABELS[preds[i]]
        ok = labels[i] == preds[i]
        ax.set_title(f"true={true_c}  pred={pred_c}",
                     color="green" if ok else "red", fontsize=9)
        ax.axis("off")
    plt.tight_layout()

    if save_path is None:
        save_path = os.path.join(MODEL_DIR, "sample_predictions.png")
    fig.savefig(save_path, dpi=150)
    plt.close(fig)
    print(f"Saved {save_path}")


if __name__ == "__main__":
    model = load_model()
    evaluate(model)
    plot_confusion_matrix(model)
    show_sample_predictions(model)
