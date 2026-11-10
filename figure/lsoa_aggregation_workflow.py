"""Generate the illustrative NDVI-to-LSOA aggregation workflow figure.

The raster values are synthetic and are used only to illustrate the diagram;
this script does not process source NDVI data.
"""

from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.patches import Rectangle


OUTPUT_PATH = Path(__file__).with_name("lsoa_aggregation_workflow.png")
POLYGONS = (
    (0, 0, 5, 2.5, "01"),
    (0, 2.5, 5, 2.5, "02"),
    (5, 0, 5, 5, "03"),
    (0, 5, 5, 5, "04"),
    (5, 5, 5, 5, "05"),
)


def style_axes(ax):
    ax.set_xlim(-0.5, 10.5)
    ax.set_ylim(10.5, -0.5)
    ax.set_xticks((0, 5, 10))
    ax.set_yticks((0, 5, 10))
    ax.set_xlabel("Longitude", fontsize=14)
    ax.set_ylabel("Latitude", fontsize=14)
    ax.tick_params(labelsize=12)
    ax.set_aspect("equal")


def add_polygons(ax, facecolors, edgecolor, linewidth, show_labels=True):
    for (x, y, width, height, label), facecolor in zip(POLYGONS, facecolors):
        ax.add_patch(
            Rectangle(
                (x, y),
                width,
                height,
                facecolor=facecolor,
                edgecolor=edgecolor,
                linewidth=linewidth,
            )
        )
        if show_labels:
            ax.text(
                x + width / 2,
                y + height / 2,
                label,
                color="darkred",
                fontsize=15,
                fontweight="bold",
                ha="center",
                va="center",
            )


def main():
    rng = np.random.default_rng(2021)
    ndvi = rng.uniform(0, 1, size=(10, 10))

    fig = plt.figure(figsize=(12.8, 14.6), facecolor="white")
    fig.suptitle(
        "Area-Weighted Raster Aggregation Workflow\n"
        "NDVI to 2021 LSOA Boundaries",
        fontsize=23,
        fontweight="bold",
        y=0.995,
        linespacing=1.1,
    )

    axes = (
        fig.add_axes((0.073, 0.53, 0.41, 0.36)),
        fig.add_axes((0.573, 0.53, 0.41, 0.36)),
        fig.add_axes((0.073, 0.058, 0.41, 0.36)),
        fig.add_axes((0.573, 0.058, 0.41, 0.36)),
    )
    titles = (
        "(1) Raw NDVI Raster\n(0.05° resolution)",
        "(2) Target: 2021 LSOA Boundaries\n(33,755 areas in England)",
        "(3) Aggregation Process\n(Raster + LSOA Overlay)",
        "(4) Final: NDVI Aggregated Values\n(One per LSOA 2021)",
    )
    for ax, title in zip(axes, titles):
        ax.set_title(title, fontsize=17, fontweight="bold", pad=14)
        style_axes(ax)

    edges = np.arange(11)
    axes[0].pcolormesh(
        edges,
        edges,
        ndvi,
        cmap="RdYlGn",
        vmin=0,
        vmax=1,
        edgecolors=(1, 1, 1, 0.25),
        linewidth=0.25,
    )

    pastel_colors = ("#fff1f1", "#f0f6ff", "#f0fff0", "#fffaf0", "#f7f0ff")
    add_polygons(axes[1], pastel_colors, edgecolor="#a94b4b", linewidth=2.2)

    axes[2].pcolormesh(
        edges,
        edges,
        ndvi,
        cmap="RdYlGn",
        vmin=0,
        vmax=1,
        edgecolors=(0.5, 0.5, 0.5, 0.35),
        linewidth=0.25,
    )
    overlay_colors = ("none",) * len(POLYGONS)
    add_polygons(
        axes[2],
        overlay_colors,
        edgecolor="darkred",
        linewidth=2.7,
        show_labels=False,
    )
    axes[2].grid(True, linestyle=":", linewidth=0.5, color="gray", alpha=0.5)

    result_colors = ("#63d69a", "#63c890", "#5da582", "#58b8a8", "#58b8a8")
    add_polygons(
        axes[3],
        result_colors,
        edgecolor="#a94b4b",
        linewidth=2.2,
        show_labels=False,
    )
    for (x, y, width, height, _), value in zip(
        POLYGONS, ("0.65", "0.60", "0.60", "0.69", "0.60")
    ):
        axes[3].text(
            x + width / 2,
            y + height / 2,
            value,
            color="white",
            fontsize=15,
            fontweight="bold",
            ha="center",
            va="center",
        )

    fig.savefig(OUTPUT_PATH, dpi=100, facecolor="white")
    plt.close(fig)
    print(f"Saved {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
