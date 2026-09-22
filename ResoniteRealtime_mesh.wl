(* ::Package:: *)

(* ResoniteRealtime_mesh.wl -- Graphics3D (Plot3D / ArrayPlot3D / ...) をワールド内の 3D オブジェクトにする

   This file is encoded in UTF-8.
   ResoniteRealtime.wl が自動でロードする (同じ ResoniteRealtime` コンテキスト)。

   ---- 何をするか ----

   1. ResoniteGraphics3DMesh[g]: Graphics3D を歩いて三角形メッシュ (頂点 / 三角形 / 頂点色 / 法線) にする。
        - GraphicsComplex (Plot3D 系。VertexColors をそのまま頂点色に)、Polygon / Triangle / Cuboid は直接、
          Sphere / Cylinder / Cone / Tube / 多面体などは DiscretizeGraphics で三角形化。
        - 色は RGBColor / Hue / GrayLevel / FaceForm / Opacity の指示を辿る。Translate / Rotate / Scale /
          GeometricTransformation は座標に畳み込む (ArrayPlot3D が使う)。
        - Line / Point / Text / Arrow は面が無いので落とす (Ignored に数を残す)。
        - BoxRatios (Plot3D の既定 {1,1,0.4}) を反映し、最長辺を "Size" (m) に正規化。
        - 座標系: Mathematica (右手, z 上) -> Resonite (左手, y 上) は (x,y,z) -> (x,z,y)。反転なので
          三角形の向きを裏返して外向き法線を保つ。法線は変換後の三角形から面積重みで計算。
   2. ResoniteMeshJSON[mesh]: ResoniteLink 0.13.1 の ImportMeshJSON 形式 (vertices: position/normal/color/uvs,
        submeshes: trianglesFlat) の JSON 文字列。
   3. ResoniteGraphics3D[g]: mesh.json + apply.json を resoloop プロジェクト (既定 ResoLoop の既定プロジェクト) の
        content/g3d/ に書き、ResoLoop.wl の ResoLoopValidate (strict) -> ResoLoopApply で
        ResoLoop_Graphics3D_<stamp> (Grabbable + StaticMesh + PBS_VertexColorMetallic (Culling Off) +
        MeshRenderer + MeshCollider) をアバターの正面に作る。

   2026-09-22 実測: 上の apply 構成 (kind: mesh 資産 + $asset:mesh) は validate --strict と apply が通る。
*)

BeginPackage["ResoniteRealtime`"];

ResoniteRealtime`ResoniteGraphics3DMesh::usage =
  "ResoniteGraphics3DMesh[g] は Graphics3D (Plot3D / ArrayPlot3D / SphericalPlot3D / Graphics3D[...] / Legended) を\n" <>
  "三角形メッシュ <|\"Points\" (Resonite 座標、m), \"Triangles\" (1 始まり), \"Colors\" ({r,g,b,a}), \"Normals\",\n" <>
  "  \"Ignored\" (落とした要素の数), \"Bounds\", \"Source\"|> にする。面が無ければ Failure[\"NoSurface\"]。\n" <>
  "オプション: \"Size\" -> 0.6 (最長辺 m), \"BoxRatios\" -> Automatic (g の BoxRatios), \"MaxTriangles\" -> 300000,\n" <>
  "  \"MaxCellMeasure\" -> Automatic (DiscretizeGraphics の細かさ), \"Color\" -> GrayLevel[0.75] (色指定の無い面)。";
ResoniteRealtime`ResoniteMeshJSON::usage =
  "ResoniteMeshJSON[mesh] は ResoniteGraphics3DMesh の結果を ResoniteLink の ImportMeshJSON 形式の JSON 文字列にする。";
ResoniteRealtime`ResoniteGraphics3D::usage =
  "ResoniteGraphics3D[g] は Graphics3D をワールド内の 3D オブジェクト (ResoLoop_Graphics3D_<stamp>) にする。\n" <>
  "resoloop プロジェクトに mesh.json + apply.json を書き、ResoLoopValidate (strict) -> ResoLoopApply で作る。\n" <>
  "オプション: \"Size\" -> 0.6, \"Placement\" -> \"User\" (アバター正面) | \"World\", \"Distance\" -> 1.2,\n" <>
  "  \"Position\" -> {0, 1.2, -1.5}, \"Rotation\" -> None, \"Offset\" -> {0,0,0} (ワールド座標の加算),\n" <>
  "  \"Name\" -> Automatic, \"Project\" -> Automatic (ResoLoop の既定プロジェクト), \"Metallic\" -> 0.05,\n" <>
  "  \"Smoothness\" -> 0.35, \"Collider\" -> True, \"Grabbable\" -> True, \"Timeout\" -> 240, \"Apply\" -> True\n" <>
  "  (False なら書くだけ)。ResoniteGraphics3DMesh のオプションも通る。\n" <>
  "戻り値: <|\"Root\" (slot 名), \"Key\", \"Files\", \"Vertices\", \"Triangles\", \"Ignored\", \"Apply\" (resoloop の報告)|> か Failure。";
ResoniteRealtime`ResoniteGraphics3DRemove::usage =
  "ResoniteGraphics3DRemove[result | rootName] は ResoniteGraphics3D が作ったオブジェクトをワールドから消す (ResoLoopSlotDelete)。";
ResoniteRealtime`$ResoniteGraphics3DProject::usage =
  "$ResoniteGraphics3DProject は ResoniteGraphics3D が使う resoloop プロジェクト名 (既定 Automatic = ResoLoop の既定)。";
ResoniteRealtime`$ResoniteGraphics3DDirectory::usage =
  "$ResoniteGraphics3DDirectory は mesh.json / apply.json / apply の checkpoint を書く場所。\n" <>
  "既定 Automatic = %LOCALAPPDATA%\\ResoLoop\\g3d (Dropbox の外。プロジェクト配下だと Dropbox が checkpoint を掴んで\n" <>
  "APPLY_STATE_WRITE_FAILED になる。2026-09-22 実機)。無ければプロジェクトの content/g3d。";

Begin["`Private`"];

Scan[Quiet[Clear[#]] &, Names["ResoniteRealtime`ResoniteGraphics3D*"]];
Quiet[Clear[ResoniteRealtime`ResoniteMeshJSON]];

If[!ValueQ[ResoniteRealtime`$ResoniteGraphics3DProject], ResoniteRealtime`$ResoniteGraphics3DProject = Automatic];
If[!ValueQ[ResoniteRealtime`$ResoniteGraphics3DDirectory], ResoniteRealtime`$ResoniteGraphics3DDirectory = Automatic];
If[!ListQ[$imLog], $imLog = {}];

(* 作業ディレクトリ: Dropbox の外 (%LOCALAPPDATA%\ResoLoop\g3d)。プロジェクト配下 (.resoloop/state) は
   Dropbox が新規ファイルを掴んで checkpoint が書けず、フォルダの com.dropbox.ignored も新規ファイルには効かなかった。 *)
imWorkDirectory[projDir_String] :=
  Module[{d = ResoniteRealtime`$ResoniteGraphics3DDirectory, la = Environment["LOCALAPPDATA"]},
    If[!StringQ[d],
      d = If[StringQ[la] && DirectoryQ[la], FileNameJoin[{la, "ResoLoop", "g3d"}],
        FileNameJoin[{projDir, "content", "g3d"}]]];
    Quiet @ CreateDirectory[d];
    Quiet @ CreateDirectory[FileNameJoin[{d, "state"}]];
    d];

(* apply の checkpoint 書き込み失敗 (Dropbox 等の一時ロック) は、同じ apply の再実行で checkpoint から収束する *)
imRetryableQ[f_Failure] :=
  MemberQ[{"APPLY_STATE_WRITE_FAILED", "APPLY_STATE_READ_FAILED"}, f[[1]]] ||
  StringContainsQ[ToString[Lookup[f[[2]], "MessageTemplate", ""]], "checkpoint"];
imRetryableQ[_] := False;

imApplyWithRetry[applyFile_, proj_, stateFile_, timeout_] :=
  Module[{a, tries = 0},
    While[True,
      tries++;
      a = Quiet @ Check[ResoLoop`ResoLoopApply[applyFile, "Project" -> proj, "State" -> stateFile,
        "Timeout" -> timeout], $Failed];
      If[!imRetryableQ[a] || tries >= 3, Break[]];
      AppendTo[$imLog, <|"Time" -> DateObject[], "Retry" -> tries, "Reason" -> a[[1]]|>];
      Pause[1.5]];
    a];

(* ============================================================
   Graphics3D -> 三角形
   ============================================================ *)

imUnwrap[Legended[x_, ___]] := imUnwrap[x];
imUnwrap[Labeled[x_, ___]] := imUnwrap[x];
imUnwrap[Style[x_, ___]] := imUnwrap[x];
imUnwrap[x_] := x;

(* 色の指示 -> {r,g,b} *)
imRGB[c_] :=
  Module[{l = Quiet @ Check[List @@ ColorConvert[c, "RGB"], $Failed]},
    If[ListQ[l] && Length[l] >= 3, N[Take[l, 3]], {0.75, 0.75, 0.75}]];
imColorQ[c_] := MatchQ[c, _RGBColor | _Hue | _GrayLevel | _CMYKColor | _XYZColor | _LABColor | _LCHColor | _LUVColor];

(* VertexColors は RGBColor でも {r,g,b} / {r,g,b,a} の数値リストでも来る (Plot3D は数値リスト。2026-09-22 実測) *)
imVertexColorQ[c_] := imColorQ[c] || MatchQ[c, {_?NumericQ, _?NumericQ, _?NumericQ} | {_?NumericQ, _?NumericQ, _?NumericQ, _?NumericQ}];
imVertexRGBA[c_, opacity_] :=
  Which[
    MatchQ[c, {_?NumericQ, _?NumericQ, _?NumericQ}], Append[N[c], N[opacity]],
    MatchQ[c, {_?NumericQ, _?NumericQ, _?NumericQ, _?NumericQ}], N[c],
    True, With[{l = Quiet @ Check[List @@ ColorConvert[c, "RGB"], {}]},
      If[Length[l] === 4, N[l], Append[imRGB[c], N[opacity]]]]];

(* 状態: <|"Color" -> {r,g,b}, "Opacity" -> a, "M" -> 3x3, "V" -> {x,y,z}|> (座標変換は点 -> M.p + V) *)
imApplyDirective[d_, st_] :=
  Module[{s = st},
    Which[
      imColorQ[d],
        s["Color"] = imRGB[d];
        With[{l = Quiet @ Check[List @@ ColorConvert[d, "RGB"], {}]},
          If[Length[l] === 4, s["Opacity"] = N[l[[4]]]]],
      MatchQ[d, Opacity[_?NumericQ, ___]], s["Opacity"] = N[d[[1]]];
        If[Length[d] >= 2 && imColorQ[d[[2]]], s["Color"] = imRGB[d[[2]]]],
      MatchQ[d, _Directive], Scan[(s = imApplyDirective[#, s]) &, List @@ d],
      MatchQ[d, FaceForm[_]],
        With[{f = d[[1]]}, If[imColorQ[f], s = imApplyDirective[f, s],
          If[ListQ[f] && f =!= {} && imColorQ[First[f]], s = imApplyDirective[First[f], s]]]],
      MatchQ[d, _List], Scan[(s = imApplyDirective[#, s]) &, d],
      True, Null];
    s];

imDirectiveQ[d_] :=
  imColorQ[d] || MatchQ[d, _Opacity | _Directive | _FaceForm | _EdgeForm | _Specularity | _Lighting | _Glow |
    _Texture | _Thickness | _AbsoluteThickness | _PointSize | _AbsolutePointSize | _Dashing | _AbsoluteDashing |
    _CapForm | _JoinForm | _Arrowheads | _Antialiasing | _Rule | _RuleDelayed | _LightingAngle];

(* 変換の合成: 親 (M1,V1) の中の子 (M2,V2) -> (M1.M2, M1.V2 + V1) *)
imCompose[st_, {m2_, v2_}] :=
  Join[st, <|"M" -> st["M"].m2, "V" -> st["M"].v2 + st["V"]|>];

imTransformSpec[tf_TransformationFunction] :=
  With[{mat = Quiet @ Check[TransformationMatrix[tf], $Failed]},
    If[MatrixQ[mat] && Dimensions[mat] === {4, 4}, {N[mat[[1 ;; 3, 1 ;; 3]]], N[mat[[1 ;; 3, 4]]]}, None]];
imTransformSpec[{m_?MatrixQ, v_List}] /; Dimensions[m] === {3, 3} && Length[v] === 3 := {N[m], N[v]};
imTransformSpec[m_?MatrixQ] /; Dimensions[m] === {3, 3} := {N[m], {0., 0., 0.}};
imTransformSpec[_] := None;

imTransformSpecs[tf_List] /; !MatrixQ[tf] && AllTrue[tf, (imTransformSpec[#] =!= None) &] := imTransformSpec /@ tf;
imTransformSpecs[tf_] := With[{s = imTransformSpec[tf]}, If[s === None, {}, {s}]];

(* 集めた断片: <|"Points" -> n x 3 (Mathematica 座標, 変換適用済), "Triangles" -> m x 3 (1 始まり, 局所), "Colors" -> n x 4|> *)
imAddPiece[pts_, tris_, cols_] :=
  If[MatrixQ[pts] && ListQ[tris] && tris =!= {},
    AppendTo[$imPieces, <|"Points" -> N[pts], "Triangles" -> tris, "Colors" -> cols|>]];

imIgnore[h_] := ($imIgnored[h] = Lookup[$imIgnored, h, 0] + 1);

imApplyTransform[pts_, st_] :=
  If[st["M"] === IdentityMatrix[3] && st["V"] === {0., 0., 0.}, N[pts],
    (N[pts].Transpose[st["M"]]) + ConstantArray[st["V"], Length[pts]]];

imColorRows[st_, n_Integer] := ConstantArray[Append[st["Color"], st["Opacity"]], n];

(* 多角形 (頂点列) を扇状に三角形化 *)
imFan[n_Integer] := If[n < 3, {}, Table[{1, k, k + 1}, {k, 2, n - 1}]];

(* 座標つき多角形 (単一) *)
imPolygonCoords[coords_?MatrixQ, st_, cols_ : None] :=
  With[{n = Length[coords]},
    If[n >= 3,
      imAddPiece[imApplyTransform[coords, st], imFan[n],
        If[MatrixQ[cols] && Dimensions[cols][[1]] === n, cols, imColorRows[st, n]]]]];

(* GraphicsComplex の中の index 多角形 *)
imPolygonIndices[idx_List, st_] :=
  Module[{cx = $imComplex, pts, cols, n = Length[idx]},
    If[!AssociationQ[cx] || n < 3, Return[Null]];
    pts = Quiet @ Check[cx["Points"][[idx]], $Failed];
    If[!MatrixQ[pts], Return[Null]];
    cols = If[MatrixQ[cx["Colors"]], Quiet @ Check[cx["Colors"][[idx]], None], None];
    imAddPiece[imApplyTransform[pts, st], imFan[n],
      If[MatrixQ[cols], cols, imColorRows[st, n]]]];

(* GraphicsComplex 全体の多角形を一括で (Plot3D: 1 万個の三角形を 1 断片に) *)
imPolygonIndexList[polys : {{__Integer} ..}, st_] :=
  Module[{cx = $imComplex, tris, used, remap, pts, cols},
    If[!AssociationQ[cx], Return[Null]];
    tris = Join @@ Map[Function[p, Map[p[[#]] &, imFan[Length[p]]]], Select[polys, Length[#] >= 3 &]];
    If[tris === {}, Return[Null]];
    used = Union[Flatten[tris]];
    If[Max[used] > Length[cx["Points"]], Return[imIgnore["BadIndex"]]];
    remap = AssociationThread[used -> Range[Length[used]]];
    pts = cx["Points"][[used]];
    cols = If[MatrixQ[cx["Colors"]], cx["Colors"][[used]], imColorRows[st, Length[used]]];
    imAddPiece[imApplyTransform[pts, st], Map[Lookup[remap, #] &, tris, {2}], cols]];

(* 整数の並びは GraphicsComplex の中でだけ「頂点インデックス」。外では整数座標 (Polygon[{{0,0,0},{1,0,0},...}]) *)
imInComplexQ[] := AssociationQ[$imComplex];

imPolygon[spec_, st_] :=
  Which[
    imInComplexQ[] && MatchQ[spec, {__Integer}], imPolygonIndices[spec, st],
    imInComplexQ[] && MatchQ[spec, {{__Integer} ..}], imPolygonIndexList[spec, st],
    MatchQ[spec, {{_?NumericQ, _?NumericQ, _?NumericQ} ..}], imPolygonCoords[spec, st],
    MatchQ[spec, {{{_?NumericQ, _?NumericQ, _?NumericQ} ..} ..}], Scan[imPolygonCoords[#, st] &, spec],
    True, imIgnore["Polygon"]];

(* 直方体: 面ごとに 4 頂点 (法線を平らに保つ) *)
imCuboid[a_List, b_List, st_] :=
  Module[{lo = N[MapThread[Min, {a, b}]], hi = N[MapThread[Max, {a, b}]], c, faces},
    c[i_, j_, k_] := {If[i == 0, lo[[1]], hi[[1]]], If[j == 0, lo[[2]], hi[[2]]], If[k == 0, lo[[3]], hi[[3]]]};
    faces = {
      {c[0, 0, 0], c[0, 1, 0], c[1, 1, 0], c[1, 0, 0]},  (* z = lo, 下 *)
      {c[0, 0, 1], c[1, 0, 1], c[1, 1, 1], c[0, 1, 1]},  (* z = hi, 上 *)
      {c[0, 0, 0], c[1, 0, 0], c[1, 0, 1], c[0, 0, 1]},  (* y = lo *)
      {c[0, 1, 0], c[0, 1, 1], c[1, 1, 1], c[1, 1, 0]},  (* y = hi *)
      {c[0, 0, 0], c[0, 0, 1], c[0, 1, 1], c[0, 1, 0]},  (* x = lo *)
      {c[1, 0, 0], c[1, 1, 0], c[1, 1, 1], c[1, 0, 1]}}; (* x = hi *)
    Scan[imPolygonCoords[#, st] &, faces]];

(* DiscretizeGraphics で三角形化する図形 *)
imDiscretize[prim_, st_] :=
  Module[{m, pts, cells, tris, mcm = $imMaxCellMeasure},
    m = Quiet @ Check[
      TimeConstrained[
        If[mcm === Automatic, DiscretizeGraphics[prim], DiscretizeGraphics[prim, MaxCellMeasure -> mcm]], 20, $Failed],
      $Failed];
    If[!MeshRegionQ[m], Return[imIgnore[Head[prim]]]];
    pts = MeshCoordinates[m];
    cells = MeshCells[m, 2];
    tris = Join @@ Map[Function[c, With[{p = c[[1]]}, Map[p[[#]] &, imFan[Length[p]]]]], cells];
    If[tris === {}, Return[imIgnore[Head[prim]]]];
    imAddPiece[imApplyTransform[pts, st], tris, imColorRows[st, Length[pts]]]];

imDiscretizableQ[e_] :=
  MatchQ[e, _Sphere | _Ball | _Cylinder | _Cone | _Tube | _Ellipsoid | _Hexahedron | _Tetrahedron | _Prism | _Pyramid |
    _Polyhedron | _Simplex | _Dodecahedron | _Icosahedron | _Octahedron | _CapsuleShape | _BSplineSurface |
    _BoundaryMeshRegion | _MeshRegion | _FilledTorus | _SphericalShell | _Parallelepiped | _Disk | _Annulus |
    _ConicHullRegion | _Cuboid];

imPoint3Q[p_] := MatchQ[p, {_?NumericQ, _?NumericQ, _?NumericQ}];

imWalk[expr_, st_] :=
  Which[
    ListQ[expr], imWalkList[expr, st],
    MatchQ[expr, _GraphicsComplex], imGraphicsComplex[expr, st],
    MatchQ[expr, Polygon[_, ___]], imPolygonWithOpts[expr, st],
    MatchQ[expr, Triangle[_]], imTriangle[expr[[1]], st],
    MatchQ[expr, Cuboid[_List]], imCuboid[expr[[1]], expr[[1]] + 1, st],
    MatchQ[expr, Cuboid[_List, _List]], imCuboid[expr[[1]], expr[[2]], st],
    MatchQ[expr, Cuboid[]], imCuboid[{0, 0, 0}, {1, 1, 1}, st],
    MatchQ[expr, Sphere[]], imDiscretize[Sphere[{0, 0, 0}, 1], st],
    MatchQ[expr, Sphere[_?MatrixQ, ___]], Scan[imDiscretize[Sphere[#, Sequence @@ Rest[expr]], st] &, expr[[1]]],
    MatchQ[expr, Ball[_?MatrixQ, ___]], Scan[imDiscretize[Sphere[#, Sequence @@ Rest[expr]], st] &, expr[[1]]],
    MatchQ[expr, (Cylinder | Cone)[{_?imPoint3Q, _?imPoint3Q}, ___]], imDiscretize[expr, st],
    MatchQ[expr, (Cylinder | Cone)[{{_?imPoint3Q, _?imPoint3Q} ..}, ___]],
      Scan[imDiscretize[Head[expr][#, Sequence @@ Rest[expr]], st] &, expr[[1]]],
    imDiscretizableQ[expr], imDiscretize[expr, st],
    MatchQ[expr, Translate[_, _]], imTranslate[expr, st],
    MatchQ[expr, Rotate[_, __]], imWithTransform[expr[[1]], RotationTransform @@ Rest[expr], st],
    MatchQ[expr, Scale[_, __]], imWithTransform[expr[[1]], ScalingTransform @@ Rest[expr], st],
    MatchQ[expr, GeometricTransformation[_, _]], imGeometric[expr, st],
    MatchQ[expr, GraphicsGroup[_, ___] | Style[_, ___] | Annotation[_, ___] | Tooltip[_, ___] | Mouseover[_, ___] |
      StatusArea[_, ___] | PopupWindow[_, ___] | EventHandler[_, ___] | Button[_, ___] | Hyperlink[_, ___] |
      Labeled[_, ___] | Legended[_, ___]], imWalk[expr[[1]], st],
    MatchQ[expr, _Line | _Point | _Text | _Arrow | _BezierCurve | _BSplineCurve | _Inset | _Raster3D | _Image3D |
      _Locator | _JoinedCurve | _FilledCurve], imIgnore[Head[expr]],
    imDirectiveQ[expr], Null,
    True, imIgnore[Head[expr]]];

imWalkList[list_List, st0_] :=
  Module[{st = st0},
    Scan[Function[e, If[imDirectiveQ[e], st = imApplyDirective[e, st], imWalk[e, st]]], list]];

imTriangle[spec_, st_] :=
  Which[
    imInComplexQ[] && MatchQ[spec, {__Integer}], imPolygonIndices[spec, st],
    imInComplexQ[] && MatchQ[spec, {{__Integer} ..}], Scan[imPolygonIndices[#, st] &, spec],
    MatchQ[spec, {{_?NumericQ, _, _}, {_?NumericQ, _, _}, {_?NumericQ, _, _}}], imPolygonCoords[spec, st],
    MatchQ[spec, {{{_?NumericQ, _, _} ..} ..}], Scan[imPolygonCoords[#, st] &, spec],
    True, imIgnore["Triangle"]];

imPolygonWithOpts[Polygon[spec_, opts___], st_] :=
  Module[{vc = Lookup[Association[{opts}], VertexColors, None], cols = None},
    If[ListQ[vc] && vc =!= {} && AllTrue[vc, imVertexColorQ],
      cols = Map[imVertexRGBA[#, st["Opacity"]] &, vc]];
    If[MatrixQ[cols] && MatchQ[spec, {{_?NumericQ, _?NumericQ, _?NumericQ} ..}],
      imPolygonCoords[spec, st, cols],
      imPolygon[spec, st]]];

imGraphicsComplex[GraphicsComplex[pts_, prims_, opts___], st_] :=
  Module[{o = Association[Cases[{opts}, _Rule | _RuleDelayed]], vc, cols = None, p = N[pts]},
    If[!MatrixQ[p] || Dimensions[p][[2]] =!= 3, Return[imIgnore["GraphicsComplex"]]];
    vc = Lookup[o, VertexColors, None];
    If[ListQ[vc] && Length[vc] === Length[p] && AllTrue[vc, imVertexColorQ],
      cols = Map[imVertexRGBA[#, st["Opacity"]] &, vc]];
    Block[{$imComplex = <|"Points" -> p, "Colors" -> cols|>},
      imWalk[prims, st]]];

imTranslate[Translate[prims_, v_], st_] :=
  Which[
    MatchQ[v, {_?NumericQ, _?NumericQ, _?NumericQ}],
      imWalk[prims, imCompose[st, {IdentityMatrix[3], N[v]}]],
    MatchQ[v, {{_?NumericQ, _?NumericQ, _?NumericQ} ..}],
      Scan[imWalk[prims, imCompose[st, {IdentityMatrix[3], N[#]}]] &, v],
    True, imIgnore["Translate"]];

imWithTransform[prims_, tf_, st_] :=
  With[{s = imTransformSpec[tf]},
    If[s === None, imIgnore["Transform"], imWalk[prims, imCompose[st, s]]]];

imGeometric[GeometricTransformation[prims_, tf_], st_] :=
  With[{specs = imTransformSpecs[tf]},
    If[specs === {}, imIgnore["GeometricTransformation"],
      Scan[imWalk[prims, imCompose[st, #]] &, specs]]];

(* ---- 法線 (面積重みの面法線を頂点に集める) ---- *)
imNormals[pts_, tris_] :=
  Module[{a, b, c, fn, idx, acc, vn, norms},
    a = pts[[tris[[All, 1]]]]; b = pts[[tris[[All, 2]]]]; c = pts[[tris[[All, 3]]]];
    fn = With[{u = b - a, v = c - a},
      Transpose[{u[[All, 2]] v[[All, 3]] - u[[All, 3]] v[[All, 2]],
                 u[[All, 3]] v[[All, 1]] - u[[All, 1]] v[[All, 3]],
                 u[[All, 1]] v[[All, 2]] - u[[All, 2]] v[[All, 1]]}]];
    idx = Join[tris[[All, 1]], tris[[All, 2]], tris[[All, 3]]];
    acc = GroupBy[Thread[{idx, Join[fn, fn, fn]}], First -> Last, Total];
    vn = Lookup[acc, Range[Length[pts]], {0., 0., 1.}];
    norms = Sqrt[Total[vn^2, {2}]];
    vn = vn / (norms + 10^-12);
    (* 縮退 (長さ 0) は上向き *)
    MapThread[If[#2 < 10^-9, {0., 1., 0.}, #1] &, {vn, norms}]];

Options[ResoniteRealtime`ResoniteGraphics3DMesh] = {
  "Size" -> 0.6, "BoxRatios" -> Automatic, "MaxTriangles" -> 300000, "MaxCellMeasure" -> Automatic,
  "Color" -> GrayLevel[0.75]};

ResoniteRealtime`ResoniteGraphics3DMesh[gIn_, opts : OptionsPattern[]] :=
  Module[{g = imUnwrap[gIn], prims, gopts, st, pieces, ignored, pts, tris, cols, off, br, lo, hi, ext,
          factor, size, center, s, maxT, normals},
    If[Head[g] =!= Graphics3D || Length[g] < 1,
      Return[Failure["NotGraphics3D", <|"MessageTemplate" -> "Graphics3D ではありません: " <> ToString[Head[gIn]]|>]]];
    prims = g[[1]];
    (* Plot3D はオプションを入れ子のリストで持つことがあるので 1 段下まで見る *)
    gopts = Association[Cases[Rest[List @@ g], _Rule | _RuleDelayed, {1, 2}]];
    st = <|"Color" -> imRGB[OptionValue["Color"]], "Opacity" -> 1., "M" -> IdentityMatrix[3], "V" -> {0., 0., 0.}|>;
    Block[{$imPieces = {}, $imIgnored = <||>, $imComplex = None, $imMaxCellMeasure = OptionValue["MaxCellMeasure"]},
      Quiet @ Check[imWalk[prims, st], Null];
      pieces = $imPieces; ignored = $imIgnored];
    If[pieces === {},
      Return[Failure["NoSurface", <|"MessageTemplate" -> "面を持つ図形がありません (Line / Point だけ?)。",
        "Ignored" -> ignored|>]]];
    (* 断片を結合 *)
    off = Accumulate[Prepend[Map[Length[#["Points"]] &, Most[pieces]], 0]];
    pts = Join @@ Map[#["Points"] &, pieces];
    tris = Join @@ MapThread[Function[{pc, o}, pc["Triangles"] + o], {pieces, off}];
    cols = Join @@ Map[#["Colors"] &, pieces];
    maxT = OptionValue["MaxTriangles"];
    If[IntegerQ[maxT] && Length[tris] > maxT,
      Return[Failure["TooManyTriangles", <|"MessageTemplate" -> "三角形が " <> ToString[Length[tris]] <> " 個で上限 " <>
        ToString[maxT] <> " を超えています。PlotPoints を減らしてください。", "Triangles" -> Length[tris]|>]]];
    (* BoxRatios と大きさ *)
    br = OptionValue["BoxRatios"];
    If[br === Automatic, br = Lookup[gopts, BoxRatios, Automatic]];
    lo = Min /@ Transpose[pts]; hi = Max /@ Transpose[pts];
    ext = Map[If[# < 10^-9, 1., #] &, hi - lo];
    center = (lo + hi)/2;
    size = N[OptionValue["Size"]];
    If[MatchQ[br, {_?NumericQ, _?NumericQ, _?NumericQ}] && Min[br] > 0,
      factor = N[br]/ext; s = size/Max[N[br]],
      factor = {1., 1., 1.}; s = size/Max[ext]];
    pts = ((pts - ConstantArray[center, Length[pts]]) * ConstantArray[factor, Length[pts]]) * s;
    (* Mathematica (x,y,z; z 上) -> Resonite (x,z,y; y 上)。反転なので三角形の向きを裏返す *)
    pts = pts[[All, {1, 3, 2}]];
    tris = tris[[All, {1, 3, 2}]];
    normals = imNormals[pts, tris];
    <|"Points" -> pts, "Triangles" -> tris, "Colors" -> N[cols], "Normals" -> normals,
      "Ignored" -> ignored, "Bounds" -> {Min /@ Transpose[pts], Max /@ Transpose[pts]},
      "Source" -> <|"Head" -> Head[gIn], "BoxRatios" -> br, "Pieces" -> Length[pieces]|>|>];

(* ============================================================
   ImportMeshJSON
   ============================================================ *)

imRound[x_] := Round[x, 10^-5];

ResoniteRealtime`ResoniteMeshJSON[mesh_Association] :=
  Module[{pts = imRound[mesh["Points"]], nrm = imRound[mesh["Normals"]], cols = imRound[mesh["Colors"]], verts, flat, ba},
    verts = MapThread[
      <|"position" -> <|"x" -> #1[[1]], "y" -> #1[[2]], "z" -> #1[[3]]|>,
        "normal" -> <|"x" -> #2[[1]], "y" -> #2[[2]], "z" -> #2[[3]]|>,
        "color" -> <|"r" -> #3[[1]], "g" -> #3[[2]], "b" -> #3[[3]], "a" -> If[Length[#3] >= 4, #3[[4]], 1.]|>,
        "uvs" -> {<|"$type" -> "2D", "uv" -> <|"x" -> 0., "y" -> 0.|>|>}|> &,
      {pts, nrm, cols}];
    flat = Flatten[mesh["Triangles"]] - 1;
    ba = ExportByteArray[<|"vertices" -> verts,
        "submeshes" -> {<|"$type" -> "trianglesFlat", "vertexIndices" -> flat|>}|>, "RawJSON"];
    ByteArrayToString[ba, "UTF-8"]];

(* ============================================================
   ワールドへ (resoloop apply)
   ============================================================ *)

imResoLoopQ[] := Names["ResoLoop`ResoLoopApply"] =!= {} && Length[DownValues[ResoLoop`ResoLoopApply]] > 0;

imEnsureResoLoop[] :=
  (If[!imResoLoopQ[],
     With[{f = FileNameJoin[{$iPackageDirectory, "ResoLoop.wl"}]},
       If[FileExistsQ[f], Quiet @ Check[Block[{$CharacterEncoding = "UTF-8"}, Get[f]], Null]]]];
   imResoLoopQ[]);

imStamp[] := DateString[Now, {"Year", "Month", "Day", "-", "Hour", "Minute", "Second"}] <> "-" <>
  StringTake[IntegerString[RandomInteger[{0, 16^4 - 1}], 16, 4], 4];

imApplyJSON[key_, rootName_, meshFile_, pos_, rot_, o_] :=
  <|"schemaVersion" -> "1",
    "ownership" -> <|"key" -> key|>,
    "slot" -> Join[<|"key" -> "root", "name" -> rootName, "parent" -> "Root",
        "position" -> N[pos], "scale" -> {1, 1, 1}, "runtimeRelocatable" -> True|>,
      If[ListQ[rot] && Length[rot] === 4, <|"rotation" -> N[rot]|>, <||>]],
    "components" -> Join[
      If[TrueQ[o["Grabbable"]], {<|"key" -> "grabbable", "type" -> "FrooxEngine.Grabbable", "fields" -> <|"Scalable" -> True|>|>}, {}],
      {<|"key" -> "ai", "type" -> "FrooxEngine.AI_GeneratedContent",
         "fields" -> <|"Source" -> "Mathematica Graphics3D via ResoniteRealtime (ResoniteGraphics3D)"|>|>}],
    "assets" -> <|"mesh" -> <|"kind" -> "mesh", "source" -> meshFile|>|>,
    "children" -> {
      <|"slot" -> <|"key" -> "assets", "name" -> "_Assets"|>,
        "components" -> {
          <|"key" -> "mesh", "type" -> "FrooxEngine.StaticMesh", "fields" -> <|"URL" -> "$asset:mesh"|>|>,
          <|"key" -> "mat", "type" -> "FrooxEngine.PBS_VertexColorMetallic",
            "fields" -> <|"AlbedoColor" -> {1, 1, 1, 1}, "Culling" -> "Off", "VertexColorTarget" -> "Albedo",
              "Metallic" -> N[o["Metallic"]], "Smoothness" -> N[o["Smoothness"]]|>|>}|>,
      <|"slot" -> <|"key" -> "model", "name" -> "Model"|>,
        "components" -> Join[
          {<|"key" -> "renderer", "type" -> "FrooxEngine.MeshRenderer",
             "fields" -> <|"Mesh" -> "$component:mesh", "Materials" -> {"$component:mat"}|>|>},
          If[TrueQ[o["Collider"]],
            {<|"key" -> "collider", "type" -> "FrooxEngine.MeshCollider",
               "fields" -> <|"Mesh" -> "$component:mesh", "Sidedness" -> "DualSided"|>|>}, {}]]|>}|>;

(* 置き場所: アバターの正面 (ResoLoopUserPlacement) か、ResoniteLink の icUserFrontPose、無ければ固定位置 *)
imPlacement[o_] :=
  Module[{p, pos = N[o["Position"]], rot = o["Rotation"]},
    If[o["Placement"] === "User",
      p = Quiet @ Check[ResoLoop`ResoLoopUserPlacement["Distance" -> o["Distance"]], $Failed];
      If[AssociationQ[p] && MatchQ[Lookup[p, "Position", None], {_, _, _}],
        pos = N[p["Position"]]; rot = Lookup[p, "Rotation", rot],
        If[StringQ[$iState["Link"]],
          p = Quiet @ Check[icUserFrontPose[Automatic, o["Distance"], Automatic], None];
          If[AssociationQ[p] && p["Parent"] === "Root", pos = N[p["Position"]]; rot = p["Rotation"]]]]];
    <|"Position" -> pos + N[o["Offset"]], "Rotation" -> If[ListQ[rot] && Length[rot] === 4, N[rot], None]|>];

Options[ResoniteRealtime`ResoniteGraphics3D] = Join[{
  "Placement" -> "User", "Distance" -> 1.2, "Position" -> {0, 1.2, -1.5}, "Rotation" -> None,
  "Offset" -> {0, 0, 0}, "Name" -> Automatic, "Project" -> Automatic, "Metallic" -> 0.05,
  "Smoothness" -> 0.35, "Collider" -> True, "Grabbable" -> True, "Timeout" -> 240, "Apply" -> True},
  Options[ResoniteRealtime`ResoniteGraphics3DMesh]];

ResoniteRealtime`ResoniteGraphics3D[g_, opts : OptionsPattern[]] :=
  Module[{o, mesh, json, proj, dir, work, key, rootName, meshFile, applyFile, stateFile, place, applyJSON, v, a,
          t0 = AbsoluteTime[]},
    o = Association @ Join[Options[ResoniteRealtime`ResoniteGraphics3D], {opts}];
    mesh = ResoniteRealtime`ResoniteGraphics3DMesh[g,
      Sequence @@ Normal[KeyTake[o, Keys[Options[ResoniteRealtime`ResoniteGraphics3DMesh]]]]];
    If[FailureQ[mesh], Return[mesh]];
    If[!imEnsureResoLoop[],
      Return[Failure["NoResoLoop", <|"MessageTemplate" -> "ResoLoop.wl がロードできません (resoloop が要ります)。"|>]]];
    proj = Replace[o["Project"], Automatic :> Replace[ResoniteRealtime`$ResoniteGraphics3DProject, Automatic -> Automatic]];
    dir = Quiet @ Check[ResoLoop`ResoLoopProject[proj], $Failed];
    If[!StringQ[dir] || !DirectoryQ[dir],
      Return[Failure["NoProject", <|"MessageTemplate" -> "resoloop プロジェクトが見つかりません: " <> ToString[proj]|>]]];
    key = "g3d-" <> imStamp[];
    rootName = Replace[o["Name"], Automatic -> "ResoLoop_Graphics3D_" <> StringDrop[key, 4]];
    work = imWorkDirectory[dir];
    meshFile = FileNameJoin[{work, key <> ".mesh.json"}];
    applyFile = FileNameJoin[{work, key <> ".apply.json"}];
    stateFile = FileNameJoin[{work, "state", key <> ".json"}];
    json = ResoniteRealtime`ResoniteMeshJSON[mesh];
    Quiet @ Check[Export[meshFile, json, "Text", CharacterEncoding -> "UTF-8"],
      Return[Failure["Write", <|"MessageTemplate" -> "mesh.json を書けませんでした: " <> meshFile|>]]];
    place = imPlacement[o];
    applyJSON = imApplyJSON[key, rootName, key <> ".mesh.json", place["Position"], place["Rotation"], o];
    Quiet @ Check[Export[applyFile, applyJSON, "RawJSON"],
      Return[Failure["Write", <|"MessageTemplate" -> "apply.json を書けませんでした: " <> applyFile|>]]];
    AppendTo[$imLog, <|"Time" -> DateObject[], "Key" -> key, "Root" -> rootName, "Vertices" -> Length[mesh["Points"]],
      "Triangles" -> Length[mesh["Triangles"]]|>];
    If[!TrueQ[o["Apply"]],
      Return[<|"Root" -> rootName, "Key" -> key, "Files" -> {meshFile, applyFile}, "Vertices" -> Length[mesh["Points"]],
        "Triangles" -> Length[mesh["Triangles"]], "Ignored" -> mesh["Ignored"], "Placement" -> place, "Apply" -> None|>]];
    v = Quiet @ Check[ResoLoop`ResoLoopValidate[applyFile, "Strict" -> True, "Project" -> proj], $Failed];
    If[FailureQ[v], Return[v]];
    If[AssociationQ[v] && Lookup[v, "valid", True] === False,
      Return[Failure["Invalid", <|"MessageTemplate" -> "apply の検証に失敗: " <> ToString[Lookup[v, "issues", {}]],
        "Validation" -> v|>]]];
    a = imApplyWithRetry[applyFile, proj, stateFile, o["Timeout"]];
    If[FailureQ[a] || a === $Failed,
      Return[If[FailureQ[a], a, Failure["Apply", <|"MessageTemplate" -> "resoloop apply が失敗しました。"|>]]]];
    <|"Root" -> rootName, "Key" -> key, "Files" -> {meshFile, applyFile, stateFile}, "Vertices" -> Length[mesh["Points"]],
      "Triangles" -> Length[mesh["Triangles"]], "Ignored" -> mesh["Ignored"], "Placement" -> place,
      "Apply" -> a, "Seconds" -> Round[AbsoluteTime[] - t0, 0.1]|>];

ResoniteRealtime`ResoniteGraphics3DRemove[r_Association] /; KeyExistsQ[r, "Root"] :=
  ResoniteRealtime`ResoniteGraphics3DRemove[r["Root"]];
ResoniteRealtime`ResoniteGraphics3DRemove[rootName_String] :=
  Module[{hits, id},
    If[!imEnsureResoLoop[], Return[Failure["NoResoLoop", <|"MessageTemplate" -> "ResoLoop.wl がありません。"|>]]];
    hits = Quiet @ Check[ResoLoop`ResoLoopFind["Name" -> rootName, "Exact" -> True], $Failed];
    (* 一致レコードの最上位の id。FirstCase[..., Infinity] は子 (components の id) を先に拾うので使わない (2026-09-22 実機) *)
    id = If[ListQ[hits],
      Lookup[SelectFirst[hits, AssociationQ[#] && Lookup[#, "name", None] === rootName &,
        SelectFirst[hits, AssociationQ, <||>]], "id", None],
      None];
    If[!StringQ[id], Return[Failure["NotFound", <|"MessageTemplate" -> rootName <> " が見つかりません。"|>]]];
    ResoLoop`ResoLoopSlotDelete[id, "Confirm" -> True]];

End[];
EndPackage[];
