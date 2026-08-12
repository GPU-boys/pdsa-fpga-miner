import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

# -----------------------------------------------------------------------------
# Helper: draw a rounded node with title and body text
# -----------------------------------------------------------------------------
def draw_node(ax, x, y, width, height, title, body_lines,
              title_size=11, body_size=9,
              facecolor='white', edgecolor='black', linewidth=1.5):
    """Draw a rounded-rectangle taxonomy node."""
    box = FancyBboxPatch(
        (x - width / 2, y - height / 2), width, height,
        boxstyle="round,pad=0.08",
        facecolor=facecolor, edgecolor=edgecolor, linewidth=linewidth
    )
    ax.add_patch(box)

    # Title (bold, near top)
    ax.text(
        x, y + height / 2 - 0.20, title,
        ha='center', va='top', fontsize=title_size,
        fontweight='bold', color='black'
    )

    # Body text (left-aligned inside the box looks cleaner for multi-line)
    line_spacing = 0.26
    start_y = y + height / 2 - 0.50
    for i, line in enumerate(body_lines):
        ax.text(
            x, start_y - i * line_spacing, line,
            ha='center', va='top', fontsize=body_size,
            linespacing=1.15, color='black'
        )


# -----------------------------------------------------------------------------
# Helper: draw arrow from box edge to box edge
# -----------------------------------------------------------------------------
def draw_arrow(ax, x1, y1, w1, h1, x2, y2, w2, h2):
    """Draw an arrow between the edges of two boxes."""
    dx = x2 - x1
    dy = y2 - y1
    dist = (dx ** 2 + dy ** 2) ** 0.5
    if dist == 0:
        return

    # Start/end at box boundaries
    sx = x1 + (dx / dist) * (w1 / 2)
    sy = y1 + (dy / dist) * (h1 / 2)
    ex = x2 - (dx / dist) * (w2 / 2)
    ey = y2 - (dy / dist) * (h2 / 2)

    arrow = FancyArrowPatch(
        (sx, sy), (ex, ey),
        arrowstyle='->', mutation_scale=14,
        linewidth=1.4, color='black'
    )
    ax.add_patch(arrow)


# -----------------------------------------------------------------------------
# Main figure setup
# -----------------------------------------------------------------------------
fig, ax = plt.subplots(figsize=(16, 12))
ax.set_xlim(0, 16)
ax.set_ylim(0, 12)
ax.axis('off')

# -----------------------------------------------------------------------------
# Central hub
# -----------------------------------------------------------------------------
cx, cy = 8.0, 6.0
cw, ch = 3.0, 0.9
draw_node(ax, cx, cy, cw, ch,
          'Multi-Algorithm PoW\\nMining Accelerators',
          [], title_size=12)

# -----------------------------------------------------------------------------
# Peripheral nodes: (x, y, w, h, title, [body lines], facecolor, linewidth)
# -----------------------------------------------------------------------------
nodes = [
    # --- ASIC (Top) ---
    (
        8.0, 10.3, 4.0, 1.9,
        'ASIC: Fixed Silicon [[13]]',
        [
            'Architecture: Custom-cell ASIC',
            'Performance: >100 TH/s, ~3,000 W',
            'Efficiency: >10,000 Mhash/s/W',
            'Observation: Permanently locked to a',
            'single algorithm; no runtime switch'
        ],
        'white', 1.5
    ),

    # --- GPU (Upper Right) ---
    (
        13.3, 7.8, 4.2, 2.1,
        'GPU: General Purpose [[1]]',
        [
            'Architecture: SIMT (RTX 3080 / RTX 4090)',
            'Performance: 127 MH/s – 2.0 GH/s',
            'Power: 230–260 W per card',
            'Efficiency: 0.49–8.3 Mhash/s/W',
            'Observation: Software recompile only;',
            'no hardware-level runtime switch'
        ],
        'white', 1.5
    ),

    # --- THIS WORK (Lower Right) ---
    (
        11.0, 2.4, 4.4, 2.4,
        'This Work: PDSA + DPR',
        [
            'Architecture: DPR + hardware-resident',
            'scheduler on Xilinx Kria KV260',
            'Performance: 15.04 MH/s (SHA-256d)',
            '          4.0 MH/s (SHA-3-256)',
            'Efficiency: 12.18 / 1.58 Mhash/s/W',
            'Observation: Runtime switch in ~10.4 ms;',
            'generalizable RP interface'
        ],
        '#f0f0f0', 2.2   # Slightly shaded + thicker border to highlight
    ),

    # --- FPGA Fixed (Lower Left) ---
    (
        5.0, 2.4, 4.0, 1.9,
        'FPGA: Fixed Bitstream [[2]][[9]]',
        [
            'Architecture: Fixed bitstream (Virtex-7,',
            'compact FPGA processor)',
            'Performance: Up to 514.92 MH/s [[2]]',
            'Efficiency: Not reported',
            'Observation: Single algorithm per',
            'bitstream; no runtime switch'
        ],
        'white', 1.5
    ),

    # --- CPU / Embedded (Upper Left) ---
    (
        2.7, 7.8, 4.0, 1.9,
        'CPU: Embedded Core',
        [
            'Architecture: Cortex-A53 (same SoC)',
            'Performance: ~50 kH/s, ~2.0 W',
            'Efficiency: ~0.025 Mhash/s/W',
            'Observation: Software-only mining;',
            'Von Neumann bottleneck limits throughput'
        ],
        'white', 1.5
    ),
]

# Draw all peripheral nodes
for x, y, w, h, title, lines, fc, lw in nodes:
    draw_node(ax, x, y, w, h, title, lines, facecolor=fc, linewidth=lw)

# Draw connections to center
for x, y, w, h, title, lines, fc, lw in nodes:
    draw_arrow(ax, x, y, w, h, cx, cy, cw, ch)

# -----------------------------------------------------------------------------
# Save
# -----------------------------------------------------------------------------
plt.tight_layout()
plt.savefig(
    'mining_platform_comparison_taxonomy.png',
    dpi=300, bbox_inches='tight', facecolor='white', pad_inches=0.3
)
plt.show()