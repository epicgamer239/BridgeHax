from __future__ import annotations

import argparse
from statistics import mean


def focal_length_px(known_height_m: float, known_distance_m: float, bbox_height_px: float) -> float:
    if known_height_m <= 0 or known_distance_m <= 0 or bbox_height_px <= 0:
        raise ValueError("All calibration inputs must be > 0.")
    return (known_distance_m * bbox_height_px) / known_height_m


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compute calibrated focal length for VisionBridge distance estimation."
    )
    parser.add_argument("--known-height-m", type=float, required=True, help="Real object height in meters.")
    parser.add_argument("--known-distance-m", type=float, required=True, help="Measured camera distance in meters.")
    parser.add_argument(
        "--bbox-heights-px",
        type=float,
        nargs="+",
        required=True,
        help="One or more measured bounding box heights in pixels.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    estimates = [
        focal_length_px(args.known_height_m, args.known_distance_m, h) for h in args.bbox_heights_px
    ]
    print(f"sample_estimates_px={', '.join(f'{v:.2f}' for v in estimates)}")
    print(f"recommended_focal_length_px={mean(estimates):.2f}")


if __name__ == "__main__":
    main()

