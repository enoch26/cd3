---
name: figure-editing
description: 'Edit workflow figures and keep README captions consistent. Use when removing or rearranging panels, simplifying the NDVI aggregation example, changing figure titles, or updating diagram descriptions.'
---

# Editing workflow figures

## Repository context

- Read the [repository guidance](../../copilot-instructions.md) and the relevant
  section of the [README](../../../README.md) before making changes.
- README figures live in [figure/](../../../figure/). An image, its alt text,
  and its caption are separate surfaces that must stay consistent.
- The [aggregation diagram](../../../figure/lsoa_aggregation_workflow.png) uses
  NDVI as its example. Its four panels show the raw raster, target boundaries,
  raster/polygon overlay, and final LSOA values in reading order.
- These are illustrative exposure values, not independently estimated
  small-area measurements. Do not imply that editing a diagram implements a
  data-processing workflow.

## Procedure

1. Inspect the worktree and preserve existing changes. Read the caption and
   view the actual image; the caption may not describe every visible panel.
2. Locate a generating script or editable source before choosing an editing
   method. Prefer regenerating from source when available.
3. If only a PNG is available, check for local image-processing libraries.
   Pillow can crop and rearrange existing panels and redraw headings without
   recreating the underlying plots. A missing generator does not prevent
   editing the image.
4. When removing panels:
   - Remove their plot content and headings, not just caption references.
   - Reflow the remaining panels into a compact layout without empty slots.
   - Renumber panels consecutively in reading order.
   - Update the overall title when the example or scope changes.
5. Preserve retained plot content, values, axes, units, and legends. Inspect
   pixel dimensions and plot boundaries before cropping. Avoid hard-coded
   coordinates copied from a differently sized image.
6. Update the README alt text and caption to match the final panel count,
   numbering, subjects, and row layout. Leave unrelated documentation intact.
7. Save the actual repository image, then reopen it for visual inspection.

## Lessons from the NDVI simplification

- The original image contained six panels even though its alt text described
  five. Treat the image itself as evidence when identifying panels.
- Removing the original PM10 panels 2 and 6 left four NDVI-related panels.
  A 2-by-2 arrangement made the resulting workflow compact and readable.
- Cropping preserved the existing plots; redrawing titles removed the PM10
  references and allowed consistent numbering from 1 through 4.
- Pillow handled the PNG edits, and Matplotlib's font manager supplied a
  local font. Check availability before assuming either library is installed.

## Verification

- Open the saved PNG and confirm removed panels and obsolete titles are gone.
- Check that headings, tick labels, axes, and captions are not clipped and
  that text remains readable at the README display size.
- Verify that the PNG decodes successfully, for example with Pillow's
  `Image.verify()`, in addition to visually checking it.
- Compare the image with the README caption and alt text.
- Review the diff for unintended changes. Preserve existing line endings;
  for CRLF files, `git -c core.whitespace=cr-at-eol diff --check` avoids
  reporting carriage returns as trailing whitespace.
- Remove temporary editing helpers after checking the saved result.
