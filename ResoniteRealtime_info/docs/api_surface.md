# ResoniteRealtime_surface API Reference

## 概要
Package: ResoniteRealtime_surface. Context: `ResoniteRealtime``. Loaded automatically by ResoniteRealtime (https://github.com/transreal/ResoniteRealtime) after ResoniteRealtime_docboard (https://github.com/transreal/ResoniteRealtime_docboard); shares the `ResoniteRealtime`Private`` context and uses tablet/list helpers (itXxx / icXxx / idXxx).
Purpose: map the thumbnail-list grid onto curved surfaces (cylinder / sphere inside / Möbius strip / arbitrary surface).

## 設計
- Plane coordinates: grid cells live on a plane (m, origin = center of the grid extent, x right, y up). A surface is a map S(x, y) → 3D point in a frame fixed at the center (avatar eye, y up, +z = front).
- spec = <|"Name","Label","Map"->Function[{x,y,g},{X,Y,Z}],"Radius","Y0","Fit"->Function[g,<|...|>],"Flip","TwoSided","Rows"|>
- g = dims <|"W" (grid width m), "H" (height m), "Y0" (vertical shift), "R" (radius), ...values added by Fit|>.
- Cell i = small UIX Canvas tile at S(c_i); orientation = tangent plane (ex=∂S/∂x, ey=∂S/∂y orthogonalized, ez=ex×ey). UIX front is -z, so write the map so ez points away from center → front faces center ("Flip"->True inverts).
- Tile picture = strip texture (same JPEG as plane) cropped per tile via SpriteProvider.Rect (UV, bottom-left origin, 0..1). No Mask.
- Click = ray/surface intersection: each tile's Hit Button writes the index to State Selected (ButtonValueSet<int>). Same mapping solvable in Wolfram: ResoniteThumbnailSurfaceHit (Newton on S(x,y)=o+t d).
- Slot structure: `<Name>` (Grabbable, AI_GeneratedContent; position = center = avatar eye, rotation = horizontal gaze) ├ State (ValueField<int> Selected; -4 = change shape) ├ Data (signed rows + "shape"/"geometry") ├ Panel (header Canvas above surface top: title/status/connect/shape/list/close/veil) ├ Backing (header backing) └ Content (Assets, Cell<i> [Canvas+SpriteProvider+Image, child Hit (Image+Button+ButtonValueSet<int>, child Label)], Back<i> backing meshes).
- "Change shape" (Selected = -4): cycles `$ResoniteThumbnailShapes`. For a curved shape, reads Root (Depth 1) → "User ..." (Depth 1, child Head) in the monitor tick to get eye position and horizontal gaze, then rebuilds in the same row. If avatar not found / unreadable in 8 s, uses 1.3 m in front of the current panel (user side, -z) as center. Back to plane: placed 1.4 m in front of previous center.
- Avatar search: Root direct children plus holder slots (names containing holder/spawn) are scanned; with several users the one nearest the list is chosen.
- "TwoSided" -> True: cells on both sides of the same place (Möbius 2nd lap); cells offset toward front by half backing depth + 1 mm, backing at surface center. Ray inverse picks the cell facing the ray.
- "Rows" -> None | Function[{n, cw, spec, dims}, rows] (3-arg function also OK): number of grid rows suited to the surface; None = same as plane (MaxRows rows, extend horizontally). dims = <|"CW","CH","Pad"|>. Result sets "Columns" and "MaxRows" via layout opts unless "Columns" is given explicitly.
- Sphere: sinusoidal projection (φ=y/R, θ=x/(R cos φ)); radius chosen by bisection as minimal R satisfying R ≥ Radius, ym/R ≤ $itSphereMaxLat (1.0 rad), R cos(ym/R) ≥ W/(1.8π); row count 1..24 chosen to minimize radius (ties within 1% → longitude half-width ≈ 2× latitude half-width).
- Möbius: 2 laps (s=4πx/W); w(s)=cos(s/2)·up+sin(s/2)·out; S(x+W/2,y)=S(x,−y); rows = max count (≤7) that fills ≥90% of 4πR.
- Fit adjusts radius: Cylinder R=max(R, W/(2π·0.9)); Mobius R=max(R, W/(4π)).

## Public functions

### ResoniteThumbnailSurface[name_String] → Association
Returns registered surface definition from `$ResoniteThumbnailSurfaces`; Failure "UnknownShape" if unregistered. Built-ins: "Plane", "Cylinder", "SphereInside", "Mobius", "TorusOutside" (not in cycle).

### ResoniteThumbnailSurface[map, opts]
Builds a custom surface. map = Function[{x,y,g},{X,Y,Z}] (x,y plane coords in m; g dims). Also ResoniteThumbnailSurface[assoc] (needs "Map" key) fills defaults.
→ Association (spec)
Options: "Name" -> "Custom" (name), "Label" -> Automatic (display label), "Radius" -> 1.5 (initial g["R"]), "Y0" -> 0. (vertical shift m), "Fit" -> None (None | Function[g,<|"R"->...|>]), "Flip" -> False (invert orientation), "TwoSided" -> False (cells on both faces), "Rows" -> None (row-count function)
例: `$ResoniteThumbnailSurfaces["MyShape"] = ResoniteThumbnailSurface[Function[{x,y,g},{g["R"] Sin[x/g["R"]], y, g["R"] Cos[x/g["R"]]}], "Name"->"MyShape","Label"->"My"]; ResoniteThumbnailGadget[rows, "Shape"->"MyShape"]`

### ResoniteThumbnailSurfaceFrames[spec, g_Association, {{x,y},...}] → {Association,...}
Per-point <|"Position","Rotation" (quaternion x,y,z,w),"X","Y","Z"|> (point on surface + tangent frame; Z = cell back direction). spec may be name or Association. Failure "UnknownShape".

### ResoniteThumbnailSurfaceFrames[root_String] → {Association,...}
Frames for each cell of a built list. Failure "NotSurface" if not a curved list.

### ResoniteThumbnailSurfaceHit[root_String, {origin, dir}, detail_:None]
Cell index hit by ray origin + t·dir (t>0) in list root coordinates (center = avatar); None if between cells / no hit. Works for plane lists too.
→ Integer | None; with "Detail": <|"Cell","XY" (plane coords),"Point","T"|>. Failure "NoGadget".

### ResoniteThumbnailShape[root_String, shape_] → Association
Rebuilds list root in another shape ("Plane" | "Cylinder" | "SphereInside" | "Mobius" | registered name | spec Association). Failure "NoGadget" / "UnknownShape". Curved center = avatar eye (read without waiting inside monitor tick; deferred job returns <|"Deferred"->True,"Id","Via"->"Surface","Kind"->"ThumbnailGadget","Shape","Rows"|>). To plane: placed in front of previous center.

### ResoniteThumbnailShape[root_String] → Association
Switches to next shape in `$ResoniteThumbnailShapes` (same as "change shape" button).

## Variables

### $ResoniteThumbnailShapes
型: List, 初期値: {"Plane", "Cylinder", "SphereInside", "Mobius"}
Shape order cycled by the "change shape" button; entries are names (keys of `$ResoniteThumbnailSurfaces`) or ResoniteThumbnailSurface[...] specs.

### $ResoniteThumbnailSurfaces
型: Association, 初期値: built-ins (Plane, Cylinder, SphereInside, Mobius, TorusOutside)
Registry name → spec. Built-ins reset on each load; user-added names are kept.

## Built-in surfaces
- "Plane": Radius 1.4, Y0 0, Map {x, y, R}. Plane lists are built with the classic single Canvas; "Plane" tile spec is for testing the mapping.
- "Cylinder": Label "円筒", Radius 1.3, Y0 -0.1; Map {R sin t, y, R cos t}, t=x/R.
- "SphereInside": Label "球の内側", Radius 1.0, Y0 -0.1; Fit itSphereFit; Rows itSphereRows.
- "Mobius": Label "メビウスの帯", Radius 1.6, Y0 0, TwoSided True; Rows itMobiusRows.
- "TorusOutside": Label "トーラスの外側", Radius 0.9, Y0 0; Fit gives g "A","B","D" (major radius, tube radius, distance D=A+B+1.0 in front); Map u=x/(A+B), v=y/B; wraps the outer face of a vertical-axis torus in front.

## Usage
`ResoniteThumbnailGadget[rows, "Shape" -> "Cylinder"]` / "change shape" button / `ResoniteThumbnailShape[root, shape]`. Registered as `$ResoniteThumbnailSurfaces["MyShape"] = ResoniteThumbnailSurface[...]`.

## Internal tunables (Private context)
$itSurfaceViewDistance=1.3 (fallback center distance in front of plane list), $itSurfacePlaneDistance=1.4 (curved→plane placement), $itSurfaceUserWait=8 (s, avatar read timeout), $itSphereMaxLat=1.0, $itTileBackDepth=0.008, $itSurfaceOpenBack=0.45 (opened PDF placed this far in front of the tile, ≥0.6 m from center), $itTileUVTopLeft=False (set True if tile rows appear upside down), $itSurfaceStep=10^-4 (finite-difference step).