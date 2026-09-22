(* ::Package:: *)

(* ResoniteRealtime_chat.wl -- Chat セル (ClaudeEval の ClaudeInput) をワールド内で実現するガジェット

   This file is encoded in UTF-8.
   ResoniteRealtime.wl が自動でロードする (同じ ResoniteRealtime` コンテキスト)。

   ---- 何をするか ----

   1. ノートブック側: ResoniteChat[prompt] / ResoniteChatCell[] (ResoniteInput セル)。
      プロンプトを LLM に投げ、答えをノートブックに書き、同時にワールド内のパネルへ出す。
   2. ワールド側: ResoniteChatGadget[] が ResoniteLink (L2) だけで UIX パネルを組み立てる
      (世界側のノード作業ゼロ)。パネルの入力欄に打って「送信」チェックを入れると、
      ResoniteChatStart[] のポーリングが拾って LLM に投げ、答えをパネルへ返す。
   3. L1 ブリッジ経由: 世界の ProtoFlux から "ask<TAB>質問" が来ても同じ処理を走らせる。

   ---- アクセスレベル (2026-09-06 の暫定値。今後更新する) ----

   ワールドが Public なら 0.25、Private なら 1.0 ($ResoniteWorldAccessLevels)。
   - SourceVault の文脈は release context "resonite-public" (MaxPrivacyLevel 0.25) /
     "resonite-private" (1.0) で引く。
   - LLM への PrivacyLevel = Max[プロンプトの機密度, 文脈の機密度, (Private ワールドなら 1.0)]。
     0.5 を越えると claudecode が $ClaudePrivateModel (ローカル LLM) へ回す (fail-closed)。
   - プロンプトの機密度がワールドのアクセスレベルを越える (Private ノートの内容を Public
     ワールドに出そうとした) ときは LLM を呼ばずに拒否する。

   ---- 設計上の約束 ----

   - 常駐 Dynamic でポーリングしない。世界側入力の監視は ScheduledTask 1 本
     (ResoniteChatStart / ResoniteChatStop で必ず対にする)。
   - ScheduledTask / SocketListen のコールバックの中では FrontEnd を触らない
     (LLM は ClaudeQueryBg、画像化だけ UsingFrontEnd で最小限)。
   - ResoniteLink のメッセージ組立は本体の ResoniteRealtimeAddSlot / AddComponent /
     UpdateComponent / GetSlot を通す (このファイルに $type を書かない)。
*)

BeginPackage["ResoniteRealtime`"];

ResoniteRealtime`$ResoniteWorldAccess::usage =
  "$ResoniteWorldAccess は今開いているワールドの公開度 (\"Private\" | \"Contacts\" | \"ContactsPlus\" | \"Public\")。既定 \"Public\" (厳しい側)。";
ResoniteRealtime`$ResoniteWorldAccessLevels::usage =
  "$ResoniteWorldAccessLevels はワールド公開度 → アクセスレベル (表示上限 PL) の表。\n" <>
  "既定 <|\"Private\" -> 1.0, \"Contacts\" -> 0.5, \"ContactsPlus\" -> 0.25, \"Public\" -> 0.25|> (2026-09-22 指示)。";
ResoniteRealtime`$ResoniteWorldOwner::usage =
  "$ResoniteWorldOwner が True なら今のワールドは自分のもの (公開度の表が効く)。False (既定、厳しい側) なら公開度に関わらず 0.25。\n" <>
  "ResoniteLink からワールドの所有者と公開度は取れないので手で設定する: ResoniteAccessLevel[\"Private\", \"Owner\" -> True]。";
ResoniteRealtime`ResoniteAccessLevel::usage =
  "ResoniteAccessLevel[] は現在のワールドのアクセスレベル (表示上限 PL: 1.0 / 0.5 / 0.25) を返す。\n" <>
  "ResoniteAccessLevel[\"Private\" | \"Contacts\" | \"ContactsPlus\" | \"Public\", \"Owner\" -> True | False] で\n" <>
  "$ResoniteWorldAccess (と $ResoniteWorldOwner) を設定して返す。オーナーでなければ一律 0.25。";

ResoniteRealtime`ResoniteChat::usage =
  "ResoniteChat[prompt] はプロンプトを LLM に投げ、答えをノートブックとワールド内パネルの両方へ出す。\n" <>
  "オプション: \"Notebook\" -> Automatic (答えをノートブックにも書く), \"World\" -> True,\n" <>
  "  \"SourceVault\" -> Automatic (SourceVault KB の文脈を付ける), \"Evaluate\" -> False\n" <>
  "  (答えの Mathematica コードを評価して図なら板に出す), \"Model\" -> Automatic, \"Timeout\" -> 180,\n" <>
  "  \"Origin\" -> \"Notebook\" | \"World\" | \"Bridge\"。\n" <>
  "戻り値: <|\"Answer\", \"PrivacyLevel\", \"AccessLevel\", \"Context\", \"Shown\"|> か Failure。";
ResoniteRealtime`ResoniteChatCell::usage =
  "ResoniteChatCell[] は入力ノートブックに ResoniteInput セル (Shift+Enter で ResoniteChat を走らせる) を挿入する。";
ResoniteRealtime`ResoniteChatGadget::usage =
  "ResoniteChatGadget[] は ResoniteLink でワールド内に Chat パネル (入力欄 / 送信ボタン / 答え / 板) を組み立てる。\n" <>
  "既定ではアバターの頭の正面に置く: \"Placement\" -> \"User\" | \"World\", \"Distance\" -> 1.5 (m),\n" <>
  "  \"Height\" -> Automatic (目の高さ - 0.25 m。数値なら足元からの高さ), \"User\" -> Automatic (名前の一部で選ぶ)。\n" <>
  "オプション: \"Position\" -> {0, 1.4, 1.5}, \"Parent\" -> \"Root\" (Placement が World のとき), \"Name\" -> \"Mathematica Chat\",\n" <>
  "  \"CanvasSize\" -> {1200, 800} (単位), \"PanelScale\" -> 0.001 (m/単位), \"FontSize\" -> 28,\n" <>
  "  \"Board\" -> True (図を出す板も作る)。\n" <>
  "戻り値: ID の Association ($icState[\"Gadget\"] にも保持)。";
ResoniteRealtime`ResoniteChatAttach::usage =
  "ResoniteChatAttach[ids] は別のカーネルが作ったパネル (ResoniteChatGadget の戻り値) をこのカーネルで引き継ぐ。";
ResoniteRealtime`ResoniteChatRemoveGadget::usage =
  "ResoniteChatRemoveGadget[] はワールド内の Chat パネルを消す。";
ResoniteRealtime`ResoniteChatStart::usage =
  "ResoniteChatStart[] はワールド内パネルの入力を監視する ScheduledTask を 1 本だけ起動する。\n" <>
  "オプション: \"PollInterval\" -> 1.5 (秒), \"Evaluate\" -> False。";
ResoniteRealtime`ResoniteChatStop::usage =
  "ResoniteChatStop[] は監視タスクを止める。";
ResoniteRealtime`ResoniteChatShow::usage =
  "ResoniteChatShow[text] はワールド内パネルの答え欄に文字列をそのまま出す。\n" <>
  "ResoniteChatShow[expr] (文字列以外) は板に画像として出す。";
ResoniteRealtime`ResoniteChatLog::usage =
  "ResoniteChatLog[n] は直近 n 件の会話レコード (<|\"Time\",\"Origin\",\"Prompt\",\"Answer\",\"PrivacyLevel\"|>) を返す。";
ResoniteRealtime`ResoniteChatStatus::usage =
  "ResoniteChatStatus[] はガジェット・監視タスク・アクセスレベルの状態を返す。";

Begin["`Private`"];

(* 本体と同じ理由 (引数パターン変更時に旧定義が残る) で、このファイルの公開シンボルだけ落とす。
   $ResoniteWorldAccess は設定値なので落とさない (Private 側の $icState に写しを持つ)。 *)
Scan[Quiet[Clear[#]] &,
  Join[Names["ResoniteRealtime`ResoniteChat*"], {"ResoniteRealtime`ResoniteAccessLevel"}]];

(* ---- 状態 (再ロードで壊さない) ---- *)
If[!AssociationQ[$icState],
  $icState = <|"Gadget" -> None, "Task" -> None, "Busy" -> False,
    "WorldAccess" -> "Public", "ContextsRegistered" -> False, "LastError" -> None|>];
If[!ListQ[$icLog], $icLog = {}];
$icLogLimit = 100;

(* 2026-09-22: 2 段 (Public/Private) から 4 段へ。旧表しか無いカーネルは新表に置き換える *)
If[!AssociationQ[ResoniteRealtime`$ResoniteWorldAccessLevels] ||
   !KeyExistsQ[ResoniteRealtime`$ResoniteWorldAccessLevels, "Contacts"],
  ResoniteRealtime`$ResoniteWorldAccessLevels =
    <|"Private" -> 1.0, "Contacts" -> 0.5, "ContactsPlus" -> 0.25, "Public" -> 0.25|>];
If[!StringQ[ResoniteRealtime`$ResoniteWorldAccess],
  ResoniteRealtime`$ResoniteWorldAccess = Lookup[$icState, "WorldAccess", "Public"]];
If[!BooleanQ[ResoniteRealtime`$ResoniteWorldOwner], ResoniteRealtime`$ResoniteWorldOwner = False];

(* ============================================================
   アクセスレベル
   ============================================================ *)

icAccessName[] :=
  Module[{a = ResoniteRealtime`$ResoniteWorldAccess},
    If[!StringQ[a] || !KeyExistsQ[ResoniteRealtime`$ResoniteWorldAccessLevels, a],
      a = "Public";
      ResoniteRealtime`$ResoniteWorldAccess = a];
    $icState = Join[$icState, <|"WorldAccess" -> a|>];
    a];

(* オーナーでないワールドは公開度に関わらず 0.25 (2026-09-22 指示)。所有者/公開度は ResoniteLink から
   取れないので手動 ($ResoniteWorldOwner / $ResoniteWorldAccess)。既定は厳しい側 (非オーナー = 0.25)。 *)
ResoniteRealtime`ResoniteAccessLevel[] :=
  If[!TrueQ[ResoniteRealtime`$ResoniteWorldOwner], 0.25,
    N @ Lookup[ResoniteRealtime`$ResoniteWorldAccessLevels, icAccessName[], 0.25]];

Options[ResoniteRealtime`ResoniteAccessLevel] = {"Owner" -> Automatic};

ResoniteRealtime`ResoniteAccessLevel[access_String, opts : OptionsPattern[]] /;
    KeyExistsQ[ResoniteRealtime`$ResoniteWorldAccessLevels, access] := (
  ResoniteRealtime`$ResoniteWorldAccess = access;
  With[{o = OptionValue[ResoniteRealtime`ResoniteAccessLevel, {opts}, "Owner"]},
    If[BooleanQ[o], ResoniteRealtime`$ResoniteWorldOwner = o]];
  ResoniteRealtime`ResoniteAccessLevel[]);

(* SourceVault の release context 名。非オーナーは常に public (0.25) *)
icReleaseContext[] :=
  If[!TrueQ[ResoniteRealtime`$ResoniteWorldOwner], "resonite-public",
    "resonite-" <> ToLowerCase[icAccessName[]]];

(* ============================================================
   他パッケージとの弱い結合 (ロード順に依存しない)
   ============================================================ *)

icSym[name_String] :=
  If[Length[Names[name]] > 0, Symbol[name], None];

icClaudeQ[]   := MemberQ[$Packages, "ClaudeCode`"];
icSVQ[]       := MemberQ[$Packages, "SourceVault`"];
icNBAccessQ[] := MemberQ[$Packages, "NBAccess`"];

(* SourceVault の release context を初回だけ登録する (登録簿は永続化される)。 *)
icEnsureReleaseContexts[] :=
  Module[{reg, list, f},
    If[TrueQ[$icState["ContextsRegistered"]] || !icSVQ[], Return[Null]];
    reg  = icSym["SourceVault`SourceVaultRegisterReleaseContext"];
    list = icSym["SourceVault`SourceVaultListReleaseContexts"];
    If[reg === None, Return[Null]];
    f = Quiet @ Check[list[], {}];
    If[!ListQ[f], f = {}];
    KeyValueMap[
      Function[{name, level},
        With[{ctx = "resonite-" <> ToLowerCase[name]},
          If[!MemberQ[f, ctx],
            Quiet @ Check[reg[ctx, <|"MaxPrivacyLevel" -> N[level],
              "DisplayName" -> "Resonite " <> name <> " world",
              "AllowAnswerGeneration" -> True|>], Null]]]],
      ResoniteRealtime`$ResoniteWorldAccessLevels];
    $icState = Join[$icState, <|"ContextsRegistered" -> True|>];
    Null];

(* SourceVault KB から文脈を引く。<|"Text", "PrivacyLevel"|> か None。
   KBAnswer は LLM を呼ばず、release context の MaxPrivacyLevel で絞った根拠文だけ返す。 *)
icSourceVaultContext[prompt_String, accessLevel_] :=
  Module[{ans, f, txt, pl},
    If[!icSVQ[], Return[None]];
    icEnsureReleaseContexts[];
    ans = icSym["SourceVault`SourceVaultKBAnswer"];
    If[ans === None, Return[None]];
    f = Quiet @ Check[
      ans[prompt, "ReleaseContext" -> icReleaseContext[], "MaxContextCharacters" -> 1500],
      $Failed];
    If[!AssociationQ[f] || Lookup[f, "Count", 0] === 0, Return[None]];
    txt = Lookup[f, "ContextText", ""];
    pl  = Lookup[f, "MaxPrivacyLevel", accessLevel];
    If[!StringQ[txt] || StringTrim[txt] === "", Return[None]];
    (* release context で絞ってあるはずだが、二重に確認する (迷ったら厳しい側) *)
    If[!NumericQ[pl] || pl > accessLevel, Return[None]];
    <|"Text" -> txt, "PrivacyLevel" -> N[pl]|>];

(* プロンプト自体の機密度 (ノートブック起点のときだけ NBAccess に聞く) *)
icPromptPrivacy[origin_String, nb_] :=
  Module[{req, cell, lv1, lv2},
    Which[
      origin === "Notebook" && icNBAccessQ[] && Head[nb] === NotebookObject,
        req  = icSym["NBAccess`NBNotebookRequiredAccessLevel"];
        cell = icSym["NBAccess`NBCellObjectPrivacyLevel"];
        lv1 = If[req =!= None, Quiet @ Check[req[nb], 0.], 0.];
        lv2 = If[cell =!= None,
          Quiet @ Check[cell[Quiet @ EvaluationCell[]], 0.], 0.];
        Max[Select[{lv1, lv2, 0.}, NumericQ]],
      (* 世界起点: ワールドの中で打たれた文字はそのワールドの水準 (Private 1.0 / Contacts 0.5 / それ以外 0)。
         0.25 は「表示上限」であって文字の機密度ではないので 0 に丸める *)
      origin === "World" || origin === "Bridge",
        With[{l = ResoniteRealtime`ResoniteAccessLevel[]}, If[l > 0.25, l, 0.]],
      True, 0.]];

(* ============================================================
   LLM 呼び出し
   ============================================================ *)

$icSystemPrefix =
"あなたは Mathematica から Resonite (VR) のワールド内に置かれたチャットパネルに答えを出すアシスタントです。\n" <>
"答えはパネルにそのまま表示されるので、簡潔に、見出し記号や太字などの Markdown 装飾は最小限にしてください。\n" <>
"計算や図が要るときだけ ```mathematica ブロックで Wolfram Language を 1 つ書いてください (説明は日本語)。\n";

icBuildPrompt[prompt_String, context_] :=
  $icSystemPrefix <>
  If[AssociationQ[context],
    "\n[参考資料 (SourceVault)]\n" <> context["Text"] <> "\n[参考資料ここまで]\n", ""] <>
  "\n[質問]\n" <> prompt;

(* origin が Notebook なら進捗表示つきの ClaudeQuerySync、それ以外 (ScheduledTask / SocketListen
   の中) は FrontEnd を触らない ClaudeQueryBg を使う。 *)
(* claudecode のオプション記号 (Model / PrivacyLevel / Timeout) はコンテキストが
   ロード順で変わり得るので、Options の実際のキーから名前で引く。 *)
icOpt[fn_, name_String] :=
  SelectFirst[Keys[Options[fn]], SymbolName[#] === name &, Symbol[name]];

(* テスト用の差し替え口: $icQueryOverride = Function[{prompt, privacy}, "answer"] を置くと
   LLM を呼ばずにそれを使う (test_chat.wl が使う)。 *)
If[!ValueQ[$icQueryOverride], $icQueryOverride = None];

icQueryLLM[fullPrompt_String, privacy_, origin_String, model_, timeout_] :=
  Module[{sync, bg, res, f, o},
    If[$icQueryOverride =!= None,
      res = $icQueryOverride[fullPrompt, privacy];
      Return[If[StringQ[res] || MatchQ[res, _Failure], res,
        iFailure["LLM", "override が文字列を返しませんでした。"]]]];
    If[!icClaudeQ[],
      Return[iFailure["NoClaudeCode", "claudecode.wl がロードされていません。"]]];
    sync = icSym["ClaudeCode`ClaudeQuerySync"];
    bg   = icSym["ClaudeCode`ClaudeQueryBg"];
    res = Quiet @ Check[
      If[origin === "Notebook" && sync =!= None,
        f = sync;
        f[fullPrompt, icOpt[f, "Model"] -> model, icOpt[f, "PrivacyLevel"] -> privacy,
          icOpt[f, "Timeout"] -> timeout],
        (* ClaudeQueryBg に PrivacyLevel は無い: 0.5 を越えるときは $ClaudePrivateModel を明示する *)
        f = bg;
        f[fullPrompt,
          icOpt[f, "Model"] -> If[privacy > 0.5 && model === Automatic,
            icPrivateModelSpec[], model],
          icOpt[f, "Timeout"] -> timeout]],
      $Failed];
    If[!StringQ[res], Return[iFailure["LLM", "LLM から文字列の応答が得られませんでした。"]]];
    If[StringStartsQ[res, "Error:"], Return[iFailure["LLM", res]]];
    res];

(* PrivacyLevel > 0.5 でローカル LLM が無ければ送らない (fail-closed) *)
icPrivateModelSpec[] :=
  Module[{m = icSym["ClaudeCode`$ClaudePrivateModel"]},
    If[ListQ[m] && Length[m] >= 2, m,
      Throw[iFailure["PrivateModelNotConfigured",
        "PrivacyLevel > 0.5 の内容ですが $ClaudePrivateModel (ローカル LLM) が未設定です。"], icTag]]];

(* ```mathematica ... ``` を取り出す (最初の 1 つ) *)
icExtractCode[answer_String] :=
  Module[{m},
    m = StringCases[answer,
      "```" ~~ ("mathematica" | "wolfram" | "wl") ~~ Shortest[code___] ~~ "```" :> code, 1];
    If[m === {}, None, StringTrim[First[m]]]];

icGraphicsQ[e_] :=
  MatchQ[e, _Graphics | _Graphics3D | _Image | _Legended | _GraphicsBox | _Grid | _Dataset] ||
  ImageQ[e];

(* 答えの中のコードを評価する (既定 off)。図なら板へ、それ以外は文字列で返す。 *)
icEvaluate[code_String, size_] :=
  Module[{r},
    r = Quiet @ Check[TimeConstrained[ToExpression[code], 120, $Aborted], $Failed];
    Which[
      r === $Aborted, <|"Kind" -> "Text", "Value" -> "(評価が 120 秒で打ち切られました)"|>,
      icGraphicsQ[r], <|"Kind" -> "Graphics", "Value" -> r|>,
      True, <|"Kind" -> "Text", "Value" -> ToString[r, InputForm]|>]];

(* ============================================================
   ResoniteChat 本体
   ============================================================ *)

Options[ResoniteRealtime`ResoniteChat] = {
  "Notebook" -> Automatic, "World" -> True, "SourceVault" -> Automatic,
  "Evaluate" -> False, "Model" -> Automatic, "Timeout" -> 180, "Origin" -> "Notebook"};

ResoniteRealtime`ResoniteChat[prompt_String, opts : OptionsPattern[]] :=
  Catch[
    Module[{origin, nb, access, promptPL, context, privacy, full, answer, code, ev,
            showText, out, useSV, writeNB, model, timeout, t0},
      origin  = OptionValue[ResoniteRealtime`ResoniteChat, {opts}, "Origin"];
      model   = OptionValue[ResoniteRealtime`ResoniteChat, {opts}, "Model"];
      timeout = OptionValue[ResoniteRealtime`ResoniteChat, {opts}, "Timeout"];
      useSV   = OptionValue[ResoniteRealtime`ResoniteChat, {opts}, "SourceVault"];
      writeNB = OptionValue[ResoniteRealtime`ResoniteChat, {opts}, "Notebook"];
      If[StringTrim[prompt] === "", Return[iFailure["EmptyPrompt", "プロンプトが空です。"]]];
      nb = If[origin === "Notebook", Quiet @ Check[EvaluationNotebook[], None], None];
      t0 = iNow[];

      access   = ResoniteRealtime`ResoniteAccessLevel[];
      promptPL = icPromptPrivacy[origin, nb];
      (* Private ノートの内容を Public ワールドへ出さない *)
      If[promptPL > access,
        Return[iFailure["WorldAccessDenied",
          "プロンプトの機密度 " <> ToString[promptPL] <> " がワールドのアクセスレベル " <>
          ToString[access] <> " (" <> icAccessName[] <> ") を越えています。" <>
          "ワールドへは出しません。ResoniteAccessLevel[\"Private\"] で切り替えられます。"]]];

      context = If[useSV === False, None, icSourceVaultContext[prompt, access]];
      privacy = Max[promptPL, If[AssociationQ[context], context["PrivacyLevel"], 0.]];
      full    = icBuildPrompt[prompt, context];

      icSetStatus["考え中... (" <> icAccessName[] <> ", PL " <> ToString[privacy] <> ")"];
      answer = icQueryLLM[full, privacy, origin, model, timeout];
      If[MatchQ[answer, _Failure],
        $icState = Join[$icState, <|"LastError" -> answer|>];
        icSetStatus["エラー: " <> ToString[answer[[1]]]];
        Return[answer]];

      (* 任意: コードの評価 *)
      code = icExtractCode[answer];
      ev = If[TrueQ[OptionValue[ResoniteRealtime`ResoniteChat, {opts}, "Evaluate"]] && StringQ[code],
        icEvaluate[code, 800], None];

      (* ノートブックへ *)
      If[origin === "Notebook" && writeNB =!= False && Head[nb] === NotebookObject && icClaudeQ[],
        With[{w = icSym["ClaudeCode`ClaudeWriteResponse"]},
          If[w =!= None, Quiet @ Check[w[nb, answer], Null]]]];

      (* ワールドへ *)
      showText = icStripFences[answer];
      If[AssociationQ[ev] && ev["Kind"] === "Text",
        showText = showText <> "\n\n= " <> ev["Value"]];
      out = If[TrueQ[OptionValue[ResoniteRealtime`ResoniteChat, {opts}, "World"]],
        icShowInWorld[showText, If[AssociationQ[ev] && ev["Kind"] === "Graphics", ev["Value"], None]],
        None];
      icSetStatus["done (" <> ToString[Round[iNow[] - t0]] <> " s)"];

      iPush[$icLog, <|"Time" -> DateObject[], "Origin" -> origin, "Prompt" -> prompt,
        "Answer" -> answer, "PrivacyLevel" -> privacy, "AccessLevel" -> access|>, $icLogLimit];
      <|"Answer" -> answer, "PrivacyLevel" -> privacy, "AccessLevel" -> access,
        "Context" -> If[AssociationQ[context], context["Text"], None], "Shown" -> out,
        "Evaluated" -> ev|>],
    icTag];

(* コードフェンスはパネルでは読めないので中身だけ残す *)
icStripFences[s_String] :=
  StringReplace[StringReplace[s, "```" ~~ Except["\n"] ... ~~ "\n" -> ""], "```" -> ""];

(* ============================================================
   ワールド側: パネル (UIX) を L2 で組み立てる
   ============================================================ *)

(* ResoniteLink の応答を確認して失敗なら Throw。AddSlot/AddComponent は <|"Id","Response"|>、
   それ以外は生の応答 (Failure か Association) を返すので両方受ける。 *)
icCheck[r_Association /; KeyExistsQ[r, "Response"]] :=
  If[MatchQ[r["Response"], _Failure], Throw[r["Response"], icTag], r["Id"]];
icCheck[r_Failure] := Throw[r, icTag];
icCheck[r_] := r;

icSlot[name_String, parent_String, more___Rule] :=
  icCheck[ResoniteRealtime`ResoniteRealtimeAddSlot["Name" -> name, "Parent" -> parent, more]];

icComp[slot_String, type_String, members_Association : <||>, id_ : Automatic] :=
  icCheck[ResoniteRealtime`ResoniteRealtimeAddComponent[slot, type, members, id]];

$icUIX = "[FrooxEngine]FrooxEngine.UIX.";
$icFE  = "[FrooxEngine]FrooxEngine.";

(* UIX の Graphic (Image / Text) はマテリアルが無いと描画されない (in-game の UIBuilder は
   UI_UnlitMaterial / UI_TextUnlitMaterial を必ず付ける)。パネルごとに 1 つずつ作って共有する。 *)
If[!AssociationQ[$icMats], $icMats = <||>];

icText[slot_String, content_String, size_, id_ : Automatic] :=
  icComp[slot, $icUIX <> "Text",
    (* 整列 (enum) は ResoniteLink での書式が未確認なので既定のままにする *)
    Join[<|"Content" -> content, "Size" -> N[size], "ParseRichText" -> False,
        "Color" -> RGBColor[0.95, 0.95, 0.95, 1]|>,
      If[StringQ[Lookup[$icMats, "Text", None]],
        <|"Materials" -> <|"$type" -> "list",
            "elements" -> {ResoniteRealtime`ResoniteRealtimeRef[$icMats["Text"]]}|>|>, <||>]], id];

icImage[slot_String, tint_RGBColor] :=
  icComp[slot, $icUIX <> "Image",
    Join[<|"Tint" -> tint|>,
      If[StringQ[Lookup[$icMats, "Image", None]],
        <|"Material" -> ResoniteRealtime`ResoniteRealtimeRef[$icMats["Image"]]|>, <||>]]];

(* コンポーネントのメンバ (フィールド) の ID を getSlot の応答から拾う。
   応答のメンバは <|"$type"->..., "value"->..., "id"->"Reso_..."|> の形で id を持つ。 *)
icMemberId[slotId_String, compId_String, member_String] :=
  Module[{t, comp, m},
    t = ResoniteRealtime`ResoniteRealtimeGetSlot[slotId, "Depth" -> 0, "IncludeComponentData" -> True];
    comp = icFindComponent[t, compId];
    If[!AssociationQ[comp], Return[None]];
    m = Lookup[Lookup[comp, "members", <||>], member, None];
    If[AssociationQ[m], Lookup[m, "id", None], None]];

(* パネルの 5 mm 後ろ (奥 = +z。2026-09-06 実機で確認) に置く不透明な板 (QuadMesh + UnlitMaterial + MeshRenderer) *)
icBackdrop[root_String, w_, h_] :=
  Module[{bd, mesh, mat},
    bd = icSlot["Backdrop", root, "Position" -> {0, 0, 0.005}, "Scale" -> {w, h, 1}];
    mesh = icComp[bd, $icFE <> "QuadMesh", <||>];
    mat  = icComp[bd, $icFE <> "UnlitMaterial", <|"TintColor" -> RGBColor[0.06, 0.07, 0.1, 1]|>];
    icComp[bd, $icFE <> "MeshRenderer",
      <|"Mesh" -> ResoniteRealtime`ResoniteRealtimeRef[mesh],
        "Materials" -> <|"$type" -> "list",
          "elements" -> {ResoniteRealtime`ResoniteRealtimeRef[mat]}|>|>];
    bd];

icMakeMaterials[slot_String] :=
  ($icMats = <|
     "Image" -> icComp[slot, $icFE <> "UI_UnlitMaterial", <||>,
       ResoniteRealtime`ResoniteRealtimeNewId["UIMat"]],
     "Text" -> icComp[slot, $icFE <> "UI_TextUnlitMaterial", <||>,
       ResoniteRealtime`ResoniteRealtimeNewId["UITextMat"]]|>);

icLayoutElement[slot_String, minH_, flexH_] :=
  icComp[slot, $icUIX <> "LayoutElement",
    <|"MinHeight" -> N[minH], "FlexibleHeight" -> N[flexH]|>];

(* Canvas の Size はスロットスケール 1 で「メートル」。文字サイズや行の高さも同じ単位なので、
   Resonite の流儀どおり Canvas を 1200x800 単位にして Panel スロットを "PanelScale" (m/単位) で縮める。
   見た目は CanvasSize * PanelScale = 1.2 m x 0.8 m。(2026-09-06 実機: 単位を混ぜると要素がパネルの外へ飛ぶ) *)
Options[ResoniteRealtime`ResoniteChatGadget] = {
  "Placement" -> "User", "Distance" -> 1.5, "Height" -> Automatic, "User" -> Automatic,
  "Position" -> {0, 1.4, 1.5}, "Parent" -> "Root", "Name" -> "Mathematica Chat",
  "CanvasSize" -> {1200, 800}, "PanelScale" -> 0.001, "FontSize" -> 28, "Board" -> True,
  "Backdrop" -> False};

(* ---- アバターの正面に出す ----
   ユーザの根 slot (UserRoot コンポーネントを持つ "User ..." という名の slot) を探し、その親の座標系で
   「根の位置 + 向き * Distance + 上に Height」に置き、向きも根に合わせる (キャンバスの表は -z なので
   根と同じ回転にするとユーザを向く)。親を同じにするのは、根の親 (Spawn holder) が回転している
   ワールドでもグローバル座標の合成を省くため (2026-09-06 実機: holder は y 軸 180° 回転していた)。 *)
icQuatForward[{x_, y_, z_, w_}] :=
  {2 (x z + w y), 2 (y z - w x), 1 - 2 (x^2 + y^2)};

(* 四元数 (x,y,z,w) の積 (親 ⊗ 子 = 子を親の座標系で回す) とベクトルの回転 *)
icQuatMul[{x1_, y1_, z1_, w1_}, {x2_, y2_, z2_, w2_}] :=
  {w1 x2 + x1 w2 + y1 z2 - z1 y2,
   w1 y2 - x1 z2 + y1 w2 + z1 x2,
   w1 z2 + x1 y2 - y1 x2 + z1 w2,
   w1 w2 - x1 x2 - y1 y2 - z1 z2};

icQuatRotate[{x_, y_, z_, w_}, v_List] :=
  With[{u = {x, y, z}}, v + 2 w Cross[u, v] + 2 Cross[u, Cross[u, v]]];

(* 水平方向の向き f (y を捨てて正規化) から、直立した y 軸回転の四元数 *)
icYawQuat[f_List] :=
  With[{th = ArcTan[f[[3]], f[[1]]]}, {0, Sin[th/2], 0, Cos[th/2]}];

icUserRoot[userSpec_] :=
  Module[{r, slots, cands, val, hit, head},
    val = If[AssociationQ[#], Lookup[#, "value", #], #] &;
    r = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeGetSlot["Root", "Depth" -> 2,
      "IncludeComponentData" -> False, "Timeout" -> 30], $Failed];
    If[!AssociationQ[r], Return[None]];
    slots = Cases[r, a_Association /; KeyExistsQ[a, "children"] && KeyExistsQ[a, "id"] :> a, {0, Infinity}];
    cands = Select[slots, StringStartsQ[ToString[val[Lookup[#, "name", ""]]], "User "] &];
    If[StringQ[userSpec],
      cands = Select[cands, StringContainsQ[ToString[val[#["name"]]], userSpec] &]];
    (* UserRoot コンポーネントを持つものだけ *)
    hit = SelectFirst[cands,
      Function[s, With[{d = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeGetSlot[s["id"], "Depth" -> 0,
          "IncludeComponentData" -> True], $Failed]},
        AssociationQ[d] && AnyTrue[Lookup[d["data"], "components", {}],
          StringEndsQ[Lookup[#, "componentType", ""], ".UserRoot"] &]]]];
    If[!AssociationQ[hit], Return[None]];
    (* 頭 (視点) は根の子 "Head"。デスクトップでは根の回転が視線と一致しない
       (2026-09-06 実機: 根はほぼ無回転で Head がヨー 90°) ので、頭の姿勢を使う *)
    head = Module[{d = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeGetSlot[hit["id"], "Depth" -> 1,
        "IncludeComponentData" -> False, "Timeout" -> 20], $Failed]},
      If[!AssociationQ[d], None,
        SelectFirst[Lookup[d["data"], "children", {}], ToString[val[Lookup[#, "name", ""]]] === "Head" &]]];
    <|"Id" -> hit["id"], "Name" -> val[hit["name"]],
      "Parent" -> Lookup[Lookup[hit, "parent", <||>], "targetId", "Root"],
      "Position" -> Lookup[val[hit["position"]], {"x", "y", "z"}],
      "Rotation" -> Lookup[val[hit["rotation"]], {"x", "y", "z", "w"}],
      "HeadPosition" -> If[AssociationQ[head], Lookup[val[head["position"]], {"x", "y", "z"}], None],
      "HeadRotation" -> If[AssociationQ[head], Lookup[val[head["rotation"]], {"x", "y", "z", "w"}], None]|>];

(* 根の親の座標系での <|"Parent","Position","Rotation"|> か None。
   height: 数値なら根 (足元) からの高さ、Automatic なら目の高さ - 0.25 m *)
icUserFrontPose[userSpec_, distance_, height_] :=
  Module[{u = icUserRoot[userSpec], q, f, eye, h},
    If[!AssociationQ[u], Return[None]];
    q = If[ListQ[u["HeadRotation"]], icQuatMul[u["Rotation"], u["HeadRotation"]], u["Rotation"]];
    f = icQuatForward[q];
    f = {f[[1]], 0, f[[3]]};
    f = If[Norm[f] < 10^-6, icQuatForward[u["Rotation"]] {1, 0, 1}, f/Norm[f]];
    eye = u["Position"] + If[ListQ[u["HeadPosition"]], icQuatRotate[u["Rotation"], u["HeadPosition"]], {0, 1.6, 0}];
    h = If[NumericQ[height], u["Position"][[2]] + height, eye[[2]] - 0.25];
    <|"Parent" -> u["Parent"],
      "Position" -> {eye[[1]], h, eye[[3]]} + distance*f,
      "Rotation" -> icYawQuat[f], "User" -> u["Name"]|>];

(* 構成 (すべて L2 の addSlot / addComponent):

   <Name>                       Grabbable, AI_GeneratedContent
   ├─ Panel                     Canvas (Size = CanvasSize [m], 触れる)
   │  └─ VLayout                VerticalLayout
   │     ├─ Title               Text
   │     ├─ Input               Image + Button + TextField + TextEditor  (入力欄)
   │     │  └─ Text             Text  ← 打った文字はここの Content に入る
   │     ├─ SendRow             HorizontalLayout
   │     │  ├─ Send             Checkbox  ← チェックで送信 (WL が読んで False に戻す)
   │     │  └─ SendLabel        Text
   │     ├─ Status              Text
   │     └─ Answer              Text  (答え)
   └─ (板)                      ResoniteRealtimeBoard (図の出力先。"Board" -> True のとき)

   送信を Checkbox にしているのは、Button + ButtonValueShift の結線に
   「フィールド (メンバ) の ID」が要り、ResoniteLink の応答でそれを確実に取れるか
   未検証だから。Checkbox は自分の State を読めばよく、参照結線が要らない。 *)
ResoniteRealtime`ResoniteChatGadget[opts : OptionsPattern[]] :=
  Catch[
    Module[{pos, parent, name, csz, pscale, fs, useBoard, ids, root, panel, vl, input, inText,
            row, board, chk, rot},
      If[!StringQ[$iState["Link"]],
        Return[iFailure["NotConnected",
          "パネルの組み立てには ResoniteLink が要ります。ResoniteRealtimeLinkConnect[port] を先に実行してください。"]]];
      pos      = OptionValue[ResoniteRealtime`ResoniteChatGadget, {opts}, "Position"];
      parent   = OptionValue[ResoniteRealtime`ResoniteChatGadget, {opts}, "Parent"];
      name     = OptionValue[ResoniteRealtime`ResoniteChatGadget, {opts}, "Name"];
      csz      = OptionValue[ResoniteRealtime`ResoniteChatGadget, {opts}, "CanvasSize"];
      pscale   = OptionValue[ResoniteRealtime`ResoniteChatGadget, {opts}, "PanelScale"];
      fs       = OptionValue[ResoniteRealtime`ResoniteChatGadget, {opts}, "FontSize"];
      useBoard = OptionValue[ResoniteRealtime`ResoniteChatGadget, {opts}, "Board"];
      ids = <||>;

      (* 置き場所: 既定はアバターの正面。見つからなければ "Position" / "Parent" に落ちる *)
      rot = None;
      If[OptionValue[ResoniteRealtime`ResoniteChatGadget, {opts}, "Placement"] === "User",
        With[{p = icUserFrontPose[
            OptionValue[ResoniteRealtime`ResoniteChatGadget, {opts}, "User"],
            OptionValue[ResoniteRealtime`ResoniteChatGadget, {opts}, "Distance"],
            OptionValue[ResoniteRealtime`ResoniteChatGadget, {opts}, "Height"]]},
          If[AssociationQ[p],
            parent = p["Parent"]; pos = p["Position"]; rot = p["Rotation"];
            ids["User"] = p["User"]]]];

      root = icSlot[name, parent, "Position" -> pos,
        Sequence @@ If[ListQ[rot], {"Rotation" -> rot}, {}],
        "Id" -> ResoniteRealtime`ResoniteRealtimeNewId["Chat"]];
      ids["Root"] = root;
      icComp[root, $icFE <> "Grabbable", <|"Scalable" -> True|>];
      icComp[root, $icFE <> "AI_GeneratedContent",
        <|"Source" -> "Mathematica ResoniteRealtime chat gadget (LLM answers)"|>];

      panel = icSlot["Panel", root, "Scale" -> {pscale, pscale, pscale}];
      ids["Panel"] = panel;
      icComp[panel, $icUIX <> "Canvas",
        <|"Size" -> N[csz], "AcceptRemoteTouch" -> True, "AcceptPhysicalTouch" -> True|>];
      icMakeMaterials[panel];
      ids = Join[ids, $icMats];
      (* パネル全体の背景 Image。UI マテリアルは Alpha のままにする:
         BlendMode を Opaque にすると同じ平面の文字と Z ファイトして真っ黒になる (2026-09-06 実機)。
         見た目は半透明の板になる (Tint の alpha を上げても不透明にはならない)。
         "Backdrop" -> True で UIX の外に不透明な Quad を置くが、実機では前後どちらに置いても
         パネルを覆ってしまったので既定 off (原因未解明)。 *)
      icImage[panel, RGBColor[0.07, 0.08, 0.11, 1]];
      If[TrueQ[OptionValue[ResoniteRealtime`ResoniteChatGadget, {opts}, "Backdrop"]],
        ids["Backdrop"] = icBackdrop[root, csz[[1]]*pscale, csz[[2]]*pscale]];

      vl = icSlot["VLayout", panel];
      icComp[vl, $icUIX <> "VerticalLayout",
        <|"PaddingTop" -> 24., "PaddingBottom" -> 24., "PaddingLeft" -> 24., "PaddingRight" -> 24.,
          "Spacing" -> 12., "ForceExpandWidth" -> True, "ForceExpandHeight" -> False|>];

      (* タイトル *)
      With[{s = icSlot["Title", vl]},
        icLayoutElement[s, fs*1.6, 0];
        ids["TitleText"] = icText[s, name, fs*1.2]];

      (* 入力欄: Image(背景) + Button(選択で編集開始) + TextEditor + TextField
         TextEditor.Text → 子 slot の Text、TextField.Editor → TextEditor *)
      input = icSlot["Input", vl];
      ids["Input"] = input;
      icLayoutElement[input, fs*4, 0];
      icImage[input, RGBColor[0.22, 0.24, 0.32, 1]];
      inText = icSlot["Text", input];
      ids["InputText"] = icText[inText, "", fs, ResoniteRealtime`ResoniteRealtimeNewId["InText"]];
      icComp[input, $icUIX <> "Button", <||>];
      ids["Editor"] = icComp[input, $icFE <> "TextEditor",
        <|"Text" -> ResoniteRealtime`ResoniteRealtimeRef[ids["InputText"]]|>,
        ResoniteRealtime`ResoniteRealtimeNewId["Editor"]];
      icComp[input, $icUIX <> "TextField",
        <|"Editor" -> ResoniteRealtime`ResoniteRealtimeRef[ids["Editor"]]|>];

      (* 送信行 *)
      row = icSlot["SendRow", vl];
      icLayoutElement[row, fs*1.8, 0];
      icComp[row, $icUIX <> "HorizontalLayout", <|"Spacing" -> 12., "ForceExpandWidth" -> False|>];
      (* 送信ボタン。UIX で押せるのは Button (InteractionElement) だけで、Checkbox は Button ではない
         (2026-09-06 実機: Checkbox 単体はクリックに反応しない)。
         Button + ButtonToggle → ValueField<bool>.Value の結線にする。ButtonToggle の TargetValue は
         **フィールド (メンバ) の ID** を指す。メンバ ID は getSlot の応答に入っている。 *)
      With[{s = icSlot["Send", row]},
        icComp[s, $icUIX <> "LayoutElement",
          <|"MinWidth" -> N[fs*1.6], "MinHeight" -> N[fs*1.6], "FlexibleWidth" -> 0.|>];
        icImage[s, RGBColor[0.3, 0.32, 0.4, 1]];
        icComp[s, $icUIX <> "Button", <||>];
        ids["SendBox"] = icComp[s, $icFE <> "ValueField<bool>", <|"Value" -> False|>,
          ResoniteRealtime`ResoniteRealtimeNewId["Send"]];
        With[{fieldId = icMemberId[s, ids["SendBox"], "Value"]},
          If[StringQ[fieldId],
            icComp[s, $icFE <> "ButtonToggle",
              <|"TargetValue" -> ResoniteRealtime`ResoniteRealtimeRef[fieldId]|>],
            Throw[iFailure["NoMemberId", "ValueField<bool>.Value のメンバ ID が取れませんでした。"], icTag]]];
        chk = icSlot["Check", s];
        icComp[chk, $icUIX <> "RectTransform", <|"AnchorMin" -> {0.25, 0.25}, "AnchorMax" -> {0.75, 0.75}|>];
        icImage[chk, RGBColor[0.9, 0.95, 1, 1]]];
      With[{s = icSlot["SendLabel", row]},
        icText[s, "\[LeftGuillemet] チェックで送信 / check to send", fs*0.8]];

      (* 状態・答え *)
      With[{s = icSlot["Status", vl]},
        icLayoutElement[s, fs*1.2, 0];
        ids["StatusText"] = icText[s, "ready", fs*0.7,
          ResoniteRealtime`ResoniteRealtimeNewId["Status"]]];
      With[{s = icSlot["Answer", vl]},
        icLayoutElement[s, fs*4, 1];
        ids["AnswerText"] = icText[s, "", fs*0.9,
          ResoniteRealtime`ResoniteRealtimeNewId["Answer"]]];

      (* 図の出力先の板 (パネルの右隣) *)
      If[TrueQ[useBoard],
        board = ResoniteRealtime`ResoniteRealtimeBoard["Parent" -> root,
          "Position" -> {csz[[1]]*pscale*0.5 + 0.5, 0, 0}, "Size" -> Min[csz[[2]]*pscale, 0.8],
          "Name" -> "Chat Board"];
        If[MatchQ[board, _Failure], Throw[board, icTag]];
        ids["Board"] = board];

      ids = Join[ids, <|"Name" -> name, "Created" -> DateObject[]|>];
      $icState = Join[$icState, <|"Gadget" -> ids|>];
      ids],
    icTag];

ResoniteRealtime`ResoniteChatAttach[ids_Association] /; KeyExistsQ[ids, "Root"] :=
  ($icState = Join[$icState, <|"Gadget" -> ids|>];
   If[AssociationQ[Lookup[ids, "Board", None]],
     $iState = Join[$iState, <|"Board" -> ids["Board"]|>]];
   ids);

ResoniteRealtime`ResoniteChatRemoveGadget[] :=
  Module[{g = $icState["Gadget"], r},
    ResoniteRealtime`ResoniteChatStop[];
    If[!AssociationQ[g], Return[None]];
    r = ResoniteRealtime`ResoniteRealtimeRemoveSlot[g["Root"]];
    (* 板は Chat slot の子なので一緒に消える。本体側の記録だけ落とす *)
    If[AssociationQ[Lookup[g, "Board", None]] &&
       AssociationQ[Lookup[$iState, "Board", None]] &&
       $iState["Board"]["Slot"] === g["Board"]["Slot"],
      $iState = Join[$iState, <|"Board" -> None|>]];
    $icState = Join[$icState, <|"Gadget" -> None|>];
    r];

(* ---- パネルへの書き込み ---- *)

icGadget[] := Lookup[$icState, "Gadget", None];

icSetText[key_String, text_String] :=
  Module[{g = icGadget[]},
    If[!AssociationQ[g] || !StringQ[$iState["Link"]], Return[None]];
    Quiet @ Check[
      ResoniteRealtime`ResoniteRealtimeUpdateComponent[g[key], <|"Content" -> text|>],
      $Failed]];

icSetStatus[text_String] := icSetText["StatusText", text];

(* 送信フラグ (ValueField<bool>.Value) を書く *)
icSetCheckbox[value : (True | False)] :=
  Module[{g = icGadget[]},
    If[!AssociationQ[g], Return[None]];
    Quiet @ Check[
      ResoniteRealtime`ResoniteRealtimeUpdateComponent[g["SendBox"], <|"Value" -> value|>],
      $Failed]];

(* 答え欄 + (図があれば) 板。板は Chat の板を優先し、無ければ本体の板/L1 に落ちる。 *)
(* 板に画像を出すには L3 (ResoniteRealtimeStart の HTTP 配信) か公開 URL が要る。
   無いと "http://127.0.0.1:None/..." を書いてしまい板が真っ黒になる (2026-09-06 実機)。 *)
icImageServerQ[] :=
  IntegerQ[Lookup[$iState, "Port", None]] ||
  (StringQ[ResoniteRealtime`$ResoniteRealtimePublicBaseURL] &&
    ResoniteRealtime`$ResoniteRealtimePublicBaseURL =!= "");

icShowInWorld[text_String, graphics_] :=
  Module[{g = icGadget[], t, r},
    t = icSetText["AnswerText", text];
    If[graphics =!= None && !icImageServerQ[],
      icSetStatus["(画像配信サーバが無いので板に出せません: ResoniteRealtimeStart[])"];
      Return[<|"Text" -> t,
        "Image" -> iFailure["NoServer",
          "板へ画像を出すには ResoniteRealtimeStart[] (画像配信) を先に実行してください。"]|>]];
    r = If[graphics =!= None,
      Block[{$iState = If[AssociationQ[g] && AssociationQ[Lookup[g, "Board", None]],
          Join[$iState, <|"Board" -> g["Board"]|>], $iState]},
        Quiet @ Check[UsingFrontEnd @
          ResoniteRealtime`ResoniteRealtimeShowImage[graphics, "Size" -> 800], $Failed]],
      None];
    <|"Text" -> t, "Image" -> r|>];

ResoniteRealtime`ResoniteChatShow[text_String] := icSetText["AnswerText", text];
ResoniteRealtime`ResoniteChatShow[expr_] := icShowInWorld["", expr]["Image"];

(* ============================================================
   ワールド側入力の監視 (ScheduledTask 1 本)
   ============================================================ *)

(* getSlot の応答から、ID で指定したコンポーネントのメンバ値を拾う。
   応答の木構造 (children / components のキー名) に依存しないよう、
   "id" と "componentType" を持つ Association を全部集めてから探す。 *)
icFindComponent[data_, id_String] :=
  Module[{hits},
    hits = Cases[data,
      a_Association /; Lookup[a, "id", None] === id && KeyExistsQ[a, "componentType"] :> a,
      {0, Infinity}];
    If[hits === {}, None, First[hits]]];

icMemberValue[comp_, member_String] :=
  Module[{m},
    If[!AssociationQ[comp], Return[None]];
    m = Lookup[Lookup[comp, "members", <||>], member, None];
    Which[
      AssociationQ[m] && KeyExistsQ[m, "value"], m["value"],
      True, m]];

(* ---- 監視 tick (ScheduledTask の中で動く) ----
   **ScheduledTask の中では ResoniteLink の応答を受ける非同期ハンドラが走れない**
   (2026-09-06 実機: 待つ getSlot は必ずタイムアウトし、5 秒 x 毎 tick でカーネルが塞がり FE が固まった)。
   なので tick では絶対に待たない:
     Idle      : getSlot を送るだけ ("Wait" -> False)。messageId を控えて AwaitSlot へ
     AwaitSlot : 直近の受信メッセージから sourceMessageId が一致する応答を探す。
                 見つかれば処理、10 秒来なければ失敗 1 回と数えて Idle へ
   書き込み (状態欄・フラグ戻し・答え) も Block[{$iLinkWaitDefault = False}] で送りっぱなし。
   LLM 呼び出し (ClaudeQueryBg = RunProcess) だけは同期で、その間 (数秒〜数十秒) はカーネルが塞がる。 *)
icPollReply[msgId_String] :=
  Module[{hits},
    hits = Select[ResoniteRealtime`ResoniteRealtimeLinkMessages[Max[60, $iLinkLimit]],
      AssociationQ[#["Message"]] &&
        Lookup[#["Message"], "sourceMessageId", None] === msgId &];
    If[hits === {}, None, Last[hits]["Message"]]];

icPoll[] :=
  Module[{g = icGadget[], pending, sent, res},
    If[!AssociationQ[g] || !StringQ[$iState["Link"]] || TrueQ[$icState["Busy"]],
      Return[Null]];
    pending = Lookup[$icState, "Pending", None];
    If[!AssociationQ[pending],
      (* Idle: 送るだけ *)
      sent = Quiet @ Check[
        ResoniteRealtime`ResoniteRealtimeGetSlot[g["Root"], "Depth" -> -1,
          "IncludeComponentData" -> True, "Wait" -> False], $Failed];
      If[AssociationQ[sent] && StringQ[Lookup[sent, "MessageId", None]],
        $icState = Join[$icState, <|"Pending" -> <|"MessageId" -> sent["MessageId"], "Time" -> iNow[]|>|>],
        $icState = Join[$icState, <|"PollFailures" -> Lookup[$icState, "PollFailures", 0] + 1,
          "LastError" -> sent|>]];
      Return[Null]];
    (* AwaitSlot *)
    res = icPollReply[pending["MessageId"]];
    Which[
      AssociationQ[res],
        $icState = Join[$icState, <|"Pending" -> None, "PollFailures" -> 0|>];
        If[Lookup[res, "success", True] === False,
          $icState = Join[$icState, <|"LastError" -> res|>]; Return[Null]];
        icPollHandle[g, res],
      iNow[] - pending["Time"] > 10,
        $icState = Join[$icState, <|"Pending" -> None,
          "PollFailures" -> Lookup[$icState, "PollFailures", 0] + 1,
          "LastError" -> iFailure["Timeout", "getSlot の応答が 10 秒来ませんでした。"]|>];
        Null,
      True, Null]];

(* 応答 (slotData) を読み、送信フラグが立っていれば処理する。ここからの書き込みは待たない *)
icPollHandle[g_Association, res_Association] :=
  Module[{state, txt, ev, r},
    state = icMemberValue[icFindComponent[res, g["SendBox"]], "Value"];
    If[state =!= True, Return[Null]];
    txt = icMemberValue[icFindComponent[res, g["InputText"]], "Content"];
    Block[{$iLinkWaitDefault = False},
      icSetCheckbox[False];
      If[!StringQ[txt] || StringTrim[txt] === "",
        icSetStatus["(入力が空です)"]; Return[Null, Module]];
      ev = TrueQ[Lookup[$icState, "PollEvaluate", False]];
      $icState = Join[$icState, <|"Busy" -> True|>];
      (* "flux:" / "pf:" で始まる入力は ProtoFlux ガジェット (ResoniteRealtime_flux.wl) へ *)
      r = Quiet @ Check[
        If[Length[Names["ResoniteRealtime`Private`ifRoutePrefixQ"]] > 0 && ifRoutePrefixQ[txt],
          ResoniteRealtime`ResoniteFluxChat[ifStripPrefix[txt], "Origin" -> "World", "Notebook" -> False],
          ResoniteRealtime`ResoniteChat[txt, "Origin" -> "World", "Notebook" -> False,
            "Evaluate" -> ev]], $Failed];
      $icState = Join[$icState, <|"Busy" -> False|>];
      If[MatchQ[r, _Failure], icSetText["AnswerText", "エラー: " <> ToString[r[[1]]]]];
      r]];

Options[ResoniteRealtime`ResoniteChatStart] = {"PollInterval" -> 1.5, "Evaluate" -> False};

ResoniteRealtime`ResoniteChatStart[opts : OptionsPattern[]] :=
  Module[{dt, task},
    If[!AssociationQ[icGadget[]],
      Return[iFailure["NoGadget", "先に ResoniteChatGadget[] でパネルを作ってください。"]]];
    ResoniteRealtime`ResoniteChatStop[];
    dt = OptionValue[ResoniteRealtime`ResoniteChatStart, {opts}, "PollInterval"];
    $icState = Join[$icState,
      <|"PollEvaluate" -> TrueQ[OptionValue[ResoniteRealtime`ResoniteChatStart, {opts}, "Evaluate"]]|>];
    task = SessionSubmit[ScheduledTask[ResoniteRealtime`Private`icPoll[], dt]];
    $icState = Join[$icState, <|"Task" -> task, "PollInterval" -> dt|>];
    (* L1 経由 ("ask<TAB>質問") も同じ処理へ *)
    ResoniteRealtime`ResoniteRealtimeOn["ask", ResoniteRealtime`Private`icBridgeAsk];
    icSetStatus["listening (" <> ToString[dt] <> " s)"];
    task];

ResoniteRealtime`ResoniteChatStop[] :=
  Module[{t = Lookup[$icState, "Task", None]},
    If[MatchQ[t, _TaskObject], Quiet[TaskRemove[t]]];
    $icState = Join[$icState, <|"Task" -> None, "Busy" -> False, "Pending" -> None|>];
    Quiet[ResoniteRealtime`ResoniteRealtimeOn["ask", None]];
    None];

(* SocketListen のコールバック内: 重い処理はここでせず、次の tick に回す *)
icBridgeAsk[rec_Association] :=
  Module[{q = StringRiffle[Lookup[rec, "Args", {}], "\t"]},
    If[StringTrim[q] === "", Return[Null]];
    SessionSubmit[ScheduledTask[
      Block[{ResoniteRealtime`Private`$iLinkWaitDefault = False},
        ResoniteRealtime`ResoniteChat[q, "Origin" -> "Bridge", "Notebook" -> False]], {0.1}]];
    Null];

(* ============================================================
   ノートブック側: ResoniteInput セル
   ============================================================ *)

(* ClaudeInput (SourceVault default.nb) と同じ評価関数の形。プレーンテキストを取り出して
   ResoniteChat に渡す。スタイルはノートブックの StyleDefinitions に埋め込む
   (テンプレートのスタイルシートは触らない)。 *)
$icCellStyle =
  Cell[StyleData["ResoniteInput", StyleDefinitions -> StyleData["Text"]],
    CellFrame -> {{3, 1}, {1, 1}},
    CellFrameColor -> RGBColor[0.2, 0.6, 0.55],
    CellDingbat -> Cell[BoxData[StyleBox["\[FilledDiamond]",
      FontColor -> RGBColor[0.2, 0.6, 0.55], FontSize -> 16, FontWeight -> "Bold"]],
      Background -> None],
    CellMargins -> {{66, 50}, {5, 8}},
    Background -> RGBColor[0.94, 0.985, 0.97],
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
          If[Length[Names["ResoniteRealtime`ResoniteChat"]] > 0,
            Symbol["ResoniteRealtime`ResoniteChat"][tasktext],
            Print[Style["ResoniteRealtime がロードされていません。", Red]]],
          Null]]]];

(* セルスタイルをノートブックの StyleDefinitions に埋め込む (テンプレートのスタイルシートは触らない)。
   既に埋め込みスタイルシートならその中に足し、名前参照なら継承して包む。 *)
icEnsureCellStyleNamed[nb_NotebookObject, styleName_String, style_Cell] :=
  Module[{sd, base},
    sd = Quiet @ CurrentValue[nb, StyleDefinitions];
    If[StringContainsQ[ToString[sd, InputForm], "\"" <> styleName <> "\""], Return[nb]];
    base = Which[
      StringQ[sd], Cell[StyleData[StyleDefinitions -> sd]],
      MatchQ[sd, _FrontEnd`FileName], Cell[StyleData[StyleDefinitions -> sd]],
      True, Cell[StyleData[StyleDefinitions -> "Default.nb"]]];
    If[MatchQ[sd, Notebook[_List, ___]],
      SetOptions[nb, StyleDefinitions -> Notebook[Append[First[sd], style], Rest[sd]]],
      SetOptions[nb, StyleDefinitions -> Notebook[{base, style}, Visible -> False,
        StyleDefinitions -> "PrivateStylesheetFormatting.nb"]]];
    nb];

icEnsureCellStyle[nb_NotebookObject] := icEnsureCellStyleNamed[nb, "ResoniteInput", $icCellStyle];

ResoniteRealtime`ResoniteChatCell[] :=
  Module[{nb = InputNotebook[]},
    If[Head[nb] =!= NotebookObject, Return[$Failed]];
    icEnsureCellStyle[nb];
    NotebookWrite[nb, Cell["", "ResoniteInput"], All];
    SelectionMove[nb, All, CellContents];
    nb];

(* ============================================================
   状態
   ============================================================ *)

ResoniteRealtime`ResoniteChatLog[n_Integer : 20] :=
  Take[$icLog, -Min[n, Length[$icLog]]];

ResoniteRealtime`ResoniteChatStatus[] :=
  <|"WorldAccess" -> icAccessName[], "AccessLevel" -> ResoniteRealtime`ResoniteAccessLevel[],
    "ReleaseContext" -> icReleaseContext[],
    "Gadget" -> If[AssociationQ[icGadget[]], icGadget[]["Root"], None],
    "Listening" -> MatchQ[Lookup[$icState, "Task", None], _TaskObject],
    "PollInterval" -> Lookup[$icState, "PollInterval", None],
    "Busy" -> TrueQ[$icState["Busy"]],
    "PollFailures" -> Lookup[$icState, "PollFailures", 0],
    "LinkConnected" -> StringQ[$iState["Link"]],
    "ClaudeCode" -> icClaudeQ[], "SourceVault" -> icSVQ[],
    "Conversations" -> Length[$icLog], "LastError" -> Lookup[$icState, "LastError", None]|>;

(* claudecode の docs 注入: プロンプトにこれらの語があれば ResoniteRealtime_info/docs/api.md を付ける *)
If[MemberQ[$Packages, "ClaudeCode`"] && Length[Names["ClaudeCode`$ClaudePackageKeywordMap"]] > 0,
  (* Symbol[...][key] = v は効かず (Set が LHS を評価しない)、With[{m = Symbol[...]}] は
     記号でなく値 (Association) が差し込まれる。文字列で組んで ToExpression するのが確実。 *)
  Quiet @ Check[
    ToExpression[
      "If[!AssociationQ[ClaudeCode`$ClaudePackageKeywordMap], ClaudeCode`$ClaudePackageKeywordMap = <||>]; " <>
      "ClaudeCode`$ClaudePackageKeywordMap[\"ResoniteRealtime\"] = " <>
      "{\"Resonite\", \"ResoniteLink\", \"ProtoFlux\", \"ProtoGraph\", \"ResoniteChat\", \"ResoniteFlux\", \"ワールド\"};"],
    Null]];

End[];

EndPackage[];
