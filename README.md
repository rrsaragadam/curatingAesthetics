# Wardrobe

A native macOS app for curating your closet: photograph your clothes and shoes,
let the app lift each piece off its background, and mix pieces into outfits.

- **Closet**: every piece on a clean card, a "closet by color" strip you can
  click to filter, category chips, search, favorites, and an "idle" flag on
  pieces you haven't worn in a while. The side panel shows texture, material,
  size, care, wear count and the outfits a piece is in.
- **Add photos**: pick or drop photos; Apple Vision removes the background on
  device, trims the cut-out, picks the main color and guesses the category.
- **Add from link**: paste a product page. Wardrobe reads the store's product
  data (schema.org JSON-LD, Open Graph, Shopify's product JSON) for the photo,
  sizes, material and care, removes the photo's background, and guesses the
  fabric so outfits can account for texture.
- **Outfit builder**: flip through each slot on a linen board, lock what you
  love and shuffle the rest (⌘R). The "This look" panel shows the palette with
  each piece's texture and notes on the texture and color mix. Save to the
  lookbook (⌘S).
- **Lookbook**: saved outfits with a "This week" strip. "Worn today" logs the
  look and bumps every piece's wear count. Rate looks with stars, filter by
  occasion, and double-click a look to reopen it in the builder.

Everything is stored locally in `~/Library/Application Support/Wardrobe/`
(`wardrobe.json` plus cut-out PNGs in `Images/`). Nothing leaves your Mac
except the request to a product page you paste.

## Build and run

Requires macOS 14 Sonoma or later and Xcode 15 or later.

1. Open `Package.swift` in Xcode (File › Open, or `xed .` in this folder).
2. Pick the **Wardrobe** scheme and **My Mac** as the destination.
3. Press ⌘R.

From Terminal you can also run `swift run`.

On first launch the closet is empty. Use **Explore with a sample closet first**
to load illustrated sample pieces and looks; remove them later from
Wardrobe › Settings.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘N | Add photos |
| ⌘L | Add from link |
| ⌘1 / ⌘2 / ⌘3 | Closet / Outfit builder / Lookbook |
| ⌘R | Shuffle unlocked slots (builder) |
| ⌘S | Save look (builder) |

## Code map

```
Sources/Wardrobe/
  App/          App entry, window, navigation state, menu commands, settings
  Models/       ClothingItem, Outfit, Fabric (texture), color naming and families
  Store/        WardrobeStore (JSON + PNG persistence), sample closet
  Services/     ImageProcessor (Vision cut-outs), ProductImporter (links), Stylist hook
  Views/        Closet, Builder, Lookbook, shared theme and garment drawing
  Resources/    Bricolage Grotesque (SIL Open Font License)
```

## Stylist (later)

There's no AI stylist yet. `Services/Stylist.swift` defines the `Stylist`
protocol (outfit critique and closet gaps) and `StylistProvider.current`,
which returns `nil` for now. The sidebar card and the builder's "This look"
panel are where its answers are meant to appear.
