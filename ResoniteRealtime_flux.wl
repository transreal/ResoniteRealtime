(* ::Package:: *)

(* ResoniteRealtime_flux.wl -- ProtoFlux を返すガジェット (ProtoGraph 経由)

   This file is encoded in UTF-8.
   ResoniteRealtime.wl が自動でロードする (同じ ResoniteRealtime` コンテキスト)。
   ResoniteRealtime_chat.wl の LLM 呼び出し・アクセスレベル・パネル表示をそのまま使う。

   ---- 方式 (docs/protoflux-llm-generation-proposal.md) ----

   LLM には ResoniteLink の JSON を書かせず、**ProtoGraph** (Flux SDK のテキスト言語、
   ProtoFlux 1:1) を書かせる。
     生成 → 静的検査 (実在ノードのカタログと突合) → flux-sdk build (あれば) → 修正ループ
   カタログは Resonite の DLL を反射して作った references/protoflux-nodes.json
   (再生成は ResoniteRealtime_info/resources/tools/protoflux-nodes-dump.fsx + protoflux-catalog-build.wl。references/ は
   GitHub に公開しないので、カタログと protograph 抜粋は利用者が setup.md の手順で作る)。
   言語仕様は references/protograph/protograph-skill.md (公式 docs の抜粋)。

   flux-sdk (dotnet tool "Papaltine.FluxSDK") が無くても生成と静的検査までは動く。
   build と .brson 出力は flux-sdk があるときだけ。
*)

BeginPackage["ResoniteRealtime`"];

ResoniteRealtime`$ResoniteFluxSDK::usage =
  "$ResoniteFluxSDK は flux-sdk 実行ファイルのパス。Automatic なら PATH と ~/.dotnet/tools を探す。";
ResoniteRealtime`$ResoniteFluxProjects::usage =
  "$ResoniteFluxProjects は生成した ProtoGraph プロジェクトの置き場 (既定 $packageDirectory/ResoniteFlux_projects)。";
ResoniteRealtime`ResoniteFluxCatalog::usage =
  "ResoniteFluxCatalog[] は ProtoFlux ノードのカタログ (Association のリスト) を返す。\n" <>
  "各要素: <|\"Type\",\"Name\",\"Category\",\"Inputs\",\"Outputs\",\"Impulses\",\"Result\"|>。";
ResoniteRealtime`ResoniteFluxCatalogSearch::usage =
  "ResoniteFluxCatalogSearch[query, n] はカタログを語で検索して上位 n 件 (既定 30) を返す。";
ResoniteRealtime`ResoniteFluxUnknownNodes::usage =
  "ResoniteFluxUnknownNodes[source] は ProtoGraph ソース中の、カタログにも予約語にも無いノード名を返す。";
ResoniteRealtime`ResoniteFluxBuild::usage =
  "ResoniteFluxBuild[pgFile] は flux-sdk build を走らせ <|\"Success\",\"Output\",\"Diagnostics\",\"Brson\"|> を返す。\n" <>
  "flux-sdk が無ければ Failure[\"NoFluxSDK\"]。";
ResoniteRealtime`ResoniteFluxGenerate::usage =
  "ResoniteFluxGenerate[spec] は仕様 (自然言語) から ProtoGraph モジュールを LLM に書かせ、\n" <>
  "静的検査 → (flux-sdk があれば) build → 修正を最大 \"MaxRounds\" 回まわす。\n" <>
  "オプション: \"MaxRounds\" -> 3, \"Module\" -> Automatic, \"Model\" -> Automatic, \"Timeout\" -> 300,\n" <>
  "  \"Build\" -> Automatic, \"SourceVault\" -> False, \"Origin\" -> \"Notebook\"。\n" <>
  "戻り値: <|\"Source\",\"Module\",\"File\",\"Project\",\"Unknown\",\"Build\",\"Rounds\",\"Answer\",\"PrivacyLevel\"|>。";
ResoniteRealtime`ResoniteFluxChat::usage =
  "ResoniteFluxChat[prompt] は ResoniteChat の ProtoFlux 版: 生成した ProtoGraph をノートブックと\n" <>
  "ワールド内パネルに出し、.pg をプロジェクトに保存する。オプションは ResoniteFluxGenerate と同じ。";
ResoniteRealtime`ResoniteFluxCell::usage =
  "ResoniteFluxCell[] は ResoniteFluxInput セル (Shift+Enter で ResoniteFluxChat) を挿入する。";
ResoniteRealtime`ResoniteFluxDeploy::usage =
  "ResoniteFluxDeploy[result] は生成結果を世界へ入れる手順を返す。.brson があれば Resonite へドラッグ&ドロップ。\n" <>
  "\"Method\" -> \"ResoniteLink\" で Flux SDK のホットデプロイ (resources/tools/flux-deploy.fsx、実験的) を試す。";

Begin["`Private`"];

Scan[Quiet[Clear[#]] &, Names["ResoniteRealtime`ResoniteFlux*"]];

If[!AssociationQ[$ifState],
  $ifState = <|"Catalog" -> None, "Skill" -> None, "SDK" -> None|>];

If[!ValueQ[ResoniteRealtime`$ResoniteFluxSDK], ResoniteRealtime`$ResoniteFluxSDK = Automatic];
If[!StringQ[ResoniteRealtime`$ResoniteFluxProjects],
  ResoniteRealtime`$ResoniteFluxProjects = FileNameJoin[{$iPackageDirectory, "ResoniteFlux_projects"}]];

$ifInfoDir = FileNameJoin[{$iPackageDirectory, "ResoniteRealtime_info", "references"}];
$ifToolsDir = FileNameJoin[{$iPackageDirectory, "ResoniteRealtime_info", "resources", "tools"}];
$ifCatalogFile = FileNameJoin[{$ifInfoDir, "protoflux-nodes.json"}];
$ifSkillFile   = FileNameJoin[{$ifInfoDir, "protograph", "protograph-skill.md"}];

(* ============================================================
   カタログ
   ============================================================ *)

ifReadJSON[file_String] :=
  If[FileExistsQ[file],
    Quiet @ Check[ImportByteArray[ReadByteArray[file], "RawJSON"], $Failed], $Failed];

ResoniteRealtime`ResoniteFluxCatalog[] :=
  Module[{c},
    If[ListQ[$ifState["Catalog"]], Return[$ifState["Catalog"]]];
    c = ifReadJSON[$ifCatalogFile];
    If[!ListQ[c], Return[{}]];
    $ifState = Join[$ifState, <|"Catalog" -> c|>];
    c];

(* 1 行の要約: Type (Category) in: A:T, B:T  out: X:float  impulse: OnChange  -> result *)
ifNodeLine[n_Association] :=
  StringJoin[
    Lookup[n, "Type", "?"], "  [", Lookup[n, "Category", ""], "]",
    If[Lookup[n, "Inputs", {}] =!= {},
      "  in: " <> StringRiffle[Lookup[n, "Inputs", {}], ", "], ""],
    If[Lookup[n, "Outputs", {}] =!= {},
      "  out: " <> StringRiffle[Lookup[n, "Outputs", {}], ", "], ""],
    If[Lookup[n, "Impulses", {}] =!= {},
      "  impulse: " <> StringRiffle[Lookup[n, "Impulses", {}], ", "], ""],
    If[StringQ[Lookup[n, "Result", None]] && n["Result"] =!= "",
      "  -> " <> n["Result"], ""]];

ifWords[s_String] :=
  DeleteDuplicates @ Select[
    ToLowerCase /@ StringSplit[s, Except[LetterCharacter | DigitCharacter] ..],
    StringLength[#] >= 2 &];

ResoniteRealtime`ResoniteFluxCatalogSearch[query_String, n_Integer : 30] :=
  Module[{cat = ResoniteRealtime`ResoniteFluxCatalog[], ws, scored},
    ws = ifWords[query];
    If[ws === {} || cat === {}, Return[{}]];
    scored = Map[
      Function[node,
        With[{hay = ToLowerCase[StringJoin[Lookup[node, "Type", ""], " ",
            Lookup[node, "Name", ""], " ", Lookup[node, "Category", ""]]]},
          {Total[Map[If[StringContainsQ[hay, #], 1, 0] &, ws]], node}]],
      cat];
    scored = Select[scored, First[#] > 0 &];
    scored = SortBy[scored, {-First[#], StringLength[#[[2]]["Type"]]} &];
    Take[scored[[All, 2]], UpTo[n]]];

(* ProtoGraph の予約語・キーワードノード (小文字は言語予約、これらは検査対象外) *)
$ifKeywordNodes = {"If", "Display", "ImpulseDisplay", "Write", "Read", "Delay", "Sequence",
  "Impulse", "AsyncImpulse", "Operation", "AsyncOperation"};

(* 大文字始まりの識別子で、直後に "(" か "<" が来るものをノード呼び出しとみなす。
   use で持ち込んだモジュール名と、ローカルで定義した値名 (X = ...) は除く。 *)
ResoniteRealtime`ResoniteFluxUnknownNodes[src_String] :=
  Module[{cat = ResoniteRealtime`ResoniteFluxCatalog[], known, calls, locals, uses},
    known = DeleteDuplicates @ Join[
      Map[First[StringSplit[Lookup[#, "Type", ""], "<"]] &, cat],
      $ifKeywordNodes];
    calls = DeleteDuplicates @ StringCases[src,
      WordBoundary ~~ id : (CharacterRange["A", "Z"] ~~ (LetterCharacter | DigitCharacter | "_") ...) ~~
        Whitespace ... ~~ ("(" | "<") :> id];
    locals = DeleteDuplicates @ StringCases[src,
      StartOfLine ~~ Whitespace ... ~~ id : (CharacterRange["A", "Z"] ~~ (LetterCharacter | DigitCharacter | "_") ...) ~~
        Whitespace ... ~~ "=" ~~ Except["="] :> id];
    uses = DeleteDuplicates @ Flatten @ StringCases[src,
      StartOfLine ~~ "use" ~~ Whitespace ~~ rest : Except["\n"] .. :>
        StringCases[rest, id : (CharacterRange["A", "Z"] ~~ (LetterCharacter | DigitCharacter | "_") ...) :> id]];
    Complement[calls, known, locals, uses]];

(* ============================================================
   flux-sdk
   ============================================================ *)

ifFindSDK[] :=
  Module[{cands, exe},
    If[StringQ[ResoniteRealtime`$ResoniteFluxSDK] && FileExistsQ[ResoniteRealtime`$ResoniteFluxSDK],
      Return[ResoniteRealtime`$ResoniteFluxSDK]];
    If[StringQ[$ifState["SDK"]] && FileExistsQ[$ifState["SDK"]], Return[$ifState["SDK"]]];
    exe = If[$OperatingSystem === "Windows", "flux-sdk.exe", "flux-sdk"];
    cands = Join[
      {FileNameJoin[{$HomeDirectory, ".dotnet", "tools", exe}]},
      Map[FileNameJoin[{#, exe}] &,
        StringSplit[Replace[Environment["PATH"], Except[_String] -> ""],
          If[$OperatingSystem === "Windows", ";", ":"]]]];
    cands = Select[cands, FileExistsQ];
    If[cands === {}, None,
      $ifState = Join[$ifState, <|"SDK" -> First[cands]|>];
      First[cands]]];

$ifResoniteDir = "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Resonite";

(* Resonite の DLL の場所。環境変数 RESONITE_MANAGED_DATA_PATH があればそれに任せ、
   無ければ -L で渡す ($Language=Japanese だと ProcessEnvironment 付きの StartProcess が
   落ちるので環境変数は渡さない)。 *)
ifSDKLibraryArgs[] :=
  If[StringQ[Environment["RESONITE_MANAGED_DATA_PATH"]] || !DirectoryQ[$ifResoniteDir], {},
    {"-L", $ifResoniteDir}];

(* 診断行: "error" / "warning" / "Error" を含む行、および穴 (_) の期待型メッセージ *)
ifDiagnostics[out_String] :=
  Select[StringSplit[out, "\n"],
    StringContainsQ[#, "error" | "Error" | "ERROR" | "warning" | "Warning" | "expected" | "Expected"] &];

ResoniteRealtime`ResoniteFluxBuild[pgFile_String] :=
  Module[{sdk, r, out, brson, dir, ok},
    sdk = ifFindSDK[];
    If[sdk === None,
      Return[iFailure["NoFluxSDK",
        "flux-sdk が見つかりません。dotnet tool install --global --version 1.9.0 Papaltine.FluxSDK で入れるか、" <>
        "$ResoniteFluxSDK にパスを設定してください。"]]];
    If[!FileExistsQ[pgFile], Return[iFailure["NoFile", "ファイルがありません: " <> pgFile]]];
    dir = DirectoryName[pgFile];
    r = Quiet @ Check[
      RunProcess[Join[{sdk, "build"}, ifSDKLibraryArgs[], {pgFile}], ProcessDirectory -> dir],
      $Failed];
    If[!AssociationQ[r], Return[iFailure["Build", "flux-sdk を起動できませんでした。"]]];
    out = StringJoin[Lookup[r, "StandardOutput", ""], "\n", Lookup[r, "StandardError", ""]];
    brson = Select[FileNames["*.brson", dir, Infinity],
      StringContainsQ[FileBaseName[#], FileBaseName[pgFile]] &];
    ok = Lookup[r, "ExitCode", 1] === 0 && brson =!= {};
    <|"Success" -> ok, "ExitCode" -> Lookup[r, "ExitCode", None], "Output" -> out,
      "Diagnostics" -> ifDiagnostics[out],
      "Brson" -> If[brson === {}, None, First[SortBy[brson, -FileDate[#, "Modification"] &]]]|>];

(* ============================================================
   生成
   ============================================================ *)

ifSkill[] :=
  Module[{s},
    If[StringQ[$ifState["Skill"]], Return[$ifState["Skill"]]];
    s = If[FileExistsQ[$ifSkillFile],
      Quiet @ Check[Import[$ifSkillFile, "Text", CharacterEncoding -> "UTF-8"], ""], ""];
    If[!StringQ[s], s = ""];
    $ifState = Join[$ifState, <|"Skill" -> s|>];
    s];

(* 仕様の語に関係なく必ず手掛かりに入れる定番: 流れ制御・動的変数・WebSocket・文字列処理
   (スモークテストで LLM が「TAB 分割ノードが無い」と誤解したので Strings 系を足した) *)
$ifCoreNodeQueries = "If While For Sequence Write ValueWrite Display Update FireOnTrue FireOnLocalTrue " <>
  "DynamicVariable Dynamic Impulse Websocket LocalUser Slot Delay Timer " <>
  "String Split Substring IndexOf Parse Format Concat ToString Length";

$ifConventions =
"[このプロジェクトの約束]\n" <>
"- 出力は 1 つの ProtoGraph モジュールだけ。```protograph フェンスで囲み、フェンスの外に説明を短く書く。\n" <>
"- 1 行目は `module <PascalCase 名>`。入出力は `in` / `out`、本文は `where { ... }`。\n" <>
"- ノード名は下の [ノードカタログ] か ProtoGraph の予約語 (if / while / for / switch / impulse / bind / sync / local / display / ~read / ~write / ~trigger) だけを使う。カタログに無い名前を作らない。\n" <>
"- 世界のオブジェクトへの結線は `in` (Source) / `out` (Drive) で宣言し、本文で探さない。\n" <>
"- Mathematica (WL) との連携は WebsocketTextMessageReceiver / WebsocketTextMessageSender (TAB 区切りの 1 行、JSON 不可) か、" <>
"動的変数 (~read / ~write) を使う。\n" <>
"- 迷ったら froox コンテキストの純粋なデータフローで書き、impulse は最小限にする。\n";

ifGenerationPrompt[spec_String, moduleName_, hints_List, prior_, diagnostics_List] :=
  StringJoin[
    "あなたは Resonite の ProtoFlux を ProtoGraph (Flux SDK のテキスト言語) で書くプログラマです。\n",
    "以下の言語リファレンスと約束に厳密に従い、仕様を満たすモジュールを書いてください。\n\n",
    "[ProtoGraph 言語リファレンス]\n", ifSkill[], "\n\n",
    $ifConventions, "\n",
    "[ノードカタログ (Type [Category] in: 入力 out: 出力 impulse: 継続 -> 既定出力)]\n",
    StringRiffle[Map[ifNodeLine, hints], "\n"], "\n\n",
    If[StringQ[moduleName], "[モジュール名] " <> moduleName <> "\n", ""],
    "[仕様]\n", spec, "\n",
    If[StringQ[prior],
      "\n[前回の出力]\n```protograph\n" <> prior <> "\n```\n" <>
      "[前回の問題点]\n" <> StringRiffle[diagnostics, "\n"] <>
      "\n上の問題点を直した完全なモジュールを出力してください。\n", ""]];

ifExtractPG[answer_String] :=
  Module[{m},
    m = StringCases[answer,
      "```" ~~ ("protograph" | "pg" | "ProtoGraph") ~~ Shortest[code___] ~~ "```" :> code, 1];
    If[m === {},
      m = StringCases[answer, "```" ~~ Shortest[code___] ~~ "```" :> code, 1]];
    If[m === {}, None, StringTrim[First[m]]]];

ifModuleName[src_String, fallback_] :=
  Module[{m = StringCases[src, StartOfLine ~~ "module" ~~ Whitespace ~~ n : (LetterCharacter ~~ (LetterCharacter | DigitCharacter | "_") ...) :> n, 1]},
    If[m === {}, fallback, First[m]]];

ifSlug[s_String] :=
  With[{t = StringReplace[s, Except[LetterCharacter | DigitCharacter] .. -> "-"]},
    StringTake[StringTrim[t, "-"], UpTo[40]]];

Options[ResoniteRealtime`ResoniteFluxGenerate] = {
  "Format" -> "Graph", "Place" -> Automatic, "Display" -> True,
  "MaxRounds" -> 3, "Module" -> Automatic, "Model" -> Automatic, "Timeout" -> 300,
  "Build" -> Automatic, "SourceVault" -> False, "Origin" -> "Notebook", "Hints" -> 40};

(* ============================================================
   グラフ記述モード ("Format" -> "Graph"、既定)
   LLM に JSON のグラフ記述を書かせ、検証 → ResoniteLink で配置 → probe 読み戻し → 修正。
   ワールド内で**そのまま実行される** ProtoFlux になる (ResoniteRealtime_fluxlink.wl)。
   ============================================================ *)

$ifGraphExample =
"```json\n" <>
"{\"name\": \"SumDemo\",\n" <>
" \"nodes\": [\n" <>
"  {\"id\": \"a\", \"type\": \"ValueInput<float>\", \"value\": 1.0},\n" <>
"  {\"id\": \"b\", \"type\": \"ValueInput<float>\", \"value\": 2.0},\n" <>
"  {\"id\": \"sum\", \"type\": \"ValueAdd<float>\", \"inputs\": {\"A\": \"a\", \"B\": \"b\"}},\n" <>
"  {\"id\": \"path\", \"type\": \"ValueObjectInput<string>\", \"value\": \"wl/sum\"},\n" <>
"  {\"id\": \"here\", \"type\": \"ElementSource<Slot>\", \"ref\": \"$root\"},\n" <>
"  {\"id\": \"w\", \"type\": \"WriteOrCreateDynamicValueVariable<float>\",\n" <>
"   \"inputs\": {\"Value\": \"sum\", \"Path\": \"path\", \"Target\": \"here\"}},\n" <>
"  {\"id\": \"tick\", \"type\": \"LocalUpdate\", \"impulses\": {\"OnUpdate\": \"w\"}}\n" <>
" ],\n" <>
" \"probes\": [\"wl/sum\"]}\n" <>
"```";

$ifGraphCoreQueries = "ValueInput ValueObjectInput ElementSource ValueSource LocalUpdate SecondsTimer Update " <>
  "FireOnTrue FireOnLocalTrue DynamicImpulseReceiver DynamicImpulseTrigger WriteOrCreateDynamicValueVariable " <>
  "ReadDynamicValueVariable If Sequence While For ValueAdd ValueSub ValueMul ValueDiv ValueMod Conditional " <>
  "ValueEquals ValueLessThan ValueGreaterThan Unpack Pack ToString Format Concat LocalUserSlot LocalUser " <>
  "Websocket ValueDisplay";

ifGraphPrompt[spec_String, hints_List, prior_, diagnostics_List] :=
  StringJoin[
    "あなたは Resonite の ProtoFlux をノードグラフの JSON 記述で書くプログラマです。",
    "書いた JSON は Mathematica がそのままワールドに配置・結線し、実行結果 (probes) を読み戻して確認します。\n\n",
    ResoniteRealtime`$ResoniteFluxGraphSpec, "\n",
    "[例]\n", $ifGraphExample, "\n\n",
    "[ノードカタログ (Type [Category] in: 入力名:型 out: 出力名:型 impulse: インパルス出力名 -> 既定出力型)。global<T> の入力は globals で定数を与える]\n",
    StringRiffle[Map[ifNodeLine, hints], "\n"], "\n\n",
    "[仕様]\n", spec, "\n",
    If[StringQ[prior],
      "\n[前回の出力]\n" <> prior <> "\n[前回の問題点]\n" <> StringRiffle[diagnostics, "\n"] <>
      "\n問題点を直した完全な JSON を出力してください。\n", ""],
    "\n短い説明のあとに JSON を 1 つだけ ```json フェンスで出力してください。"];

(* ```json ... ``` を Association に *)
ifExtractGraph[answer_String] :=
  Module[{m, ba, g},
    m = StringCases[answer, "```" ~~ ("json" | "JSON") ~~ Shortest[code___] ~~ "```" :> code, 1];
    (* フェンスが無ければ最初の "{" から最後の "}" まで *)
    If[m === {},
      With[{p1 = StringPosition[answer, "{", 1], p2 = StringPosition[answer, "}"]},
        If[p1 =!= {} && p2 =!= {} && p2[[-1, 1]] > p1[[1, 1]],
          m = {StringTake[answer, {p1[[1, 1]], p2[[-1, 1]]}]}]]];
    If[m === {}, Return[None]];
    ba = StringToByteArray[StringTrim[First[m]], "UTF-8"];
    g = Quiet @ Check[ImportByteArray[ba, "RawJSON"], $Failed];
    If[AssociationQ[g] && KeyExistsQ[g, "nodes"], g, None]];

ifGenerateGraph[spec_String, opts_List] :=
  Catch[
    Module[{maxRounds, model, timeout, origin, nHints, place, access, promptPL, privacy,
            hints, prior, diags, answer, g, v, placed, probes, round, name, projDir, file, t0, context, display},
      maxRounds = OptionValue[ResoniteRealtime`ResoniteFluxGenerate, opts, "MaxRounds"];
      model     = OptionValue[ResoniteRealtime`ResoniteFluxGenerate, opts, "Model"];
      timeout   = OptionValue[ResoniteRealtime`ResoniteFluxGenerate, opts, "Timeout"];
      origin    = OptionValue[ResoniteRealtime`ResoniteFluxGenerate, opts, "Origin"];
      nHints    = OptionValue[ResoniteRealtime`ResoniteFluxGenerate, opts, "Hints"];
      place     = OptionValue[ResoniteRealtime`ResoniteFluxGenerate, opts, "Place"];
      If[place === Automatic, place = StringQ[$iState["Link"]]];
      t0 = iNow[];
      access   = ResoniteRealtime`ResoniteAccessLevel[];
      promptPL = icPromptPrivacy[origin, If[origin === "Notebook", Quiet @ Check[EvaluationNotebook[], None], None]];
      If[promptPL > access,
        Return[iFailure["WorldAccessDenied",
          "仕様の機密度 " <> ToString[promptPL] <> " がワールドのアクセスレベル " <> ToString[access] <> " を越えています。"]]];
      context = If[TrueQ[OptionValue[ResoniteRealtime`ResoniteFluxGenerate, opts, "SourceVault"]],
        icSourceVaultContext[spec, access], None];
      privacy = Max[promptPL, If[AssociationQ[context], context["PrivacyLevel"], 0.]];
      hints = DeleteDuplicatesBy[Join[
        ResoniteRealtime`ResoniteFluxCatalogSearch[spec, nHints],
        ResoniteRealtime`ResoniteFluxCatalogSearch[$ifGraphCoreQueries, 60]], #["Type"] &];

      prior = None; diags = {}; g = None; placed = None; probes = <||>; round = 0; v = None;
      While[round < maxRounds,
        round++;
        icSetStatus["ProtoFlux 生成 " <> ToString[round] <> "/" <> ToString[maxRounds]];
        answer = icQueryLLM[
          ifGraphPrompt[spec <> If[AssociationQ[context], "\n[参考]\n" <> context["Text"], ""], hints, prior, diags],
          privacy, origin, model, timeout];
        If[MatchQ[answer, _Failure], Return[answer]];
        g = ifExtractGraph[answer];
        If[!AssociationQ[g],
          prior = answer; diags = {"```json フェンスの中に nodes を持つ JSON がありません。"}; Continue[]];
        v = ResoniteRealtime`ResoniteFluxValidateGraph[g];
        diags = v["Errors"];
        If[diags === {} && TrueQ[place],
          If[AssociationQ[placed], Quiet @ ResoniteRealtime`ResoniteFluxRemove[placed]];
          placed = ResoniteRealtime`ResoniteFluxPlace[g];
          Which[
            MatchQ[placed, _Failure],
              diags = {"配置に失敗: " <> ToString[placed[[1]]] <> " " <>
                ToString[Lookup[placed[[2]], "MessageTemplate", ""]]}; placed = None,
            placed["Errors"] =!= {},
              diags = placed["Errors"],
            True,
              probes = Lookup[placed, "Probes", <||>];
              With[{missing = Keys @ Select[probes, MatchQ[#, _Missing] &]},
                If[missing =!= {},
                  diags = {"配置はできたが probes " <> StringRiffle[missing, ", "] <>
                    " が作られていない。インパルスの起点 (LocalUpdate 等) から WriteOrCreateDynamicValueVariable まで impulses が繋がっているか、" <>
                    "Target が ElementSource<Slot> (ref \"$root\") か、Path が ValueObjectInput<string> かを確認して直すこと。"}]]]];
        If[diags === {}, Break[]];
        prior = ExportString[g, "RawJSON"]];

      (* 配置できていれば最初の probe をワールド内の 3D テキストに出す (観測用) *)
      display = None;
      If[AssociationQ[placed] && diags === {} && TrueQ[OptionValue[ResoniteRealtime`ResoniteFluxGenerate, opts, "Display"]] &&
         Lookup[placed, "ProbeNames", {}] =!= {},
        display = Quiet @ Check[ResoniteRealtime`ResoniteFluxDisplay[placed, First[placed["ProbeNames"]]], $Failed]];

      name = ToString[Lookup[g, "name", "graph"]];
      projDir = FileNameJoin[{ResoniteRealtime`$ResoniteFluxProjects, ifSlug[name]}];
      Quiet @ CreateDirectory[projDir, CreateIntermediateDirectories -> True];
      file = FileNameJoin[{projDir, name <> ".flux.json"}];
      If[AssociationQ[g], BinaryWrite[file, ExportByteArray[g, "RawJSON"]]; Close[file]];
      icSetStatus["ProtoFlux " <> If[diags === {}, "OK", "未解決あり"] <>
        If[AssociationQ[placed], " 配置済 " <> ToString[Length[Lookup[placed, "Nodes", <||>]]] <> " ノード", ""] <>
        " (" <> ToString[round] <> " round, " <> ToString[Round[iNow[] - t0]] <> " s)"];
      <|"Format" -> "Graph", "Graph" -> g, "Source" -> If[AssociationQ[g], ExportString[g, "RawJSON"], None],
        "Module" -> name, "File" -> file, "Project" -> projDir,
        "Placed" -> placed, "Probes" -> probes, "Display" -> display, "Unknown" -> {}, "Build" -> None,
        "Rounds" -> round, "Diagnostics" -> diags, "Answer" -> answer,
        "PrivacyLevel" -> privacy, "AccessLevel" -> access, "Elapsed" -> Round[iNow[] - t0]|>],
    icTag];

ResoniteRealtime`ResoniteFluxGenerate[spec_String, opts : OptionsPattern[]] /;
    OptionValue[ResoniteRealtime`ResoniteFluxGenerate, {opts}, "Format"] === "Graph" :=
  If[StringTrim[spec] === "", iFailure["EmptyPrompt", "仕様が空です。"], ifGenerateGraph[spec, {opts}]];

ResoniteRealtime`ResoniteFluxGenerate[spec_String, opts : OptionsPattern[]] :=
  Catch[
    Module[{maxRounds, modName, model, timeout, doBuild, origin, nHints, access, promptPL,
            context, privacy, hints, prior, diags, answer, src, unknown, round, build,
            projDir, file, name, result, t0},
      maxRounds = OptionValue[ResoniteRealtime`ResoniteFluxGenerate, {opts}, "MaxRounds"];
      modName   = OptionValue[ResoniteRealtime`ResoniteFluxGenerate, {opts}, "Module"];
      model     = OptionValue[ResoniteRealtime`ResoniteFluxGenerate, {opts}, "Model"];
      timeout   = OptionValue[ResoniteRealtime`ResoniteFluxGenerate, {opts}, "Timeout"];
      doBuild   = OptionValue[ResoniteRealtime`ResoniteFluxGenerate, {opts}, "Build"];
      origin    = OptionValue[ResoniteRealtime`ResoniteFluxGenerate, {opts}, "Origin"];
      nHints    = OptionValue[ResoniteRealtime`ResoniteFluxGenerate, {opts}, "Hints"];
      If[StringTrim[spec] === "", Return[iFailure["EmptyPrompt", "仕様が空です。"]]];
      t0 = iNow[];

      (* アクセスレベルと機密度は Chat と同じ規則 *)
      access   = ResoniteRealtime`ResoniteAccessLevel[];
      promptPL = icPromptPrivacy[origin, If[origin === "Notebook", Quiet @ Check[EvaluationNotebook[], None], None]];
      If[promptPL > access,
        Return[iFailure["WorldAccessDenied",
          "仕様の機密度 " <> ToString[promptPL] <> " がワールドのアクセスレベル " <> ToString[access] <> " を越えています。"]]];
      context = If[TrueQ[OptionValue[ResoniteRealtime`ResoniteFluxGenerate, {opts}, "SourceVault"]],
        icSourceVaultContext[spec, access], None];
      privacy = Max[promptPL, If[AssociationQ[context], context["PrivacyLevel"], 0.]];

      (* ノードの手掛かり: 仕様の語 + 流れ制御の定番 *)
      hints = DeleteDuplicatesBy[Join[
        ResoniteRealtime`ResoniteFluxCatalogSearch[spec, nHints],
        ResoniteRealtime`ResoniteFluxCatalogSearch[$ifCoreNodeQueries, 40]], #["Type"] &];
      If[doBuild === Automatic, doBuild = ifFindSDK[] =!= None];

      prior = None; diags = {}; src = None; unknown = {}; build = None; round = 0;
      While[round < maxRounds,
        round++;
        icSetStatus["ProtoGraph 生成 " <> ToString[round] <> "/" <> ToString[maxRounds]];
        answer = icQueryLLM[
          ifGenerationPrompt[spec <> If[AssociationQ[context], "\n[参考]\n" <> context["Text"], ""],
            If[StringQ[modName], modName, None], hints, prior, diags],
          privacy, origin, model, timeout];
        If[MatchQ[answer, _Failure], Return[answer]];
        src = ifExtractPG[answer];
        If[!StringQ[src],
          prior = answer; diags = {"出力に ```protograph フェンスのコードがありません。"}; Continue[]];
        name = ifModuleName[src, If[StringQ[modName], modName, "Generated"]];
        (* 静的検査 *)
        unknown = ResoniteRealtime`ResoniteFluxUnknownNodes[src];
        diags = If[unknown === {}, {},
          {"カタログに無いノード名: " <> StringRiffle[unknown, ", "] <>
           " (実在するノードに置き換えるか、削ってください)"}];
        (* 保存 *)
        projDir = FileNameJoin[{ResoniteRealtime`$ResoniteFluxProjects, ifSlug[name]}];
        Quiet @ CreateDirectory[projDir, CreateIntermediateDirectories -> True];
        file = FileNameJoin[{projDir, name <> ".pg"}];
        Export[file, src, "Text", CharacterEncoding -> "UTF-8"];
        (* build *)
        If[TrueQ[doBuild] && unknown === {},
          build = ResoniteRealtime`ResoniteFluxBuild[file];
          If[AssociationQ[build] && !TrueQ[build["Success"]],
            diags = Join[diags, Take[build["Diagnostics"], UpTo[20]]];
            If[build["Diagnostics"] === {},
              diags = Append[diags, "flux-sdk build が失敗しました:\n" <>
                StringTake[build["Output"], UpTo[2000]]]]]];
        If[diags === {}, Break[]];
        prior = src];

      result = <|"Source" -> src, "Module" -> name, "File" -> file, "Project" -> projDir,
        "Unknown" -> unknown, "Build" -> build, "Rounds" -> round,
        "Diagnostics" -> diags, "Answer" -> answer, "PrivacyLevel" -> privacy,
        "AccessLevel" -> access, "Elapsed" -> Round[iNow[] - t0]|>;
      icSetStatus["ProtoGraph " <> If[diags === {}, "OK", "未解決あり"] <>
        " (" <> ToString[round] <> " round, " <> ToString[Round[iNow[] - t0]] <> " s)"];
      result],
    icTag];

(* ============================================================
   ガジェット (Chat と同じパネルに ProtoGraph を出す)
   ============================================================ *)

Options[ResoniteRealtime`ResoniteFluxChat] =
  Join[Options[ResoniteRealtime`ResoniteFluxGenerate], {"Notebook" -> Automatic, "World" -> True}];

ResoniteRealtime`ResoniteFluxChat[prompt_String, opts : OptionsPattern[]] :=
  Module[{genOpts, r, nb, origin, text, w},
    origin = OptionValue[ResoniteRealtime`ResoniteFluxChat, {opts}, "Origin"];
    genOpts = FilterRules[{opts}, Options[ResoniteRealtime`ResoniteFluxGenerate]];
    r = ResoniteRealtime`ResoniteFluxGenerate[prompt, Sequence @@ genOpts];
    If[MatchQ[r, _Failure], icSetText["AnswerText", "エラー: " <> ToString[r[[1]]]]; Return[r]];
    text = If[Lookup[r, "Format", "ProtoGraph"] === "Graph",
      StringJoin[
        "ProtoFlux ", r["Module"], "  (", If[r["Diagnostics"] === {}, "OK", "未解決あり"], ", ",
        ToString[r["Rounds"]], " round)\n",
        If[AssociationQ[r["Placed"]],
          "配置: " <> ToString[Length[r["Placed"]["Nodes"]]] <> " ノード (slot " <> r["Placed"]["Root"] <> ")\n" <>
          "probes: " <> StringRiffle[KeyValueMap[#1 <> " = " <> ToString[#2] &, Lookup[r, "Probes", <||>]], ", "] <> "\n",
          "配置: なし (ResoniteLink 未接続か失敗)\n"],
        If[r["Diagnostics"] =!= {}, StringRiffle[r["Diagnostics"], "\n"] <> "\n", ""],
        "\n", If[AssociationQ[r["Graph"]],
          StringRiffle[Map[ToString[#["id"]] <> ": " <> ToString[#["type"]] &, Lookup[r["Graph"], "nodes", {}]], "\n"],
          "(グラフ無し)"]],
      StringJoin[
        "module ", r["Module"], "  (", If[r["Diagnostics"] === {}, "OK", "未解決あり"], ", ",
        ToString[r["Rounds"]], " round)\n",
        If[AssociationQ[r["Build"]],
          "build: " <> If[TrueQ[r["Build"]["Success"]], "OK  " <> ToString[r["Build"]["Brson"]], "失敗"] <> "\n",
          "build: (flux-sdk なし。静的検査のみ)\n"],
        If[r["Diagnostics"] =!= {}, StringRiffle[r["Diagnostics"], "\n"] <> "\n", ""],
        "\n", If[StringQ[r["Source"]], r["Source"], "(コード無し)"]]];
    (* ノートブックへ *)
    nb = If[origin === "Notebook", Quiet @ Check[EvaluationNotebook[], None], None];
    If[OptionValue[ResoniteRealtime`ResoniteFluxChat, {opts}, "Notebook"] =!= False &&
       Head[nb] === NotebookObject && icClaudeQ[],
      w = icSym["ClaudeCode`ClaudeWriteResponse"];
      If[w =!= None, Quiet @ Check[w[nb,
        StringReplace[r["Answer"], "```protograph" -> "```text"] <>
        If[AssociationQ[Lookup[r, "Placed", None]],
          "\n\n配置済み: " <> ToString[Length[r["Placed"]["Nodes"]]] <> " ノード (slot `" <> r["Placed"]["Root"] <> "`)、probes: " <>
          ToString[Lookup[r, "Probes", <||>]], ""] <>
        "\n\n保存先: `" <> r["File"] <> "`" <>
        If[AssociationQ[r["Build"]] && StringQ[r["Build"]["Brson"]],
          "\n.brson: `" <> r["Build"]["Brson"] <> "` (Resonite へドラッグ&ドロップでインポート)", ""]], Null]]];
    (* ワールドへ *)
    If[TrueQ[OptionValue[ResoniteRealtime`ResoniteFluxChat, {opts}, "World"]],
      icSetText["AnswerText", text]];
    iPush[$icLog, <|"Time" -> DateObject[], "Origin" -> origin, "Prompt" -> prompt,
      "Answer" -> r["Answer"], "PrivacyLevel" -> r["PrivacyLevel"], "AccessLevel" -> r["AccessLevel"],
      "Mode" -> "ProtoFlux", "File" -> r["File"]|>, $icLogLimit];
    r];

(* 世界側の入力欄で "flux:" / "pf:" で始めると ProtoFlux モードにする (Chat のポーラから呼ばれる) *)
ifRoutePrefixQ[s_String] := StringMatchQ[StringTrim[s], ("flux:" | "pf:" | "protoflux:") ~~ ___, IgnoreCase -> True];
ifStripPrefix[s_String] := StringTrim[StringReplace[StringTrim[s],
  StartOfString ~~ ("flux:" | "pf:" | "protoflux:" | "Flux:" | "PF:" | "ProtoFlux:") -> ""]];

$ifCellStyle =
  Cell[StyleData["ResoniteFluxInput", StyleDefinitions -> StyleData["Text"]],
    CellFrame -> {{3, 1}, {1, 1}},
    CellFrameColor -> RGBColor[0.55, 0.35, 0.7],
    CellDingbat -> Cell[BoxData[StyleBox["\[FilledDiamond]",
      FontColor -> RGBColor[0.55, 0.35, 0.7], FontSize -> 16, FontWeight -> "Bold"]],
      Background -> None],
    CellMargins -> {{66, 50}, {5, 8}},
    Background -> RGBColor[0.97, 0.95, 0.99],
    Evaluatable -> True,
    CellGroupingRules -> "InputGrouping",
    CellEvaluationFunction -> Function[{content, fmt},
      Module[{tasktext},
        tasktext = If[StringQ[content], content,
          Quiet @ Check[First[FrontEndExecute[
            FrontEnd`ExportPacket[Cell[content, "Text"], "PlainText"]]], $Failed]];
        If[StringQ[tasktext],
          tasktext = StringReplace[tasktext, {"\\\\" -> "\\",
            "\\|" ~~ hex6 : RegularExpression["[0-9a-fA-F]{6}"] :>
              FromCharacterCode[FromDigits[hex6, 16]],
            "\\:" ~~ hex4 : RegularExpression["[0-9a-fA-F]{4}"] :>
              FromCharacterCode[FromDigits[hex4, 16]]}]];
        If[StringQ[tasktext] && StringTrim[tasktext] =!= "",
          If[Length[Names["ResoniteRealtime`ResoniteFluxChat"]] > 0,
            Symbol["ResoniteRealtime`ResoniteFluxChat"][tasktext],
            Print[Style["ResoniteRealtime がロードされていません。", Red]]],
          Null]]]];

ResoniteRealtime`ResoniteFluxCell[] :=
  Module[{nb = InputNotebook[]},
    If[Head[nb] =!= NotebookObject, Return[$Failed]];
    icEnsureCellStyleNamed[nb, "ResoniteFluxInput", $ifCellStyle];
    NotebookWrite[nb, Cell["", "ResoniteFluxInput"], All];
    SelectionMove[nb, All, CellContents];
    nb];

(* ============================================================
   デプロイ
   ============================================================ *)

Options[ResoniteRealtime`ResoniteFluxDeploy] = {"Method" -> "Import", "Parent" -> "Flux"};

ResoniteRealtime`ResoniteFluxDeploy[r_Association, opts : OptionsPattern[]] :=
  Module[{method, brson, script, port, res},
    method = OptionValue[ResoniteRealtime`ResoniteFluxDeploy, {opts}, "Method"];
    brson = If[AssociationQ[Lookup[r, "Build", None]], Lookup[r["Build"], "Brson", None], None];
    Which[
      method === "Import",
        If[StringQ[brson],
          <|"Method" -> "Import", "Brson" -> brson,
            "Instruction" -> "Resonite のウインドウへ .brson をドラッグ&ドロップするとノードとして実体化します。" <>
              "in/out がある場合は Flux SDK UI (I/O Assigner) で世界のフィールドに結線してください。"|>,
          iFailure["NoBrson", "build 済みの .brson がありません。flux-sdk を入れて ResoniteFluxBuild を通してください。"]],
      method === "ResoniteLink",
        script = FileNameJoin[{$ifToolsDir, "flux-deploy.fsx"}];
        port = Lookup[$iState, "LinkPort", None];
        If[!FileExistsQ[script], Return[iFailure["NoScript", "flux-deploy.fsx がありません。"]]];
        If[!IntegerQ[port], Return[iFailure["NotConnected", "ResoniteLink の port が分かりません。ResoniteRealtimeLinkConnect[port] を先に。"]]];
        res = Quiet @ Check[RunProcess[{"dotnet", "fsi", script, r["Project"], r["Module"],
            ToString[port], OptionValue[ResoniteRealtime`ResoniteFluxDeploy, {opts}, "Parent"]},
          ProcessDirectory -> r["Project"]], $Failed];
        If[!AssociationQ[res], Return[iFailure["Deploy", "dotnet fsi を起動できませんでした。"]]];
        <|"Method" -> "ResoniteLink", "ExitCode" -> res["ExitCode"],
          "Output" -> res["StandardOutput"] <> "\n" <> res["StandardError"]|>,
      True, iFailure["BadMethod", "Method は \"Import\" か \"ResoniteLink\"。"]]];

End[];

EndPackage[];
