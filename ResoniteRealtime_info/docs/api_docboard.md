# ResoniteRealtime_docboard API Reference

## 概要
Package: ResoniteRealtime_docboard (https://github.com/transreal/ResoniteRealtime_docboard). Loaded automatically by ResoniteRealtime.wl after ResoniteRealtime_tablet.wl. Shares the `ResoniteRealtime`Private`` context and uses tablet parts (itXxx / icXxx). Encoding: UTF-8. Symbols are in context `ResoniteRealtime``.
Two features:
1. Template-less PDF viewer built only from Resonite components.
2. Thumbnail board that can be saved to the inventory and reused.

## 1. Document viewer (Mathematica PDF Viewer)
Used when the world has no standard-viewer template. The standard-viewer clone requires a template in the world, which is lost when the world is reopened, so a native viewer is built instead.
Structure:
- Mathematica PDF Viewer: Grabbable, AI_GeneratedContent
  - Document: StaticDocument (URL = served URL) -> DocumentPageTexture (PageIndex, 0-based) -> SpriteProvider; ValueField<int> Page (1-based, display); DocumentAssetMetadata (PageCount)
  - Backing: opaque back plate
  - Panel: Canvas with title, page image (UIX Image, PreserveAspect), buttons [<<] [<] n / N [>] [>>] [Close]
- Paging runs inside the world only: ButtonValueShift<int> / ButtonValueSet<int> move PageIndex and Page together and stop at the ends. n / N is a ValueTextFormatDriver<int>. Close is ButtonDestroy.
- Wolfram does not rasterize pages, so it is fast. Resonite does the rendering (same components as the standard viewer).
- Canvas is {1000, 1440}, scale 0.0006.
- Used automatically by ResoniteShowObject and by PDFs opened from a board when no standard-viewer template exists ($ResonitePDFMode = "Native").

### ResoniteDocViewer[file, opts]
Opens a PDF in Resonite's own document display (StaticDocument + DocumentPageTexture). No standard-viewer template needed. Paging and close work inside the world only.
→ Association (viewer info) or Failure
Options: "Title" -> Automatic (title text), "Position" -> Automatic (front right of the tablet), "Parent" -> "Root" (parent slot)

### ResoniteDocViewerRemove[root] → Null
Removes one document viewer. ResoniteDocViewerRemove[] removes all.

### $ResonitePDFLite
型: Boolean, 初期値: True
When the standard-viewer template is missing or cloning fails, open with ResoniteDocViewer. False: fall back to the Wolfram page-image panel.

## 2. Thumbnail board saved to the inventory
Requirements: the board can be saved and reused; it has a "Connect" button like the tablet; if ResoniteRealtime is loaded, PDFs open without the tablet (template built in). On connect, the world privacy and owner are checked first, and the board refuses to open if the proper privacy level (PL) is not reached.
- Strip images are imported with importTexture2DFile into Resonite assets (local://) and the StaticTexture2D URL is swapped (saving uploads to the cloud; an http URL would need Wolfram running).
- Rows (title / file / URI / sensitivity) and layout are stored as JSON in a ValueField<string> of child "Data". It is HMAC-SHA256 signed (key = $ResoniteBoardKeyFile, this PC only; see key ring below). If someone in the world edits file paths or sensitivity, the signature fails and the connection is refused (required, because Wolfram opens local files and shows them in the world). Signed string: line 1 = 64 hex chars signature, lines 2+ = JSON (v = 1, rows, layout, scale, builtLevel, built, title).
- Child "Flux": OnLoaded / OnDuplicate -> SetSlotActiveSelf(Content, False) -> SetSlotActiveSelf(Veil, True). A board taken out of the inventory or duplicated hides its grid (images and titles) until Wolfram verifies, showing only "Press Connect to display".
- "Connect" (Selected = -3) is noticed by the resident monitor, which takes over: reads the root at Depth 1 and Panel at Depth 1, verifies the signature, re-reads world info (privacy, host, owner), then shows only rows below the display limit. Cells at or above the limit stay covered by the veil and refuse to open. The veil is re-applied if the privacy level changes later.
- If the standard-viewer template is known, a clone is stored hidden as a child of the board (same as the tablet; it is saved with the board).
- A PDF opened from the board appears in front of the board's cells.
- Candidate boards are polled every 2 s ($idCandPollSeconds) without waiting; board named "SourceVault Thumbnails". Connection stages are logged (BoardLog, last 40 entries; see ResoniteTabletStatus[]["BoardLog"]).
- Status line shows elapsed time while checking (e.g. "Checking world privacy and owner… n s") and while opening a PDF ("Opening <title>… n s"). Check timeout 30 s ($idBoardCheckSeconds): if no world info arrives, the stricter limit applies.

### Boards made on another PC (key ring)
The key is per PC ($UserBaseDirectory), so a board made on another PC fails the signature on this PC.
- Key ring: each PC puts its own key at <SourceVault PrivateVault>/keys/resonite-board/<PC name>-<fingerprint>.key (synced by Dropbox between own PCs only). Verification tries own key -> key ring keys. Signing always uses own key (earlier boards still pass).
- If the board's PC has no key in the ring yet, rows are not trusted and only Eagle items are re-fetched: only rows with URI sv://object/eagle-<Id> are kept; file path is discarded (SourceVault resolves it from this PC's Eagle at open time); sensitivity = max(this PC's SourceVault value, the written value) (1.0 if no SourceVault). Other rows become unopenable cells (sensitivity 1.0). sv://file/ rows are not taken (sensitivity 0.0 could point to any file). If no row can be taken, the connection is refused as before.

### ResoniteBoardAdopt[root] → Null
Takes over a thumbnail board placed in the world from the inventory (same as the Connect button; needs the monitor tick). Verifies signature, re-reads world privacy and owner, then shows only cells below the display limit.

### ResoniteBoardDiagnose[root] → Association
Diagnoses a board whose Connect does not work (call from a notebook; waits for getSlot).
ResoniteBoardDiagnose[] finds boards directly under Root and inside containers and diagnoses all. If unreadable, "Reply" holds the raw reply.
Returns: name, parent, and State ValueField<int> value in the world (Connect press = -3), whether the monitor has it as candidate / adopting / connected, and recent log (BoardLog).

### $ResoniteBoardKeyFile
型: String, 初期値: FileNameJoin[{$UserBaseDirectory, "ApplicationData", "ResoniteRealtime", "board.key"}]
Key file (32 bytes, created if missing) for signing board row data. This PC only. Boards built on another PC pass only if their key is in $ResoniteBoardKeyRing.

### $ResoniteBoardKeyRing
型: String | Automatic | None, 初期値: Automatic
Folder shared among own PCs holding each PC's key as <PC name>-<fingerprint>.key. Verification tries own key -> ring keys. Automatic = <SourceVault PrivateVault>/keys/resonite-board (not used if SourceVault is absent). None: not used. A board from a PC with no key in the ring gets only its Eagle items (sv://object/eagle-) re-fetched from this PC's SourceVault.

## 3. Worker kernel
A resident subkernel moves heavy jobs out of the monitor tick. The tick is an interrupt-type evaluation; blocking it makes the FE show "dynamic evaluation abandoned" dialogs, which cannot be closed from VR.
Jobs: thumbnail strips (image load/stitch/JPEG; 289 items ~40 s), Eagle folder lists (3.5–11 s; rows and sensitivity built with this kernel's SourceVault), page counts of large PDFs (130 MB: 5–8 s).
- Launch via LinkLaunch (0.02 s); kernel is up in ~2 s (-subkernel, uses a subkernel seat).
- Definitions are sent once via Language`ExtendedFullDefinition (resent after package reload). Jobs are written as EvaluatePacket; the tick polls LinkReadyQ for ReturnPacket (no waiting).
- Results over 200000 bytes are written to a WXF temp file and only the file name is returned.
- Job timeout 600 s, start timeout 60 s. Expressions containing unbound Temporary variables are not sent.

### ResoniteTabletWorkerStatus[] → Association
Worker kernel state: <|"Phase", "Alive", "Queue", "Job", "SlowTicks" (stages of ticks over 1 s)|>. Clue when the FE hangs.

### ResoniteTabletWorkerStop[] → Null
Stops the worker kernel (restarted when the next job arrives).

### $ResoniteTabletWorker
型: Boolean, 初期値: True
Build thumbnail strips, Eagle folder lists and large-PDF page counts in the worker kernel. False: in this kernel (blocking inside the tick may trigger the FE dynamic-evaluation dialog).