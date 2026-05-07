# filename: train.py
# course: cs 471
# authors: kaden campbell, lundon dotson, kevin davis

"""
train cnn character classifier on chars74k (englishfnt)

outputs:
    output/character_cnn.pt        pytorch checkpoint of best validation accuracy
    output/CharacterCNN.mlpackage  coreml model for ios app deployment
"""

import os

import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader, Subset
from torchvision import datasets, transforms

# paths relative to script (script can run from anywhere)
DATA_DIR = os.path.join(os.path.dirname(__file__), "data", "chars74k", "English", "Fnt")
MODEL_DIR = os.path.join(os.path.dirname(__file__), "output")
CHECKPOINT_PATH = os.path.join(MODEL_DIR, "character_cnn.pt")
COREML_PATH = os.path.join(MODEL_DIR, "CharacterCNN.mlpackage")

NUM_CLASSES = 62
IMG_SIZE = 28
SEED = 42

# imagefolder sorts Sample001 through Sample062 alphabetically
# so class index i corresponds to Sample{i+1:03d}:
#   0 through 9 are digits
#   10 through 35 are uppercase A through Z
#   36 through 61 are lowercase a through z
CLASS_LABELS = (
    [str(d) for d in range(10)]
    + [chr(ord("A") + i) for i in range(26)]
    + [chr(ord("a") + i) for i in range(26)]
)


class CharacterCNN(nn.Module):
    """28x28 grayscale to 62 class character classifier

    architecture:
        3 conv blocks (1, 32, 64, 128 channels) with maxpool reductions
        flatten then 2 fc layers with dropout regularization
        roughly 1.8m trainable parameters total
    """

    def __init__(self, num_classes=NUM_CLASSES):
        super().__init__()
        # convolutional feature extractor
        # progressive channel increase: 1, 32, 64, 128
        # spatial dimension reductions via maxpool noted inline
        self.features = nn.Sequential(
            nn.Conv2d(1, 32, kernel_size=3, padding=1),
            nn.ReLU(inplace=True),
            nn.MaxPool2d(2),                               # 28 reduces to 14
            nn.Conv2d(32, 64, kernel_size=3, padding=1),
            nn.ReLU(inplace=True),
            nn.MaxPool2d(2),                               # 14 reduces to 7
            nn.Conv2d(64, 128, kernel_size=3, padding=1),
            nn.ReLU(inplace=True),
        )
        # fully connected classifier head
        # dropout 0.3 on both fc layers to combat overfitting
        # (without dropout, train accuracy diverges from test by ~5%)
        self.classifier = nn.Sequential(
            nn.Flatten(),
            nn.Dropout(0.3),
            nn.Linear(128 * 7 * 7, 256),
            nn.ReLU(inplace=True),
            nn.Dropout(0.3),
            nn.Linear(256, num_classes),
        )

    def forward(self, x):
        return self.classifier(self.features(x))


def _train_transform():
    """training augmentation pipeline
    rotation and affine simulate natural camera tilt and small misalignments
    fill=255 means white padding when transforms create out of bounds regions
    """
    return transforms.Compose([
        transforms.Grayscale(num_output_channels=1),
        transforms.Resize((IMG_SIZE, IMG_SIZE)),
        transforms.RandomRotation(10, fill=255),
        transforms.RandomAffine(0, translate=(0.05, 0.05), scale=(0.9, 1.1), fill=255),
        transforms.ToTensor(),
    ])


def _eval_transform():
    """evaluation pipeline without augmentation
    keeps eval deterministic and aligned with deployment
    """
    return transforms.Compose([
        transforms.Grayscale(num_output_channels=1),
        transforms.Resize((IMG_SIZE, IMG_SIZE)),
        transforms.ToTensor(),
    ])


def get_dataloaders(batch_size=64, seed=SEED):
    """deterministic 80/20 train test split with augmentation only on train

    seed=42 ensures all evaluation scripts see identical test set
    (breakdown.py, evaluate.py, case_insensitive.py all rely on this)
    """
    if not os.path.isdir(DATA_DIR):
        raise FileNotFoundError(
            f"Dataset not found at {DATA_DIR}. Run download_dataset.py first."
        )

    # two parallel imagefolder views over same directory
    # one with augmentation (train) and one without (eval)
    # subsets share underlying samples but apply different transforms
    train_full = datasets.ImageFolder(DATA_DIR, transform=_train_transform())
    eval_full = datasets.ImageFolder(DATA_DIR, transform=_eval_transform())

    # 80/20 split
    n = len(train_full)
    n_test = n // 5
    n_train = n - n_test

    # generate deterministic permutation of indices
    # subset's first n_train are train, remaining are test
    g = torch.Generator().manual_seed(seed)
    perm = torch.randperm(n, generator=g).tolist()
    train_idx, test_idx = perm[:n_train], perm[n_train:]

    train_loader = DataLoader(
        Subset(train_full, train_idx),
        batch_size=batch_size, shuffle=True, num_workers=2,
    )
    test_loader = DataLoader(
        Subset(eval_full, test_idx),
        batch_size=batch_size, shuffle=False, num_workers=2,
    )
    return train_loader, test_loader, train_full.classes


def device():
    """pick best available compute device
    priority: apple metal performance shaders > cuda > cpu
    """
    if torch.backends.mps.is_available():
        return torch.device("mps")
    if torch.cuda.is_available():
        return torch.device("cuda")
    return torch.device("cpu")


def train(epochs=10, batch_size=64, lr=1e-3):
    """main training loop with per epoch validation and best checkpoint saving

    optimizer: adam (adaptive per parameter learning rate)
    loss: cross entropy (combines softmax with negative log likelihood)
    saves checkpoint whenever val accuracy improves
    exports best to coreml after final epoch
    """
    os.makedirs(MODEL_DIR, exist_ok=True)
    dev = device()
    print(f"Device: {dev}")

    train_loader, test_loader, _ = get_dataloaders(batch_size=batch_size)
    model = CharacterCNN().to(dev)
    optimizer = optim.Adam(model.parameters(), lr=lr)
    criterion = nn.CrossEntropyLoss()

    best_acc = 0.0
    for epoch in range(1, epochs + 1):
        # training pass: update weights on all training batches
        model.train()
        total_loss = 0.0
        n_seen = 0
        for imgs, labels in train_loader:
            imgs, labels = imgs.to(dev), labels.to(dev)
            optimizer.zero_grad()
            logits = model(imgs)
            loss = criterion(logits, labels)
            loss.backward()
            optimizer.step()
            # accumulate weighted by batch size to handle final smaller batch
            total_loss += loss.item() * imgs.size(0)
            n_seen += imgs.size(0)
        train_loss = total_loss / n_seen

        # validation pass: no gradient, no dropout, just inference
        model.eval()
        correct = 0
        total = 0
        with torch.no_grad():
            for imgs, labels in test_loader:
                imgs, labels = imgs.to(dev), labels.to(dev)
                preds = model(imgs).argmax(1)
                correct += (preds == labels).sum().item()
                total += labels.size(0)
        acc = correct / total

        # save checkpoint only if this epoch beat previous best
        # ensures final checkpoint is best ever seen, not just last epoch
        flag = ""
        if acc > best_acc:
            best_acc = acc
            torch.save(model.state_dict(), CHECKPOINT_PATH)
            flag = "  saved"
        print(f"Epoch {epoch:2d}/{epochs}  loss={train_loss:.4f}  val_acc={acc:.4f}{flag}")

    print(f"\nBest val accuracy: {best_acc:.4f}")
    print(f"Checkpoint: {CHECKPOINT_PATH}")

    # reload best weights from disk before coreml export
    # ensures exported model matches best checkpoint, not just last epoch's weights
    model.load_state_dict(torch.load(CHECKPOINT_PATH, map_location="cpu"))
    export_to_coreml(model.cpu(), COREML_PATH)


def export_to_coreml(model, output_path):
    """export trained pytorch model to coreml mlpackage for ios

    deferred import of coremltools because it pulls in heavy dependencies
    only needed at end of training (not during epoch loop)
    """
    import coremltools as ct

    model.eval()
    # dummy input matches expected production shape (batch=1, channels=1, 28, 28)
    # tracing captures graph; required for coreml conversion
    example = torch.rand(1, 1, IMG_SIZE, IMG_SIZE)
    traced = torch.jit.trace(model, example)

    # imagetype tells coreml to accept cvpixelbuffer at inference
    # scale=1/255 maps uint8 pixel range [0, 255] into [0, 1] expected by model
    # classifierconfig adds class labels so output is named (label, probabilities)
    # convert_to="mlprogram" picks newer ml program format (smaller, faster)
    mlmodel = ct.convert(
        traced,
        inputs=[ct.ImageType(
            name="image",
            shape=(1, 1, IMG_SIZE, IMG_SIZE),
            color_layout=ct.colorlayout.GRAYSCALE,
            scale=1.0 / 255.0,
        )],
        classifier_config=ct.ClassifierConfig(class_labels=CLASS_LABELS),
        convert_to="mlprogram",
    )
    mlmodel.short_description = "Chars74K Fnt 62-class character classifier"
    mlmodel.author = "CS 471 glassesocr"
    mlmodel.save(output_path)
    print(f"CoreML model: {output_path}")


if __name__ == "__main__":
    train()
