#!/usr/bin/env python3
"""
Thumbnail & Palette Generator for Ambxst Wallpaper System
Generates thumbnails for video files, images, and GIFs using FFmpeg and ImageMagick.
Also generates a dynamic color palette (dominant colors) for each media file.
Uses only Python standard library + system tools (FFmpeg, ImageMagick).
"""

import json
import os
import subprocess
import sys
import threading
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import List, Optional, Tuple

# Supported extensions
VIDEO_EXTENSIONS = {".mp4", ".webm", ".mov", ".avi", ".mkv"}
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".tif", ".tiff", ".bmp"}
GIF_EXTENSIONS = {".gif"}

# Default thumbnail size
THUMBNAIL_SIZE = "140x140"

# Palette sample size (resize image to this square before counting colors)
PALETTE_SAMPLE_SIZE = 128
# Maximum number of colors in the palette
MAX_PALETTE_COLORS = 25


class ThumbnailGenerator:
    def __init__(
        self,
        config_path: str,
        cache_base_path: str,
        fallback_path: Optional[str] = None,
    ):
        self.config_path = Path(config_path)
        self.cache_base_path = Path(cache_base_path)
        self.fallback_path = Path(fallback_path).expanduser() if fallback_path else None
        self.wall_path: Optional[Path] = None
        self.thumbnails_dir: Optional[Path] = None
        self.palettes_dir: Optional[Path] = None
        self.files_to_process = []
        self.total_files = 0
        self.processed_count = 0
        self.lock = threading.Lock()

    def load_config(self) -> bool:
        """Load wallpaper configuration."""
        try:
            if not self.config_path.exists():
                print(f"ERROR: Config file not found: {self.config_path}")
                return False

            with open(self.config_path, "r") as f:
                config = json.load(f)

            wall_path = config.get("wallPath", "")
            if not wall_path:
                if self.fallback_path:
                    print(
                        f"ℹ️  wallPath not found in config, using fallback: {self.fallback_path}"
                    )
                    wall_path = str(self.fallback_path)
                else:
                    print("ERROR: wallPath not found in config")
                    return False

            self.wall_path = Path(wall_path).expanduser()
            if not self.wall_path.exists():
                print(f"ERROR: Wallpaper directory not found: {self.wall_path}")
                return False

            # Setup directories
            self.thumbnails_dir = self.cache_base_path / "thumbnails"
            self.thumbnails_dir.mkdir(parents=True, exist_ok=True)

            self.palettes_dir = self.cache_base_path / "palettes"
            self.palettes_dir.mkdir(parents=True, exist_ok=True)

            print(f"✓ Config loaded: {self.wall_path}")
            print(f"✓ Thumbnails cache: {self.thumbnails_dir}")
            print(f"✓ Palettes cache: {self.palettes_dir}")
            return True

        except Exception as e:
            print(f"ERROR loading config: {e}")
            return False

    def find_files(self) -> List[Path]:
        """Find all media files in wallpaper directory and subdirectories, excluding hidden folders."""
        files = []

        if self.wall_path is None:
            print("ERROR: wall_path not initialized")
            return []

        try:
            for file_path in self.wall_path.rglob("*"):
                if file_path.is_file() and not file_path.name.startswith("."):
                    # Check if any parent directory is hidden
                    if not any(
                        part.startswith(".")
                        for part in file_path.relative_to(self.wall_path).parts[:-1]
                    ):
                        ext = file_path.suffix.lower()
                        if (
                            ext in VIDEO_EXTENSIONS
                            or ext in IMAGE_EXTENSIONS
                            or ext in GIF_EXTENSIONS
                        ):
                            files.append(file_path)

            files.sort()
            print(f"✓ Found {len(files)} media files")
            return files

        except Exception as e:
            print(f"ERROR scanning directory: {e}")
            return []

    def get_thumbnail_path(self, file_path: Path) -> Path:
        """Get thumbnail path for a media file in the proxy structure."""
        if self.wall_path is None or self.thumbnails_dir is None:
            raise RuntimeError("Paths not initialized")

        try:
            relative_path = file_path.relative_to(self.wall_path)
        except ValueError:
            raise ValueError(f"File {file_path} is not within {self.wall_path}")

        thumbnail_name = file_path.name + ".jpg"
        thumbnail_path = self.thumbnails_dir / relative_path.parent / thumbnail_name
        return thumbnail_path

    def get_palette_path(self, file_path: Path) -> Path:
        """Get palette JSON path for a media file."""
        if self.wall_path is None or self.palettes_dir is None:
            raise RuntimeError("Paths not initialized")

        try:
            relative_path = file_path.relative_to(self.wall_path)
        except ValueError:
            raise ValueError(f"File {file_path} is not within {self.wall_path}")

        palette_name = file_path.name + ".json"
        palette_path = self.palettes_dir / relative_path.parent / palette_name
        return palette_path

    def needs_thumbnail(self, file_path: Path) -> bool:
        """Check if file needs thumbnail generation."""
        thumbnail_path = self.get_thumbnail_path(file_path)

        if not thumbnail_path.exists():
            return True

        try:
            file_mtime = file_path.stat().st_mtime
            thumbnail_mtime = thumbnail_path.stat().st_mtime
            return file_mtime > thumbnail_mtime
        except:
            return True

    def needs_palette(self, file_path: Path) -> bool:
        """Check if file needs palette generation."""
        palette_path = self.get_palette_path(file_path)

        if not palette_path.exists():
            return True

        try:
            file_mtime = file_path.stat().st_mtime
            palette_mtime = palette_path.stat().st_mtime
            return file_mtime > palette_mtime
        except:
            return True

    def generate_video_thumbnail(self, video_path: Path) -> Tuple[bool, str]:
        """Generate thumbnail for a video file using FFmpeg."""
        thumbnail_path = self.get_thumbnail_path(video_path)

        try:
            thumbnail_path.parent.mkdir(parents=True, exist_ok=True)

            cmd = [
                "ffmpeg",
                "-y",
                "-i",
                str(video_path),
                "-ss",
                "00:00:01",
                "-vframes",
                "1",
                "-vf",
                f"scale=140:140:force_original_aspect_ratio=increase,crop=140:140",
                "-q:v",
                "2",
                "-f",
                "image2",
                str(thumbnail_path),
            ]

            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30,
            )

            if result.returncode == 0 and thumbnail_path.exists():
                return True, "Success"
            else:
                error_msg = result.stderr.strip() if result.stderr else "Unknown error"
                return False, error_msg

        except subprocess.TimeoutExpired:
            return False, "Timeout"
        except Exception as e:
            return False, str(e)

    def generate_image_thumbnail(self, image_path: Path) -> Tuple[bool, str]:
        """Generate thumbnail for an image file using ImageMagick."""
        thumbnail_path = self.get_thumbnail_path(image_path)

        try:
            thumbnail_path.parent.mkdir(parents=True, exist_ok=True)

            cmd = [
                "convert",
                str(image_path),
                "-resize",
                "140x140^",
                "-gravity",
                "center",
                "-extent",
                "140x140",
                "-quality",
                "85",
                str(thumbnail_path),
            ]

            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=15,
            )

            if result.returncode == 0 and thumbnail_path.exists():
                return True, "Success"
            else:
                error_msg = result.stderr.strip() if result.stderr else "Unknown error"
                return False, error_msg

        except subprocess.TimeoutExpired:
            return False, "Timeout"
        except Exception as e:
            return False, str(e)

    def generate_gif_thumbnail(self, gif_path: Path) -> Tuple[bool, str]:
        """Generate thumbnail for a GIF file using FFmpeg."""
        thumbnail_path = self.get_thumbnail_path(gif_path)

        try:
            thumbnail_path.parent.mkdir(parents=True, exist_ok=True)

            cmd = [
                "ffmpeg",
                "-y",
                "-i",
                str(gif_path),
                "-vframes",
                "1",
                "-vf",
                f"scale=140:140:force_original_aspect_ratio=increase,crop=140:140",
                "-q:v",
                "2",
                "-f",
                "image2",
                str(thumbnail_path),
            ]

            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=15,
            )

            if result.returncode == 0 and thumbnail_path.exists():
                return True, "Success"
            else:
                error_msg = result.stderr.strip() if result.stderr else "Unknown error"
                return False, error_msg

        except subprocess.TimeoutExpired:
            return False, "Timeout"
        except Exception as e:
            return False, str(e)

    def generate_palette(self, file_path: Path) -> Tuple[bool, str]:
        """
        Generate a color palette (dominant colors) for a media file.
        Uses ImageMagick to create a small PPM image, then counts colors in pure Python.
        Returns (success, message).
        """
        palette_path = self.get_palette_path(file_path)

        try:
            palette_path.parent.mkdir(parents=True, exist_ok=True)

            # Step 1: Use ImageMagick to resize and convert to PPM (binary P6 format)
            # PPM is simple to parse without external libraries.
            # We'll request a sample size of PALETTE_SAMPLE_SIZE x PALETTE_SAMPLE_SIZE.
            cmd = [
                "convert",
                str(file_path),
                "-resize",
                f"{PALETTE_SAMPLE_SIZE}x{PALETTE_SAMPLE_SIZE}^",
                "-gravity",
                "center",
                "-extent",
                f"{PALETTE_SAMPLE_SIZE}x{PALETTE_SAMPLE_SIZE}",
                "-strip",           # Remove metadata
                "ppm:-",            # Output PPM to stdout
            ]

            result = subprocess.run(
                cmd,
                capture_output=True,
                timeout=20,
            )

            if result.returncode != 0:
                error_msg = result.stderr.decode("utf-8", errors="ignore").strip()
                return False, f"ImageMagick failed: {error_msg}"

            ppm_data = result.stdout

            # Step 2: Parse PPM P6 format
            # Format: "P6\n<width> <height>\n<maxval>\n<binary RGB data>"
            header_end = ppm_data.find(b"\n", 0, 100)  # first newline after magic
            if header_end == -1 or not ppm_data.startswith(b"P6"):
                return False, "Invalid PPM header (not P6)"

            # Find second newline (dimensions)
            dims_start = header_end + 1
            dims_end = ppm_data.find(b"\n", dims_start, dims_start + 30)
            if dims_end == -1:
                return False, "Invalid PPM dimensions"

            dims_line = ppm_data[dims_start:dims_end].decode("ascii")
            try:
                width_str, height_str = dims_line.split()
                width = int(width_str)
                height = int(height_str)
            except:
                return False, "Could not parse PPM dimensions"

            # Maxval line
            maxval_start = dims_end + 1
            maxval_end = ppm_data.find(b"\n", maxval_start, maxval_start + 10)
            if maxval_end == -1:
                return False, "Invalid PPM maxval"

            maxval_line = ppm_data[maxval_start:maxval_end].decode("ascii")
            try:
                maxval = int(maxval_line)
            except:
                return False, "Could not parse PPM maxval"

            data_start = maxval_end + 1
            expected_bytes = width * height * 3
            if len(ppm_data) - data_start < expected_bytes:
                return False, f"Incomplete PPM data: expected {expected_bytes}, got {len(ppm_data)-data_start}"

            # Step 3: Read RGB triples and count frequencies
            # We'll use a tuple (r,g,b) as key, but we can reduce bit depth to group similar colors.
            # For simplicity, we'll use the raw 8-bit per channel (after scaling if maxval != 255).
            pixel_data = ppm_data[data_start:data_start + expected_bytes]

            # If maxval is not 255, we need to scale values to 0-255 range
            scale = 255.0 / maxval if maxval != 255 else 1.0

            color_counter = Counter()
            idx = 0
            for _ in range(width * height):
                r = int(pixel_data[idx] * scale)
                g = int(pixel_data[idx+1] * scale)
                b = int(pixel_data[idx+2] * scale)
                idx += 3
                # Round to nearest integer and clamp
                color_counter[(r, g, b)] += 1

            # Step 4: Get most common colors up to MAX_PALETTE_COLORS
            most_common = color_counter.most_common(MAX_PALETTE_COLORS)
            palette_hex = []
            for (r, g, b), _ in most_common:
                hex_color = "#{:02x}{:02x}{:02x}".format(r, g, b)
                palette_hex.append(hex_color)

            # Step 5: Save as JSON
            palette_data = {
                "colors": palette_hex,
                "size": len(palette_hex),
            }
            with open(palette_path, "w") as f:
                json.dump(palette_data, f, indent=2)

            return True, f"Palette generated with {len(palette_hex)} colors"

        except subprocess.TimeoutExpired:
            return False, "Timeout"
        except Exception as e:
            return False, str(e)

    def generate_single_thumbnail(self, file_path: Path) -> Tuple[bool, str]:
        """Generate thumbnail for a single file based on its type."""
        try:
            ext = file_path.suffix.lower()
            if ext in VIDEO_EXTENSIONS:
                success, message = self.generate_video_thumbnail(file_path)
            elif ext in IMAGE_EXTENSIONS:
                success, message = self.generate_image_thumbnail(file_path)
            elif ext in GIF_EXTENSIONS:
                success, message = self.generate_gif_thumbnail(file_path)
            else:
                return False, f"Unknown file type: {ext}"

            # Update progress
            with self.lock:
                self.processed_count += 1
                progress = (self.processed_count / self.total_files) * 100
                status = "✓" if success else "✗"
                print(
                    f"[{self.processed_count}/{self.total_files}] {status} {file_path.name} ({progress:.1f}%)"
                )

            return success, message

        except Exception as e:
            return False, str(e)

    def process_files(self, max_workers: int = 4) -> None:
        """Process files with multithreading for both thumbnails and palettes."""
        all_files = self.files_to_process

        if not all_files:
            print("✓ All thumbnails are up to date")
            return

        print(f"⚡ Processing {len(all_files)} files with {max_workers} workers...")
        start_time = time.time()

        failed_files = []
        palette_failed = []

        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            # Submit thumbnail jobs
            future_to_file = {
                executor.submit(self.generate_single_thumbnail, file_path): file_path
                for file_path in all_files
            }

            # Also submit palette jobs (if needed)
            palette_futures = {}
            for file_path in all_files:
                if self.needs_palette(file_path):
                    future = executor.submit(self.generate_palette, file_path)
                    palette_futures[future] = file_path

            # Process thumbnail results
            for future in as_completed(future_to_file):
                file_path = future_to_file[future]
                try:
                    success, message = future.result()
                    if not success:
                        failed_files.append((file_path, message))
                except Exception as e:
                    failed_files.append((file_path, str(e)))

            # Process palette results
            for future in as_completed(palette_futures):
                file_path = palette_futures[future]
                try:
                    success, message = future.result()
                    if not success:
                        palette_failed.append((file_path, message))
                except Exception as e:
                    palette_failed.append((file_path, str(e)))

        elapsed = time.time() - start_time
        total_files = len(all_files)
        success_count = total_files - len(failed_files)

        print(f"\n🏁 Processing complete in {elapsed:.1f}s")
        print(f"✅ Thumbnails success: {success_count}/{total_files}")

        if failed_files:
            print(f"❌ Thumbnails failed: {len(failed_files)}")
            for file_path, error in failed_files[:3]:
                print(f"   • {file_path.name}: {error}")
            if len(failed_files) > 3:
                print(f"   ... and {len(failed_files) - 3} more")

        if palette_failed:
            print(f"⚠️  Palettes failed: {len(palette_failed)}")
            for file_path, error in palette_failed[:3]:
                print(f"   • {file_path.name}: {error}")
            if len(palette_failed) > 3:
                print(f"   ... and {len(palette_failed) - 3} more")

    def run(self) -> int:
        """Main execution function."""
        print("🖼️  Ambxst Thumbnail & Palette Generator")
        print("=" * 40)

        if not self.load_config():
            return 1

        files = self.find_files()
        if not files:
            print("ℹ️  No media files found")
            return 0

        # Filter files that need thumbnails OR palettes
        for file_path in files:
            if self.needs_thumbnail(file_path) or self.needs_palette(file_path):
                self.files_to_process.append(file_path)

        self.total_files = len(self.files_to_process)

        if self.total_files == 0:
            print("✓ All thumbnails and palettes are up to date")
            return 0

        print(f"📋 {self.total_files} files need processing (thumbnails or palettes)")

        max_workers = min(4, os.cpu_count() or 1, self.total_files)

        try:
            self.process_files(max_workers)
            print("🎉 Generation complete!")
            return 0
        except KeyboardInterrupt:
            print("\n⚠️  Interrupted by user")
            return 130
        except Exception as e:
            print(f"❌ Unexpected error: {e}")
            return 1


def main():
    """Entry point."""
    if len(sys.argv) < 3 or len(sys.argv) > 4:
        print(
            "Usage: python3 thumbgen.py <config_path> <cache_base_path> [fallback_wall_path]"
        )
        return 1

    config_path = sys.argv[1]
    cache_base_path = sys.argv[2]
    fallback_path = sys.argv[3] if len(sys.argv) == 4 else None

    generator = ThumbnailGenerator(config_path, cache_base_path, fallback_path)
    return generator.run()


if __name__ == "__main__":
    sys.exit(main())