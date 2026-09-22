(* ::Package:: *)

(* ResoniteRealtime_fluxlink.wl -- グラフ記述 (JSON) を ResoniteLink で ProtoFlux ノードとして配置・結線する

   This file is encoded in UTF-8.
   ResoniteRealtime.wl が自動でロードする (同じ ResoniteRealtime` コンテキスト)。

   ---- 実機で確認した仕様 (2026-09-06、Resonite 2026.9 / ResoniteLink 0.13) ----

   - ノードは ProtoFluxBindings のコンポーネント。型名は
       論理ノード  ProtoFlux.Runtimes.Execution.Nodes.<Cat>.<Node><T>
                 → [ProtoFluxBindings]FrooxEngine.ProtoFlux.Runtimes.Execution.Nodes.<Cat>.<Node><float>
       コアノード  FrooxEngine.ProtoFlux.CoreNodes.<Node><T>
                 → [ProtoFluxBindings]FrooxEngine.FrooxEngine.ProtoFlux.CoreNodes.<Node><[FrooxEngine]FrooxEngine.Slot>
     間違えると応答が来ない (タイムアウト)。
   - 入力 (SyncRef<INodeValueOutput<T>>) は **出力元ノードのコンポーネント ID** への reference。
     出力が複数あるノード (Unpack_Float3 の X/Y/Z 等) はそのメンバ ID。
   - インパルス出力 (OnUpdate, OnTrue, ...) は **行き先ノードのコンポーネント ID** への reference。
   - 定数は ValueInput<T> / ValueObjectInput<string> の Value。
   - 世界のスロット/コンポーネントは GlobalReference<T> (Reference → 対象 ID) + ElementSource<T> (Source → GlobalReference)。
   - 動的変数への書き込み先には DynamicVariableSpace が要る (無いと OnNotFound で何も起きない)。
   - こうして置いたノード群は**そのまま実行される** (1+2 → 動的変数 3、入力を変えると追随)。

   ---- グラフ記述 (LLM が書く JSON) ----

   {"name": "SumDemo",
    "nodes": [
      {"id": "a",    "type": "ValueInput<float>", "value": 1.0},
      {"id": "b",    "type": "ValueInput<float>", "value": 2.0},
      {"id": "sum",  "type": "ValueAdd<float>", "inputs": {"A": "a", "B": "b"}},
      {"id": "path", "type": "ValueObjectInput<string>", "value": "wl/sum"},
      {"id": "here", "type": "ElementSource<Slot>", "ref": "$root"},
      {"id": "w",    "type": "WriteOrCreateDynamicValueVariable<float>",
                     "inputs": {"Value": "sum", "Path": "path", "Target": "here"}},
      {"id": "tick", "type": "LocalUpdate", "impulses": {"OnUpdate": "w"}}],
    "probes": ["wl/sum"]}

   node: id / type (カタログの Type に具体型を入れたもの) / value (定数) / inputs (名前 → ノード id か "id.Output")
         / impulses (名前 → ノード id) / ref ("$root" | "$panel" | "$user" | 世界の ID) / globals (名前 → 定数)
   probes: 配置後に読み戻す動的変数名 (ルートスロットの空間 "wl" にある)
*)

BeginPackage["ResoniteRealtime`"];

ResoniteRealtime`ResoniteFluxBindingType::usage =
  "ResoniteFluxBindingType[\"ValueAdd<float>\"] はカタログから ProtoFluxBindings のコンポーネント型名を作る。未知なら None。";
ResoniteRealtime`ResoniteFluxValidateGraph::usage =
  "ResoniteFluxValidateGraph[graph] はグラフ記述 (Association) を検査して <|\"OK\",\"Errors\",\"Warnings\",\"Nodes\"|> を返す。";
ResoniteRealtime`ResoniteFluxPlace::usage =
  "ResoniteFluxPlace[graph] はグラフ記述を ResoniteLink でワールドに配置・結線する。\n" <>
  "オプション: \"Parent\" -> Automatic (Chat パネルの根か Root), \"Position\" -> Automatic, \"Name\" -> Automatic,\n" <>
  "  \"Spacing\" -> {0.35, 0.25}。戻り値: <|\"Root\",\"Nodes\",\"Slots\",\"Errors\",\"Probes\"|>。";
ResoniteRealtime`ResoniteFluxProbe::usage =
  "ResoniteFluxProbe[placed] は配置したグラフの probes (動的変数) を読み戻す。";
ResoniteRealtime`ResoniteFluxRemove::usage =
  "ResoniteFluxRemove[placed] は配置したグラフのルートスロットを消す。";
ResoniteRealtime`ResoniteFluxDisplay::usage =
  "ResoniteFluxDisplay[placed, var] は配置したグラフの動的変数 var (probes の 1 つ) をワールド内の 3D テキストに出す。\n" <>
  "数値なら ToString ノードで文字列化する変換グラフを足し、DynamicValueVariableDriver<string> で TextRenderer に流す。\n" <>
  "オプション: \"Position\" -> {0, 0.4, 0}, \"Scale\" -> 0.3, \"Color\" -> Yellow。戻り値: <|\"Slot\",\"Text\",\"Converter\"|>。";
ResoniteRealtime`ResoniteFluxDrive::usage =
  "ResoniteFluxDrive[placed, var, targetMemberId, type] は動的変数 var で世界のフィールド (メンバ ID) を駆動する\n" <>
  "DynamicValueVariableDriver<type> を付ける (ValueFieldDrive の駆動先は ResoniteLink で書けないが、この経路なら駆動できる)。";
ResoniteRealtime`$ResoniteFluxGraphSpec::usage =
  "$ResoniteFluxGraphSpec は LLM に渡すグラフ記述の仕様文 (日本語)。";

Begin["`Private`"];

Scan[Quiet[Clear[#]] &, {"ResoniteRealtime`ResoniteFluxBindingType", "ResoniteRealtime`ResoniteFluxValidateGraph",
  "ResoniteRealtime`ResoniteFluxPlace", "ResoniteRealtime`ResoniteFluxProbe", "ResoniteRealtime`ResoniteFluxRemove",
  "ResoniteRealtime`ResoniteFluxDisplay", "ResoniteRealtime`ResoniteFluxDrive"}];

$ilBindPfx = "[ProtoFluxBindings]FrooxEngine.";
$ilFE      = "[FrooxEngine]FrooxEngine.";

(* ---- 型名 ---- *)

$ilPrimitives = {"float", "int", "bool", "string", "double", "long", "uint", "ulong", "byte", "sbyte", "short",
  "ushort", "char", "decimal", "float2", "float3", "float4", "int2", "int3", "int4", "uint2", "uint3", "uint4",
  "double2", "double3", "double4", "floatQ", "doubleQ", "color", "colorX", "bool2", "bool3", "bool4",
  "float2x2", "float3x3", "float4x4", "DateTime", "TimeSpan", "Uri"};

(* 型引数: 基本型はそのまま、[..] 付きはそのまま、それ以外は FrooxEngine の型として修飾 *)
ilTypeArg[a_String] :=
  With[{s = StringTrim[a]},
    Which[
      MemberQ[$ilPrimitives, s], s,
      StringStartsQ[s, "["], s,
      StringContainsQ[s, "<"], (* 入れ子 (IValue<float> など) *)
        With[{m = StringCases[s, base__ ~~ "<" ~~ args__ ~~ ">" :> {base, args}, 1]},
          If[m === {}, s,
            ilTypeArg[m[[1, 1]]] <> "<" <> StringRiffle[ilTypeArg /@ StringSplit[m[[1, 2]], ","], ","] <> ">"]],
      True, $ilFE <> s]];

(* "ValueAdd<float>" → {"ValueAdd", {"float"}} *)
ilSplitType[t_String] :=
  With[{m = StringCases[StringTrim[t], base : Except["<"] .. ~~ "<" ~~ args__ ~~ ">" ~~ EndOfString :> {base, args}, 1]},
    If[m === {}, {StringTrim[t], {}},
      {m[[1, 1]], StringTrim /@ ilSplitArgs[m[[1, 2]]]}]];

(* 入れ子を壊さずにカンマで割る *)
ilSplitArgs[s_String] :=
  Module[{depth = 0, parts = {}, cur = ""},
    Do[Which[
        ch === "<", depth++; cur = cur <> ch,
        ch === ">", depth--; cur = cur <> ch,
        ch === "," && depth === 0, AppendTo[parts, cur]; cur = "",
        True, cur = cur <> ch],
      {ch, Characters[s]}];
    Append[parts, cur]];

(* object 型 (C# の class): string / Uri / Slot / User / コンポーネント等。数値・bool・ベクトル・色・DateTime は value 型 *)
ilObjectTypeQ[a_String] :=
  With[{s = StringTrim[a]},
    s === "string" || s === "Uri" || StringStartsQ[s, "["] ||
      !MemberQ[$ilPrimitives, s]];

ilCatalogEntry[base_String] :=
  Module[{cat = ResoniteRealtime`ResoniteFluxCatalog[]},
    SelectFirst[cat, First[StringSplit[Lookup[#, "Type", ""], "<"]] === base &]];

ResoniteRealtime`ResoniteFluxBindingType[t_String] :=
  Module[{base, args, entry, ns, name},
    {base, args} = ilSplitType[t];
    entry = ilCatalogEntry[base];
    If[!AssociationQ[entry], Return[None]];
    ns = Lookup[entry, "Namespace", ""];
    name = If[args === {}, base, base <> "<" <> StringRiffle[ilTypeArg /@ args, ","] <> ">"];
    $ilBindPfx <> ns <> "." <> name];

(* ---- 値の型付け (ValueInput<T> の Value) ---- *)
ilTypedValue[argType_String, v_] :=
  Switch[argType,
    "float" | "double", ResoniteRealtime`ResoniteRealtimeValue[argType, N[v]],
    "int" | "long" | "uint" | "byte" | "short", ResoniteRealtime`ResoniteRealtimeValue[argType, Round[v]],
    "bool", ResoniteRealtime`ResoniteRealtimeValue[TrueQ[v]],
    "string", ResoniteRealtime`ResoniteRealtimeValue[ToString[v]],
    "float3", ResoniteRealtime`ResoniteRealtimeValue[N[v]],
    "float2", ResoniteRealtime`ResoniteRealtimeValue[N[v]],
    "float4" | "floatQ", ResoniteRealtime`ResoniteRealtimeValue["float4" /. "float4" -> argType,
      <|"x" -> N[v[[1]]], "y" -> N[v[[2]]], "z" -> N[v[[3]]], "w" -> N[v[[4]]]|>],
    "colorX" | "color", If[ColorQ[v], ResoniteRealtime`ResoniteRealtimeValue[v],
      ResoniteRealtime`ResoniteRealtimeValue[RGBColor @@ v]],
    _, ResoniteRealtime`ResoniteRealtimeValue[v]];

(* ---- 検査 ---- *)

ilNodeId[n_Association] := ToString[Lookup[n, "id", ""]];

ResoniteRealtime`ResoniteFluxValidateGraph[g_Association] :=
  Module[{nodes, ids, errors = {}, warnings = {}, entries = <||>},
    nodes = Lookup[g, "nodes", {}];
    If[!ListQ[nodes] || nodes === {}, Return[<|"OK" -> False, "Errors" -> {"nodes が空です。"}, "Warnings" -> {}, "Nodes" -> <||>|>]];
    ids = ilNodeId /@ nodes;
    If[!DuplicateFreeQ[ids], AppendTo[errors, "id が重複しています: " <> StringRiffle[Select[Tally[ids], #[[2]] > 1 &][[All, 1]], ", "]]];
    Scan[Function[n,
      Module[{id = ilNodeId[n], type = ToString[Lookup[n, "type", ""]], base, args, entry, inNames, impNames, outNames},
        {base, args} = ilSplitType[type];
        entry = ilCatalogEntry[base];
        If[!AssociationQ[entry],
          AppendTo[errors, id <> ": ノード型 " <> type <> " はカタログにありません。"],
          entries[id] = entry;
          inNames  = First /@ StringSplit[Lookup[entry, "Inputs", {}], ":"];
          impNames = Lookup[entry, "Impulses", {}];
          If[StringContainsQ[Lookup[entry, "Type", ""], "<"] && args === {},
            AppendTo[errors, id <> ": " <> type <> " は型引数が要ります (例 " <> Lookup[entry, "Type", ""] <> " の T を float などにする)。"]];
          (* string / Slot / User などは object 型。Value 系ノードに入れると Resonite が型を解決できない
             (2026-09-06 実機: WriteOrCreateDynamicValueVariable<string> は "Failed to resolve type") *)
          If[args =!= {} && AnyTrue[args, ilObjectTypeQ] && StringContainsQ[base, "Value"] && !StringContainsQ[base, "Object"],
            AppendTo[errors, id <> ": " <> type <> " の型引数 " <> StringRiffle[Select[args, ilObjectTypeQ], ","] <>
              " は object 型なので Value 系ノードには使えません。" <>
              StringReplace[base, {"ValueInput" -> "ValueObjectInput", "ValueSource" -> "ObjectValueSource",
                "DynamicValueVariable" -> "DynamicObjectVariable", "ValueFieldDrive" -> "ObjectFieldDrive",
                "ValueWrite" -> "ObjectWrite"}] <> "<" <> StringRiffle[args, ","] <> "> を使ってください。"]];
          KeyValueMap[Function[{k, v},
            If[!MemberQ[inNames, k], AppendTo[errors, id <> ": 入力 " <> k <> " は " <> type <> " にありません。使えるのは " <> StringRiffle[inNames, ", "]]];
            With[{src = First[StringSplit[ToString[v], "."]]},
              If[!MemberQ[ids, src], AppendTo[errors, id <> ": 入力 " <> k <> " の元 " <> ToString[v] <> " というノードがありません。"]]]],
            Lookup[n, "inputs", <||>]];
          KeyValueMap[Function[{k, v},
            If[!MemberQ[impNames, k], AppendTo[errors, id <> ": インパルス " <> k <> " は " <> type <> " にありません。使えるのは " <> StringRiffle[impNames, ", "]]];
            If[!MemberQ[ids, ToString[v]], AppendTo[errors, id <> ": インパルス " <> k <> " の行き先 " <> ToString[v] <> " というノードがありません。"]]],
            Lookup[n, "impulses", <||>]];
          If[KeyExistsQ[n, "value"] && !StringContainsQ[base, "Input"],
            AppendTo[warnings, id <> ": value は ValueInput / ValueObjectInput にだけ使えます。無視します。"]];
          If[KeyExistsQ[n, "ref"] && !StringContainsQ[base, "Source"],
            AppendTo[warnings, id <> ": ref は ElementSource / ValueSource / ObjectValueSource / ReferenceSource にだけ使えます。"]]]]],
      nodes];
    If[Lookup[g, "probes", {}] === {}, AppendTo[warnings, "probes が無いので実行結果を確認できません。"]];
    <|"OK" -> errors === {}, "Errors" -> errors, "Warnings" -> warnings, "Nodes" -> entries|>];

(* ---- 配置 ---- *)

Options[ResoniteRealtime`ResoniteFluxPlace] = {
  "Parent" -> Automatic, "Position" -> Automatic, "Name" -> Automatic, "Spacing" -> {0.35, 0.25},
  "SpaceName" -> "wl"};

(* データ入力の依存深さ (レイアウト用) *)
ilDepths[nodes_List] :=
  Module[{ids = ilNodeId /@ nodes, depth, changed = True, iter = 0},
    depth = Association[Map[# -> 0 &, ids]];
    While[changed && iter < 50, changed = False; iter++;
      Scan[Function[n,
        With[{srcs = Map[First[StringSplit[ToString[#], "."]] &, Values[Lookup[n, "inputs", <||>]]],
              id = ilNodeId[n]},
          With[{d = If[srcs === {}, 0, 1 + Max[Lookup[depth, srcs, 0]]]},
            If[d > depth[id], depth[id] = d; changed = True]]]], nodes]];
    depth];

ilResolveRef[ref_, ctx_Association] :=
  Switch[ToString[ref],
    "$root", ctx["Root"],
    "$panel", Lookup[ctx, "Panel", ctx["Root"]],
    "$user", Lookup[ctx, "User", None],
    _, ToString[ref]];

ResoniteRealtime`ResoniteFluxPlace[g_Association, opts : OptionsPattern[]] :=
  Catch[
    Module[{v, nodes, name, parent, pos, spacing, root, compIds = <||>, slotIds = <||>, depths, rowIdx = <||>,
            errors = {}, ctx, byId, outCache = <||>, r, probes},
      If[!StringQ[$iState["Link"]],
        Return[iFailure["NotConnected", "ResoniteLink に接続していません。"]]];
      v = ResoniteRealtime`ResoniteFluxValidateGraph[g];
      If[!TrueQ[v["OK"]], Return[iFailure["InvalidGraph", StringRiffle[v["Errors"], "\n"]]]];
      nodes = Lookup[g, "nodes", {}];
      byId = Association[Map[ilNodeId[#] -> # &, nodes]];
      name = Replace[OptionValue[ResoniteRealtime`ResoniteFluxPlace, {opts}, "Name"],
        Automatic -> "Flux " <> ToString[Lookup[g, "name", "graph"]]];
      spacing = OptionValue[ResoniteRealtime`ResoniteFluxPlace, {opts}, "Spacing"];
      (* 置き場所: 指定 > Chat パネルの根の左隣 > ユーザの正面 > Root *)
      parent = OptionValue[ResoniteRealtime`ResoniteFluxPlace, {opts}, "Parent"];
      pos = OptionValue[ResoniteRealtime`ResoniteFluxPlace, {opts}, "Position"];
      Which[
        StringQ[parent], If[pos === Automatic, pos = {0, 0, 0}],
        AssociationQ[icGadget[]], parent = icGadget[]["Root"]; If[pos === Automatic, pos = {-1.6, 0.3, 0}],
        True,
          With[{p = icUserFrontPose[Automatic, 1.5, Automatic]},
            If[AssociationQ[p], parent = p["Parent"]; If[pos === Automatic, pos = p["Position"]],
              parent = "Root"; If[pos === Automatic, pos = {0, 1.2, 1.5}]]]];

      root = icSlot[name, parent, "Position" -> pos, "Id" -> ResoniteRealtime`ResoniteRealtimeNewId["Flux"]];
      (* 途中で失敗したら作りかけのルートごと消してから Failure を返す *)
      $ilCurrentRoot = root;
      icComp[root, $ilFE <> "DynamicVariableSpace",
        <|"SpaceName" -> OptionValue[ResoniteRealtime`ResoniteFluxPlace, {opts}, "SpaceName"]|>];
      icComp[root, $ilFE <> "AI_GeneratedContent", <|"Source" -> "Mathematica ResoniteFlux (LLM-generated ProtoFlux)"|>];
      ctx = <|"Root" -> root, "Panel" -> If[AssociationQ[icGadget[]], icGadget[]["Root"], root],
        "User" -> With[{u = icUserRoot[Automatic]}, If[AssociationQ[u], u["Id"], None]]|>;

      (* pass 1: スロットとノード本体 (定数・参照だけ) *)
      depths = ilDepths[nodes];
      Scan[Function[n,
        Module[{id = ilNodeId[n], type = ToString[n["type"]], bind, base, args, slot, members = <||>, gref, entry},
          {base, args} = ilSplitType[type];
          bind = ResoniteRealtime`ResoniteFluxBindingType[type];
          entry = v["Nodes"][id];
          rowIdx[depths[id]] = Lookup[rowIdx, depths[id], -1] + 1;
          slot = icSlot[id <> " (" <> base <> ")", root,
            "Position" -> {spacing[[1]]*depths[id], -spacing[[2]]*rowIdx[depths[id]], 0}];
          slotIds[id] = slot;
          If[KeyExistsQ[n, "value"] && args =!= {},
            members["Value"] = ilTypedValue[First[args], n["value"]]];
          If[KeyExistsQ[n, "ref"] && args =!= {},
            gref = icComp[slot, "[FrooxEngine]FrooxEngine.ProtoFlux.GlobalReference<" <> ilTypeArg[First[args]] <> ">",
              <|"Reference" -> ResoniteRealtime`ResoniteRealtimeRef[ilResolveRef[n["ref"], ctx]]|>];
            members["Source"] = ResoniteRealtime`ResoniteRealtimeRef[gref]];
          KeyValueMap[Function[{k, val},
            With[{gt = ilGlobalArgType[entry, k]},
              members[k] = ResoniteRealtime`ResoniteRealtimeRef[
                icComp[slot, "[FrooxEngine]FrooxEngine.ProtoFlux.GlobalValue<" <> ilTypeArg[gt] <> ">",
                  <|"Value" -> ilTypedValue[gt, val]|>]]]],
            Lookup[n, "globals", <||>]];
          compIds[id] = icComp[slot, bind, members, ResoniteRealtime`ResoniteRealtimeNewId["Node"]]]],
        nodes];

      (* pass 2: 結線 (入力 → 出力元、インパルス → 行き先) *)
      Scan[Function[n,
        Module[{id = ilNodeId[n], members = <||>},
          KeyValueMap[Function[{k, src},
            members[k] = ResoniteRealtime`ResoniteRealtimeRef[ilOutputId[ToString[src], compIds, slotIds, outCache]]],
            Lookup[n, "inputs", <||>]];
          KeyValueMap[Function[{k, dst},
            members[k] = ResoniteRealtime`ResoniteRealtimeRef[compIds[ToString[dst]]]],
            Lookup[n, "impulses", <||>]];
          If[members =!= <||>,
            r = ResoniteRealtime`ResoniteRealtimeUpdateComponent[compIds[id], members];
            If[MatchQ[r, _Failure], AppendTo[errors, id <> ": 結線に失敗 " <> ToString[r[[1]]]]]]]],
        nodes];

      probes = Lookup[g, "probes", {}];
      $ilCurrentRoot = None;
      r = <|"Root" -> root, "Parent" -> parent, "Name" -> name, "Nodes" -> compIds, "Slots" -> slotIds,
        "Errors" -> errors, "ProbeNames" -> probes, "Graph" -> g|>;
      If[probes =!= {}, Pause[1.5]; r["Probes"] = ResoniteRealtime`ResoniteFluxProbe[r]];
      r],
    icTag,
    Function[{f, tag},
      If[StringQ[$ilCurrentRoot],
        Quiet @ ResoniteRealtime`ResoniteRealtimeRemoveSlot[$ilCurrentRoot]; $ilCurrentRoot = None];
      f]];

If[!ValueQ[$ilCurrentRoot], $ilCurrentRoot = None];

(* global<T> 入力の T をカタログの Inputs ("Tag:global<string>") から引く *)
ilGlobalArgType[entry_Association, member_String] :=
  With[{m = SelectFirst[Lookup[entry, "Inputs", {}], StringStartsQ[#, member <> ":"] &]},
    If[!StringQ[m], "string",
      StringReplace[StringDrop[m, StringLength[member] + 1], {"global<" -> "", ">" ~~ EndOfString -> ""}]]];

(* "id" → そのノードのコンポーネント ID、"id.Out" → 出力メンバの ID *)
ilOutputId[src_String, compIds_, slotIds_, outCache_] :=
  Module[{parts = StringSplit[src, "."], id, out, mid},
    id = First[parts];
    If[Length[parts] === 1, Return[compIds[id]]];
    out = StringRiffle[Rest[parts], "."];
    mid = icMemberId[slotIds[id], compIds[id], out];
    If[StringQ[mid], mid,
      Throw[iFailure["NoOutput", id <> " に出力 " <> out <> " が見つかりません。"], icTag]]];

ResoniteRealtime`ResoniteFluxProbe[placed_Association] :=
  Module[{t, dvs, val},
    val = If[AssociationQ[#], Lookup[#, "value", #], #] &;
    t = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeGetSlot[placed["Root"], "Depth" -> -1,
      "IncludeComponentData" -> True], $Failed];
    If[!AssociationQ[t], Return[<||>]];
    dvs = Cases[t, a_Association /; StringContainsQ[Lookup[a, "componentType", ""], "DynamicValueVariable" | "DynamicReferenceVariable"] :> a, {0, Infinity}];
    Association @ Map[Function[name,
      name -> With[{hit = SelectFirst[dvs, val[Lookup[Lookup[#, "members", <||>], "VariableName", ""]] === name &]},
        If[AssociationQ[hit], val[Lookup[hit["members"], "Value", None]], Missing["NotFound"]]]],
      Lookup[placed, "ProbeNames", {}]]];

ResoniteRealtime`ResoniteFluxRemove[placed_Association] :=
  ResoniteRealtime`ResoniteRealtimeRemoveSlot[placed["Root"]];

(* ---- 世界内での観測: 動的変数 → 3D テキスト ----
   実機 (2026-09-06): DynamicValueVariableDriver<T>.Target (FieldDrive) は **メンバ ID への reference で書ける**。
   ValueFieldDrive ノードの駆動先 (Proxy) は書けないので、フィールドを動かすときはこの経路を使う。 *)

(* グラフ記述から、probes の変数の型引数を推定する (書き込みノードの型引数) *)
ilProbeType[g_Association, var_String] :=
  Module[{writers, pathIds, hit},
    pathIds = Map[ilNodeId, Select[Lookup[g, "nodes", {}],
      StringContainsQ[ToString[Lookup[#, "type", ""]], "Input<string>"] && ToString[Lookup[#, "value", ""]] === var &]];
    writers = Select[Lookup[g, "nodes", {}],
      StringContainsQ[ToString[Lookup[#, "type", ""]], "DynamicValueVariable<" | "DynamicObjectVariable<"] &&
        MemberQ[pathIds, ToString[Lookup[Lookup[#, "inputs", <||>], "Path", ""]]] &];
    If[writers === {}, "float",
      With[{args = Last[ilSplitType[ToString[First[writers]["type"]]]]}, If[args === {}, "float", First[args]]]]];

ilToStringNode[argType_String] :=
  Switch[argType,
    "int", "ToString_Int", "float", "ToString_Float", "bool", "ToString_Bool", "double", "ToString_Double",
    "long", "ToString_Long", "float3", "ToString_Float3", "float2", "ToString_Float2", "colorX", "ToString_ColorX",
    _, None];

Options[ResoniteRealtime`ResoniteFluxDisplay] = {
  "Position" -> {0, 0.4, 0}, "Scale" -> 0.3, "Color" -> RGBColor[1, 0.9, 0.2, 1], "Type" -> Automatic};

ResoniteRealtime`ResoniteFluxDisplay[placed_Association, var_String, opts : OptionsPattern[]] :=
  Catch[
    Module[{root = placed["Root"], type, disp, tr, textId, conv, textVar, sc},
      If[!StringQ[$iState["Link"]], Return[iFailure["NotConnected", "ResoniteLink に接続していません。"]]];
      type = Replace[OptionValue[ResoniteRealtime`ResoniteFluxDisplay, {opts}, "Type"],
        Automatic -> ilProbeType[Lookup[placed, "Graph", <||>], var]];
      sc = OptionValue[ResoniteRealtime`ResoniteFluxDisplay, {opts}, "Scale"];
      disp = icSlot["Display " <> var, root,
        "Position" -> OptionValue[ResoniteRealtime`ResoniteFluxDisplay, {opts}, "Position"], "Scale" -> {sc, sc, sc}];
      tr = icComp[disp, $ilFE <> "TextRenderer",
        <|"Text" -> "?", "Color" -> OptionValue[ResoniteRealtime`ResoniteFluxDisplay, {opts}, "Color"]|>];
      textId = icMemberId[disp, tr, "Text"];
      If[!StringQ[textId], Throw[iFailure["NoMemberId", "TextRenderer.Text のメンバ ID が取れません。"], icTag]];
      (* string ならそのまま、数値なら変換グラフで <var>_text に書いたものを流す *)
      textVar = If[type === "string", var, var <> "_text"];
      conv = None;
      If[type =!= "string",
        With[{ts = ilToStringNode[type]},
          If[ts === None, Throw[iFailure["NoToString", type <> " を文字列にするノードが分かりません。"], icTag]];
          conv = ResoniteRealtime`ResoniteFluxPlace[
            <|"name" -> "Display " <> var, "nodes" -> {
               <|"id" -> "here", "type" -> "ElementSource<Slot>", "ref" -> root|>,
               <|"id" -> "p1", "type" -> "ValueObjectInput<string>", "value" -> var|>,
               <|"id" -> "read", "type" -> "ReadDynamicValueVariable<" <> type <> ">",
                 "inputs" -> <|"Source" -> "here", "Path" -> "p1"|>|>,
               <|"id" -> "ts", "type" -> ts, "inputs" -> <|"V" -> "read.Value"|>|>,
               <|"id" -> "p2", "type" -> "ValueObjectInput<string>", "value" -> textVar|>,
               <|"id" -> "w", "type" -> "WriteOrCreateDynamicObjectVariable<string>",
                 "inputs" -> <|"Value" -> "ts", "Path" -> "p2", "Target" -> "here"|>|>,
               <|"id" -> "tick", "type" -> "LocalUpdate", "impulses" -> <|"OnUpdate" -> "w"|>|>},
              "probes" -> {}|>,
            "Parent" -> root, "Position" -> {0.9, 0, 0}, "Name" -> "Display " <> var <> " (converter)"];
          If[MatchQ[conv, _Failure], Throw[conv, icTag]]]];
      icComp[disp, $ilFE <> "DynamicValueVariableDriver<string>",
        <|"VariableName" -> textVar, "DefaultValue" -> "-", "Target" -> ResoniteRealtime`ResoniteRealtimeRef[textId]|>];
      <|"Slot" -> disp, "Text" -> tr, "Variable" -> textVar, "Type" -> type, "Converter" -> conv|>],
    icTag];

ResoniteRealtime`ResoniteFluxDrive[placed_Association, var_String, targetMemberId_String, type_String : "float"] :=
  Module[{drv},
    If[!StringQ[$iState["Link"]], Return[iFailure["NotConnected", "ResoniteLink に接続していません。"]]];
    drv = ResoniteRealtime`ResoniteRealtimeAddComponent[placed["Root"],
      $ilFE <> "DynamicValueVariableDriver<" <> ilTypeArg[type] <> ">",
      <|"VariableName" -> var, "Target" -> ResoniteRealtime`ResoniteRealtimeRef[targetMemberId]|>];
    If[MatchQ[drv["Response"], _Failure], drv["Response"], drv["Id"]]];

(* ---- LLM に渡す仕様文 ---- *)
ResoniteRealtime`$ResoniteFluxGraphSpec =
"[グラフ記述の書式]\n" <>
"JSON 1 つを ```json フェンスで出力する。キー:\n" <>
"  name: 短い英数字の名前\n" <>
"  nodes: ノードの配列。各ノードは\n" <>
"    id: 英数字の一意名\n" <>
"    type: 下のノードカタログにある Type に具体型を入れたもの (例 ValueAdd<float>, ValueInput<int>, ElementSource<Slot>)。\n" <>
"          型引数は float / int / bool / string / float3 / colorX / Slot / User など。\n" <>
"    value: 定数 (ValueInput<T> と ValueObjectInput<string> だけ)\n" <>
"    inputs: {入力名: 元ノード id}。元ノードの出力が複数あるときは \"id.出力名\" (例 \"u.X\")\n" <>
"    impulses: {インパルス出力名: 行き先ノード id}\n" <>
"    ref: 世界の参照 (ElementSource<Slot> などの Source 用)。\"$root\" = このグラフのルートスロット、\"$panel\" = Chat パネル、\"$user\" = 自分のアバターの根\n" <>
"    globals: {入力名: 定数} (カタログで global<T> と書かれた入力用。例 DynamicImpulseReceiver の Tag)\n" <>
"  probes: 配置後に読み戻す動的変数名の配列\n" <>
"[約束]\n" <>
"- 定数は ValueInput<T> / ValueObjectInput<string> ノードにして inputs から参照する (inputs に数値を直接書かない)。\n" <>
"- string / Uri / Slot / User などは object 型。Value 系でなく Object 系のノードを使う: ValueObjectInput<string>, " <>
"WriteOrCreateDynamicObjectVariable<string>, ReadDynamicObjectVariable<string>, ObjectValueSource<string>。" <>
"数値・bool・float3・colorX は value 型 (ValueInput<float>, WriteOrCreateDynamicValueVariable<int> など)。\n" <>
"- 数値を文字にするのは ToString_Int / ToString_Float (入力 V)。\n" <>
"- 毎フレーム動かすなら LocalUpdate、周期なら SecondsTimer (Interval 入力)、条件なら FireOnTrue、外部からなら DynamicImpulseReceiver を impulses の起点にする。\n" <>
"- 結果は必ず WriteOrCreateDynamicValueVariable<T> で動的変数 \"wl/<名前>\" に書く (Target は ElementSource<Slot> の ref \"$root\"、Path は ValueObjectInput<string>)。その名前を probes に入れる。\n" <>
"- ノード数は 40 以下。カタログに無いノード型・入力名・インパルス名を作らない。\n";

End[];

EndPackage[];
