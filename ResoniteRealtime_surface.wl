(* ::Package:: *)

(* ResoniteRealtime_surface.wl -- サムネイル一覧を曲面に貼る (円筒 / 球の内側 / メビウスの帯 / 任意の面。2026-09-26)

   This file is encoded in UTF-8.
   ResoniteRealtime.wl が自動でロードする (ResoniteRealtime_docboard.wl の後。同じ ResoniteRealtime`Private` コンテキストで
   タブレットと一覧の部品 (itXxx / icXxx / idXxx) を使う)。

   ---- 考え方 (2026-09-26 ユーザー指示「アバターを中心とした湾曲パネル / 球の内面に切り替えるボタン。各サムネイル領域を
   変換後の表面領域に対応させる関数を設計し、表面をフォーカスして左クリックした点が表面と交わる領域のサムネイルを開く。
   メビウスの帯やトーラスの外側など、自由に面を設計できる汎用のものに」) ----
   平面の一覧の升目 (itThumbLayout / itThumbCell) は「平面座標」(m、升目の範囲の中心が原点、x 右 / y 上) に置いてある。
   **面 (surface) は平面座標 -> 3D 点の写像** S(x, y) で、座標系は中心 (アバターの目の位置、y 上、+z = 正面) に固定:
     spec = <|"Name", "Label", "Map" -> Function[{x, y, g}, {X, Y, Z}], "Radius", "Y0", "Fit" -> Function[g, <|...|>], "Flip"|>
     g    = 面の寸法 <|"W" (升目の範囲の幅 m), "H" (高さ m), "Y0" (上下のずらし), "R" (半径), ...Fit が足す値|>
   升目 i は平面座標の中心 c_i に置いた小さな UIX Canvas (タイル) で、位置 = S(c_i)、向き = 接平面
   (ex = ∂S/∂x、ey = ∂S/∂y を直交化、ez = ex × ey。UIX の表は -z なので、ez が中心から外へ向くように面を書くと表が中心を向く)。
   タイルの絵は帯のテクスチャ (平面と同じ JPEG) の升目の矩形だけを、タイルごとの SpriteProvider.Rect (UV、左下原点、0..1) で
   切り出したもの (テクスチャは帯の枚数のまま)。2026-09-26 実機: 最初は帯全体を升目の外まで広げた Image を UIX Mask で
   切る作りにしたが、Mask が切らず、升目ごとに帯全体 (36 列 x 7 段、幅 4.7 m) がその接平面に出た (ユーザー「外側の元の平面を
   消せないか」。接平面は円筒・球の外側にあるので「外に元の平面が残っている」ように見えた)。
   **クリック = 光線と面の交点の升目**: Resonite のレーザーはタイルのコライダーに当たる = 面を升目ごとの接平面で近似した面との
   交点で、その升目の Button が ButtonValueSet<int> で番号を Selected に書く (平面と同じ監視、State スロット 1 つ)。
   同じ対応を Wolfram 側でも解ける: ResoniteThumbnailSurfaceHit[root, {origin, dir}] (Newton 法で S(x,y) = o + t d を解き、
   (x, y) を含む升目の番号を返す。面の設計の確かめとテスト用)。

   構成 (曲面):
     <Name>                   Grabbable, AI_GeneratedContent  (位置 = 中心 = アバターの目、向き = 視線の水平方向)
     ├─ State                 ValueField<int> Selected (平面と同じ。-4 = 形を変える)
     ├─ Data                  署名つき行 (平面と同じ + "shape" / "geometry")
     ├─ Panel                 見出しの Canvas (題名 / 状態欄 / 接続 / 形を変更 / リスト / 閉じる / 覆い)。面の上端の上に接平面で
     ├─ Backing               見出しの裏板
     └─ Content               升目 (引き継ぎは Panel に Content が無ければ根の Content を使う)
        ├─ Assets             UI マテリアル、帯ごとの StaticTexture2D + SpriteProvider、裏板の BoxMesh + 材質 (共有)
        ├─ Cell<i>            Canvas + SpriteProvider (帯 k、Rect = 升目) + Image (位置・向き = S(c_i) の接平面、拡大率 = px -> m)
        │  └─ Hit             ほぼ透明の Image + Button + ButtonValueSet<int> (i)、子 Label: 題名
        └─ Back<i>            裏板 (MeshRenderer、メッシュと材質は Assets の共有)

   「形を変更」(Selected = -4): $ResoniteThumbnailShapes の順に次の形へ。曲面にするときは監視の tick で待たずに
   Root (Depth 1) -> "User ..." (Depth 1、子の Head) を読んで中心 (目の位置と視線の水平方向) を決め、同じ行で組み直す。
   アバターが見つからない / 8 秒で読めないときは、今のパネルの 1.3 m 手前 (利用者側 -z) を中心にする。
   平面に戻すときは、直前の中心の正面 1.4 m に置く。
*)

BeginPackage["ResoniteRealtime`"];

ResoniteRealtime`ResoniteThumbnailSurface::usage =
  "ResoniteThumbnailSurface[name] はサムネイル一覧を貼る面の定義 (Association) を返す。組み込み: \"Plane\" (平面), \"Cylinder\" (円筒),\n" <>
  "\"SphereInside\" (球の内側), \"Mobius\" (メビウスの帯), \"TorusOutside\" (トーラスの外側、切り替えの巡回には入れていない)。\n" <>
  "ResoniteThumbnailSurface[Function[{x, y, g}, {X, Y, Z}], opts] は任意の面を作る。x, y は平面の一覧の座標 (m、升目の範囲の中心が原点、\n" <>
  "x 右 / y 上)、g は寸法 <|\"W\", \"H\", \"Y0\", \"R\", ...|>。戻り値は中心 (アバターの目、y 上、+z = 正面) から見た点。\n" <>
  "升目の表 (UIX の -z) は ez = (∂S/∂x) × (∂S/∂y) の逆を向くので、ez が中心から外へ向くように書くと中心から見える (\"Flip\" -> True で反転)。\n" <>
  "オプション: \"Name\", \"Label\", \"Radius\" -> 1.5 (g[\"R\"] の初期値), \"Y0\" -> 0 (上下のずらし m),\n" <>
  "\"Fit\" -> None | Function[g, <|\"R\" -> ...|>] (寸法から半径などを決める)、\"Flip\" -> False。\n" <>
  "使い方: ResoniteThumbnailGadget[rows, \"Shape\" -> \"Cylinder\"] / 一覧の「形を変更」ボタン / ResoniteThumbnailShape[root, shape]。\n" <>
  "名前で使うには $ResoniteThumbnailSurfaces[\"MyShape\"] = ResoniteThumbnailSurface[...] と登録する。";
ResoniteRealtime`ResoniteThumbnailSurfaceFrames::usage =
  "ResoniteThumbnailSurfaceFrames[spec, g, {{x, y}, ...}] は平面座標の点ごとの <|\"Position\", \"Rotation\" (四元数 x,y,z,w), \"X\", \"Y\", \"Z\"|>\n" <>
  "(面の上の点と接平面。Z は升目の裏向き)。ResoniteThumbnailSurfaceFrames[root] は組んだ一覧の升目ごとのフレーム。";
ResoniteRealtime`ResoniteThumbnailSurfaceHit::usage =
  "ResoniteThumbnailSurfaceHit[root, {origin, dir}] は一覧 root の座標系 (中心 = アバター) の光線 origin + t dir (t > 0) が面と交わる点の\n" <>
  "升目の番号を返す (升目の間 / 面に当たらなければ None)。ResoniteThumbnailSurfaceHit[root, {origin, dir}, \"Detail\"] は\n" <>
  "<|\"Cell\", \"XY\" (平面座標), \"Point\", \"T\"|>。ワールドのクリックは Resonite が升目のコライダーで同じことをする。";
ResoniteRealtime`ResoniteThumbnailShape::usage =
  "ResoniteThumbnailShape[root, shape] はサムネイル一覧 root を別の形 (\"Plane\" | \"Cylinder\" | \"SphereInside\" | \"Mobius\" | 面の定義) で組み直す。\n" <>
  "ResoniteThumbnailShape[root] は次の形 ($ResoniteThumbnailShapes の順。一覧の「形を変更」ボタンと同じ)。\n" <>
  "曲面の中心はアバターの目の位置 (監視の tick の中なら待たずに読む)。";
ResoniteRealtime`$ResoniteThumbnailShapes::usage =
  "$ResoniteThumbnailShapes (既定 {\"Plane\", \"Cylinder\", \"SphereInside\", \"Mobius\"}): 一覧の「形を変更」ボタンが巡回する形の順。\n" <>
  "名前 ($ResoniteThumbnailSurfaces のキー) か ResoniteThumbnailSurface[...] の定義を並べる。";
ResoniteRealtime`$ResoniteThumbnailSurfaces::usage =
  "$ResoniteThumbnailSurfaces は名前 -> 面の定義 (ResoniteThumbnailSurface[...]) の登録簿。組み込みの形はロードのたびに入れ直し、\n" <>
  "利用者が足した名前は残す。";

Begin["`Private`"];

(* ============================================================
   面の定義
   ============================================================ *)

(* "TwoSided" -> True: 同じ場所の表と裏の両方に升目が来る面 (メビウスの帯の 2 周目)。升目は面から表の側へ裏板の厚みの半分だけ浮かせ、
   裏板は面の中央に置く (裏側の升目の裏板が表側の升目を隠さないように)。光線の逆写像は光線に表を向けた升目を選ぶ *)
(* "Rows" -> None | Function[{n, cw, spec, dims}, 段数]: 面に合わせた升目の段数 (n = 件数、cw = 升目 1 列の幅 m、
   dims = <|"CW", "CH" (段の高さ m), "Pad" (余白 m)|>。3 引数の関数でもよい)。None なら平面と同じ
   (縦 MaxRows 段、横に伸ばす) *)
$itSurfaceDefaults = <|"Name" -> "Custom", "Label" -> Automatic, "Radius" -> 1.5, "Y0" -> 0., "Fit" -> None, "Flip" -> False,
  "TwoSided" -> False, "Rows" -> None|>;

Options[ResoniteRealtime`ResoniteThumbnailSurface] = {"Name" -> "Custom", "Label" -> Automatic, "Radius" -> 1.5, "Y0" -> 0.,
  "Fit" -> None, "Flip" -> False, "TwoSided" -> False, "Rows" -> None};
ResoniteRealtime`ResoniteThumbnailSurface[name_String] :=
  Replace[Lookup[ResoniteRealtime`$ResoniteThumbnailSurfaces, name, None],
    None :> iFailure["UnknownShape", "形 " <> name <> " は登録されていません。登録済み: " <>
      StringRiffle[Keys[ResoniteRealtime`$ResoniteThumbnailSurfaces], ", "]]];
ResoniteRealtime`ResoniteThumbnailSurface[map_, opts : OptionsPattern[]] /; !StringQ[map] && !AssociationQ[map] :=
  Join[$itSurfaceDefaults, Association[Options[ResoniteRealtime`ResoniteThumbnailSurface]], Association[{opts}], <|"Map" -> map|>];
ResoniteRealtime`ResoniteThumbnailSurface[a_Association] /; KeyExistsQ[a, "Map"] := Join[$itSurfaceDefaults, a];

(* 球の内側: 半径は、上下の端 (φ) で cos φ が縮めても横の端が ±0.9π に収まるよう、また上下の端が 1.2 rad を超えないよう広げる *)
(* 球の内側の半径: 次を満たす一番小さい R
     R >= 最小半径 (spec の "Radius")、上下の端の緯度 ym / R <= $itSphereMaxLat、
     一番上 (下) の段でも横の端が ±0.9π に収まる: (W/2) / (R cos(ym/R)) <= 0.9π  <=>  R cos(ym/R) >= W / (1.8π)
   R cos(ym/R) は R について単調増加なので二分法で解く (2026-09-26: 前の反復 R = f(R) は段が多いと振動して、
   升目が極の近くで重なる半径を返すことがあった) *)
$itSphereMaxLat = 1.0;   (* 升目を置く緯度の上限 (rad、約 57°。頭上・足元まで貼らない) *)
itSphereMinR[w_?NumericQ, ym_?NumericQ, rmin_?NumericQ] :=
  Module[{need = w/(1.8 Pi), g = #1 Cos[ym/#1] &, lo, hi},
    lo = N[Max[rmin, ym/$itSphereMaxLat, 10^-3]];
    If[g[lo] >= need, Return[lo]];
    hi = 2 lo; While[g[hi] < need, hi *= 2];
    Do[With[{m = (lo + hi)/2}, If[g[m] >= need, hi = m, lo = m]], {60}];
    hi];
itSphereFit[g_Association] := <|"R" -> itSphereMinR[g["W"], g["H"]/2 + Abs[g["Y0"]], g["R"]]|>;
(* 球の段数 (2026-09-26 ユーザー「球の内面表示で湾曲が足りない。半径を小さく」): 平面と同じ 7 段だと横長の帯
   (462 件 = 66 列 x 7 段、緯度 ±28°) になり、横幅を ±0.9π に収めるために半径が 1.7 m に広がって円筒のように見えた。
   段数を 1..24 で試して半径が一番小さくなる段数にする。1% 以内で並ぶ段数 (件数が少なく最小半径 1.0 m で頭打ちのとき等) からは、
   球らしい釣り合い = 経度の半幅 ≈ 緯度の半幅の 2 倍 (球面の 360° x 180°) に一番近い段数を選ぶ (1 段の輪にならない)。
   同じサムネイルの大きさで 462 件 = 12 段・半径 1.48 m・緯度 ±53°、289 件 = 10 段・1.18 m (7 段のときは 1.72 m / 1.5 m)。
   dims = <|"CW" (列の幅 m), "CH" (段の高さ m), "Pad" (余白 m)|> (itSurfaceLayoutOpts が渡す) *)
itSphereRows[n_Integer, cw_?NumericQ, spec_Association, dims_Association] :=
  Module[{cands, best},
    cands = Table[
      With[{w = Ceiling[n/r] dims["CW"] + dims["Pad"], ym = (r dims["CH"] + dims["Pad"])/2 + Abs[spec["Y0"]]},
        With[{R = itSphereMinR[w, ym, spec["Radius"]]},
          (* {段数, 半径, 経度の半幅 / 緯度の半幅} *)
          {r, R, (w/2)/(R Cos[ym/R])/(ym/R)}]],
      {r, 1, Min[24, Max[1, n]]}];
    best = Min[cands[[All, 2]]];
    First[MinimalBy[Select[cands, #[[2]] <= 1.01 best &], Abs[Log[#[[3]]/2]] &]][[1]]];

(* メビウスの帯の段数: 2 周 (= 4π R0) を 9 割以上埋める一番多い段数 (MaxRows 段まで)。少なすぎて埋まらなければ 1 段
   (2026-09-26 ユーザー「半分の長さにするか、縦の列を削減することで表裏両方に」。289 件 = 2 段 x 145 列、462 件 = 3 段、1000 件以上は 7 段で
   半径が広がる。7 段のままだと 289 件の帯は 2 周で 5.5 m しかなく、半径 1.6 m の輪 (1 周 10 m) の 3 割にしか升目が無かった) *)
itMobiusRows[n_Integer, cw_?NumericQ, spec_Association, maxRows_Integer : 7] :=
  With[{need = 0.9*4 Pi spec["Radius"]},
    SelectFirst[Range[Max[1, maxRows], 1, -1], Ceiling[n/#]*cw >= need &, 1]];

$itSurfaceBuiltins = <|
  (* 平面 (タイル版。「形を変更」の平面は従来の Canvas 1 枚で組む。面の関数の確かめ用) *)
  "Plane" -> <|"Name" -> "Plane", "Label" -> "平面", "Radius" -> 1.4, "Y0" -> 0., "Fit" -> None, "Flip" -> False,
    "Map" -> Function[{x, y, g}, {x, y, g["R"]}]|>,
  (* 円筒: 中心を軸に、横 x を弧長にして巻く (幅が 0.9 周を超えるなら半径を広げる) *)
  "Cylinder" -> <|"Name" -> "Cylinder", "Label" -> "円筒", "Radius" -> 1.3, "Y0" -> -0.1, "Flip" -> False,
    "Fit" -> Function[g, <|"R" -> N[Max[g["R"], g["W"]/(2 Pi 0.9)]]|>],
    "Map" -> Function[{x, y, g}, With[{R = g["R"], t = x/g["R"]}, {R Sin[t], y, R Cos[t]}]]|>,
  (* 球の内側: 正弦図法 (φ = y/R、θ = x/(R cos φ)) で横の間隔を保つ (極に寄っても升目が重ならない) *)
  "SphereInside" -> <|"Name" -> "SphereInside", "Label" -> "球の内側", "Radius" -> 1.0, "Y0" -> -0.1, "Flip" -> False,
    "Fit" -> itSphereFit, "Rows" -> Function[{n, cw, spec, dims}, itSphereRows[n, cw, spec, dims]],
    "Map" -> Function[{x, y, g},
      With[{R = g["R"], ph = y/g["R"]}, With[{th = x/(g["R"] Cos[ph])}, R {Cos[ph] Sin[th], Sin[ph], Cos[ph] Cos[th]}]]]|>,
  (* メビウスの帯: 中心の周りの円 (半径 R) に沿って横 x を **2 周** (s = 4π x / W)、縦 y は半回転ねじれる向き
     w(s) = cos(s/2) 上 + sin(s/2) 外。s = 0 (正面) で縦に立ち、真後ろで水平。
     2026-09-26 ユーザー指示「表裏がないのがポイントなのに片面にしか割り当てられていない」: w(s + 2π) = -w(s) なので
     2 周目は S(x + W/2, y) = S(x, -y) と同じ点に、接平面の法線が逆向きで来る = 1 周目の裏面。帯の長さは平面の半分 (1 周 = W/2) で、
     一続きの升目の列が表と裏を両方埋める (表裏の区別が無い面をたどると 2 周で元に戻る)。両端は S(W/2, y) = S(-W/2, y) *)
  "Mobius" -> <|"Name" -> "Mobius", "Label" -> "メビウスの帯", "Radius" -> 1.6, "Y0" -> 0., "Flip" -> False, "TwoSided" -> True,
    "Rows" -> Function[{n, cw, spec}, itMobiusRows[n, cw, spec]],
    "Fit" -> Function[g, <|"R" -> N[Max[g["R"], g["W"]/(4 Pi)]]|>],
    "Map" -> Function[{x, y, g},
      With[{s = 4 Pi x/g["W"]}, With[{rh = {Sin[s], 0, Cos[s]}}, g["R"] rh + y (Cos[s/2] {0, 1, 0} + Sin[s/2] rh)]]]|>,
  (* トーラスの外側 (面の設計の例。巡回には入れていない): 正面 D m に縦軸のトーラス (大半径 A、管の半径 B)。
     横 x を外周の弧長 (u = x / (A + B))、縦 y を管の角 (v = y / B) にして、手前の外側の面に貼る *)
  "TorusOutside" -> <|"Name" -> "TorusOutside", "Label" -> "トーラスの外側", "Radius" -> 0.9, "Y0" -> 0., "Flip" -> False,
    "Fit" -> Function[g, With[{b = N[Max[0.45, g["H"]/2.6]]}, With[{a = N[Max[g["R"], g["W"]/(2 Pi 0.9) - b]]},
      <|"A" -> a, "B" -> b, "D" -> a + b + 1.0|>]]],
    "Map" -> Function[{x, y, g},
      With[{u = x/(g["A"] + g["B"]), v = y/g["B"]}, With[{m = {Sin[u], 0, -Cos[u]}},
        {0, 0, g["D"]} + g["A"] m + g["B"] (Cos[v] m + Sin[v] {0, 1, 0})]]]|>
|>;
(* 組み込みはロードのたびに入れ直し、利用者が足した名前は残す *)
ResoniteRealtime`$ResoniteThumbnailSurfaces =
  Join[If[AssociationQ[ResoniteRealtime`$ResoniteThumbnailSurfaces], ResoniteRealtime`$ResoniteThumbnailSurfaces, <||>],
    $itSurfaceBuiltins];
If[!ListQ[ResoniteRealtime`$ResoniteThumbnailShapes],
  ResoniteRealtime`$ResoniteThumbnailShapes = {"Plane", "Cylinder", "SphereInside", "Mobius"}];

itSurfaceSpec[s_String] := With[{a = Lookup[ResoniteRealtime`$ResoniteThumbnailSurfaces, s, None]},
  If[AssociationQ[a] && KeyExistsQ[a, "Map"], Join[$itSurfaceDefaults, a], None]];
itSurfaceSpec[a_Association] := If[KeyExistsQ[a, "Map"], Join[$itSurfaceDefaults, a], None];
itSurfaceSpec[_] := None;
itSurfaceName[s_String] := s;
itSurfaceName[a_Association] := ToString[Lookup[a, "Name", "Custom"]];
itSurfaceName[_] := "Plane";
itSurfaceLabel[s_] :=
  With[{sp = itSurfaceSpec[s]},
    Which[
      itSurfaceName[s] === "Plane", "平面",
      AssociationQ[sp] && StringQ[sp["Label"]], sp["Label"],
      True, itSurfaceName[s]]];
(* 曲面で組むか (平面は従来の Canvas 1 枚。"Plane" の名前なら定義があっても平面の組み立て) *)
itSurfaceShapeQ[s_] := itSurfaceName[s] =!= "Plane" && AssociationQ[itSurfaceSpec[s]];
itSurfaceRecQ[rec_Association] := itSurfaceName[Lookup[rec, "Shape", "Plane"]] =!= "Plane";
itSurfaceRecQ[_] := False;

(* 升目の並べ方のオプション: 面が "Rows" を持てば、その段数になる列数 ("Columns") を足す (itThumbPlan から。帯の JPEG の鍵にも入る)。
   列数を明示されていれば触らない *)
itSurfaceLayoutOpts[o_Association, n_Integer] :=
  Module[{sp = itSurfaceSpec[Lookup[o, "Shape", "Plane"]], tw, cw, rows},
    If[!itSurfaceShapeQ[Lookup[o, "Shape", "Plane"]] || !AssociationQ[sp] || sp["Rows"] === None || IntegerQ[Lookup[o, "Columns", None]] || n < 1,
      Return[o]];
    tw = Round[o["ThumbSize"][[1]]];
    cw = (tw + 16)*o["ThumbMeters"]/tw;   (* 升目 1 列 = サムネイル幅 + 隙間 16 px (itThumbLayout) *)
    (* 4 つ目の引数: 段の高さ (サムネイル + 題名 + 隙間) と上下左右の余白 (2 x 24 - 16 px)。3 引数の関数には渡らない *)
    rows = Quiet @ Check[sp["Rows"][n, N[cw], sp,
      <|"CW" -> N[cw], "CH" -> N[(Round[o["ThumbSize"][[2]]] + Round[o["LabelHeight"]] + 16)*o["ThumbMeters"]/tw],
        "Pad" -> N[32*o["ThumbMeters"]/tw]|>], None];
    If[!IntegerQ[rows] || rows < 1, Return[o]];
    Join[o, <|"Columns" -> Ceiling[n/rows], "MaxRows" -> rows|>]];

(* 寸法: W / H (m) と定義の初期値に、Fit の結果を重ねる *)
itSurfaceGeometry[spec_Association, wM_?NumericQ, hM_?NumericQ] :=
  Module[{g = <|"W" -> N[wM], "H" -> N[hM], "Y0" -> N[spec["Y0"]], "R" -> N[spec["Radius"]]|>, f = spec["Fit"]},
    If[f =!= None, With[{r = Quiet @ Check[f[g], <||>]}, If[AssociationQ[r], g = Join[g, N[r]]]]];
    g];

(* ============================================================
   面の上の点と接平面 (升目 1 つ = タイル 1 枚の置き方)
   ============================================================ *)
itSurfacePoint[spec_Association, g_Association, {x_?NumericQ, y_?NumericQ}] :=
  N[spec["Map"][N[x], N[y + g["Y0"]], g]];

(* 回転行列 (列 = 回した x / y / z 軸) -> 四元数 {x, y, z, w} (icQuatRotate / itQRotate と同じ規約) *)
itMatToQuat[{ex_List, ey_List, ez_List}] :=
  Module[{m = Transpose[{ex, ey, ez}], tr, s},
    tr = m[[1, 1]] + m[[2, 2]] + m[[3, 3]];
    N @ Which[
      tr > 0,
        s = 2 Sqrt[tr + 1];
        {(m[[3, 2]] - m[[2, 3]])/s, (m[[1, 3]] - m[[3, 1]])/s, (m[[2, 1]] - m[[1, 2]])/s, s/4},
      m[[1, 1]] > m[[2, 2]] && m[[1, 1]] > m[[3, 3]],
        s = 2 Sqrt[1 + m[[1, 1]] - m[[2, 2]] - m[[3, 3]]];
        {s/4, (m[[1, 2]] + m[[2, 1]])/s, (m[[1, 3]] + m[[3, 1]])/s, (m[[3, 2]] - m[[2, 3]])/s},
      m[[2, 2]] > m[[3, 3]],
        s = 2 Sqrt[1 + m[[2, 2]] - m[[1, 1]] - m[[3, 3]]];
        {(m[[1, 2]] + m[[2, 1]])/s, s/4, (m[[2, 3]] + m[[3, 2]])/s, (m[[1, 3]] - m[[3, 1]])/s},
      True,
        s = 2 Sqrt[1 + m[[3, 3]] - m[[1, 1]] - m[[2, 2]]];
        {(m[[1, 3]] + m[[3, 1]])/s, (m[[2, 3]] + m[[3, 2]])/s, s/4, (m[[2, 1]] - m[[1, 2]])/s}]];

$itSurfaceStep = 10^-4;
itSurfaceFrame[spec_Association, g_Association, {x_?NumericQ, y_?NumericQ}] :=
  Module[{h = $itSurfaceStep, p, sx, sy, ex, ey, ez},
    p = itSurfacePoint[spec, g, {x, y}];
    sx = (itSurfacePoint[spec, g, {x + h, y}] - itSurfacePoint[spec, g, {x - h, y}])/(2 h);
    sy = (itSurfacePoint[spec, g, {x, y + h}] - itSurfacePoint[spec, g, {x, y - h}])/(2 h);
    (* 退化した点 (微分が 0) は正面向きの平面として扱う *)
    ex = If[Norm[sx] < 10^-9, {1., 0., 0.}, sx/Norm[sx]];
    ey = sy - (sy . ex) ex;
    ey = If[Norm[ey] < 10^-9, With[{t = Cross[{0., 0., 1.}, ex]}, If[Norm[t] < 10^-9, {0., 1., 0.}, t/Norm[t]]], ey/Norm[ey]];
    ez = Cross[ex, ey];
    If[TrueQ[spec["Flip"]], ex = -ex; ez = -ez];
    <|"Position" -> p, "Rotation" -> itMatToQuat[{ex, ey, ez}], "X" -> ex, "Y" -> ey, "Z" -> ez|>];

ResoniteRealtime`ResoniteThumbnailSurfaceFrames[spec0_, g_Association, pts_List] :=
  With[{spec = itSurfaceSpec[spec0]},
    If[!AssociationQ[spec], iFailure["UnknownShape", "面の定義がありません: " <> ToString[Short[spec0]]],
      Map[itSurfaceFrame[spec, g, #] &, pts]]];
ResoniteRealtime`ResoniteThumbnailSurfaceFrames[root_String] :=
  Module[{rec = Lookup[itThumbs[], root, None], spec},
    If[!AssociationQ[rec] || !itSurfaceRecQ[rec], Return[iFailure["NotSurface", root <> " は曲面の一覧ではありません。"]]];
    spec = itSurfaceSpec[rec["Surface"]];
    If[!AssociationQ[spec], Return[iFailure["UnknownShape", "面の定義がありません。"]]];
    Map[itSurfaceFrame[spec, rec["Geometry"], #] &, itSurfaceCells[rec["Layout"], rec["Scale"]]]];

(* 升目の中心の平面座標 (m)。原点 = 升目の範囲 (帯から見出しを除いた部分、幅 SW x 高さ H - HH) の中心、y は上向き *)
itSurfaceCells[L_Association, ps_] :=
  Module[{yc = L["HH"] + (L["H"] - L["HH"])/2},
    Table[With[{r = itThumbCell[L, i]},
        N[{(r[[1]] + r[[3]]/2 - L["SW"]/2)*ps, (yc - (r[[2]] + r[[4]]/2))*ps}]],
      {i, L["N"]}]];
itSurfaceGridMeters[L_Association, ps_] := N[{L["SW"]*ps, (L["H"] - L["HH"])*ps}];

(* 平面座標の点を含む升目 (升目の間なら None) *)
itSurfaceCellAtXY[L_Association, ps_, {x_?NumericQ, y_?NumericQ}] :=
  Module[{cells = itSurfaceCells[L, ps], hw = L["TW"]*ps/2, hh = (L["TH"] + L["LH"])*ps/2, i},
    i = SelectFirst[Range[Length[cells]], Abs[x - cells[[#, 1]]] <= hw && Abs[y - cells[[#, 2]]] <= hh &, None];
    i];

(* ============================================================
   逆写像: 光線 o + t d (t > 0) と面の交点 -> 平面座標 -> 升目
   S(x, y) - o - t d = 0 を (x, y, t) について Newton 法で解く。初期値は面を粗く標本した点のうち光線に近いもの
   ============================================================ *)
itSurfaceRayHit[spec_Association, g_Association, {o_List, d0_List}] :=
  Module[{d = N[d0]/Norm[N[d0]], xs, ys, samples, dist, starts, solve, sols, h = $itSurfaceStep, W = g["W"], H = g["H"]},
    xs = Subdivide[-W/2, W/2, 48]; ys = Subdivide[-H/2, H/2, 12];
    samples = Flatten[Table[{x, y}, {x, xs}, {y, ys}], 1];
    (* 光線 (前方だけ) からの距離 *)
    dist = Map[With[{v = itSurfacePoint[spec, g, #] - o}, With[{t = v . d}, If[t <= 0, Infinity, Norm[v - t d]]]] &, samples];
    (* 表裏のある面は同じ点に 2 つの (x, y) がある。両方の近くから解けるよう多めに *)
    starts = samples[[Take[Ordering[dist], UpTo[12]]]];
    solve[{x0_, y0_}] :=
      Module[{z = {x0, y0, (itSurfacePoint[spec, g, {x0, y0}] - o) . d}, F, J, dz, k = 0},
        F[{x_, y_, t_}] := itSurfacePoint[spec, g, {x, y}] - o - t d;
        While[k++ < 30,
          J = Transpose[{
            (itSurfacePoint[spec, g, {z[[1]] + h, z[[2]]}] - itSurfacePoint[spec, g, {z[[1]] - h, z[[2]]}])/(2 h),
            (itSurfacePoint[spec, g, {z[[1]], z[[2]] + h}] - itSurfacePoint[spec, g, {z[[1]], z[[2]] - h}])/(2 h),
            -d}];
          dz = Quiet @ Check[LinearSolve[J, F[z]], $Failed];
          If[!VectorQ[dz, NumericQ], Return[None, Module]];
          z = z - dz;
          If[Norm[dz] < 10^-9, Break[]]];
        If[Norm[F[z]] < 10^-6 && z[[3]] > 0 && Abs[z[[1]]] <= W/2 + 10^-6 && Abs[z[[2]]] <= H/2 + 10^-6, z, None]];
    sols = SortBy[DeleteCases[solve /@ starts, None], Last];
    If[sols === {}, Return[None]];
    (* 同じ点に表と裏の升目がある面 (TwoSided): 一番近い交点のうち、升目の表 (-Z) が光線の来る側を向くもの (Z . d > 0) *)
    With[{near = Select[sols, #[[3]] - sols[[1, 3]] < 10^-6 &]},
      SelectFirst[near, itSurfaceFrame[spec, g, #[[1 ;; 2]]]["Z"] . d > 0 &, First[near]]]];

ResoniteRealtime`ResoniteThumbnailSurfaceHit[root_String, ray : {_List, _List}, detail_ : None] :=
  Module[{rec = Lookup[itThumbs[], root, None], spec, g, z, cell},
    If[!AssociationQ[rec], Return[iFailure["NoGadget", root <> " はサムネイル一覧ではありません。"]]];
    If[itSurfaceRecQ[rec],
      spec = itSurfaceSpec[rec["Surface"]]; g = rec["Geometry"],
      (* 平面の一覧: 根の平面 (z = 0、升目の範囲の中心は根の中心から見出しの分だけ下) *)
      With[{L = rec["Layout"], ps = rec["Scale"]},
        spec = itSurfaceSpec["Plane"];
        g = <|"W" -> L["SW"]*ps, "H" -> (L["H"] - L["HH"])*ps, "Y0" -> 0., "R" -> 0.|>;
        spec["Map"] = With[{dx = (L["SW"]/2 - L["W"]/2)*ps, dy = -L["HH"]*ps/2}, Function[{x, y, gg}, {x + dx, y + dy, 0.}]]]];
    If[!AssociationQ[spec] || !AssociationQ[g], Return[iFailure["UnknownShape", "面の定義がありません。"]]];
    z = itSurfaceRayHit[spec, g, N[ray]];
    cell = If[ListQ[z], itSurfaceCellAtXY[rec["Layout"], rec["Scale"], z[[1 ;; 2]]], None];
    If[detail === "Detail",
      <|"Cell" -> cell, "XY" -> If[ListQ[z], z[[1 ;; 2]], None],
        "Point" -> If[ListQ[z], itSurfacePoint[spec, g, z[[1 ;; 2]]], None], "T" -> If[ListQ[z], z[[3]], None]|>,
      cell]];

(* ============================================================
   中心 (アバターの目の位置と視線の水平方向)
   ============================================================ *)
$itSurfaceViewDistance = 1.3;    (* アバターが見つからないとき: 平面の一覧のこれだけ手前 (利用者側 -z) を中心に *)
$itSurfacePlaneDistance = 1.4;   (* 曲面から平面に戻すとき: 中心の正面これだけ先に置く *)
$itSurfaceUserWait = 8;          (* アバターの読み取りを待つ秒数 (tick の巡を跨いで) *)

(* 利用者の根 (Depth 1 で読んだ data。子の "Head" があれば目の位置と視線) -> 中心 *)
itUserCenterFrom[d_Association] :=
  Module[{p, q, sc, parent, head, hp, hq, f, eye},
    p = itSlotVec[d, "position", {"x", "y", "z"}, None];
    q = itSlotVec[d, "rotation", {"x", "y", "z", "w"}, {0., 0., 0., 1.}];
    sc = itSlotVec[d, "scale", {"x", "y", "z"}, {1., 1., 1.}];
    parent = Lookup[Replace[Lookup[d, "parent", <||>], Except[_Association] -> <||>], "targetId", None];
    If[!ListQ[p] || !StringQ[parent], Return[None]];
    head = SelectFirst[Lookup[d, "children", {}], AssociationQ[#] && ToString[itVal[Lookup[#, "name", ""]]] === "Head" &, None];
    hp = If[AssociationQ[head], itSlotVec[head, "position", {"x", "y", "z"}, None], None];
    hq = If[AssociationQ[head], itSlotVec[head, "rotation", {"x", "y", "z", "w"}, None], None];
    (* デスクトップでは根の回転が視線と一致しない (Head がヨーを持つ) ので頭の回転を掛ける (icUserFrontPose と同じ) *)
    f = icQuatForward[If[ListQ[hq], icQuatMul[q, hq], q]];
    f = {f[[1]], 0., f[[3]]};
    If[Norm[f] < 10^-6, f = icQuatForward[q] {1, 0, 1}];
    If[Norm[f] < 10^-6, f = {0., 0., 1.}];
    eye = p + If[ListQ[hp], itQRotate[q, sc*hp], {0., 1.6*sc[[2]], 0.}];
    <|"Parent" -> parent, "Position" -> N[eye], "Rotation" -> N[icYawQuat[f/Norm[f]]],
      "User" -> ToString[itVal[Lookup[d, "name", ""]]]|>];

(* 読み取りの応答から利用者の根の候補 ("User ..." という名の子) *)
itUserSlotsIn[res_Association] :=
  Select[itSlotsUpTo[Replace[Lookup[res, "data", <||>], Except[_Association] -> <||>], 1],
    StringQ[Lookup[#, "id", None]] && StringStartsQ[ToString[itVal[Lookup[#, "name", ""]]], "User "] &];

(* 複数いれば、一覧に一番近い人 (押した人のはず)。一覧とアバターの親が違ってもよいよう、Root の直下の入れ物の姿勢 (frames:
   id -> {position, rotation, scale}、Root の読み取りに入っている) で両方を Root の座標に直して比べる。直せなければ同じ親の中で、
   それも無ければ最初の人 *)
itToRootFrame[parent_, p_List, frames_Association] :=
  Which[
    parent === "Root", p,
    KeyExistsQ[frames, parent], With[{f = frames[parent]}, f[[1]] + itQRotate[f[[2]], f[[3]]*p]],
    True, None];
itSlotParent[s_Association] := Lookup[Replace[Lookup[s, "parent", <||>], Except[_Association] -> <||>], "targetId", None];
itPickUser[users_List, near_] := itPickUser[users, near, <||>];
itPickUser[users_List, near_, frames_Association] :=
  Module[{np, withPos, same},
    If[Length[users] <= 1 || !AssociationQ[near] || !ListQ[Lookup[near, "Position", None]], Return[First[users, None]]];
    np = itToRootFrame[Lookup[near, "Parent", None], near["Position"], frames];
    withPos = Map[{#, With[{p = itSlotVec[#, "position", {"x", "y", "z"}, None]},
        If[ListQ[p], itToRootFrame[itSlotParent[#], p, frames], None]]} &, users];
    If[ListQ[np] && AnyTrue[withPos, ListQ[#[[2]]] &],
      Return[First[SortBy[Select[withPos, ListQ[#[[2]]] &], Norm[#[[2]] - np] &]][[1]]]];
    same = Select[users, itSlotParent[#] === Lookup[near, "Parent", None] && ListQ[itSlotVec[#, "position", {"x", "y", "z"}, None]] &];
    If[same === {}, First[users],
      First[SortBy[same, Norm[itSlotVec[#, "position", {"x", "y", "z"}, {0., 0., 0.}] - near["Position"]] &]]]];

(* 一覧の記録 (または置き場所) から、アバターが見つからないときの中心:
   曲面の一覧ならその中心、平面の一覧ならパネルの手前 (利用者側 -z) $itSurfaceViewDistance *)
itSurfaceFallbackCenter[rec_] :=
  Module[{c = If[AssociationQ[rec], Lookup[rec, "Center", None], None], pose, q},
    If[AssociationQ[c], Return[c]];
    pose = If[AssociationQ[rec], Lookup[rec, "Pose", None], None];
    If[!AssociationQ[pose] || !ListQ[Lookup[pose, "Position", None]],
      pose = Quiet @ Check[itThumbPose[1.4, 1.2, Association[Options[ResoniteRealtime`ResoniteThumbnailGadget]]], None]];
    If[!AssociationQ[pose], Return[<|"Parent" -> "Root", "Position" -> {0., 1.5, 0.}, "Rotation" -> {0., 0., 0., 1.}|>]];
    q = Replace[Lookup[pose, "Rotation", None], Except[{_, _, _, _}] -> {0., 0., 0., 1.}];
    <|"Parent" -> pose["Parent"], "Position" -> N[pose["Position"] + itQRotate[q, {0., 0., -$itSurfaceViewDistance}]],
      "Rotation" -> N[q]|>];

(* ノートブックから (待ってよい): アバターを getSlot で探す。見つからなければ fallback *)
itSurfaceCenterSync[rec_] :=
  Module[{u = Quiet @ Check[icUserRoot[Automatic], None], d},
    If[!AssociationQ[u], Return[itSurfaceFallbackCenter[rec]]];
    d = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeGetSlot[u["Id"], "Depth" -> 1, "IncludeComponentData" -> False, "Timeout" -> 20], $Failed];
    Replace[If[AssociationQ[d] && AssociationQ[Lookup[d, "data", None]], itUserCenterFrom[d["data"]], None],
      None :> itSurfaceFallbackCenter[rec]]];

(* 平面の一覧を中心の正面に置く姿勢 (曲面から平面に戻すとき) *)
itFlatPoseFromCenter[c_Association] :=
  With[{q = Replace[Lookup[c, "Rotation", None], Except[{_, _, _, _}] -> {0., 0., 0., 1.}]},
    <|"Parent" -> c["Parent"], "Position" -> N[c["Position"] + itQRotate[q, {0., 0., $itSurfacePlaneDistance}]], "Rotation" -> N[q]|>];

itWithCenter[opts_List, c_] := Append[DeleteCases[opts, ("Center" -> _) | ("Center" :> _)], "Center" -> c];

(* ============================================================
   形の切り替え (「形を変更」= Selected -4、ResoniteThumbnailShape)
   ============================================================ *)
itThumbNextShape[cur_] :=
  Module[{list = ResoniteRealtime`$ResoniteThumbnailShapes, names, k},
    If[!ListQ[list] || list === {}, list = {"Plane", "Cylinder", "SphereInside", "Mobius"}];
    names = itSurfaceName /@ list;
    k = FirstPosition[names, itSurfaceName[cur], {0}][[1]];
    list[[Mod[k, Length[list]] + 1]]];

ResoniteRealtime`ResoniteThumbnailShape[root_String] :=
  With[{rec = Lookup[itThumbs[], root, None]},
    If[!AssociationQ[rec], iFailure["NoGadget", root <> " はサムネイル一覧ではありません。"],
      ResoniteRealtime`ResoniteThumbnailShape[root, itThumbNextShape[Lookup[rec, "Shape", "Plane"]]]]];
ResoniteRealtime`ResoniteThumbnailShape[root_String, shape_] :=
  Module[{rec = Lookup[itThumbs[], root, None], opts},
    If[!AssociationQ[rec], Return[iFailure["NoGadget", root <> " はサムネイル一覧ではありません。"]]];
    If[itSurfaceName[shape] =!= "Plane" && !AssociationQ[itSurfaceSpec[shape]],
      Return[iFailure["UnknownShape", "形 " <> itSurfaceName[shape] <> " は登録されていません。"]]];
    opts = {"Title" -> rec["Title"], "Name" -> Lookup[rec, "Name", "SourceVault Thumbnails"], "Shape" -> shape};
    Which[
      (* 平面へ: 直前の中心 (曲面なら) の正面、無ければタブレットの隣 *)
      !itSurfaceShapeQ[shape],
        idBoardStatus[root, "形を変えています: " <> itSurfaceLabel[shape]];
        itThumbRebuild[root, itWithCenter[opts, Lookup[rec, "Center", Automatic]]],
      itAsyncContextQ[],
        itSurfaceJobStart[Lookup[rec, "AllRows", rec["Rows"]], opts, root, rec],
      True,
        itThumbRebuild[root, itWithCenter[opts, itSurfaceCenterSync[rec]]]]];

itThumbRebuild[root_String, opts_List] :=
  Module[{rec = Lookup[itThumbs[], root, None]},
    If[!AssociationQ[rec], Return[None]];
    ResoniteRealtime`ResoniteThumbnailGadgetRemove[root];
    ResoniteRealtime`ResoniteThumbnailGadget[Lookup[rec, "AllRows", rec["Rows"]], Sequence @@ opts]];

(* ---- tick の中の組み直し: アバターを待たずに読む (Root Depth 1 -> "User ..." Depth 1) ----
   $itState["SurfaceJobs"]: id -> <|"Phase" (Scan | ScanWait | UserWait), "Rows", "Opts", "Remove" (組み直す一覧 or None), "Near"|> *)
itSurfaceJobs[] := Replace[Lookup[$itState, "SurfaceJobs", <||>], Except[_Association] -> <||>];

itSurfaceJobStart[rows_List, opts_List, remove_, rec_] :=
  Module[{id = StringTake[CreateUUID[], 8], shape = Lookup[Association[opts], "Shape", "Plane"]},
    $itState["SurfaceJobs"] = Append[itSurfaceJobs[], id -> <|"Id" -> id, "Phase" -> "Scan", "Rows" -> rows, "Opts" -> opts,
      "Remove" -> remove, "Rec" -> rec, "Near" -> If[AssociationQ[rec], Lookup[rec, "Pose", Lookup[rec, "Center", None]], None],
      "Since" -> iNow[]|>];
    $itDeferred[id] = <|"Expr" -> None, "Label" -> "サムネイル一覧 (" <> itSurfaceLabel[shape] <> ")", "Time" -> iNow[],
      "Status" -> "Pending", "Via" -> "Surface"|>;
    If[StringQ[remove], idBoardStatus[remove, "アバターの位置を読んでいます… (次の形: " <> itSurfaceLabel[shape] <> ")"]];
    itSetStatus["サムネイル一覧を " <> itSurfaceLabel[shape] <> " にします (アバターの位置を読んでいます)"];
    <|"Deferred" -> True, "Id" -> id, "Via" -> "Surface", "Kind" -> "ThumbnailGadget", "Shape" -> itSurfaceName[shape],
      "Rows" -> Length[rows]|>];

itProcessSurfaceJobs[] :=
  KeyValueMap[Function[{id, j},
      With[{nj = Quiet @ Check[itSurfaceJobStep[j], itSurfaceJobFinish[j, None, "失敗"]; None]},
        $itState["SurfaceJobs"] = If[AssociationQ[nj], Append[itSurfaceJobs[], id -> nj], KeyDrop[itSurfaceJobs[], id]]]],
    itSurfaceJobs[]];

(* 2026-09-26 実機: アバター ("User ...") は Root の直下とは限らない (このワールドは "Spawn - User Holder" の中)。Root の直下で
   見つからず、前の中心に組み直していた (ユーザー「以前の座標が残っていてその場所に生成される」)。Root を Depth 1 で読み、入れ物
   (itHolderQ: 名前に holder / spawn) も 1 段ずつ読んで、利用者の根を全部集めてから一覧に一番近い人を選ぶ
   (ボタンは押した人を記録しないので、押した人 = 一覧に一番近いアバターとみなす。在席ゲートがあるので普通はオーナー) *)
itSurfaceJobStep[j_Association] :=
  Module[{res, kids, users, holders, u, mid, mids, c, got},
    Switch[j["Phase"],
      "Scan",
        mid = itSendGet["Root", 1, False];
        If[!StringQ[mid], itSurfaceJobFinish[j, None, "Root を読めません"]; Return[None]];
        Join[j, <|"Phase" -> "ScanWait", "MessageId" -> mid, "Sent" -> iNow[]|>],
      "ScanWait",
        res = icPollReply[j["MessageId"]];
        If[!AssociationQ[res],
          If[iNow[] - j["Sent"] > $itSurfaceUserWait, itSurfaceJobFinish[j, None, "Root の読み取りが来ません"]; Return[None]];
          Return[j]];
        kids = itSlotsUpTo[Replace[Lookup[res, "data", <||>], Except[_Association] -> <||>], 1];
        users = itUserSlotsIn[res];
        holders = Select[kids, StringQ[Lookup[#, "id", None]] && itHolderQ[#] &];
        mids = DeleteCases[Map[itSendGet[#["id"], 1, False] &, holders], Except[_String]];
        Join[j, <|"Phase" -> "HolderWait", "Users" -> users, "HolderMessages" -> mids, "Sent" -> iNow[],
          "Frames" -> Association @ Map[#["id"] -> {itSlotVec[#, "position", {"x", "y", "z"}, {0., 0., 0.}],
            itSlotVec[#, "rotation", {"x", "y", "z", "w"}, {0., 0., 0., 1.}], itSlotVec[#, "scale", {"x", "y", "z"}, {1., 1., 1.}]} &,
            Select[kids, StringQ[Lookup[#, "id", None]] &]]|>],
      "HolderWait",
        (* 入れ物の読み取りが全部来るまで ($itSurfaceUserWait 秒で打ち切り、来た分で選ぶ) *)
        got = Map[icPollReply, j["HolderMessages"]];
        If[MemberQ[got, None] && iNow[] - j["Sent"] <= $itSurfaceUserWait, Return[j]];
        users = Join[j["Users"], Flatten[Map[itUserSlotsIn, Select[got, AssociationQ]], 1]];
        users = DeleteDuplicatesBy[users, Lookup[#, "id", None] &];
        u = itPickUser[users, j["Near"], Lookup[j, "Frames", <||>]];
        If[!AssociationQ[u], itSurfaceJobFinish[j, None, "アバターが見つかりません"]; Return[None]];
        mid = itSendGet[u["id"], 1, False];
        If[!StringQ[mid], itSurfaceJobFinish[j, None, "アバターを読めません"]; Return[None]];
        Join[j, <|"Phase" -> "UserWait", "MessageId" -> mid, "Sent" -> iNow[], "User" -> u["id"], "Candidates" -> Length[users]|>],
      "UserWait",
        res = icPollReply[j["MessageId"]];
        If[!AssociationQ[res],
          If[iNow[] - j["Sent"] > $itSurfaceUserWait, itSurfaceJobFinish[j, None, "アバターの読み取りが来ません"]; Return[None]];
          Return[j]];
        c = If[AssociationQ[Lookup[res, "data", None]], itUserCenterFrom[res["data"]], None];
        itSurfaceJobFinish[j, c, If[AssociationQ[c], "", "アバターの位置が読めません"]];
        None,
      _, None]];

(* 中心が決まった (c = None ならアバター無しの中心): 古い一覧を消して組み直す (tick の中なので組み立ては予約になる) *)
itSurfaceJobFinish[j_Association, c0_, why_String] :=
  Module[{c = c0, r, note = ""},
    If[!AssociationQ[c],
      c = itSurfaceFallbackCenter[Lookup[j, "Rec", None]];
      note = " (" <> why <> "。パネルの手前を中心にします)"];
    If[StringQ[j["Remove"]] && KeyExistsQ[itThumbs[], j["Remove"]],
      ResoniteRealtime`ResoniteThumbnailGadgetRemove[j["Remove"]]];
    r = Quiet @ Check[ResoniteRealtime`ResoniteThumbnailGadget[j["Rows"], Sequence @@ itWithCenter[j["Opts"], c]], $Failed];
    $itDeferred[j["Id"]] = Join[Lookup[$itDeferred, j["Id"], <||>],
      <|"Status" -> If[AssociationQ[r], "Done", "Failed"], "Result" -> r, "Finished" -> iNow[], "Center" -> c, "Note" -> note|>];
    itSetStatus["サムネイル一覧: " <> itSurfaceLabel[Lookup[Association[j["Opts"]], "Shape", "Plane"]] <> " で組み直します" <> note];
    r];

(* ============================================================
   曲面の組み立て (itThumbGadgetBuild から。o = オプションの Association)
   ============================================================ *)
$itTileBackDepth = 0.008;

itTileBackingAssets[assets_String, {w_?NumericQ, h_?NumericQ}, depth_] :=
  Module[{mesh, mat},
    mesh = icComp[assets, $icFE <> "BoxMesh", <|"Size" -> N[{w, h, depth}]|>, ResoniteRealtime`ResoniteRealtimeNewId["TileBackMesh"]];
    mat = icComp[assets, $icFE <> "PBS_Metallic", <|"AlbedoColor" -> $itBackingColor, "Metallic" -> 0., "Smoothness" -> 0.25|>,
      ResoniteRealtime`ResoniteRealtimeNewId["TileBackMat"]];
    {mesh, mat}];
(* 升目の置き場所: 片面の面は面の上、裏板はその裏 (+Z)。表裏のある面 (TwoSided) は升目を表の側 (-Z) へ裏板の半分 + 1 mm 浮かせ、
   裏板は面の中央 (表と裏の升目が裏板を共有する形になる) *)
itTileOffset[spec_Association, depth_] := If[TrueQ[spec["TwoSided"]], depth/2 + 0.001, 0.];
itTilePosition[spec_Association, fr_Association, depth_] := N[fr["Position"] - fr["Z"] itTileOffset[spec, depth]];
itTileBack[parent_String, name_String, fr_Association, depth_, {mesh_String, mat_String}, twoSided_ : False] :=
  With[{s = icSlot[name, parent, "Position" -> N[fr["Position"] + If[TrueQ[twoSided], 0., depth/2 + 0.002] fr["Z"]],
      "Rotation" -> fr["Rotation"]]},
    icComp[s, $icFE <> "MeshRenderer",
      <|"Mesh" -> ResoniteRealtime`ResoniteRealtimeRef[mesh],
        "Materials" -> <|"$type" -> "list", "elements" -> {ResoniteRealtime`ResoniteRealtimeRef[mat]}|>|>];
    s];

(* 升目 i の帯 k と、帯の画像の中での升目の矩形 (UV: 左下原点、0..1) -> {k, {x, y, w, h}}。
   帯 k の画像は幅 wk px (最後の帯は SW - 左端)、高さ H px (見出しの帯込み)、升目の矩形は itThumbCell (左上原点の px) *)
itTileUVRect[L_Association, i_Integer, stripX_List] :=
  Module[{c = Mod[i - 1, L["Cols"]], k, r, x0s, wk, n = Length[stripX]},
    k = Min[n, Quotient[c, $itThumbStripCols] + 1];
    r = itThumbCell[L, i];
    x0s = r[[1]] - stripX[[k]];
    wk = If[k === n, L["SW"] - stripX[[k]], stripX[[k + 1]] - stripX[[k]]];
    {k, N[{x0s/wk, If[TrueQ[$itTileUVTopLeft], r[[2]], L["H"] - r[[2]] - r[[4]]]/L["H"], r[[3]]/wk, r[[4]]/L["H"]}]}];
(* UV の縦の原点 (False = 左下、テクスチャの流儀)。実機で升目の段が上下逆に出たら True にする *)
If[!BooleanQ[$itTileUVTopLeft], $itTileUVTopLeft = False];
(* ResoniteLink の Rect の書式 (2026-09-26 実機で読み書きを確認): <|"position" -> <|x, y|>, "size" -> <|x, y|>|> *)
itRectValue[{x_, y_, w_, h_}] :=
  <|"$type" -> "Rect", "value" -> <|"position" -> <|"x" -> N[x], "y" -> N[y]|>, "size" -> <|"x" -> N[w], "y" -> N[h]|>|>|>;

itThumbSurfaceBuild[o_Association, plan_Association, files_List, fs_] :=
  Module[{rows, hidden, shown, over, L, nStrips, stripX, urls, url, ps, spec, gridM, g, cells, center, root, state, sel,
          content, assets, texs, back, fr, tile, sp, hit, lbl, wires = {}, head, hy, hfr, Lh, wh, bw, panel, s,
          titleText, statusText, connectBtn, title, veil, vt, vid, fid, rec, frames, tileSize},
    {rows, hidden, shown, over, L, nStrips, stripX} = Lookup[plan, {"Rows", "Hidden", "Shown", "Over", "Layout", "NStrips", "StripX"}];
    spec = itSurfaceSpec[o["Shape"]];
    If[!AssociationQ[spec], Return[iFailure["UnknownShape", "形 " <> itSurfaceName[o["Shape"]] <> " は登録されていません。"]]];
    urls = ResoniteRealtime`ResoniteRealtimeAsset /@ files;
    url = First[urls];
    ps = N[o["ThumbMeters"]/L["TW"]];
    gridM = itSurfaceGridMeters[L, ps];
    g = itSurfaceGeometry[spec, gridM[[1]], gridM[[2]]];
    cells = itSurfaceCells[L, ps];
    frames = Map[itSurfaceFrame[spec, g, #] &, cells];
    center = Lookup[o, "Center", Automatic];
    If[!AssociationQ[center],
      (* tick の組み立ては待てない: タブレットの隣の平面の手前。ノートブックからならアバターを探す *)
      center = If[itAsyncBuildQ[], itSurfaceFallbackCenter[None], itSurfaceCenterSync[None]]];
    root = icSlot[o["Name"], center["Parent"], "Position" -> N[center["Position"]],
      Sequence @@ If[ListQ[center["Rotation"]], {"Rotation" -> N[center["Rotation"]]}, {}],
      "Id" -> ResoniteRealtime`ResoniteRealtimeNewId["Thumbs"]];
    $itBuildRoot = root;
    icComp[root, $icFE <> "Grabbable", <|"Scalable" -> True|>];
    icComp[root, $icFE <> "AI_GeneratedContent",
      <|"Source" -> "Mathematica ResoniteRealtime thumbnail gadget (SourceVault rows, surface " <> itSurfaceName[spec] <> ")"|>];
    state = icSlot["State", root];
    sel = icComp[state, $icFE <> "ValueField<int>", <|"Value" -> 0|>, ResoniteRealtime`ResoniteRealtimeNewId["ThumbSel"]];
    content = icSlot["Content", root, "Id" -> ResoniteRealtime`ResoniteRealtimeNewId["Content"]];
    (* 共有の部品: UI マテリアル、帯のテクスチャ、升目の裏板 *)
    assets = icSlot["Assets", content];
    icMakeMaterials[assets];
    texs = Map[icComp[assets, $icFE <> "StaticTexture2D", <|"URL" -> ResoniteRealtime`ResoniteRealtimeValue["Uri", #]|>,
        ResoniteRealtime`ResoniteRealtimeNewId["ThumbTex"]] &, urls];
    tileSize = N[{L["TW"], L["TH"] + L["LH"]}];
    back = itTileBackingAssets[assets, tileSize*ps + $itBackingMargin, $itTileBackDepth];
    (* 升目 = 面の上のタイル *)
    Do[
      fr = frames[[i]];
      tile = icSlot["Cell" <> ToString[i], content, "Position" -> itTilePosition[spec, fr, $itTileBackDepth], "Rotation" -> fr["Rotation"],
        "Scale" -> {ps, ps, ps}];
      icComp[tile, $icUIX <> "Canvas", <|"Size" -> tileSize, "AcceptRemoteTouch" -> True, "AcceptPhysicalTouch" -> True|>];
      (* 絵 = 帯のテクスチャの升目の矩形だけ (タイルごとの SpriteProvider.Rect。Mask は使わない) *)
      With[{kr = itTileUVRect[L, i, stripX]},
        sp = icComp[tile, $icFE <> "SpriteProvider",
          <|"Texture" -> ResoniteRealtime`ResoniteRealtimeRef[texs[[kr[[1]]]]], "Rect" -> itRectValue[kr[[2]]]|>,
          ResoniteRealtime`ResoniteRealtimeNewId["TileSprite"]]];
      icComp[tile, $icUIX <> "Image",
        Join[<|"Sprite" -> ResoniteRealtime`ResoniteRealtimeRef[sp], "PreserveAspect" -> False, "Tint" -> RGBColor[1, 1, 1, 1]|>,
          If[StringQ[Lookup[$icMats, "Image", None]], <|"Material" -> ResoniteRealtime`ResoniteRealtimeRef[$icMats["Image"]]|>, <||>]]];
      (* 押せる面 (平面の升目と同じ: ほぼ透明の Image + Button、題名はその子) *)
      hit = icSlot["Hit", tile];
      icComp[hit, $icUIX <> "RectTransform", <|"AnchorMin" -> {0., 0.}, "AnchorMax" -> {1., 1.}|>];
      icImage[hit, RGBColor[1, 1, 1, 0.01]];
      icComp[hit, $icUIX <> "Button", <||>];
      lbl = icSlot["Label", hit];
      icComp[lbl, $icUIX <> "RectTransform", <|"AnchorMin" -> {0., 0.}, "AnchorMax" -> {1., N[L["LH"]/(L["TH"] + L["LH"])]}|>];
      itText[lbl, itWrapLabel[itThumbTitle[shown[[i]]], L["TW"] - 8, fs, 3], fs, "Center", "Top"];
      itTileBack[content, "Back" <> ToString[i], fr, $itTileBackDepth, back, TrueQ[spec["TwoSided"]]];
      AppendTo[wires, {hit, i}],
      {i, Length[shown]}];
    (* 見出し: 升目の範囲の上端の少し上 (x = 0) に接平面で置く小さな Canvas *)
    wh = $itThumbMinWidth;
    Lh = <|"W" -> wh, "H" -> L["HH"], "M" -> L["M"], "HH" -> L["HH"]|>;
    hy = gridM[[2]]/2 + (L["HH"]/2 + 30)*ps;
    hfr = itSurfaceFrame[spec, g, {0., hy}];
    panel = icSlot["Panel", root, "Position" -> hfr["Position"], "Rotation" -> hfr["Rotation"], "Scale" -> {ps, ps, ps}];
    icComp[panel, $icUIX <> "Canvas", <|"Size" -> N[{wh, L["HH"]}], "AcceptRemoteTouch" -> True, "AcceptPhysicalTouch" -> True|>];
    icImage[panel, $itThumbColors["Header"]];
    With[{bk = icSlot["Backing", root, "Position" -> N[hfr["Position"] + hfr["Z"] ($itBackingDepth/2 + 0.002)],
        "Rotation" -> hfr["Rotation"]]},
      With[{mesh = icComp[bk, $icFE <> "BoxMesh",
            <|"Size" -> N[{wh*ps + 2 $itBackingMargin, L["HH"]*ps + 2 $itBackingMargin, $itBackingDepth}]|>],
          mat = icComp[bk, $icFE <> "PBS_Metallic", <|"AlbedoColor" -> $itBackingColor, "Metallic" -> 0., "Smoothness" -> 0.25|>]},
        icComp[bk, $icFE <> "MeshRenderer", <|"Mesh" -> ResoniteRealtime`ResoniteRealtimeRef[mesh],
          "Materials" -> <|"$type" -> "list", "elements" -> {ResoniteRealtime`ResoniteRealtimeRef[mat]}|>|>]]];
    title = ToString[o["Title"]] <> "  (" <> ToString[Length[shown]] <> " 件" <>
      If[hidden > 0, ", 機密度で非表示 " <> ToString[hidden], ""] <>
      If[over > 0, ", ほか " <> ToString[over] <> " 件はリストで", ""] <> ")  [" <> itSurfaceLabel[spec] <> "]";
    bw = wh - 2 L["M"] - $itHeaderButtons*160;
    s = icSlot["Title", panel];
    icComp[s, $icUIX <> "RectTransform", itAnchors[{L["M"], 8, Max[100, bw], 60}, {wh, L["HH"]}]];
    titleText = itText[s, itTruncate[title, 60], fs*1.8, "Left", "Middle", ResoniteRealtime`ResoniteRealtimeNewId["ThumbTitle"]];
    s = icSlot["StatusBar", panel];
    icComp[s, $icUIX <> "RectTransform", itAnchors[{L["M"], 76, Max[100, bw], L["HH"] - 88}, {wh, L["HH"]}]];
    icImage[s, RGBColor[0.05, 0.07, 0.11, 1]];
    s = icSlot["Status", panel];
    icComp[s, $icUIX <> "RectTransform", itAnchors[{L["M"] + 12, 76, Max[100, bw] - 24, L["HH"] - 88}, {wh, L["HH"]}]];
    statusText = itText[s, "接続済み [" <> itAccessLabel[] <> "]  形: " <> itSurfaceLabel[spec], fs*1.5, "Left", "Middle",
      ResoniteRealtime`ResoniteRealtimeNewId["ThumbStatus"], RGBColor[0.75, 0.85, 1., 1]];
    connectBtn = itThumbHeaderButtons[panel, Lh, fs, wires];
    wires = connectBtn[[2]]; connectBtn = connectBtn[[1]];
    (* 覆い: 見出しの題名と状態欄の上だけ (ボタンは押せるまま)。保存して出し直したときに Flux が升目 (Content) を隠す *)
    veil = icSlot["Veil", panel, "Active" -> False, "Id" -> ResoniteRealtime`ResoniteRealtimeNewId["Veil"]];
    icComp[veil, $icUIX <> "RectTransform", itAnchors[{0, 0, Max[100, bw] + L["M"], L["HH"]}, {wh, L["HH"]}]];
    icImage[veil, $itThumbColors["Page"]];
    vt = icSlot["Text", veil, "Id" -> ResoniteRealtime`ResoniteRealtimeNewId["VeilTextSlot"]];
    icComp[vt, $icUIX <> "RectTransform", <|"AnchorMin" -> {0., 0.}, "AnchorMax" -> {1., 1.}|>];
    vid = itText[vt, $idVeilText, fs*1.3, "Center", "Middle", ResoniteRealtime`ResoniteRealtimeNewId["VeilText"],
      RGBColor[0.8, 0.84, 0.92, 1]];
    idBoardData[root, Join[idBoardBody[shown, o["Title"], L, ps],
      <|"shape" -> itSurfaceName[spec], "geometry" -> Select[g, NumericQ], "headerW" -> wh|>]];
    If[!itThumbsDisclosableQ[], idBoardFlux[root, content, veil]];
    fid = itThumbWire[state, sel, wires, connectBtn, vt, vid];
    rec = <|"Ids" -> <|"State" -> state, "Selected" -> sel, "Texture" -> First[texs], "Panel" -> panel, "Content" -> content,
        "Veil" -> veil, "VeilText" -> vid, "StatusText" -> statusText, "TitleText" -> titleText|>,
      "Root" -> root, "Rows" -> shown, "AllRows" -> rows, "Title" -> o["Title"], "Hidden" -> hidden, "Overflow" -> over,
      "URL" -> url, "URLs" -> urls, "Textures" -> texs, "Layout" -> L, "Meters" -> gridM, "Scale" -> ps,
      "Parent" -> center["Parent"], "Phase" -> "Ready", "Level" -> itAccessLevel[], "Covers" -> <||>, "Stash" -> None,
      "Name" -> o["Name"], "Created" -> DateObject[],
      "Shape" -> itSurfaceName[spec], "Surface" -> If[StringQ[o["Shape"]], o["Shape"], spec], "Geometry" -> g,
      "Center" -> center, "Pose" -> center, "HeaderW" -> wh|>;
    $itState["Thumbs"] = Append[itThumbs[], root -> rec];
    MapThread[Quiet @ Check[idQueueTexImport[#1, #2, root], Null] &, {texs, files}];
    itSetStatus["サムネイル一覧: " <> itTruncate[ToString[o["Title"]], 40] <> " (" <> ToString[Length[shown]] <> " 件、" <>
      itSurfaceLabel[spec] <> ")"];
    <|"Root" -> root, "WireSlot" -> state, "WireSlots" -> {state, vt}, "View" -> "Thumbnails", "Count" -> Length[shown],
      "Hidden" -> hidden, "Overflow" -> over, "Title" -> o["Title"], "Shape" -> itSurfaceName[spec]|>];

(* ---- 開いた PDF の置き場所: 押した升目の表の前 (面の法線に沿って $itSurfaceOpenBack、中心から 0.6 m より近くはしない)、
   升目の方を向けて (PDF の +z = 升目の Z の水平成分)。円筒・球では中心 (アバター) の方、メビウスの帯の外向きの面なら外に出る ---- *)
$itSurfaceOpenBack = 0.45;
itThumbAnchor[root_String, rec_Association, i_Integer] :=
  Module[{spec, fr, p, z, h},
    If[!itSurfaceRecQ[rec],
      Return[<|"Root" -> root, "Cell" -> Quiet @ Check[idCellOffset[rec, i], {0., 0., 0.}]|>]];
    spec = itSurfaceSpec[Lookup[rec, "Surface", rec["Shape"]]];
    If[!AssociationQ[spec] || !AssociationQ[Lookup[rec, "Geometry", None]], Return[<|"Root" -> root, "Cell" -> {0., 0., 0.6}|>]];
    fr = itSurfaceFrame[spec, rec["Geometry"], itSurfaceCells[rec["Layout"], rec["Scale"]][[i]]];
    z = fr["Z"];
    p = fr["Position"] - $itSurfaceOpenBack z;
    If[Norm[p] < 0.6 && Norm[p] > 10^-6, p = 0.6 p/Norm[p]];
    (* 升目が上か下を向く (メビウスの帯の真後ろで水平) ときは、中心から升目への水平の向き *)
    h = {z[[1]], 0., z[[3]]};
    If[Norm[h] < 0.3, h = {fr["Position"][[1]], 0., fr["Position"][[3]]}];
    <|"Root" -> root, "Cell" -> N[p],
      "LocalRotation" -> N[If[Norm[h] < 10^-6, {0., 0., 0., 1.}, icYawQuat[h/Norm[h]]]]|>];

(* 引き継いだ一覧 (インベントリから出した物): 行データの shape / geometry から曲面の記録を戻す *)
itSurfaceAdoptRec[rec_Association, body_Association] :=
  Module[{name = Lookup[body, "shape", "Plane"], g = Lookup[body, "geometry", None]},
    If[!StringQ[name] || name === "Plane", Return[rec]];
    Join[rec, <|"Shape" -> name, "Surface" -> name, "Geometry" -> If[AssociationQ[g], N[g], None],
      "HeaderW" -> Lookup[body, "headerW", $itThumbMinWidth]|>]];

End[];
EndPackage[];
