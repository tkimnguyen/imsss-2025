---
myst:
  html_meta:
    "description": "How to size and position images in pages on new.imsss.net"
    "property=og:description": "How to size and position images in pages on new.imsss.net"
    "property=og:title": "Size and position images on a page"
    "keywords": "Plone, IMSSS 2025, Volto, image block, alignment, size, editors"
---

# Size and position images on a page

This guide is for people editing pages on new.imsss.net.
It explains how the image block's settings work with the site's theme, and how to lay out a page of portraits, such as the Current Council Members page.

## Alignment decides which size control you can use

Select an image in a page you're editing.
The {guilabel}`Block` tab on the right shows its settings.
Which ones you can change depends on {guilabel}`Alignment`.

Centered
:   The image sits on its own line.
    {guilabel}`Block width` sets how wide it is.
    The {guilabel}`Image size` buttons {guilabel}`S`, {guilabel}`M`, and {guilabel}`L` are greyed out.

Left or right
:   The image floats at the side, and the text that follows wraps around it.
    The {guilabel}`Image size` buttons set how big it is.
    {guilabel}`Block width` is greyed out.

The theme disables one control or the other, so it isn't a fault when the size buttons are inactive.
To use {guilabel}`S`, {guilabel}`M`, or {guilabel}`L`, first set the alignment to left or right.

## Lay out a list of people with photos

For each person, add the blocks in this order:

1.  A heading with the person's name.
2.  An image block with their photo, aligned left or right.
3.  One or more text blocks with their description and links.

Alternating left and right alignment from one person to the next makes a long page easier to scan.

The site's theme starts every heading below any floating image above it.
So a tall photo never pushes the next person's name up beside it, even when the description is shorter than the photo.
This works for both heading sizes in the text toolbar: {guilabel}`H` for section titles such as "Councilors," and {guilabel}`h` for each person's name.

```{tip}
If text appears beside the wrong photo, check that each person's name is a heading, not bold text in a normal paragraph.
Only headings start below a floating image.
```

## Choose a size

- {guilabel}`M` suits most portraits next to a short description.
- {guilabel}`L` makes the photo take about half the width of the text column, which leaves little room for text beside it.
- Use the same size for everyone in a list, so the page looks even.

Upload photos with similar proportions, for example all in portrait orientation, so that they line up.
