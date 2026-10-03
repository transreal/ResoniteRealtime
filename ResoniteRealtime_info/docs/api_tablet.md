# ResoniteRealtime_tablet API Reference

## Overview
Context `ResoniteRealtime``. Auto-loaded by ResoniteRealtime.wl (https://github.com/transreal/ResoniteRealtime). It builds on the UIX helpers and `ResoniteAccessLevel` from ResoniteRealtime_chat (https://github.com/transreal/ResoniteRealtime_chat). Source: https://github.com/transreal/ResoniteRealtime_tablet

Runs ClaudeEval inside the Resonite world through a "tablet" gadget, using ResoniteLink (L2) only.
- ResoniteTablet[] builds the tablet: input field, Eval button, status line, approve/deny buttons, scrolling output, image viewer.
- Eval writes `ResoniteTabletTurn["..."]` as an Input cell into a dedicated notebook "Resonite Tablet" and evaluates it. This is the runtime-path ClaudeEval, the same as evaluating a ClaudeInput cell: proposed code runs, approval is requested, and a result cell is written.
- One ScheduledTask polls the runtime. When approval is pending, it shows the explanation and expression and enables the approve/deny buttons (they call claudecode's ClaudeRuntimeDecide). On completion or failure, it filters the new cells by privacy level, sends plain text to the output field, and sends rasterized images to the viewer.
- ResoniteShowObject[x] is the general API for showing SourceVault objects (image, PDF with paging, video, text, row list).
- ResoniteListGadget[rows] turns SourceVault core-function row lists (arXiv, Eagle, mail, ...) into a button list. The ▶ on a row shows its PDF, image or body in the viewer.

### Access level (display ceiling)
- `ResoniteAccessLevel[]` (chat side): in the owner's world, Private 1.0, Contacts 0.5, ContactsPlus/Public 0.25. If not the owner, always 0.25 (`$ResoniteWorldOwner`).
- Display rule: anything whose privacy level (cell, row or object PrivacyLevel) is >= the ceiling is NOT shown. Equality is also hidden. A non-numeric privacy level is fail-closed (treated as 1.0) and hidden. Violations return `Failure["PrivacyExceeded", ...]`.
- AccessLevel passed to the LLM is Min[ceiling, 0.5] (`$ResoniteTabletCloudMaxLevel`). It equals the ceiling only when "Model" names a local model.

### Design conventions
- Monitoring is one ScheduledTask. Inside a tick, ResoniteLink replies are never awaited. getSlot is sent with "Wait" -> False and matched by sourceMessageId on the next tick (two-phase polling).
- Writes use `Block[{$iLinkWaitDefault = False}, ...]` (fire and forget).
- The FrontEnd is touched only for turn-start cell write/eval and for rasterizing on completion.
- Messages go through ResoniteRealtimeAddSlot / AddComponent / UpdateComponent / UpdateSlot / GetSlot. Enums are `<|"$type" -> "enum", "value" -> "Name"|>`.
- Async contexts (`$CurrentTask` is a TaskObject, or a tablet turn is in progress) cannot wait for ResoniteLink replies. Gadget builders (ResoniteListGadget, ResoniteViewer, ResoniteColorToggleBox, ThumbnailGadget, ...) then reserve the build and return `<|"Deferred" -> True, "Id" -> id, "Via" -> "Tick"|"Notebook", ...|>`. Treat that as success; do not retry or report failure.
  - Build mode "Tick" (default when the monitor runs): the build is done inside the monitor tick. Phase 1 (Send) sends slots and components. Phase 2 (Wire) sends getSlot on the next tick and wires buttons from the reply (member IDs). Resend after 10 s, give up after 3 tries.
  - Build mode "Notebook": the build is evaluated as an Input cell `ResoniteTabletRunDeferred["id"]` in the tablet notebook (top-level evaluation can receive replies).
- Buttons are Button + ValueField<bool> + ButtonToggle. A press sets Value True, and WL reads it and resets it to False.
- In-world buttons are gated by owner presence ($ResoniteOwnerPresenceGate).

## Tablet lifecycle

### ResoniteTablet[opts]
Builds the tablet in the world, starts monitoring (when "Start" -> True), and removes any existing tablet first. Requires ResoniteLink (ResoniteRealtimeLinkConnect). Returns a Failure["NotConnected"] if not linked.
→ Association of IDs (Root, Panel, Viewer, Buttons, User, ...)
Options: "Placement" -> "User" ("User"|"World"), "Distance" -> 1.2, "Height" -> Automatic, "User" -> Automatic, "Position" -> {0, 1.3, 1.2}, "Parent" -> "Root", "Name" -> "Mathematica Tablet", "CanvasSize" -> {1000, 1500}, "PanelScale" -> 0.0006, "FontSize" -> 26, "Viewer" -> True (create the viewer board right of the panel), "ViewerSize" -> 1.2, "Notebook" -> Automatic (create the dedicated notebook; or give a NotebookObject), "NotebookVisible" -> True, "Model" -> Automatic (when a local model is given, the LLM gets up to the display ceiling), "Start" -> True, "PollInterval" -> 1.0
Structure: Root (Grabbable) > Panel (Canvas) > VLayout [Title, Input, ButtonRow (Eval/Clear/Cancel), Status, ApprovalRow (hidden until approval pending), Output (scrolling), ViewerBar (◀ n/N ▶ close)]; Viewer board beside the panel.

### ResoniteTabletStart[opts]
Starts the single ScheduledTask for button and runtime monitoring (tablet and list gadget).
Options: "PollInterval" -> 1.0 (seconds)

### ResoniteTabletStop[] → Null
Stops the monitoring task.

### ResoniteTabletTick[] → Null
Runs one monitoring cycle by hand (test/debug). getSlot is send-only, so replies are handled on the next call.

### ResoniteTabletEval[prompt_String]
Same as pressing Eval: starts ClaudeEval in the dedicated notebook and shows the result on the tablet. For testing from a notebook.

### ResoniteTabletTurn[prompt_String]
One tablet turn, written as an Input cell in the dedicated notebook (runtime-path ClaudeEval; PrivacySpec AccessLevel = Min[ceiling, 0.5]). Not for direct use.

### ResoniteTabletApprove[] → Null
Approves the pending proposal (same as the approve button).

### ResoniteTabletDeny[] → Null
Denies the pending proposal.

### ResoniteTabletCancel[] → Null
Stops the running turn.

### ResoniteTabletShow[text_String]
Puts the string in the output field.

### ResoniteTabletShow[expr]
Non-string expr is shown as an image in the viewer (via the ResoniteShowObject path).

### ResoniteTabletNoteTurnResult[res] → jobId | None
Inspects the return value of ResoniteTabletTurn. If it went to a ClaudeOrchestrator async job (`<|"OrchJobId" -> ...|>`), it is put under monitoring (completion is awaited via ClaudeOrchestrationStatus).

### ResoniteTabletMake3D[opts]
Turns Graphics3D (Plot3D etc.) in the previous turn's result into in-world 3D objects (the tablet's "3D生成" button; via ResoniteGraphics3D from ResoniteRealtime_mesh, https://github.com/transreal/ResoniteRealtime_mesh). Results above the display ceiling are not created.
→ List of ResoniteGraphics3D results
Options: same as ResoniteGraphics3D

### ResoniteTabletStatus[] → Association
State of tablet, monitoring, turn, viewer, lists. Keys include Gadget, Root, Task, Polling, Serve, Linked, LinkPort, Candidates, Adopted, AccessLevel, Owner, AccessMode, WorldInfo, WorldAccess, OwnerPresence, BoardLog, Turn, Viewer, PDFViewer, PDFViewers, Thumbs, NativeLog, ...

### ResoniteTabletRemove[] → Null
Removes the tablet (including its viewer) from the world and stops monitoring.

### ResoniteTabletAttach[ids_Association]
Takes over a tablet built by another kernel (the return value of ResoniteTablet).

### ResoniteTabletNotebook[] → NotebookObject | $Failed
Returns the dedicated tablet notebook, creating it if absent.

### ResoniteTabletLog[n_Integer:10] → List
Last n turn records `<|"Time","Prompt","Status","Seconds","Text","Pages"|>`.

### ResoniteTabletRegisterHeads[]
Registers the display APIs (ResoniteShowObject / ResoniteListGadget etc.) as NBAccess allowed heads (two layers: NBRegisterAllowedHeads + NBRegisterTrustedPackageHeads). Called automatically on load.

### ResoniteTabletRunDeferred[id_String]
Executes a reserved build (ResoniteListGadget etc.) as a notebook Input cell. Not for direct use.

### ResoniteTabletDeferred[] → Association
Ledger of reserved builds: id -> `<|Label, Status, Result, Time|>`.

## Resident monitoring and adoption

### ResoniteTabletServe[opts]
Starts resident monitoring. If no ResoniteLink, finds it with ResoniteRealtimeDiscover[] and connects (retry every 15 s). Scans Root's direct children for "Mathematica Tablet" (including ones spawned from inventory); when its "接続" (Connect) button is pressed, adopts it by name (ResoniteTabletAdopt). Started automatically on load in notebook sessions ($ResoniteTabletAutoServe).
Options: "PollInterval" -> 1.0, "Start" -> True
### ResoniteTabletServe[False]
Stops resident monitoring.

### ResoniteTabletFind[] → List
Tablets directly under Root: `{<|"Id","Name","Attached"|>, ...}`.

### ResoniteTabletAdopt[root]
Adopts a tablet existing in the world (e.g. from inventory; IDs are reassigned) by reading structure from slot names and component types, then starts monitoring.
### ResoniteTabletAdopt[]
Adopts the last found tablet.

### ResoniteTabletCleanup[opts] → List of removed slots
Removes gadgets directly under Root (tablet / list / PDF viewer / boards; judged by name) and empties the tablet state. For cleanup after a kernel restart lost the ledger.
Options: "Names", "Prefixes"

## Showing objects

### ResoniteShowObject[x, opts]
General API to show SourceVault objects in the world (tablet viewer / output field). x: sv:// URI | SourceVault row (Kind/URI/File/Title ...) | file path (pdf/png/jpg/mp4/txt/md/nb) | Image/Graphics | row list `{<|...|>, ...}` (→ ResoniteListGadget) | string (output field). PDF gets paging (tablet ◀ ▶). Privacy >= ceiling or non-numeric privacy → Failure["PrivacyExceeded"].
→ `<|"Kind","Pages","Title",...|>` or Failure
Options: "Title" -> Automatic, "MaxPages" -> 200, "PageSize" -> 1200

### ResoniteViewer[opts]
Creates only the image viewer board (use ResoniteShowObject without a tablet). Deferred in async contexts.
→ board Association (from ResoniteRealtimeBoard)
Options: "Placement" -> "User", "Distance" -> 1.5, "Height" -> Automatic, "User" -> Automatic, "Position" -> {0, 1.5, 1.2}, "Rotation" -> None, "Parent" -> "Root", "Size" -> 0.9, "Name" -> "Mathematica Viewer"; also ResoniteRealtimeBoard options. "Placement" -> "User" | "World".

### ResoniteViewerShow[pages, opts]
Shows a list of pages (Image | Graphics | {"PDF", file, n} | {"File", path}) in the viewer, displaying page 1.
Options: "Title" -> ""

### ResoniteViewerPage[n]
Shows page n. Also accepts "Next" | "Prev" | "First" | "Last".

### ResoniteViewerRemove[] → Null
Removes a standalone viewer.

### ResonitePDFViewer[file | pages, opts]
Shows a PDF / image / notebook in a grabbable viewer panel with paging (page image + [<<] [<] n/N [>] [>>] [close]). pages is a list of page specs (Image | {"PDF", file, n} | {"File", path}). Each call adds a new viewer (earlier ones stay; cascaded slightly right/lower/nearer, `$itPDFCascade` {0.12, -0.05, -0.06}). "Reuse" -> True loads into the latest viewer; "Reuse" -> root loads into that viewer.
→ `<|"Root","Pages","Page","Title"|>`, or `<|"Deferred" -> True, ...|>` in async contexts
Options: "Placement" -> "User" ("User"|"World"), "Distance" -> 1.0, "Height" -> Automatic, "User" -> Automatic, "Offset" -> {0.65, 0, 0} (to the user's right), "Position" -> {0, 1.3, 1.0}, "Parent" -> "Root", "CanvasSize" -> {1000, 1400}, "PanelScale" -> 0.0006, "FontSize" -> 30, "Name" -> "PDF Viewer", "Title" -> "", "PageSize" -> 1200, "MaxPages" -> 400, "Reuse" -> False, "Native" -> Automatic
See $ResonitePDFMode for Native/Lite/Panel behavior.

### ResonitePDFViewerPage[n | "Next" | "Prev" | "First" | "Last" | "+10" | "-10"]
Changes the page of the latest PDF viewer.
### ResonitePDFViewerPage[root, ...]
Same for the given viewer.

### ResonitePDFViewerRemove[] → Null
Removes the latest PDF viewer.
### ResonitePDFViewerRemove[root]
Removes that viewer.
### ResonitePDFViewerRemove[All]
Removes all.

### ResonitePDFTemplate[]
Finds and remembers the duplication template (Resonite's standard PDF viewer: name starts with "PDF Template", otherwise *.pdf) in the world (two levels below Root).
### ResonitePDFTemplate[slotId]
Sets it explicitly.
### ResonitePDFTemplate[None]
Forgets it.

### ResoniteVideoBoard[urlOrFile, opts]
Creates a board that plays video (VideoTextureProvider + AudioOutput). Playback start behavior is unverified on real hardware (2026-09-22).
→ Association of IDs
Options: same as ResoniteRealtimeBoard

## List and thumbnail gadgets

### ResoniteListGadget[rows, opts]
Turns a SourceVault row list (SourceVaultArXiv / SourceVaultEagleSummaries / SourceVaultSummaries / SourceVaultMailSearchIndex etc.) into an in-world list with buttons. ▶ shows the PDF / image / body in the viewer. Rows at/over the display ceiling are dropped. Footer "サムネ" button switches to the thumbnail list. Rows may be built by hand with keys Title / URI (sv://...) / Kind / Date / PrivacyLevel (aliases such as PL, 種別, 日付 also accepted). Deferred in async contexts. With "View" resolving to "Thumbnails" it delegates to ResoniteThumbnailGadget[rows, "Title" -> ...].
→ `<|"Root","Count","Hidden",...|>`
Options: "Title" -> "SourceVault", "RowsPerPage" -> 8, "Placement" -> Automatic (left of the tablet if present, otherwise in front of avatar; or "User" | "World"), "Distance" -> 1.4, "Height" -> Automatic, "User" -> Automatic, "Position" -> {0, 1.3, 1.4}, "Parent" -> "Root", "CanvasSize" -> {1400, 1000}, "PanelScale" -> 0.0006, "FontSize" -> 30, "Name" -> "SourceVault List", "View" -> Automatic (thumbnails if the latest tablet prompt contains 「サムネ / 一覧」) | "List" | "Thumbnails"
例: ResoniteListGadget[SourceVaultEagleSummaries["自然計算"], "Title" -> "Eagle", "View" -> "Thumbnails"]
Pass a search term to core functions; do not fetch all and filter (it takes minutes and hits the 30 s execution limit).

### ResoniteListGadgetRemove[rootId] → Null
Removes the list gadget.
### ResoniteListGadgetRemove[]
Removes all.

### ResoniteThumbnailGadget[rows, opts]
Lays out row thumbnails on one large surface (one Canvas; texture is a stitched JPEG) in a grid. Clicking a cell opens its PDF/image (same as ResoniteShowObject). The "リスト" button returns to the list. Thumbnails: Eagle item `<name>_thumbnail.png`, image itself, PDF page 1, else empty card. Placed left of the tablet (not a child of it). Stacks up to MaxRows vertically and extends horizontally without limit (289 items = 42 x 7); only surfaces taller than 2.4 m are shrunk. Wide surfaces are split into bands of 36 columns (one JPEG per band; band JPEGs are reused if the source images and layout are unchanged). Header "機密度で非表示 N" = rows over the ceiling; "ほか N 件はリストで" = rows beyond an integer MaxItems. Header "形を変更" button cycles shapes in the order of `$ResoniteThumbnailShapes` (ResoniteThumbnailShape). Curved shapes put a tile per cell at points and tangent planes of the surface; the center is the avatar's eye ("Center" -> Automatic). Surface definitions come from ResoniteRealtime_surface (https://github.com/transreal/ResoniteRealtime_surface). See also `$ResoniteThumbnailsDisclosable`.
→ Association
Options: "Title" -> "SourceVault", "Columns" -> Automatic, "ThumbSize" -> {200, 260} (px), "LabelHeight" -> 70, "FontSize" -> 18, "ThumbMeters" -> 0.12 (width of one thumbnail in m), "MaxItems" -> Infinity, "MaxRows" -> 7, "Name" -> "SourceVault Thumbnails", "Position" -> {0, 1.3, 1.4}, "Parent" -> "Root", "Shape" -> "Plane" ("Plane" | "Cylinder" (around avatar) | "SphereInside" (inside a sphere centered on avatar) | "Mobius" | ResoniteThumbnailSurface[...] (any surface)), "Center" -> Automatic (avatar eye, or `<|"Parent","Position","Rotation"|>`)
Internal: State slot has ValueField<int> Selected (0 none, i = i-th cell, -1 to list, -2 close, -3 connect, -4 change shape, -5 clear cache).

### ResoniteThumbnailGadgetRemove[rootId] → Null
Removes the thumbnail list.
### ResoniteThumbnailGadgetRemove[]
Removes all.

### ResoniteEagleFolderGadget[folder, opts]
Shows the items of an Eagle folder (name or id; smart folders OK) as a list or thumbnail list (rows come from SourceVaultEagleSummaryRow).
Options: "View" -> Automatic (thumbnails if prompt contains 「サムネ / 一覧」) | "List" | "Thumbnails", "Recursive" -> False, "Ext" -> All | "pdf" | {...}, "Title" -> Automatic

## Other gadgets

### ResoniteColorToggleBox[{c1, c2}, opts]
Creates a box whose color toggles c1 <-> c2 on each click (laser/touch). Components: BoxMesh|SphereMesh + UnlitMaterial + MeshRenderer + BoxCollider|SphereCollider + TouchButton + BooleanValueDriver<colorX> (TargetField -> TintColor) + ButtonToggle (-> driver State). No ProtoFlux. Deferred in async contexts (returns `<|"Deferred" -> True, ...|>`, which is success).
### ResoniteColorToggleBox[opts]
Same with {Red, Blue}.
→ `<|"Root","Mesh","Material","Driver","Colors",...|>` or Failure
Options: "Size" -> 0.2 (m), "Shape" -> "Box" ("Box"|"Sphere"), "Placement" -> "User" ("User"|"World"), "Distance" -> 1.0, "Height" -> Automatic, "User" -> Automatic, "Position" -> {0, 1.2, 1.0}, "Parent" -> "Root", "Offset" -> {-0.55, -0.1, -0.2} (when becoming a child of the tablet), "Name" -> "Mathematica Toggle Box", "Grabbable" -> True, "ButtonComponent" -> "TouchButton"

## Owner presence

### ResoniteOwnerPresence[] → Association
State of the owner-presence gate: `<|"Gate","Present","Watching","AckSecondsAgo","Nonce","AckNonce","Ready","Held" (pending operations),"Log" (recent executions/refusals)|>`.

## Variables

### $ResoniteTabletTurnRunner
型: None | Function[{prompt, notebook}], 初期値: None
If set, Eval calls it instead of notebook cell evaluation (testing).

### $ResoniteTabletMaxChars
型: Integer, 初期値: 6000
Max characters shown in the output field.

### $ResoniteTabletShowCode
型: True | False, 初期値: False
True also shows the LLM's proposed code (Input cell) on the tablet. Default shows only results (code stays in the notebook).

### $ResoniteTabletDeferMode
型: Automatic | True | False, 初期値: Automatic
Whether to reserve builds of list gadgets etc. Automatic = only when `$CurrentTask` is a TaskObject (inside ScheduledTask / runtime job) or a turn is active; True = always; False = never.

### $ResoniteTabletBuildMode
型: Automatic | "Tick" | "Notebook", 初期値: Automatic
Where reserved builds run. Automatic = inside the monitoring tick if it runs (no waiting: Send → next tick getSlot → wire buttons), otherwise as a notebook cell. "Tick" / "Notebook" fix it.

### $ResoniteTabletDeferRunner
型: None | Function[{id, notebook}], 初期値: None
If set, called instead of writing and evaluating the reserved cell (testing).

### $ResoniteTabletStashTemplate
型: True | False, 初期値: True
When True, a copy of the world's standard PDF viewer template is stored hidden as a child of the tablet named "PDF Template (Mathematica)" and used as the template afterward (robust to template re-spawn/deletion; included when the tablet is saved to inventory). False = no stash.

### $ResoniteNativeLogFile
型: String | None, 初期値: %TEMP%\ResoniteRealtime\native_pdf.log
Append target for the Native PDF viewer's stage log (NativeLog). Tab-separated: time / NB or headless / PID / job / stage / attempt / note. None = do not write.

### $ResonitePDFMode
型: "Native" | "Lite" | "Panel", 初期値: "Native"
"Native": open PDFs in Resonite's standard document viewer (template stored in tablet/thumbnail gadget, otherwise one in the world; duplicated via ProtoFlux and its URL swapped to the served URL). With no template, falls back to the Resonite document display (ResoniteDocViewer: StaticDocument + DocumentPageTexture; paging works only inside the world), or to the custom panel if `$ResonitePDFLite` = False. "Lite": always document display. "Panel": own page-image panel (ResonitePDFViewer).

### $ResoniteTabletAutoServe
型: True | False, 初期値: True
Whether loading ResoniteRealtime.wl in a notebook session auto-starts ResoniteTabletServe[].

### $ResoniteTabletPagePoints
型: Number, 初期値: 480
PageWidth (pt) when rendering result cells as page images. Smaller = bigger text on the board.

### $ResoniteTabletPageResolution
型: Number, 初期値: 192
Page image dpi. Page width px = PagePoints * dpi / 72 (default 1280).

### $ResoniteTabletCloudMaxLevel
型: Number, 初期値: 0.5
Upper bound of the AccessLevel passed to the LLM when no model is specified. Separate from the display ceiling.

### $ResoniteOwnerPresenceGate
型: True | False, 初期値: True
Executes in-world button operations (tablet / list / thumbnail list / PDF viewer / connect) in this kernel only while the owner (the host connected via ResoniteLink) is in that world and watching. Queried each time via world-side ProtoFlux (HostUser -> IsUserPresent, evaluated only by the host): the world must have focus, and in VR the headset must be worn. If the host's focus is on another world, or the query gets no answer, nothing runs no matter who presses (strict side). False = no check (solo debugging).

### $ResoniteOwnerPresenceFreshSeconds
型: Number, 初期値: 5
If the latest presence confirmation within this many seconds was "present", operations run immediately. If older, the pressed operation is held, the query is re-sent, and the operation runs or is refused after the answer.

### $ResoniteThumbnailsDisclosable
型: True | False, 初期値: True
Policy of 2026-09-26: thumbnail cells (shrunk image and title) are treated as disclosable regardless of privacy level. Rows are not dropped by privacy, no cover is added, and cells are not hidden when spawned from inventory. Only contents (an opened PDF etc.) are protected, judged against the display ceiling when opened. False = old behavior (rows at/over the ceiling are dropped/covered; re-spawned galleries hide up to "接続").

### $ResonitePDFPageClick
型: True | False, 初期値: True
Clicking the PDF page itself advances to the next page. For document display (ResoniteDocViewer) this is wired at build time; for a standard-viewer duplicate, the tree is read right after placement to find the page display and [次へ] and wire them (result in `ResoniteTabletStatus[]["NativeLog"]`).

### $ResoniteThumbnailShapes
型: List
Order in which the "形を変更" button cycles shapes (defined in ResoniteRealtime_surface, not in this file).