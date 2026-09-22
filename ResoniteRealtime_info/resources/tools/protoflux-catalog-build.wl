(* protoflux-catalog-build.wl -- 反射ダンプ (protoflux-nodes-raw.json) から LLM 用の
   コンパクトなカタログ (protoflux-nodes.json) を作る。
   実行: wolframscript -file ResoniteRealtime_info/resources/tools/protoflux-catalog-build.wl
   前段: dotnet fsi protoflux-nodes-dump.fsx json ResoniteRealtime_info/references/protoflux-nodes-raw.json
   入出力は ResoniteRealtime_info/references/ (GitHub には公開しない。利用者が自分の Resonite から作る) *)
dir = DirectoryName[$InputFileName];
refDir = FileNameJoin[{dir, "..", "..", "references"}];
If[!DirectoryQ[refDir], CreateDirectory[refDir]];
raw = ImportByteArray[ReadByteArray[FileNameJoin[{refDir, "protoflux-nodes-raw.json"}]], "RawJSON"];
Print["raw: ", Length[raw]];
kind[t_String] := Which[
  StringStartsQ[t, "ValueArgument<" | "ValueInput<" | "ObjectArgument<" | "ObjectInput<" | "GlobalRef<" | "Reference<" |
    "ValueArgumentList<" | "ValueInputList<" | "ObjectArgumentList<" | "ObjectInputList<"], "in",
  StringStartsQ[t, "ValueOutput<" | "ObjectOutput<"], "out",
  t === "Call" || t === "AsyncCall" || t === "Continuation" || t === "AsyncResumption" || t === "Operation", "impulse",
  True, None];
short[t_String] := StringReplace[t, {"ValueArgumentList<" -> "list<", "ValueInputList<" -> "list<",
  "ObjectArgumentList<" -> "list<", "ObjectInputList<" -> "list<",
  "ValueArgument<" -> "", "ValueInput<" -> "", "ObjectArgument<" -> "", "ObjectInput<" -> "",
  "GlobalRef<" -> "global<", "ValueOutput<" -> "", "ObjectOutput<" -> "",
  "Single" -> "float", "Int32" -> "int", "Boolean" -> "bool", "String" -> "string", "Double" -> "double",
  "Int64" -> "long", "Byte" -> "byte", "Char" -> "char"}] // (If[StringEndsQ[#, ">"] && StringCount[#, "<"] < StringCount[#, ">"], StringDrop[#, -1], #] &);
resultOf[base_String] := Module[{m},
  m = StringCases[base, ("ValueFunctionNode<" | "ObjectFunctionNode<" | "ValueCast<" | "ValueNode<" | "ObjectNode<" | "ExternalValueInput<" | "ExternalObjectInput<" | "ChangeableSource<") ~~ args__ ~~ ">" :> args, 1];
  If[m === {}, "", With[{parts = StringSplit[First[m], ","]}, short[Last[parts]]]]];
conv[n_Association] := Module[{fs = Lookup[n, "fields", {}], ins, outs, imps},
  ins  = Cases[fs, f_ /; kind[f["type"]] === "in" :> f["name"] <> ":" <> short[f["type"]]];
  outs = Cases[fs, f_ /; kind[f["type"]] === "out" :> f["name"] <> ":" <> short[f["type"]]];
  imps = Cases[fs, f_ /; kind[f["type"]] === "impulse" :> f["name"]];
  <|"Type" -> n["type"], "Name" -> n["name"], "Category" -> n["category"],
    "Inputs" -> ins, "Outputs" -> outs, "Impulses" -> imps, "Result" -> resultOf[Lookup[n, "base", ""]],
    "Namespace" -> n["namespace"]|>];
(* 同名は ProtoFlux.* (ロジック側) を優先し、FrooxEngine.ProtoFlux.CoreNodes は無いものだけ残す *)
conv2 = conv /@ raw;
logic = Select[conv2, StringStartsQ[#["Namespace"], "ProtoFlux."] &];
coreOnly = Select[conv2, !StringStartsQ[#["Namespace"], "ProtoFlux."] &];
names = Association[Map[#["Type"] -> True &, logic]];
coreOnly = Select[coreOnly, !KeyExistsQ[names, #["Type"]] && #["Category"] =!= "" &]; (* Method/Function Proxy の山 (category 空) は落とす *)
all = SortBy[Join[logic, coreOnly], {#["Category"], #["Type"]} &];
(* Namespace はバインディング型名の組み立てに使うので残す *)
Print["compact: ", Length[all], "  (logic ", Length[logic], ", core-only ", Length[coreOnly], ")"];
out = FileNameJoin[{refDir, "protoflux-nodes.json"}];
BinaryWrite[out, ExportByteArray[all, "RawJSON", "Compact" -> True]]; Close[out];
Print["wrote ", out, "  ", FileByteCount[out], " bytes"];

(* ---- ProtoFluxBindings.dll だけにあるノード (ValueInput<T> 等) を合流 ----
   前段: dotnet fsi protoflux-bindings-dump.fsx <bindings-raw.json> *)
bfile = FileNameJoin[{refDir, "protoflux-bindings-raw.json"}];
If[FileExistsQ[bfile],
  braw = ImportByteArray[ReadByteArray[bfile], "RawJSON"];
  bconv = conv /@ braw;
  have = Association[Map[#["Type"] -> True &, all]];
  extra = Select[bconv, !KeyExistsQ[have, #["Type"]] && !StringContainsQ[#["Type"], "Proxy"] &];
  extra = Map[If[#["Category"] === "",
      Append[#, "Category" -> If[StringContainsQ[#["Type"], "Input"], "Core/Inputs", "Core/Bindings"]], #] &, extra];
  all2 = SortBy[Join[all, extra], {#["Category"], #["Type"]} &];
  Print["bindings-only added: ", Length[extra], "  total: ", Length[all2]];
  BinaryWrite[out, ExportByteArray[all2, "RawJSON", "Compact" -> True]]; Close[out];
  Print["rewrote ", out, "  ", FileByteCount[out], " bytes"]];
