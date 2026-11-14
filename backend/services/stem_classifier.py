"""
PULSO In-App Multitrack Ingestion & Stem Classifier
Parses multitrack directories or ZIP archives directly on device without external web portals.
"""

import re
import os
import zipfile
import json
from typing import Dict, List, Any, Optional

STEM_CATEGORIES = {
    "click": {
        "pattern": r"(click|metronome|klick|metronomo|tempo)",
        "default_bus": 1,  # CUE / Aux
        "default_gain": 0.85,
        "color": "#9297a0"
    },
    "guide": {
        "pattern": r"(guide|cue|guia|slate|direcc|vox_cue)",
        "default_bus": 1,  # CUE / Aux
        "default_gain": 0.70,
        "color": "#f0a028"
    },
    "drums": {
        "pattern": r"(drum|bateria|perc|kick|snare|hihat|tom|cymb|loop_perc)",
        "default_bus": 0,  # Master
        "default_gain": 0.85,
        "color": "#ff4b33"
    },
    "bass": {
        "pattern": r"(bass|bajo|sub_bass|synth_bass)",
        "default_bus": 0,  # Master
        "default_gain": 0.80,
        "color": "#3ddc84"
    },
    "keys": {
        "pattern": r"(key|piano|teclado|rhodes|organ|synth|synth_lead|bell)",
        "default_bus": 0,  # Master
        "default_gain": 0.75,
        "color": "#4da6ff"
    },
    "pad": {
        "pattern": r"(pad|ambient|drone|atmos|shimmer|strings|cuerdas)",
        "default_bus": 0,  # Master
        "default_gain": 0.70,
        "color": "#b388ff"
    },
    "guitars": {
        "pattern": r"(gtr|guitar|eg|ag|electrica|acustica|lead_gtr|rhythm_gtr)",
        "default_bus": 0,  # Master
        "default_gain": 0.75,
        "color": "#ffbe55"
    },
    "vocals": {
        "pattern": r"(vox|lead_vox|bgv|vocal|coro|choir|harmony)",
        "default_bus": 0,  # Master
        "default_gain": 0.80,
        "color": "#ff79c6"
    }
}

AUDIO_EXTENSIONS = {".wav", ".aif", ".aiff", ".mp3", ".m4a", ".flac", ".ogg"}

def classify_stem_filename(filename: str) -> Dict[str, Any]:
    """Matches a filename against known multitrack naming conventions."""
    name_clean = os.path.splitext(os.path.basename(filename))[0].lower()

    for category, meta in STEM_CATEGORIES.items():
        if re.search(meta["pattern"], name_clean, re.IGNORECASE):
            return {
                "filename": filename,
                "category": category,
                "label": category.upper(),
                "bus": meta["default_bus"],
                "gain": meta["default_gain"],
                "color": meta["color"]
            }

    # Default fallback for custom or unclassified stems
    return {
        "filename": filename,
        "category": "other",
        "label": os.path.splitext(os.path.basename(filename))[0][:12].upper(),
        "bus": 0,  # Master
        "gain": 0.75,
        "color": "#c3c7cc"
    }

def inspect_multitrack_zip(zip_path: str, extract_to_dir: Optional[str] = None) -> Dict[str, Any]:
    """Scans and extracts multitrack stems from a ZIP file in-app."""
    if not os.path.exists(zip_path):
        raise FileNotFoundError(f"Multitrack archive not found: {zip_path}")

    stems = []
    metadata = {
        "archive_name": os.path.basename(zip_path),
        "detected_title": os.path.splitext(os.path.basename(zip_path))[0].replace("_", " ").title(),
        "bpm": 120.0,
        "key": "C",
        "stems": []
    }

    with zipfile.ZipFile(zip_path, 'r') as z:
        for file_info in z.infolist():
            ext = os.path.splitext(file_info.filename)[1].lower()
            if ext in AUDIO_EXTENSIONS and not file_info.filename.startswith("__MACOSX"):
                classification = classify_stem_filename(file_info.filename)
                metadata["stems"].append(classification)

                if extract_to_dir:
                    z.extract(file_info, extract_to_dir)

    # Sort stems logically: Click & Guide first, then rhythm, harmony, leads
    priority_order = ["click", "guide", "drums", "bass", "keys", "pad", "guitars", "vocals", "other"]
    metadata["stems"].sort(key=lambda s: priority_order.index(s["category"]) if s["category"] in priority_order else 99)

    return metadata

if __name__ == "__main__":
    test_files = [
        "01_Click_128bpm_4-4.wav",
        "02_Guide_Cues.wav",
        "03_Kick_Snare_Loop.wav",
        "04_Electric_Bass.wav",
        "05_Synth_Pads_Warm.wav",
        "06_Acoustic_Guitar.wav",
        "07_Lead_Gtr_Solo.wav",
        "08_Backing_Vocals.wav"
    ]
    print("Classifying Stems:")
    for f in test_files:
        res = classify_stem_filename(f)
        print(f"  {f:<30} -> {res['category'].upper():<10} (Bus: {'CUE' if res['bus']==1 else 'MASTER'})")
