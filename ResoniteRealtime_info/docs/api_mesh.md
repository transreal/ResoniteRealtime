# ResoniteRealtime_mesh API Reference

Repo: https://github.com/transreal/ResoniteRealtime_mesh
Context: `ResoniteRealtime`` (auto-loaded by ResoniteRealtime.wl; UTF-8 file). Loads ResoLoop.wl on demand (`$iPackageDirectory`/ResoLoop.wl); requires the resoloop project/ResoLoop package (https://github.com/transreal/ResoLoop).

## 概要
Turns Graphics3D (Plot3D / ArrayPlot3D / SphericalPlot3D / Graphics3D[...] / Legended) into a triangle mesh and into an in-world Resonite 3D object.
Pipeline: ResoniteGraphics3DMesh (Graphics3D → mesh Association) → ResoniteMeshJSON (ResoniteLink 0.13.1 ImportMeshJSON JSON string) → ResoniteGraphics3D (writes mesh.json + apply.json, ResoLoopValidate (strict) → ResoLoopApply; creates `ResoLoop_Graphics3D_<stamp>`: Grabbable + StaticMesh + PBS_VertexColorMetallic (Culling Off) + MeshRenderer + MeshCollider, in front of avatar).
Verified 2026-09-22: apply config (kind: mesh asset + $asset:mesh) passes validate --strict and apply.

## 変換規則 (Graphics3D walk)
- GraphicsComplex (Plot3D): VertexColors used directly as vertex colors (RGBColor or numeric {r,g,b}/{r,g,b,a}).
- Polygon (incl. VertexColors option), Triangle, Cuboid: direct. Integer lists are vertex indices only inside GraphicsComplex; outside they are coordinates.
- Sphere, Ball, Cylinder, Cone, Tube, Ellipsoid, Hexahedron, Tetrahedron, Prism, Pyramid, Polyhedron, Simplex, Dodecahedron, Icosahedron, Octahedron, CapsuleShape, BSplineSurface, BoundaryMeshRegion, MeshRegion, FilledTorus, SphericalShell, Parallelepiped, Disk, Annulus, ConicHullRegion: triangulated with DiscretizeGraphics (20 s TimeConstrained; "MaxCellMeasure" controls fineness).
- Colors: RGBColor / Hue / GrayLevel / CMYKColor / XYZColor / LABColor / LCHColor / LUVColor, Opacity, Directive, FaceForm (first color used). Default color from "Color" option.
- Translate / Rotate / Scale / GeometricTransformation (TransformationFunction, {M,v}, 3x3 matrix, lists thereof) are folded into coordinates.
- Group wrappers (GraphicsGroup, Style, Annotation, Tooltip, Legended, Labeled, ...) are unwrapped.
- Line / Point / Text / Arrow / BezierCurve / BSplineCurve / Inset / Raster3D / Image3D / Locator / JoinedCurve / FilledCurve have no surface: dropped, counted in "Ignored" (keyed by head). Unknown heads are also counted.
- Size: BoxRatios (Plot3D default {1,1,0.4}) applied, longest side normalized to "Size" (m), centered at origin.
- Coordinates: Mathematica (right-handed, z up) → Resonite (left-handed, y up): (x,y,z) → (x,z,y); triangle winding flipped to keep outward normals. Normals computed from converted triangles, area-weighted per vertex (degenerate → {0,1,0}).

## Functions
### ResoniteGraphics3DMesh[g, opts]
Walks Graphics3D (or Legended/Labeled/Style wrapping one) into a triangle mesh.
→ Association <|"Points" (Resonite coords, m), "Triangles" (1-based), "Colors" ({r,g,b,a}), "Normals", "Ignored" (assoc head→count), "Bounds" ({min,max}), "Source" (<|"Head","BoxRatios","Pieces"|>)|>; Failure["NotGraphics3D"] if not Graphics3D; Failure["NoSurface"] (with "Ignored") if no faces; Failure["TooManyTriangles"] if over "MaxTriangles".
Options: "Size" -> 0.6 (longest side, m), "BoxRatios" -> Automatic (use g's BoxRatios; or {bx,by,bz}), "MaxTriangles" -> 300000 (integer limit), "MaxCellMeasure" -> Automatic (DiscretizeGraphics fineness), "Color" -> GrayLevel[0.75] (color for faces without color spec)
例: ResoniteGraphics3DMesh[Plot3D[Sin[x y], {x, -2, 2}, {y, -2, 2}], "Size" -> 0.4]

### ResoniteMeshJSON[mesh_Association] → String
Converts a ResoniteGraphics3DMesh result to ResoniteLink ImportMeshJSON JSON string (vertices: position/normal/color/uvs; submeshes: one trianglesFlat, 0-based; values rounded to 1e-5; uvs all 0).

### ResoniteGraphics3D[g, opts]
Creates an in-world 3D object from a Graphics3D. Writes `<key>.mesh.json` and `<key>.apply.json` to the work directory (see `$ResoniteGraphics3DDirectory`), then ResoLoopValidate (Strict) → ResoLoopApply (with retry, "Timeout"). Root slot named `ResoLoop_Graphics3D_<stamp>` unless "Name" given.
→ <|"Root" (slot name), "Key" ("g3d-<stamp>"), "Files" ({mesh, apply[, state]}), "Vertices", "Triangles", "Ignored", "Placement" (<|"Position","Rotation"|>), "Apply" (resoloop report; None if "Apply"->False), "Seconds" (only when applied)|> or Failure (mesh failures, "NoResoLoop", "NoProject", "Write", "Invalid", "Apply", or validate failure).
Options: "Placement" -> "User" ("User" = in front of avatar via ResoLoopUserPlacement / icUserFrontPose fallback; otherwise use "Position"), "Distance" -> 1.2 (m in front of user), "Position" -> {0, 1.2, -1.5} (world position when not "User", or fallback), "Rotation" -> None (quaternion {x,y,z,w} or None), "Offset" -> {0,0,0} (added to final position, world coords), "Name" -> Automatic (root slot name), "Project" -> Automatic (resoloop project; Automatic uses `$ResoniteGraphics3DProject`, then ResoLoop default), "Metallic" -> 0.05, "Smoothness" -> 0.35, "Collider" -> True (add MeshCollider, DualSided), "Grabbable" -> True (Grabbable with Scalable), "Timeout" -> 240 (apply timeout s), "Apply" -> True (False = only write files), plus all ResoniteGraphics3DMesh options ("Size" -> 0.6, "BoxRatios" -> Automatic, "MaxTriangles" -> 300000, "MaxCellMeasure" -> Automatic, "Color" -> GrayLevel[0.75])
例: ResoniteGraphics3D[Plot3D[Sin[x y], {x, -2, 2}, {y, -2, 2}], "Size" -> 0.5, "Distance" -> 1.5]

### ResoniteGraphics3DRemove[result | rootName]
Removes an object created by ResoniteGraphics3D (finds slot by exact Name via ResoLoopFind, then ResoLoopSlotDelete with Confirm). Accepts the result Association (uses "Root") or the root slot name String.
→ ResoLoopSlotDelete result, or Failure["NoResoLoop"] / Failure["NotFound"]

## Variables
### $ResoniteGraphics3DProject
型: Automatic | String, 初期値: Automatic
resoloop project name used by ResoniteGraphics3D (Automatic = ResoLoop's default project); overridden by "Project" option.

### $ResoniteGraphics3DDirectory
型: Automatic | String, 初期値: Automatic
Where mesh.json / apply.json / apply checkpoints are written. Automatic = `%LOCALAPPDATA%\ResoLoop\g3d` (outside Dropbox: a project dir under Dropbox lets Dropbox grab the checkpoint and causes APPLY_STATE_WRITE_FAILED, observed 2026-09-22). Falls back to the project's `content/g3d` if unavailable.

## 生成されるapply.json構成
schemaVersion "1"; ownership.key = key; root slot (parent "Root", scalable-grabbable, runtimeRelocatable, optional rotation); components: Grabbable (Scalable True, if "Grabbable"), AI_GeneratedContent; assets.mesh = <|kind "mesh", source mesh.json|>; children: `_Assets` (StaticMesh URL `$asset:mesh`, PBS_VertexColorMetallic: AlbedoColor {1,1,1,1}, Culling Off, VertexColorTarget Albedo, Metallic, Smoothness) and `Model` (MeshRenderer + optional MeshCollider Sidedness DualSided).