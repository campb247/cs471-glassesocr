# filename: download_dataset.py
# course: cs 471
# authors: kaden campbell, lundon dotson, kevin davis

"""
download chars74k (englishfnt) dataset

fnt subset of chars74k contains 62,992 images across 62 classes
(0 through 9, A through Z, a through z) rendered from 1,016 different
computer fonts in 4 styles (normal, bold, italic, bold italic)
images are 128x128 png, black character on white background

folder layout after extraction:
    data/chars74k/English/Fnt/
        Sample001/   maps to digit '0'
        ...
        Sample010/   maps to digit '9'
        Sample011/   maps to 'A'
        ...
        Sample036/   maps to 'Z'
        Sample037/   maps to 'a'
        ...
        Sample062/   maps to 'z'

dataset source: https://info-ee.surrey.ac.uk/CVSSP/demos/chars74k/
direct download: https://info-ee.surrey.ac.uk/CVSSP/demos/chars74k/EnglishFnt.tgz

paper: de Campos, T. E., Babu, B. R., & Varma, M. (2009)
       "Character recognition in natural images" VISAPP 2009
"""

import os
import sys
import tarfile
import urllib.request

# all paths relative to this script's directory
# (so script can be run from anywhere; data lives next to source)
DATA_DIR = os.path.join(os.path.dirname(__file__), "data", "chars74k")
ARCHIVE_URL = "https://info-ee.surrey.ac.uk/CVSSP/demos/chars74k/EnglishFnt.tgz"
ARCHIVE_PATH = os.path.join(DATA_DIR, "EnglishFnt.tgz")
EXTRACTED_ROOT = os.path.join(DATA_DIR, "English", "Fnt")


def _download_with_progress(url, dest):
    """download url to dest with simple percentage progress bar"""

    def progress(block_num, block_size, total_size):
        # urllib hook fires per chunk; we render single line that overwrites itself
        downloaded = block_num * block_size
        if total_size > 0:
            pct = min(100, downloaded * 100 // total_size)
            mb = downloaded // (1024 * 1024)
            sys.stdout.write(f"\r  {pct:3d}%  ({mb} MB)")
            sys.stdout.flush()

    urllib.request.urlretrieve(url, dest, reporthook=progress)
    sys.stdout.write("\n")


def download_chars74k():
    """download and extract chars74k englishfnt if not already present"""
    os.makedirs(DATA_DIR, exist_ok=True)

    # skip if already extracted to avoid 50mb redundant download
    if os.path.isdir(EXTRACTED_ROOT):
        n = sum(len(files) for _, _, files in os.walk(EXTRACTED_ROOT))
        print(f"Already extracted at {EXTRACTED_ROOT} ({n} files).")
        return

    # download archive only if not already on disk
    # supports resuming after interrupted extract
    if not os.path.exists(ARCHIVE_PATH):
        print(f"Downloading {ARCHIVE_URL}")
        _download_with_progress(ARCHIVE_URL, ARCHIVE_PATH)
    else:
        print(f"Archive already present: {ARCHIVE_PATH}")

    print(f"Extracting to {DATA_DIR}")
    extractall_kwargs = {}
    # python 3.12+ requires explicit filter to avoid deprecationwarning
    # also future proofs against upcoming default filter change
    if sys.version_info >= (3, 12):
        extractall_kwargs["filter"] = "data"
    with tarfile.open(ARCHIVE_PATH, "r:gz") as tf:
        tf.extractall(DATA_DIR, **extractall_kwargs)

    # final sanity count: should be roughly 62,992
    n = sum(len(files) for _, _, files in os.walk(EXTRACTED_ROOT))
    print(f"Done. {n} images across 62 classes.")


if __name__ == "__main__":
    download_chars74k()
