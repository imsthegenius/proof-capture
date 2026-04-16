# Test Image Sources

All images sourced from [Unsplash](https://unsplash.com) under the [Unsplash License](https://unsplash.com/license) (free for commercial and non-commercial use, no attribution required).

## Image Provenance

| File | Unsplash Photo ID | Description |
|------|-------------------|-------------|
| `front_directional_good.jpg` | `photo-1606335543586` | Man in tank top/shorts, teal wall, directional light |
| `front_mirror_fair.jpg` | `photo-1584952449136` | Man flexing in gym mirror |
| `front_dim_poor.jpg` | `photo-1695976134833` | Shirtless man in very dark gym |
| `front_backlit_poor.jpg` | `photo-1543331044` | Person silhouetted on balcony |
| `front_window_poor.jpg` | `photo-1616386415069` | Person silhouetted against window panes |
| `side_stage_good.jpg` | `photo-1585258074413` | Side physique pose on stage |
| `side_gym_fair.jpg` | (retained from v1) | Man standing side view, dark gym |
| `side_mirror_fair.jpg` | `photo-1744551358229` | Man taking mirror selfie, side view |
| `back_studio_good.jpg` | `photo-1563427632003` | Back muscles pose, white studio background |
| `back_gym_poor.jpg` | `photo-1656785280286` | Back double bicep pose in gym |
| `back_backlit_poor.jpg` | (retained from v1) | Person from behind, strong backlight |

## Version History

- **v3 (2026-04-04)**: Trimmed to 11 images (5 front, 3 side, 3 back) to meet 3-5 per pose. Added backlit-window (`front_window_poor`) and back studio pose (`back_studio_good`). Removed redundant front images.
- **v2 (2026-04-04)**: Replaced gym action shots with standing progress photo representatives. Added `{pose}_{lighting}_{quality}` naming convention.
- **v1**: 13 images, mostly gym action shots (deadlifts, push-ups, dumbbell curls). Did not represent the Checkd use case.

## Current Role

This folder is validation-only. These images preserve known failure modes and
dataset contamination examples such as mirror selfies, stage poses, studio
backgrounds, and strong backlight silhouettes. They do not drive production
threshold calibration.
