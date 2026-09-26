(* ::Package:: *)

(* ResoniteRealtime_docboard.wl -- 雛形なしの PDF ビューア + インベントリに保存できるサムネイル一覧

   This file is encoded in UTF-8.
   ResoniteRealtime.wl が自動でロードする (ResoniteRealtime_tablet.wl の後。同じ ResoniteRealtime`Private` コンテキストで
   タブレットの部品 (itXxx / icXxx) を使う)。

   ---- 1. 文書ビューア (Mathematica PDF Viewer、2026-09-25) ----
   標準 PDF ビューアの複製は「ワールドに雛形がある」ことが前提で、ワールドを開き直すと雛形も保管も無くなり、Wolfram で
   ページを画像にする自前パネルに落ちていた (ユーザー報告「また PDF Viewer が元に戻っている」)。Resonite の部品だけで
   文書を描けるので、雛形が無いときはこれを組む:
     Mathematica PDF Viewer   Grabbable, AI_GeneratedContent
     ├─ Document              StaticDocument (URL = 配信 URL) -> DocumentPageTexture (PageIndex, 0 始まり) -> SpriteProvider,
     │                        ValueField<int> Page (1 始まり、表示用)
     ├─ Backing               不透明の裏板
     └─ Panel                 Canvas: 題名 / ページ (UIX Image、PreserveAspect) / [<<] [<] n / N [>] [>>] [閉じる]
   ページ送りはワールドの中だけで動く (ButtonValueShift<int> / ButtonValueSet<int> が PageIndex と Page を同時に動かす。
   端で止まる)。n / N は ValueTextFormatDriver<int>。閉じるは ButtonDestroy。Wolfram はページを画像にしないので速い。
   描くのは Resonite (標準ビューアと同じ部品)。

   ---- 2. サムネイル一覧をインベントリに保存して使い回す (2026-09-25 ユーザー指示) ----
   「構成したサムネイルアレイをこのままインベントリに保存して再利用できるように。タブレット同様に「接続」ボタンを付け、
   ResoniteRealtime がロードされていればタブレットが無くても PDF を開けるように (雛形も内蔵)。接続時にワールドが
   プライベートか、オーナーが誰かをまず調べ、適切な PL に達していなければ開けないように」。
     - 帯の画像は importTexture2DFile で Resonite の資産 (local://) に取り込み、StaticTexture2D の URL を差し替える
       (保存するとクラウドに上がる。http の配信 URL のままだと Wolfram が居ないと出ない)。
     - 行 (題名 / ファイル / URI / 機密度) と配置を JSON にして子 "Data" の ValueField<string> に入れる。
       **署名つき** (HMAC-SHA256、鍵はこの PC の $ResoniteBoardKeyFile)。ワールドの誰かがファイルのパスや機密度を
       書き換えると署名が合わず、接続を断る (Wolfram がローカルのファイルを開いてワールドに出すので必須)。
     - 子 "Flux": OnLoaded / OnDuplicate -> SetSlotActiveSelf(Content, False) -> SetSlotActiveSelf(Veil, True)。
       インベントリから出した / 複製した一覧は、Wolfram が確かめるまで升目 (画像と題名) を隠し、「接続を押すと表示」だけ見せる。
     - 「接続」(Selected = -3) -> 常駐監視が見つけて引き継ぐ: 根を Depth 1 → Panel を Depth 1 で読み、署名を確かめ、
       ワールド情報 (公開度・ホスト・所有者) を読み直してから、表示上限未満の行だけ見せる (上限以上の升目は覆いで隠し、
       開こうとしても断る)。公開度が後で変わっても覆いを付け直す。
     - 標準ビューアの雛形が分かっていれば、複製を一覧の子に非表示で保管する (タブレットと同じ。保存すると一緒に入る)。
     - 一覧から開いた PDF は一覧の升目の前に出す。
*)

BeginPackage["ResoniteRealtime`"];

ResoniteRealtime`ResoniteDocViewer::usage =
  "ResoniteDocViewer[file] は PDF を Resonite 自身の文書表示 (StaticDocument + DocumentPageTexture) で開く。\n" <>
  "標準ビューアの雛形が要らず、ページ送り (<< < > >>) と閉じるはワールドの中だけで動く。\n" <>
  "オプション: \"Title\" -> Automatic, \"Position\" -> Automatic (タブレットの右前), \"Parent\" -> \"Root\"。\n" <>
  "標準ビューアの雛形が無いとき、ResoniteShowObject / 一覧の PDF は自動でこれを使う ($ResonitePDFMode = \"Native\")。";
ResoniteRealtime`ResoniteDocViewerRemove::usage =
  "ResoniteDocViewerRemove[root] は文書ビューアを消す。ResoniteDocViewerRemove[] は全部消す。";
ResoniteRealtime`ResoniteBoardAdopt::usage =
  "ResoniteBoardAdopt[root] はワールドにあるサムネイル一覧 (インベントリから出した物) を引き継ぐ (「接続」ボタンと同じ。監視 tick が要る)。" <> "\n" <>
  "署名を確かめ、ワールドの公開範囲とオーナーを読み直してから、表示上限未満の升目だけ見せる。";
ResoniteRealtime`ResoniteBoardDiagnose::usage =
  "ResoniteBoardDiagnose[root] はサムネイル一覧 root の「接続」が効かないときの診断 (ノートブックから。getSlot を待つ)。\n" <>
  "ResoniteBoardDiagnose[] は Root 直下と入れ物の中のサムネイル一覧を探して全部診断する。読めなかったときは \"Reply\" に応答そのもの。\n" <>
  "ワールドでの名前・親・State の ValueField<int> の値 (接続を押すと -3)、監視の候補 / 引き継ぎ中 / 接続済みか、直近の記録 (BoardLog) を返す。";
ResoniteRealtime`$ResonitePDFLite::usage =
  "$ResonitePDFLite (既定 True): 標準ビューアの雛形が無い / 複製に失敗したとき、Resonite の文書表示 (ResoniteDocViewer) で開く。" <> "\n" <>
  "False なら従来どおり Wolfram でページを画像にする自前パネルに落ちる。";
ResoniteRealtime`ResoniteTabletWorkerStatus::usage =
  "ResoniteTabletWorkerStatus[] は作業用カーネル (重い仕事を監視の tick から外すための常駐サブカーネル) の状態:" <> "\n" <>
  "<|\"Phase\", \"Alive\", \"Queue\", \"Job\", \"SlowTicks\" (1 秒を超えた tick の段)|>。FE が止まったときの手掛かり。";
ResoniteRealtime`ResoniteTabletWorkerStop::usage =
  "ResoniteTabletWorkerStop[] は作業用カーネルを止める (次に仕事が来たら立ち上げ直す)。";
ResoniteRealtime`$ResoniteTabletWorker::usage =
  "$ResoniteTabletWorker (既定 True): サムネイルの帯・Eagle フォルダの一覧・大きな PDF のページ数を作業用カーネルで作る。" <> "\n" <>
  "監視の tick の中で長く塞ぐと FE の Dynamic が待たされ「動的評価の放棄」ダイアログが出るため。False なら従来どおりこのカーネルで。";
ResoniteRealtime`$ResoniteBoardKeyFile::usage =
  "$ResoniteBoardKeyFile はサムネイル一覧の行データに付ける署名の鍵ファイル (32 バイト、無ければ作る)。\n" <>
  "既定は $UserBaseDirectory/ApplicationData/ResoniteRealtime/board.key (この PC だけ。別の PC で作った一覧は接続を断る)。";

Begin["`Private`"];

(* ============================================================
   署名 (HMAC-SHA256)
   ============================================================ *)
If[!StringQ[ResoniteRealtime`$ResoniteBoardKeyFile],
  ResoniteRealtime`$ResoniteBoardKeyFile =
    FileNameJoin[{$UserBaseDirectory, "ApplicationData", "ResoniteRealtime", "board.key"}]];
If[!ValueQ[$idKeyCache], $idKeyCache = None];

idKey[] :=
  Module[{f = ResoniteRealtime`$ResoniteBoardKeyFile, k, st},
    If[ByteArrayQ[$idKeyCache] && Lookup[$idKeyCacheFor, "File", None] === f, Return[$idKeyCache]];
    k = If[FileExistsQ[f], Quiet @ Check[ReadByteArray[f], $Failed], $Failed];
    If[!ByteArrayQ[k] || Length[k] < 32,
      k = Quiet @ Check[GenerateSymmetricKey[]["Key"], $Failed];
      If[!ByteArrayQ[k], k = ByteArray[RandomInteger[{0, 255}, 32]]];
      Quiet[CreateDirectory[DirectoryName[f], CreateIntermediateDirectories -> True]];
      st = Quiet @ Check[OpenWrite[f, BinaryFormat -> True], $Failed];
      If[!FailureQ[st] && st =!= $Failed, BinaryWrite[st, Normal[k]]; Close[st]]];
    $idKeyCacheFor = <|"File" -> f|>;
    $idKeyCache = k];
If[!AssociationQ[$idKeyCacheFor], $idKeyCacheFor = <||>];

idSHA[b_List] := Normal[Hash[ByteArray[b], "SHA256", "ByteArray"]];
idHMAC[key_ByteArray, msg_ByteArray] :=
  Module[{k = Normal[key]},
    If[Length[k] > 64, k = idSHA[k]];
    k = Join[k, ConstantArray[0, 64 - Length[k]]];
    StringJoin[IntegerString[#, 16, 2] & /@
      idSHA[Join[BitXor[k, 92], idSHA[Join[BitXor[k, 54], Normal[msg]]]]]]];

(* 署名つきの文字列: 1 行目 = 署名 (16 進 64 文字)、2 行目以降 = JSON *)
idEncode[body_Association] :=
  Module[{json = ByteArrayToString[ExportByteArray[body, "RawJSON", "Compact" -> True], "UTF-8"]},
    idHMAC[idKey[], StringToByteArray[json, "UTF-8"]] <> "\n" <> json];
idDecode[s_String] :=
  Module[{parts = StringSplit[s, "\n", 2], body},
    If[Length[parts] =!= 2, Return[iFailure["BadData", "行データの形が違います。"]]];
    If[idHMAC[idKey[], StringToByteArray[parts[[2]], "UTF-8"]] =!= parts[[1]],
      Return[iFailure["BadSignature", "行データの署名が合いません (書き換えられた / 別の PC で作った一覧)。"]]];
    body = Quiet @ Check[ImportByteArray[StringToByteArray[parts[[2]], "UTF-8"], "RawJSON"], $Failed];
    If[!AssociationQ[body] || Lookup[body, "v", 0] =!= 1 || !ListQ[Lookup[body, "rows", None]],
      Return[iFailure["BadData", "行データを読めません。"]]];
    body];
idDecode[_] := iFailure["BadData", "行データがありません。"];

(* 行は必要なキーだけ、値は文字列 / 数 / 真偽だけ。機密度は必ず数で入れる (fail-closed の itRowPL の結果) *)
$idRowKeys = {"Kind", "Title", "URI", "File", "Id", "Ext", "Date", "URL", "PDF", "Library", "Name"};
idRowPack[row_Association] :=
  Join[Select[KeyTake[row, $idRowKeys], StringQ[#] || NumericQ[#] || BooleanQ[#] &],
    <|"PrivacyLevel" -> N[itRowPL[row]]|>];
$idLayoutKeys = {"N", "TW", "TH", "LH", "G", "M", "HH", "CW", "CH", "Cols", "Rows", "W", "H", "SW"};
idBoardBody[rows_List, title_, L_Association, ps_] :=
  <|"v" -> 1, "title" -> ToString[title], "rows" -> Map[idRowPack, rows], "layout" -> KeyTake[L, $idLayoutKeys],
    "scale" -> N[ps], "builtLevel" -> N[itAccessLevel[]], "built" -> DateString["ISODateTime"]|>;

(* 引き継いだ行の機密度: 署名つきの値と、SourceVault が読めれば今の値の大きい方 (fail-closed) *)
idRowRecheck[row_Association] :=
  Module[{pl = itPL[Lookup[row, "PrivacyLevel", 1.0]], uri = Lookup[row, "URI", None], now},
    If[StringQ[uri] && StringStartsQ[uri, "sv://"] && icSym["SourceVault`SourceVaultObjectPrivacyLevel"] =!= None,
      now = itObjectPL[uri]; pl = Max[pl, now]];
    Append[row, "PrivacyLevel" -> pl]];

(* ============================================================
   参照つき部品: tick の組み立てなら巡に回し、トップレベルならメンバ ID を待って今足す
   refs: member -> {slotOfComp, compId, memberName}
   ============================================================ *)
$idRound = None;
idAddWired[slot_String, type_String, members_Association, refs_Association, id_ : Automatic] :=
  If[ListQ[$itWireLater],
    (If[!ListQ[$idRound], $idRound = {}];
     AppendTo[$idRound, Join[<|"Action" -> "Add", "Slot" -> slot, "Type" -> type, "Members" -> members,
       "Refs" -> Map[{#[[2]], #[[3]]} &, refs]|>, If[StringQ[id], <|"Id" -> id|>, <||>]]]),
    icComp[slot, type,
      Join[members, Map[With[{mid = icMemberId[#[[1]], #[[2]], #[[3]]]},
          If[!StringQ[mid], Throw[iFailure["NoMemberId", #[[2]] <> "." <> #[[3]] <> " のメンバ ID が取れませんでした。"], icTag]];
          ResoniteRealtime`ResoniteRealtimeRef[mid]] &, refs]], id]];

(* ============================================================
   1. 文書ビューア
   ============================================================ *)
If[!ValueQ[ResoniteRealtime`$ResonitePDFLite], ResoniteRealtime`$ResonitePDFLite = True];
idDocViewers[] := Replace[Lookup[$itState, "DocViewers", <||>], Except[_Association] -> <||>];

$idDocCanvas = {1000, 1440}; $idDocScale = 0.0006;
(* meta: <|"Local" -> 127.0.0.1 の URL, "CacheKey" -> 写しの鍵|> (ResoniteRealtime_pdfcache.wl が URL を差し替えるのに使う) *)
idDocViewerBuild[url_String, title_String, n_Integer, pose_Association] := idDocViewerBuild[url, title, n, pose, <||>];
idDocViewerBuild[url_String, title_String, n_Integer, pose_Association, meta_Association] :=
  Catch[
    Block[{$idRound = None},
    Module[{W, H, ps = $idDocScale, hh = 110, bar = 120, fs = 30., root, doc, sdoc, dpt, sp, page, panel, s, lbl, lblTxt,
            by, bh, geo, btn, maxI, maxP, ref = ResoniteRealtime`ResoniteRealtimeRef, dim},
      {W, H} = $idDocCanvas; dim = <|"W" -> W, "H" -> H|>;
      If[!itLinkQ[], Return[iFailure["NotConnected", "ResoniteLink が未接続です。"]]];
      root = icSlot["Mathematica PDF Viewer", pose["Parent"], "Position" -> N[pose["Position"]],
        Sequence @@ If[ListQ[pose["Rotation"]], {"Rotation" -> pose["Rotation"]}, {}],
        "Id" -> ResoniteRealtime`ResoniteRealtimeNewId["DocV"]];
      $itBuildRoot = root;
      icComp[root, $icFE <> "Grabbable", <|"Scalable" -> True|>];
      icComp[root, $icFE <> "AI_GeneratedContent",
        <|"Source" -> "Mathematica ResoniteRealtime document viewer (StaticDocument + DocumentPageTexture)"|>];
      doc = icSlot["Document", root];
      sdoc = icComp[doc, $icFE <> "StaticDocument", <|"URL" -> ResoniteRealtime`ResoniteRealtimeValue["Uri", url]|>,
        ResoniteRealtime`ResoniteRealtimeNewId["SDoc"]];
      dpt = icComp[doc, $icFE <> "DocumentPageTexture", <|"Document" -> ref[sdoc], "PageIndex" -> 0, "Size" -> 2048|>,
        ResoniteRealtime`ResoniteRealtimeNewId["DocTex"]];
      sp = icComp[doc, $icFE <> "SpriteProvider", <|"Texture" -> ref[dpt]|>, ResoniteRealtime`ResoniteRealtimeNewId["DocSprite"]];
      page = icComp[doc, $icFE <> "ValueField<int>", <|"Value" -> 1|>, ResoniteRealtime`ResoniteRealtimeNewId["DocPage"]];
      (* 読み込めたかの確かめ用 (PageCount は Resonite が文書を読むと埋まる) *)
      icComp[doc, $icFE <> "DocumentAssetMetadata", <|"Document" -> ref[sdoc]|>, ResoniteRealtime`ResoniteRealtimeNewId["DocMeta"]];
      itBacking[root, N[{W, H}*ps]];
      panel = icSlot["Panel", root, "Scale" -> {ps, ps, ps}];
      icComp[panel, $icUIX <> "Canvas", <|"Size" -> N[{W, H}], "AcceptRemoteTouch" -> True, "AcceptPhysicalTouch" -> True|>];
      icMakeMaterials[panel];
      icImage[panel, $itThumbColors["Page"]];
      s = icSlot["Title", panel];
      icComp[s, $icUIX <> "RectTransform", itAnchors[{24, 12, W - 48, hh - 24}, {W, H}]];
      itText[s, itTruncate[title, 80], fs, "Left", "Middle"];
      s = icSlot["Page", panel];
      icComp[s, $icUIX <> "RectTransform", itAnchors[{24, hh, W - 48, H - hh - bar - 8}, {W, H}]];
      icComp[s, $icUIX <> "Image",
        Join[<|"Sprite" -> ref[sp], "PreserveAspect" -> True, "Tint" -> RGBColor[1, 1, 1, 1]|>,
          If[StringQ[Lookup[$icMats, "Image", None]], <|"Material" -> ref[$icMats["Image"]]|>, <||>]]];
      by = H - bar + 12; bh = bar - 24;
      maxI = If[n > 0, n - 1, 9999]; maxP = If[n > 0, n, 10000];
      (* ページそのものを押すと次のページ (2026-09-25 ユーザー指示: デスクトップでは視線を下の [>] まで動かさないと
         めくれず読みにくい)。[>] と同じ ButtonValueShift を 2 つ (PageIndex と表示用の番号)。最後のページで止まる *)
      (* Button はページの Image に直接付けない: Button.OnAttach が同じスロットの Image.Tint に色ドライバを付け、カーソルを
         置くとページが暗くなる (2026-09-25 実機)。ページの上に透明な押し面 (Tint の α = 0 の Image) を重ねてそこに付ける
         (ハイライト色は HSV で α を引き継ぐので透明のまま。FrooxEngine.dll で確認) *)
      With[{hit = itClickOverlay[s]},
        idAddWired[hit, $icFE <> "ButtonValueShift<int>",
          <|"Delta" -> 1, "Min" -> 0, "Max" -> maxI, "WrapAround" -> False, "MaxIsExclusive" -> False|>,
          <|"TargetValue" -> {doc, dpt, "PageIndex"}|>];
        idAddWired[hit, $icFE <> "ButtonValueShift<int>",
          <|"Delta" -> 1, "Min" -> 1, "Max" -> maxP, "WrapAround" -> False, "MaxIsExclusive" -> False|>,
          <|"TargetValue" -> {doc, page, "Value"}|>]];
      (* 操作列 *)
      geo = <|"First" -> {24, "<<"}, "Prev" -> {156, "<"}, "Next" -> {520, ">"}, "Last" -> {652, ">>"}|>;
      KeyValueMap[Function[{key, xl},
          btn = itThumbButton[panel, key, xl[[2]], {xl[[1]], by, 120, bh}, dim, RGBColor[0.25, 0.3, 0.4, 1], fs];
          Switch[key,
            "First" | "Last",
              idAddWired[btn, $icFE <> "ButtonValueSet<int>", <|"SetValue" -> If[key === "First", 0, maxI]|>,
                <|"TargetValue" -> {doc, dpt, "PageIndex"}|>];
              idAddWired[btn, $icFE <> "ButtonValueSet<int>", <|"SetValue" -> If[key === "First", 1, maxP]|>,
                <|"TargetValue" -> {doc, page, "Value"}|>],
            _,
              With[{d = If[key === "Prev", -1, 1]},
                idAddWired[btn, $icFE <> "ButtonValueShift<int>",
                  <|"Delta" -> d, "Min" -> 0, "Max" -> maxI, "WrapAround" -> False, "MaxIsExclusive" -> False|>,
                  <|"TargetValue" -> {doc, dpt, "PageIndex"}|>];
                idAddWired[btn, $icFE <> "ButtonValueShift<int>",
                  <|"Delta" -> d, "Min" -> 1, "Max" -> maxP, "WrapAround" -> False, "MaxIsExclusive" -> False|>,
                  <|"TargetValue" -> {doc, page, "Value"}|>]]]],
        geo];
      lbl = icSlot["PageLabel", panel];
      icComp[lbl, $icUIX <> "RectTransform", itAnchors[{288, by, 220, bh}, {W, H}]];
      lblTxt = itText[lbl, If[n > 0, "1 / " <> ToString[n], "1"], fs, "Center", "Middle",
        ResoniteRealtime`ResoniteRealtimeNewId["DocPgTxt"]];
      idAddWired[lbl, $icFE <> "ValueTextFormatDriver<int>",
        <|"Format" -> If[n > 0, "{0} / " <> ToString[n], "{0}"]|>,
        <|"Source" -> {doc, page, "Value"}, "Text" -> {lbl, lblTxt, "Content"}|>];
      btn = itThumbButton[panel, "Close", "閉じる", {W - 24 - 150, by, 150, bh}, dim, RGBColor[0.5, 0.25, 0.25, 1], fs];
      icComp[btn, $icFE <> "ButtonDestroy", <|"Target" -> ref[root]|>];
      If[ListQ[$itWireLater], $itWireRounds = {$idRound}];
      $itState["DocViewers"] = Append[idDocViewers[], root ->
        <|"Title" -> title, "URL" -> url, "Pages" -> n, "Parent" -> pose["Parent"], "Created" -> iNow[],
          "Doc" -> sdoc, "Local" -> Lookup[meta, "Local", url], "CacheKey" -> Lookup[meta, "CacheKey", None]|>];
      itSetStatus["PDF: " <> itTruncate[title, 40] <> " (" <> ToString[n] <> " ページ、Resonite の文書表示)"];
      <|"Root" -> root, "Kind" -> "DocViewer", "Pages" -> n, "Title" -> title|>]],
    icTag];

Options[ResoniteRealtime`ResoniteDocViewer] = {"Title" -> Automatic, "Position" -> Automatic, "Parent" -> "Root"};
ResoniteRealtime`ResoniteDocViewer[file_String, opts : OptionsPattern[]] :=
  Module[{o = Association @ Join[Options[ResoniteRealtime`ResoniteDocViewer], {opts}], url, n, title, pose},
    If[!FileExistsQ[file], Return[iFailure["NoFile", file <> " がありません。"]]];
    If[!itEnsureImageServer[], Return[iFailure["NoServer", "画像配信 (ResoniteRealtimeStart[]) が要ります。"]]];
    url = ResoniteRealtime`ResoniteRealtimeAsset[file];
    If[FailureQ[url], Return[url]];
    n = idPageCount[file];
    title = Replace[o["Title"], Automatic -> FileNameTake[file]];
    If[o["Position"] === Automatic && itTickActiveQ[],
      (* tick があれば開くジョブに載せる (タブレット / 一覧の隣に置く姿勢を読んでから組む) *)
      Return[idLiteSpawn[file, url, n, title]]];
    pose = <|"Parent" -> o["Parent"], "Position" -> Replace[o["Position"], Automatic -> {0., 1.3, 1.0}], "Rotation" -> None|>;
    With[{c = itOpenDocURL[file, url, title], local = url},
      If[itAsyncContextQ[],
        itDeferBuild[idDocViewerBuild[c["URL"], title, n, pose, <|"Local" -> local, "CacheKey" -> c["CacheKey"]|>],
          "PDF ビューア", <|"Kind" -> "DocViewer", "Pages" -> n|>],
        idDocViewerBuild[c["URL"], title, n, pose, <|"Local" -> local, "CacheKey" -> c["CacheKey"]|>]]]];

ResoniteRealtime`ResoniteDocViewerRemove[root_String] :=
  (itNoWait @ Quiet @ Check[ResoniteRealtime`ResoniteRealtimeRemoveSlot[root], Null];
   $itState["DocViewers"] = KeyDrop[idDocViewers[], root]; root);
ResoniteRealtime`ResoniteDocViewerRemove[] := Map[ResoniteRealtime`ResoniteDocViewerRemove, Keys[idDocViewers[]]];

(* 開くジョブ (DocJobs) に直接載せる: 姿勢を読んでから組む *)
idLiteSpawn[file_String, url_String, n_Integer, title_String] :=
  Module[{id = StringTake[CreateUUID[], 8], c = itOpenDocURL[file, url, title]},
    $itState["DocJobs"] = Append[Replace[Lookup[$itState, "DocJobs", {}], Except[_List] -> {}],
      <|"Id" -> id, "Phase" -> "LiteInit", "URL" -> url, "Title" -> title, "File" -> file, "Pages" -> n,
        "Time" -> iNow[], "Tries" -> 0, "Anchor" -> $itOpenAnchor, "CacheKey" -> c["CacheKey"]|>];
    itSetStatus["PDF を開いています: " <> itTruncate[title, 40]];
    <|"Native" -> True, "Lite" -> True, "Deferred" -> True, "Id" -> id, "Pages" -> n, "Title" -> title|>];

(* 雛形を使わず文書ビューアで開くか: モードが "Lite"、または雛形を知らず直近 5 分に「無い」と分かっている *)
idLiteDirectQ[] :=
  ResoniteRealtime`$ResonitePDFMode === "Lite" ||
    (TrueQ[ResoniteRealtime`$ResonitePDFLite] && !StringQ[itNativeTemplateId[]] &&
      iNow[] - Lookup[$itState, "TemplateMissingAt", -1000] <= 300);

(* 姿勢の要求: 開いた場所 (一覧の升目) があればその根、無ければタブレットの根 (Depth 0、待たない) *)
idJobPoseRequest[j_Association] :=
  With[{a = Lookup[j, "Anchor", None]},
    If[AssociationQ[a] && StringQ[Lookup[a, "Root", None]], itSendGet[a["Root"], 0, False], itNativePoseRequest[]]];
(* 読めた姿勢 d (親から見た position / rotation / scale と親) に、その座標系での offset を足した置き場所 *)
(* off は根の座標系の点 (根の拡大率を掛ける)、front は根の向きだけ回して足す (拡大率を掛けない、m) *)
idPoseFrom[d_Association, off_List] := idPoseFrom[d, off, {0., 0., 0.}];
idPoseFrom[d_Association, off_List, front_List] :=
  Module[{p, q, sc, parent},
    p = itSlotVec[d, "position", {"x", "y", "z"}, None];
    q = itSlotVec[d, "rotation", {"x", "y", "z", "w"}, {0., 0., 0., 1.}];
    sc = itSlotVec[d, "scale", {"x", "y", "z"}, {1., 1., 1.}];
    parent = Lookup[Replace[Lookup[d, "parent", <||>], Except[_Association] -> <||>], "targetId", None];
    If[ListQ[p] && StringQ[parent],
      <|"Parent" -> parent, "Position" -> p + itQRotate[q, sc*N[off] + N[front]], "Rotation" -> q|>, None]];

(* 根の座標系の点 off に、根の向き q に続けて lr だけ回した向きで置く (曲面の一覧: 升目とアバターの間でアバターの方を向ける。
   front は lr で回した座標系のずらし、m) *)
idPoseFromLocal[d_Association, off_List, front_List, lr_List] :=
  Module[{p, q, sc, parent},
    p = itSlotVec[d, "position", {"x", "y", "z"}, None];
    q = itSlotVec[d, "rotation", {"x", "y", "z", "w"}, {0., 0., 0., 1.}];
    sc = itSlotVec[d, "scale", {"x", "y", "z"}, {1., 1., 1.}];
    parent = Lookup[Replace[Lookup[d, "parent", <||>], Except[_Association] -> <||>], "targetId", None];
    If[ListQ[p] && StringQ[parent],
      <|"Parent" -> parent, "Position" -> p + itQRotate[q, sc*N[off] + itQRotate[N[lr], N[front]]],
        "Rotation" -> N[icQuatMul[q, N[lr]]]|>, None]];

(* 一覧の升目から開いた PDF の置き場所 (2026-09-25 ユーザー指摘「パネルから離れた変な位置に出る」):
   - 押した升目の真正面 (升目の中心 = 根の座標系の点。パネルを掴んで拡大していれば拡大率を掛ける)
   - パネルからの距離は $idFrontMeters (拡大率を掛けない。前は 0.45 * 拡大率で、大きくしたパネルほど遠くに出た)
   - 重ね置きのずらしは「同じ一覧から直近 $idCascadeSeconds 秒に開いた数」(4 で折り返す)。前はこのセッションで開いた全 PDF の数
     (ワールドで閉じても減らない) で右下へ 0.12k / 0.05k ずつ流れ、床の近くまで下がった *)
$idFrontMeters = 0.3; $idCascadeSeconds = 120;
idAnchorCascade[root_String] :=
  Module[{all = Replace[Lookup[$itState, "AnchorOpens", <||>], Except[_Association] -> <||>], ts, n},
    ts = Select[Replace[Lookup[all, root, {}], Except[_List] -> {}], iNow[] - # < $idCascadeSeconds &];
    n = Mod[Length[ts], 4];
    $itState["AnchorOpens"] = Append[all, root -> Append[ts, iNow[]]];
    n];

idJobPose[j_Association, k_Integer, tab_] :=
  Module[{a = Lookup[j, "Anchor", None], d = If[AssociationQ[tab] && Lookup[tab, "success", True] =!= False, Lookup[tab, "data", None], None], p, n},
    If[AssociationQ[a] && AssociationQ[d],
      n = If[StringQ[Lookup[a, "Root", None]], idAnchorCascade[a["Root"]], 0];
      p = Which[
        (* 曲面の升目 (itThumbAnchor): Cell は升目とアバターの間の点、LocalRotation はアバターの方を向く向き *)
        ListQ[Lookup[a, "Cell", None]] && ListQ[Lookup[a, "LocalRotation", None]],
          idPoseFromLocal[d, a["Cell"], {0.04 n, -0.03 n, -0.02 n}, a["LocalRotation"]],
        ListQ[Lookup[a, "Cell", None]],
          idPoseFrom[d, a["Cell"], {0.04 n, -0.03 n, -($idFrontMeters + 0.02 n)}],
        True,
        idPoseFrom[d, Lookup[a, "Offset", {0., 0., -0.45}] + {0.04 n, -0.03 n, -0.02 n}]];
      If[AssociationQ[p], Return[p]]];
    If[AssociationQ[a], d = None];   (* 一覧の姿勢が読めなかった: タブレットの姿勢ではない *)
    itNativePose[k, d]];

(* 文書ビューアの段 (itNativeStep から): LiteInit = 姿勢を要求、LitePose = 姿勢 (5 s まで待つ) で組み立てを予約 *)
idLiteStep[j_Association] :=
  Module[{tab, pose, k},
    Switch[j["Phase"],
      "LiteInit",
        (* ページ数 (n / N と端の止め) を作業用カーネルが数えている間は 40 s まで待つ *)
        If[Replace[Lookup[j, "Pages", 0], Except[_Integer] -> 0] === 0 && StringQ[Lookup[j, "File", None]] && FileExistsQ[j["File"]],
          With[{c = idPageCountCached[j["File"]]},
            Which[
              IntegerQ[c] && c > 0, Return[Join[j, <|"Pages" -> c, "WaitCount" -> False|>]],
              idPageCountPendingQ[j["File"]] && iNow[] - Lookup[j, "Time", iNow[]] < 40, Return[Join[j, <|"WaitCount" -> True|>]]]]];
        Join[j, <|"Phase" -> "LitePose", "PoseMessageId" -> idJobPoseRequest[j], "Sent" -> iNow[], "WaitCount" -> False|>],
      "LitePose",
        tab = If[StringQ[Lookup[j, "PoseMessageId", None]], icPollReply[j["PoseMessageId"]], None];
        If[!AssociationQ[tab] && StringQ[Lookup[j, "PoseMessageId", None]] && iNow[] - j["Sent"] <= 5, Return[j]];
        k = Length[itNativeDocs[]] + Length[idDocViewers[]];
        pose = idJobPose[j, k, tab];
        With[{url = Quiet @ Check[ipcURLFor[Lookup[j, "CacheKey", None], j["URL"]], j["URL"]], title = j["Title"],
              n = Replace[j["Pages"], Except[_Integer] -> 0], ps = pose,
              meta = <|"Local" -> j["URL"], "CacheKey" -> Lookup[j, "CacheKey", None]|>},
          (* 組み立ての予約 ID を控える (一覧の状態欄が「組み立て中 → 開きました」を追う) *)
          $itState["LiteBuilds"] = Append[Replace[Lookup[$itState, "LiteBuilds", <||>], Except[_Association] -> <||>],
            j["Id"] -> itEnqueueBuild["PDF ビューア", Function[idDocViewerBuild[url, title, n, ps, meta]]]]];
        itNativeLog[j["Id"], "Lite", j["Tries"], "文書ビューアを予約 (" <> ToString[pose["Parent"]] <> ")"];
        None,
      _, None]];

(* ============================================================
   2. サムネイル一覧: 画像の取り込み (http -> local:// 資産)
   ============================================================ *)
idTexImports[] := Replace[Lookup[$itState, "TexImports", {}], Except[_List] -> {}];
$idTexImportSeconds = 120;

(* tick の中 (または tick が回っている) なら要求を送って後で差し替える。トップレベルなら待って今差し替える *)
idQueueTexImport[tex_String, file_String, root_String] :=
  Module[{r},
    If[itAsyncBuildQ[] || itTickActiveQ[],
      r = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeLink[<|"$type" -> "importTexture2DFile", "filePath" -> file|>,
        "Wait" -> False], $Failed];
      If[AssociationQ[r] && StringQ[Lookup[r, "MessageId", None]],
        $itState["TexImports"] = Append[idTexImports[],
          <|"MessageId" -> r["MessageId"], "Texture" -> tex, "File" -> file, "Root" -> root, "Sent" -> iNow[]|>]];
      Return[r]];
    r = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeLink[<|"$type" -> "importTexture2DFile", "filePath" -> file|>,
      "Timeout" -> 60], $Failed];
    If[AssociationQ[r] && StringQ[Lookup[r, "assetURL", None]],
      idTexImported[tex, r["assetURL"], root]];
    r];

idTexImported[tex_String, asset_String, root_String] :=
  (itNoWait @ Quiet @ Check[ResoniteRealtime`ResoniteRealtimeUpdateComponent[tex,
     <|"URL" -> ResoniteRealtime`ResoniteRealtimeValue["Uri", asset]|>], Null];
   If[KeyExistsQ[itThumbs[], root],
     $itState["Thumbs", root, "Assets"] = Append[Replace[Lookup[itThumbs[][root], "Assets", <||>], Except[_Association] -> <||>],
       tex -> asset];
     If[Length[$itState["Thumbs", root, "Assets"]] >= Length[Replace[Lookup[itThumbs[][root], "Textures", {}], Except[_List] -> {}]],
       (* 狭い一覧では切れるので、大事な方 (保存できる) を先に *)
       idBoardStatus[root, "インベントリに保存できます (画像を取り込み済み)  [" <> itAccessLabel[] <> "]"]]]);

idProcessTexImports[] :=
  Module[{left = {}, res},
    Do[
      res = icPollReply[t["MessageId"]];
      Which[
        AssociationQ[res] && Lookup[res, "success", True] =!= False && StringQ[Lookup[res, "assetURL", None]],
          idTexImported[t["Texture"], res["assetURL"], t["Root"]],
        AssociationQ[res],
          $itState["LastError"] = iFailure["TexImport", "画像の取り込みに失敗: " <> ToString[Lookup[res, "errorInfo", ""]]],
        iNow[] - t["Sent"] > $idTexImportSeconds,
          $itState["LastError"] = iFailure["TexImport", "画像の取り込みの応答が来ません: " <> FileNameTake[t["File"]]],
        True, AppendTo[left, t]],
      {t, idTexImports[]}];
    $itState["TexImports"] = left;
    Length[left]];

(* ============================================================
   2. サムネイル一覧: 組み立ての追加部品 (itThumbGadgetBuild から呼ぶ)
   ============================================================ *)
$idVeilText = "「接続」を押すと表示します\n(Mathematica で ResoniteRealtime を読み込んでおいてください)";
(* 「接続」を押した瞬間にワールドの中だけで覆いに出す文字 (ButtonValueSet<string>。Wolfram が気付く前から見える) *)
$idVeilPressedText = "接続を要求しました\nMathematica の応答を待っています…";

(* 覆い (Veil): 升目の上に重ねる不透明の板。保存して出し直したときだけ見える (Flux が有効にする)。
   戻り値 {覆いのスロット, 文字のスロット, 文字の Text} *)
idBoardVeil[panel_String, L_Association, fs_] :=
  Module[{veil, t, tid},
    veil = icSlot["Veil", panel, "Active" -> False, "Id" -> ResoniteRealtime`ResoniteRealtimeNewId["Veil"]];
    icComp[veil, $icUIX <> "RectTransform", itAnchors[{0, L["HH"], L["W"], L["H"] - L["HH"]}, {L["W"], L["H"]}]];
    icImage[veil, $itThumbColors["Page"]];
    t = icSlot["Text", veil, "Id" -> ResoniteRealtime`ResoniteRealtimeNewId["VeilTextSlot"]];
    icComp[t, $icUIX <> "RectTransform", <|"AnchorMin" -> {0., 0.}, "AnchorMax" -> {1., 1.}|>];
    tid = itText[t, $idVeilText, fs*4., "Center", "Middle", ResoniteRealtime`ResoniteRealtimeNewId["VeilText"],
      RGBColor[0.8, 0.84, 0.92, 1]];
    {veil, t, tid}];

(* Flux: 読み込まれた (インベントリ / ワールドの保存から) / 複製されたら、升目を隠して覆いを出す *)
idBoardFlux[root_String, content_String, veil_String] :=
  Module[{flux, s, ref = ResoniteRealtime`ResoniteRealtimeRef, pfb = $itPFB, src, falseN, trueN, showVeil, hide},
    flux = icSlot["Flux", root, "Position" -> {0., -0.2, 0.}, "Scale" -> {0.02, 0.02, 0.02}];
    src[name_, target_] := Module[{sl = icSlot[name, flux], g},
      g = icComp[sl, $icFE <> "ProtoFlux.GlobalReference<[FrooxEngine]FrooxEngine.Slot>", <|"Reference" -> ref[target]|>];
      icComp[sl, pfb <> "FrooxEngine.ProtoFlux.CoreNodes.ElementSource<[FrooxEngine]FrooxEngine.Slot>", <|"Source" -> ref[g]|>,
        ResoniteRealtime`ResoniteRealtimeNewId["Node"]]];
    s = src["contentSlot", content];
    With[{c = s, v = src["veilSlot", veil]},
      falseN = icComp[icSlot["false", flux], pfb <> "ProtoFlux.Runtimes.Execution.Nodes.ValueInput<bool>", <|"Value" -> False|>,
        ResoniteRealtime`ResoniteRealtimeNewId["Node"]];
      trueN = icComp[icSlot["true", flux], pfb <> "ProtoFlux.Runtimes.Execution.Nodes.ValueInput<bool>", <|"Value" -> True|>,
        ResoniteRealtime`ResoniteRealtimeNewId["Node"]];
      showVeil = icComp[icSlot["showVeil", flux], pfb <> "ProtoFlux.Runtimes.Execution.Nodes.FrooxEngine.Slots.SetSlotActiveSelf",
        <|"Instance" -> ref[v], "Active" -> ref[trueN]|>, ResoniteRealtime`ResoniteRealtimeNewId["Node"]];
      hide = icComp[icSlot["hideContent", flux], pfb <> "ProtoFlux.Runtimes.Execution.Nodes.FrooxEngine.Slots.SetSlotActiveSelf",
        <|"Instance" -> ref[c], "Active" -> ref[falseN], "Next" -> ref[showVeil]|>, ResoniteRealtime`ResoniteRealtimeNewId["Node"]];
      icComp[icSlot["onLoaded", flux], pfb <> "ProtoFlux.Runtimes.Execution.Nodes.FrooxEngine.Slots.OnLoaded",
        <|"Trigger" -> ref[hide]|>, ResoniteRealtime`ResoniteRealtimeNewId["Node"]];
      icComp[icSlot["onDuplicate", flux], pfb <> "ProtoFlux.Runtimes.Execution.Nodes.FrooxEngine.Slots.OnDuplicate",
        <|"Trigger" -> ref[hide]|>, ResoniteRealtime`ResoniteRealtimeNewId["Node"]]];
    flux];

idBoardData[root_String, body_Association] :=
  Module[{d = icSlot["Data", root]},
    icComp[d, $icFE <> "ValueField<string>", <|"Value" -> idEncode[body]|>, ResoniteRealtime`ResoniteRealtimeNewId["BoardData"]];
    d];

(* 状態欄に入る文字数 (全角 1 文字 = 文字の大きさ 27 px の見積り、見出しの幅 - ボタン 3 つ) *)
(* 見出しの幅: 曲面の一覧は見出しが小さな Canvas (HeaderW)。右端のボタンは 5 つ (接続 / 形を変更 / リスト / 閉じる / キャッシュ削除、2026-09-26) *)
idStatusChars[rec_Association] :=
  With[{L = Lookup[rec, "Layout", <||>]},
    Max[16, Floor[(Replace[Lookup[rec, "HeaderW", None], Except[_?NumericQ] :> Lookup[L, "W", 1720]] -
      2 Lookup[L, "M", 24] - $itHeaderButtons*160 - 24)/27.]]];
idBoardStatus[root_String, text_String] :=
  Module[{rec = Lookup[itThumbs[], root, <||>], t, n, s},
    t = Lookup[Lookup[rec, "Ids", <||>], "StatusText", None];
    If[!StringQ[t], Return[None]];
    n = idStatusChars[rec];
    s = If[itLineWidth[text, 1.] <= n, text, StringTake[text, UpTo[n - 1]] <> "…"];
    If[Lookup[rec, "StatusShown", None] === s, Return[s]];   (* 同じ文字は書かない (毎 tick 呼ばれる) *)
    itNoWait @ Quiet @ Check[ResoniteRealtime`ResoniteRealtimeUpdateComponent[t, <|"Content" -> s|>], Null];
    If[KeyExistsQ[itThumbs[], root], $itState["Thumbs", root, "StatusShown"] = s];
    s];
idVeilSay[root_String, text_String] :=
  With[{t = Lookup[Lookup[Lookup[itThumbs[], root, <||>], "Ids", <||>], "VeilText", None]},
    If[StringQ[t],
      itNoWait @ Quiet @ Check[ResoniteRealtime`ResoniteRealtimeUpdateComponent[t, <|"Content" -> text|>], Null]]];

(* ============================================================
   2. サムネイル一覧: 引き継ぎ (インベントリから出した一覧の「接続」)
   ============================================================ *)
$idBoardName = "SourceVault Thumbnails";
idBoardCands[] := Replace[Lookup[$itState, "BoardCands", {}], Except[_List] -> {}];
idBoardCandInfo[] := Replace[Lookup[$itState, "BoardCandInfo", <||>], Except[_Association] -> <||>];
idBoardJobs[] := Replace[Lookup[$itState, "BoardJobs", <||>], Except[_Association] -> <||>];

(* 走査で見えた一覧 (台帳に無い物) を候補にする *)
idNoteBoardCands[kids_List, reset_] :=
  Module[{c},
    c = Select[kids, AssociationQ[#] && StringQ[Lookup[#, "id", None]] &&
      StringStartsQ[ToString[itVal[Lookup[#, "name", ""]]], $idBoardName] &&
      !KeyExistsQ[itThumbs[], #["id"]] && !KeyExistsQ[idBoardJobs[], #["id"]] &];
    (* Root の走査 (reset) でも、直前 60 s に読めていた候補は残す (入れ物の下の一覧は Root の走査で一度外れ、入れ物の走査で
       戻るまで「接続」を読まれなかった。2026-09-26) *)
    $itState["BoardCands"] = DeleteDuplicates[Join[
      If[reset, Select[idBoardCands[], iNow[] - Lookup[Lookup[idBoardCandInfo[], #, <||>], "Time", 0] < 60 &], idBoardCands[]],
      Lookup[#, "id"] & /@ c]];
    If[!AssociationQ[$idBoardSeen], $idBoardSeen = <||>];
    Scan[If[!KeyExistsQ[$idBoardSeen, #], $idBoardSeen[#] = iNow[]; idBoardLog[#, "Cand", "候補に入れました"]] &,
      Lookup[#, "id"] & /@ c];
    (* 控えた State の ID は Root の走査で捨てない (2026-09-25 実機: 入れ物の下の一覧は Root の走査 (5 s ごと) で
       候補から一度外れて入れ物の走査で戻る。そのたびに控えも捨てていたので「接続」を読む段に進めなかった) *)
    $itState["BoardCandInfo"] = Select[idBoardCandInfo[], iNow[] - Lookup[#, "Time", 0] < 300 &];
    Length[c]];

(* 候補の監視は監視の巡回 (1 対象 = 2 tick) に載せず、候補ごとに 2 秒おきに読む (待たない。2026-09-25 ユーザー指摘
   「接続を押したのに何も変化がないとわかりにくい」: 巡回だと対象が多いと 10-20 s 気付かなかった)。
   まだ State の ID を知らなければ根を Depth 1 (部品なし) で、知っていれば State を Depth 0 で読む *)
idBoardScanTargets[] := {};
$idCandPollSeconds = 2;
idPollBoardCands[] := If[TrueQ[$itState["Serve"]] && itLinkQ[], Scan[idPollBoardCand, idBoardCands[]]];
(* 接続 (候補 -> 引き継ぎ) の段階の記録 (2026-09-26 ユーザー報告「保存したサムネイル一覧の接続を押しても反応がない」:
   どこで止まったか分かる手掛かりが無かった)。ResoniteTabletStatus[]["BoardLog"]、直近 40 件 *)
idBoardLog[root_, step_String, note_String : ""] :=
  ($itState["BoardLog"] = Take[Append[Replace[Lookup[$itState, "BoardLog", {}], Except[_List] -> {}],
     <|"Time" -> DateString[{"Hour", ":", "Minute", ":", "Second"}], "Root" -> root, "Step" -> step, "Note" -> note|>],
     -Min[40, Length[Replace[Lookup[$itState, "BoardLog", {}], Except[_List] -> {}]] + 1]]);

idPollBoardCand[root_String] :=
  Module[{inf = Replace[Lookup[idBoardCandInfo[], root, <||>], Except[_Association] -> <||>], res, st, vf, msg, drop, vals},
    drop[why_] := (idBoardLog[root, "CandDrop", why];
      $itState["BoardCands"] = DeleteCases[idBoardCands[], root];
      $itState["BoardCandInfo"] = KeyDrop[idBoardCandInfo[], root]);
    If[StringQ[Lookup[inf, "Pending", None]],
      res = icPollReply[inf["Pending"]];
      Which[
        AssociationQ[res],
          inf = KeyDrop[inf, "Pending"];
          If[Lookup[res, "success", True] === False, drop["getSlot 失敗: " <> ToString[Lookup[res, "errorInfo", ""]]]; Return[None]];
          If[!StringQ[Lookup[inf, "State", None]],
            st = idChildByName[Lookup[res, "data", <||>], "State"];
            If[!AssociationQ[st], drop["子に State がありません"]; Return[None]];
            inf["State"] = st["id"];
            idBoardLog[root, "CandState", st["id"]],
            (* 「接続」は Selected (State の ValueField<int>) を -3 にする。ValueField<int> が複数あっても見落とさない *)
            vf = Select[Lookup[Lookup[res, "data", <||>], "components", {}],
              AssociationQ[#] && StringEndsQ[ToString[Lookup[#, "componentType", ""]], "ValueField<int>"] &];
            vals = Map[icMemberValue[#, "Value"] &, vf];
            If[!TrueQ[Lookup[inf, "LoggedValues", False]],
              inf["LoggedValues"] = True; idBoardLog[root, "CandRead", "ValueField<int> = " <> ToString[vals]]];
            (* -3 = 「接続」、正の数 = 升目 (サムネイル) を押した (2026-09-26: 接続を押さなくても、升目を押せば
               接続 -> ワールドの確認 -> その PDF を開く) *)
            With[{k = FirstPosition[vals, v_Integer /; v === -3 || v > 0, None, {1}]},
              If[k =!= None,
                With[{hit = vf[[First[k]]], v = vals[[First[k]]]},
                  itNoWait @ Quiet @ Check[ResoniteRealtime`ResoniteRealtimeUpdateComponent[hit["id"], <|"Value" -> 0|>], Null];
                  drop[If[v > 0, "升目 " <> ToString[v] <> " が押された", "接続が押された"]];
                  idBoardLog[root, "Connect", If[v > 0, "升目 " <> ToString[v] <> " を開くために引き継ぎます", "引き継ぎを始めます"]];
                  Return[idGatedAdopt[root, If[v > 0, v, None]], Module]]]]];
          inf["Time"] = iNow[],
        iNow[] - Lookup[inf, "Sent", 0] > 10, inf = KeyDrop[inf, "Pending"]; idBoardLog[root, "CandTimeout", "getSlot の応答が 10 s 来ません"],
        True, Return[None]]];
    If[iNow[] - Lookup[inf, "Sent", 0] >= $idCandPollSeconds,
      msg = If[StringQ[Lookup[inf, "State", None]], itSendGet[inf["State"], 0, True], itSendGet[root, 1, False]];
      If[StringQ[msg], inf = Join[inf, <|"Pending" -> msg, "Sent" -> iNow[]|>]]];
    $itState["BoardCandInfo"] = Append[idBoardCandInfo[], root -> Join[<|"Time" -> iNow[]|>, inf]];
    None];

idChildByName[d_Association, name_String] :=
  SelectFirst[Select[Lookup[d, "children", {}], AssociationQ], ToString[itVal[Lookup[#, "name", ""]]] === name &, None];

idHandleBoardCandTop[root_String, res_Association] :=
  With[{st = idChildByName[Lookup[res, "data", <||>], "State"]},
    If[AssociationQ[st],
      $itState["BoardCandInfo"] = Append[idBoardCandInfo[], root -> <|"State" -> st["id"], "Time" -> iNow[]|>],
      $itState["BoardCands"] = DeleteCases[idBoardCands[], root]]];

(* State の ValueField<int> が -3 (「接続」) なら 0 に戻して引き継ぎを始める *)
idHandleBoardCand[root_String, res_Association] :=
  Module[{vf},
    vf = SelectFirst[Lookup[Lookup[res, "data", <||>], "components", {}],
      AssociationQ[#] && StringEndsQ[ToString[Lookup[#, "componentType", ""]], "ValueField<int>"] &, None];
    If[!AssociationQ[vf] || icMemberValue[vf, "Value"] =!= -3, Return[None]];
    itNoWait @ Quiet @ Check[ResoniteRealtime`ResoniteRealtimeUpdateComponent[vf["id"], <|"Value" -> 0|>], Null];
    $itState["BoardCands"] = DeleteCases[idBoardCands[], root];
    idGatedAdopt[root]];

idStartAdopt[root_String] :=
  ($itState["BoardJobs"] = Append[idBoardJobs[], root -> <|"Root" -> root, "Phase" -> "Top", "Time" -> iNow[]|>];
   itSetStatus["サムネイル一覧を接続しています: " <> root];
   root);

(* ワールドの「接続」ボタンからの引き継ぎはオーナー在席の関門を通す (ResoniteRealtime_tablet.wl の itPressGate)。
   手で呼ぶ ResoniteBoardAdopt は通さない *)
idGatedAdopt[root_String] := idGatedAdopt[root, None];
(* open: 接続のきっかけが升目の押下ならその番号。引き継ぎと確認が済んだら開く (idFirePendingOpen) *)
idGatedAdopt[root_String, open_] :=
  (itPressGate[If[IntegerQ[open], "サムネイル一覧の接続 (升目 " <> ToString[open] <> " を開く)", "サムネイル一覧の接続"], None,
     ($itState["BoardPendingOpen"] = Append[Replace[Lookup[$itState, "BoardPendingOpen", <||>], Except[_Association] -> <||>],
        root -> open];
      idStartAdopt[root])];
   root);

(* 覚えておいた升目を開く (ワールドの確認が済んで Ready になったとき) *)
idFirePendingOpen[root_String] :=
  Module[{rec = Lookup[itThumbs[], root, None], i},
    If[!AssociationQ[rec] || Lookup[rec, "Phase", "Ready"] =!= "Ready", Return[None]];
    i = Lookup[rec, "PendingOpen", None];
    If[!IntegerQ[i], Return[None]];
    $itState["Thumbs", root, "PendingOpen"] = None;
    idBoardLog[root, "OpenPending", "升目 " <> ToString[i]];
    itThumbOpen[root, i]];

(* 診断 (待つ getSlot なのでノートブックのトップレベルから) *)
ResoniteRealtime`ResoniteBoardDiagnose[root_String] :=
  Module[{top, d, st, stRes, vals, parent, pname = None},
    top = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeGetSlot[root, "Depth" -> 1, "IncludeComponentData" -> False, "Timeout" -> 30], $Failed];
    d = If[AssociationQ[top], Lookup[top, "data", None], None];
    st = If[AssociationQ[d], idChildByName[d, "State"], None];
    stRes = If[AssociationQ[st],
      Quiet @ Check[ResoniteRealtime`ResoniteRealtimeGetSlot[st["id"], "Depth" -> 0, "IncludeComponentData" -> True, "Timeout" -> 30], $Failed],
      None];
    vals = If[AssociationQ[stRes],
      Map[icMemberValue[#, "Value"] &, Select[Lookup[Lookup[stRes, "data", <||>], "components", {}],
        AssociationQ[#] && StringEndsQ[ToString[Lookup[#, "componentType", ""]], "ValueField<int>"] &]], None];
    parent = If[AssociationQ[d], Lookup[Replace[Lookup[d, "parent", <||>], Except[_Association] -> <||>], "targetId", None], None];
    If[StringQ[parent],
      pname = With[{pr = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeGetSlot[parent, "Depth" -> 0, "IncludeComponentData" -> False,
          "Timeout" -> 30], $Failed]},
        If[AssociationQ[pr], ToString[itVal[Lookup[Lookup[pr, "data", <||>], "name", ""]]], None]]];
    <|"Found" -> AssociationQ[d],
      (* 読めなかったときは応答そのもの (success / errorInfo) を返す *)
      "Reply" -> If[AssociationQ[d], "OK", If[AssociationQ[top], KeyDrop[top, "data"], top]],
      "Name" -> If[AssociationQ[d], ToString[itVal[Lookup[d, "name", ""]]], None],
      "Parent" -> parent, "ParentName" -> pname, "ParentIsHolder" -> (StringQ[pname] && itHolderQ[<|"name" -> pname|>]),
      "Children" -> If[AssociationQ[d], Map[ToString[itVal[Lookup[#, "name", ""]]] &, Select[Lookup[d, "children", {}], AssociationQ]], None],
      "State" -> If[AssociationQ[st], st["id"], None], "StateValues" -> vals,
      "Candidate" -> MemberQ[idBoardCands[], root], "CandInfo" -> KeyDrop[Lookup[idBoardCandInfo[], root, <||>], "Pending"],
      "Adopting" -> KeyExistsQ[idBoardJobs[], root], "Attached" -> KeyExistsQ[itThumbs[], root],
      "ScanHolders" -> Lookup[$itState, "ScanHolders", None], "LastScanSecondsAgo" -> Round[iNow[] - Lookup[$itState, "LastScan", 0], 0.1],
      "Serve" -> TrueQ[Lookup[$itState, "Serve", False]],
      "BoardLog" -> Select[Replace[Lookup[$itState, "BoardLog", {}], Except[_List] -> {}], #["Root"] === root &]|>];

(* 引数なし: Root 直下と入れ物の中のサムネイル一覧を探して全部診断する (インベントリから出し直すと ID が変わるので) *)
ResoniteRealtime`ResoniteBoardDiagnose[] :=
  Module[{kids = itScanSlotsNow[]},
    If[FailureQ[kids], Return[kids]];
    Association @ Map[#["id"] -> ResoniteRealtime`ResoniteBoardDiagnose[#["id"]] &,
      Select[kids, AssociationQ[#] && StringQ[Lookup[#, "id", None]] &&
        StringStartsQ[ToString[itVal[Lookup[#, "name", ""]]], $idBoardName] &]]];

(* 手動: ResoniteBoardAdopt[root] (常駐監視が無くても。tick が回っていること) *)
ResoniteRealtime`ResoniteBoardAdopt[root_String] := idStartAdopt[root];

$idBoardReplySeconds = 20;
idProcessBoardJobs[] :=
  KeyValueMap[Function[{root, j},
      With[{nj = Quiet @ Check[idBoardStep[j], None]},
        $itState["BoardJobs"] = If[AssociationQ[nj], Append[idBoardJobs[], root -> nj], KeyDrop[idBoardJobs[], root]]]],
    idBoardJobs[]];

idBoardStep[j_Association] :=
  Module[{res, d, kids, st, data, panel, sel, dv, body, pd, content, veil, status, title, rec, stash},
    Switch[j["Phase"],
      "Top",
        Join[j, <|"Phase" -> "TopWait", "MessageId" -> itSendGet[j["Root"], 1, True], "Sent" -> iNow[]|>],
      "TopWait",
        res = icPollReply[j["MessageId"]];
        If[!AssociationQ[res], Return[If[iNow[] - j["Sent"] > $idBoardReplySeconds, idBoardLog[j["Root"], "AdoptTimeout", "根の読み取りが来ません"]; None, j]]];
        d = Lookup[res, "data", None];
        If[!AssociationQ[d], idBoardLog[j["Root"], "AdoptFail", "根が読めません: " <> ToString[Lookup[res, "errorInfo", ""]]]; Return[None]];
        st = idChildByName[d, "State"]; data = idChildByName[d, "Data"]; panel = idChildByName[d, "Panel"];
        stash = idChildByName[d, $itStashName];
        sel = itCompId[st, "ValueField<int>"];
        dv = itCompOf[data, "ValueField<string>"];
        If[!StringQ[sel] || !AssociationQ[panel],
          itSetStatus["サムネイル一覧の構造ではありません: " <> j["Root"]]; idBoardLog[j["Root"], "AdoptFail", "構造が違います (State / Panel)"]; Return[None]];
        body = idDecode[If[AssociationQ[dv], icMemberValue[dv, "Value"], None]];
        Join[j, <|"Phase" -> "PanelWait", "MessageId" -> itSendGet[panel["id"], 1, True], "Sent" -> iNow[],
          "State" -> st["id"], "Selected" -> sel, "Panel" -> panel["id"], "Body" -> body,
          "Stash" -> If[AssociationQ[stash], stash["id"], None], "Scale" -> itSlotScaleX[panel, None],
          (* 前の版の「出し直したら升目を隠す」Flux (開示してよい方針では引き継ぎで外す) *)
          "Flux" -> itSlotId[idChildByName[d, "Flux"]], "Name" -> ToString[itVal[Lookup[d, "name", $idBoardName]]],
          (* 曲面の一覧 (2026-09-26) は升目の入れ物 Content が根の子 (Panel は見出しだけ) *)
          "RootContent" -> itSlotId[idChildByName[d, "Content"]]|>],
      "PanelWait",
        res = icPollReply[j["MessageId"]];
        If[!AssociationQ[res], Return[If[iNow[] - j["Sent"] > $idBoardReplySeconds, idBoardLog[j["Root"], "AdoptTimeout", "Panel の読み取りが来ません"]; None, j]]];
        pd = Lookup[res, "data", <||>];
        content = Replace[itSlotId[idChildByName[pd, "Content"]], None :> Lookup[j, "RootContent", None]];
        veil = itSlotId[idChildByName[pd, "Veil"]];
        status = itCompId[idChildByName[pd, "Status"], "UIX.Text"];
        title = itCompId[idChildByName[pd, "Title"], "UIX.Text"];
        If[FailureQ[j["Body"]],
          (* 検証できない一覧は見せない (升目を隠し、覆いを出し、理由を書く) *)
          If[StringQ[content], itNoWait @ Quiet @ Check[ResoniteRealtime`ResoniteRealtimeUpdateSlot[content, <|"isActive" -> False|>], Null]];
          If[StringQ[veil], itNoWait @ Quiet @ Check[ResoniteRealtime`ResoniteRealtimeUpdateSlot[veil, <|"isActive" -> True|>], Null]];
          If[StringQ[status], itNoWait @ Quiet @ Check[ResoniteRealtime`ResoniteRealtimeUpdateComponent[status,
            <|"Content" -> "接続できません: " <> ToString[j["Body"]["MessageTemplate"]]|>], Null]];
          itSetStatus["サムネイル一覧を接続できません: " <> ToString[j["Body"]["MessageTemplate"]]];
          idBoardLog[j["Root"], "AdoptFail", "一覧の中身を検証できません: " <> ToString[j["Body"]["MessageTemplate"]]];
          Return[None]];
        body = j["Body"];
        rec = <|"Ids" -> <|"State" -> j["State"], "Selected" -> j["Selected"], "Panel" -> j["Panel"], "Content" -> content,
            "Veil" -> veil, "StatusText" -> status, "TitleText" -> title|>,
          "Root" -> j["Root"], "Rows" -> Map[idRowRecheck, body["rows"]], "Title" -> body["title"],
          "Layout" -> body["layout"], "Scale" -> Replace[j["Scale"], Except[_?NumericQ] -> Lookup[body, "scale", 0.0006]],
          "Hidden" -> 0, "Overflow" -> 0, "Stash" -> j["Stash"], "Adopted" -> True, "Name" -> Lookup[j, "Name", $idBoardName],
          "Phase" -> "Checking", "ConnectAt" -> iNow[], "ConnectStart" -> j["Time"], "Level" -> None, "Covers" -> <||>,
          "Created" -> DateObject[]|>;
        rec["AllRows"] = rec["Rows"];
        (* 曲面の一覧なら形と寸法 (升目から開いた PDF の置き場所・形の切り替えに使う) *)
        rec = Quiet @ Check[itSurfaceAdoptRec[rec, body], rec];
        (* 升目を押して接続した (idGatedAdopt) なら、確認が済んだら開く *)
        rec["PendingOpen"] = Lookup[Replace[Lookup[$itState, "BoardPendingOpen", <||>], Except[_Association] -> <||>], j["Root"], None];
        $itState["BoardPendingOpen"] = KeyDrop[Replace[Lookup[$itState, "BoardPendingOpen", <||>], Except[_Association] -> <||>], j["Root"]];
        $itState["Thumbs"] = Append[itThumbs[], j["Root"] -> rec];
        If[itThumbsDisclosableQ[],
          (* 升目は開示してよい: 確認を待たずに見せ、前の版の隠す Flux を外す (このまま保存し直せば次からは出してすぐ見える) *)
          If[StringQ[content], itNoWait @ Quiet @ Check[ResoniteRealtime`ResoniteRealtimeUpdateSlot[content, <|"isActive" -> True|>], Null]];
          If[StringQ[veil], itNoWait @ Quiet @ Check[ResoniteRealtime`ResoniteRealtimeUpdateSlot[veil, <|"isActive" -> False|>], Null]];
          If[StringQ[Lookup[j, "Flux", None]],
            itNoWait @ Quiet @ Check[ResoniteRealtime`ResoniteRealtimeRemoveSlot[j["Flux"]], Null];
            idBoardLog[j["Root"], "FluxRemoved", "出し直したら升目を隠す Flux を外しました"]]];
        idBoardProgress[j["Root"]];
        idForceWorldRead[];
        itSetStatus["サムネイル一覧を接続しました: " <> itTruncate[ToString[body["title"]], 40] <> " (確認中)"]; idBoardLog[j["Root"], "Adopted", ToString[Length[rec["Rows"]]] <> " 件"];
        (* 覆いの文字 (「接続を要求しました」を元に戻し、確認中の経過を出す) は覆いの子。もう 1 回読む *)
        If[StringQ[veil], Join[j, <|"Phase" -> "VeilWait", "MessageId" -> itSendGet[veil, 1, True], "Sent" -> iNow[]|>], None],
      "VeilWait",
        res = icPollReply[j["MessageId"]];
        If[!AssociationQ[res], Return[If[iNow[] - j["Sent"] > $idBoardReplySeconds, None, j]]];
        With[{vt = itCompId[idChildByName[Lookup[res, "data", <||>], "Text"], "UIX.Text"]},
          If[StringQ[vt] && KeyExistsQ[itThumbs[], j["Root"]], $itState["Thumbs", j["Root"], "Ids", "VeilText"] = vt]];
        idBoardProgress[j["Root"]];
        None,
      _, None]];

(* ワールド情報をすぐ読み直す (接続時)。読み取りの時刻が接続より後になるまで一覧は見せない *)
idForceWorldRead[] :=
  If[AssociationQ[itWorldInfo[]], $itState["WorldInfo", "LastRead"] = 0];

(* ============================================================
   2. サムネイル一覧: 表示上限の適用 (接続時・公開度が変わったとき)
   ============================================================ *)
$idBoardCheckSeconds = 30;

idWorldFreshQ[since_] :=
  Module[{w = itWorldInfo[]},
    !itAutoAccessQ[] || (AssociationQ[w] && NumericQ[w["Time"]] && w["Time"] >= since)];

idMaybeBoards[] :=
  KeyValueMap[Function[{root, rec},
      Quiet @ Check[idBoardProgress[root], Null];
      Which[
        Lookup[rec, "Phase", "Ready"] === "Checking",
          Which[
            idWorldFreshQ[rec["ConnectAt"]], idApplyLevel[root]; Quiet @ Check[idFirePendingOpen[root], Null],
            iNow[] - rec["ConnectAt"] > $idBoardCheckSeconds,
              (* ワールド情報が来ない: 厳しい側で見せる (押された升目は厳しい側の上限で開くか断る) *)
              itWorldInfoApply[None]; idApplyLevel[root, "(ワールドの情報が取れないので厳しい側)"];
              Quiet @ Check[idFirePendingOpen[root], Null]],
        Lookup[rec, "Phase", "Ready"] === "Ready" && NumericQ[Lookup[rec, "Level", None]] &&
          Abs[rec["Level"] - itAccessLevel[]] > 10^-9,
          idApplyLevel[root],
        True, Null]],
    itThumbs[]];

(* 状態欄の経過表示 (2026-09-25 ユーザー指示「接続を押したのに何も変化がないとわかりにくい。タブレットと同様に時間経過を。
   サムネイルをクリックしたときも「<ファイル名> を開いています」と出すステータスバーを」)。毎 tick 呼ぶ (同じ文字は書かない) *)
$idPhaseHint = <|"Init" -> "標準ビューアを用意しています", "PageClick" -> "ページを押してめくれるようにしています", "CheckTpl" -> "雛形を確かめています", "FindTpl" -> "雛形を探しています",
  "Before" -> "標準ビューアを複製しています", "Fired" -> "標準ビューアを複製しています", "Await" -> "標準ビューアを複製しています",
  "Configure" -> "標準ビューアを置いています", "LiteInit" -> "Resonite の文書表示を用意しています",
  "LitePose" -> "Resonite の文書表示を用意しています"|>;
idBoardProgress[root_String] :=
  Module[{rec = Lookup[itThumbs[], root, None], n, op, job, bid, b, t},
    If[!AssociationQ[rec], Return[None]];
    If[Lookup[rec, "Phase", "Ready"] === "Checking",
      n = Round[iNow[] - Lookup[rec, "ConnectStart", Lookup[rec, "ConnectAt", iNow[]]]];
      t = "ワールドの公開範囲とオーナーを確認しています… " <> ToString[n] <> " 秒";
      idBoardStatus[root, t];
      (* 覆いの文字の ID は引き継ぎの最後 (VeilWait) で分かる。書けたときだけ「書いた」と控える *)
      If[Lookup[rec, "VeilShown", None] =!= t && StringQ[Lookup[rec["Ids"], "VeilText", None]],
        idVeilSay[root, t]; $itState["Thumbs", root, "VeilShown"] = t];
      Return[t]];
    op = Lookup[rec, "Opening", None];
    If[!AssociationQ[op], Return[None]];
    n = Round[iNow[] - op["Since"]];
    t = "「" <> op["Title"] <> "」";
    job = SelectFirst[Replace[Lookup[$itState, "DocJobs", {}], Except[_List] -> {}], Lookup[#, "Id", None] === op["Job"] &, None];
    bid = Lookup[Replace[Lookup[$itState, "LiteBuilds", <||>], Except[_Association] -> <||>], op["Job"], op["Job"]];
    b = Lookup[$itDeferred, bid, None];
    Which[
      AssociationQ[job],
        idBoardStatus[root, t <> "を開いています… " <> ToString[n] <> " 秒  (" <>
          If[TrueQ[Lookup[job, "WaitCount", False]], "ページ数を数えています", Lookup[$idPhaseHint, job["Phase"], job["Phase"]]] <> ")"],
      AssociationQ[b] && Lookup[b, "Status", None] === "Pending",
        idBoardStatus[root, t <> "を開いています… " <> ToString[n] <> " 秒  (ビューアを組み立てています)"],
      AssociationQ[b] && Lookup[b, "Status", None] === "Done",
        idBoardStatus[root, t <> "を開きました (" <> ToString[n] <> " 秒)"]; $itState["Thumbs", root, "Opening"] = None,
      AssociationQ[b],
        idBoardStatus[root, t <> "を開けませんでした: " <>
          With[{r = Lookup[b, "Result", None]}, If[FailureQ[r], ToString[r["MessageTemplate"]], ToString[Lookup[b, "Status", ""]]]]];
        $itState["Thumbs", root, "Opening"] = None,
      AnyTrue[Values[itNativeDocs[]], Lookup[#, "Title", None] === op["Title"] && Lookup[#, "Created", 0] >= op["Since"] &],
        idBoardStatus[root, t <> "を開きました (" <> ToString[n] <> " 秒、標準ビューア)"]; $itState["Thumbs", root, "Opening"] = None,
      True,
        idBoardStatus[root, t <> "を開けませんでした" <>
          With[{e = Lookup[$itState, "LastError", None]}, If[FailureQ[e], ": " <> ToString[e["MessageTemplate"]], ""]]];
        $itState["Thumbs", root, "Opening"] = None];
    n];

(* 上限以上の升目に覆いを付け (無くなった分は外し)、升目を見せて覆い (Veil) を隠す *)
idApplyLevel[root_String, note_String : ""] :=
  Module[{rec = itThumbs[][root], L, rows, bad, covers, ids, nBad, surf},
    L = rec["Layout"]; rows = rec["Rows"]; ids = rec["Ids"];
    covers = Replace[Lookup[rec, "Covers", <||>], Except[_Association] -> <||>];
    (* 升目は開示してよい方針 (2026-09-26) なら覆わない (前に付けた覆いは下で外れる)。中身は開くときに判定する *)
    bad = If[itThumbsDisclosableQ[], {},
      Select[Range[Length[rows]], !itAllowedQ[Lookup[rows[[#]], "PrivacyLevel", 1.0]] &]];
    (* 曲面の一覧 (升目は面の上のタイル) には平面の覆いを置けない: 上限以上の行があれば升目ごと隠して覆いを出す (fail-closed) *)
    surf = TrueQ[Quiet @ Check[itSurfaceRecQ[rec], False]];
    (* 要らなくなった覆いを外す *)
    KeyValueMap[If[!MemberQ[bad, #1], itNoWait @ Quiet @ Check[ResoniteRealtime`ResoniteRealtimeRemoveSlot[#2], Null]] &, covers];
    covers = KeyTake[covers, bad];
    If[!surf && AssociationQ[L] && StringQ[Lookup[ids, "Content", None]],
      Do[If[!KeyExistsQ[covers, i],
          covers[i] = itNoWait @ Quiet @ Check[idCover[ids["Content"], L, i, rows[[i]]], None]],
        {i, bad}]];
    nBad = Length[bad];
    If[StringQ[Lookup[ids, "Content", None]],
      itNoWait @ Quiet @ Check[ResoniteRealtime`ResoniteRealtimeUpdateSlot[ids["Content"], <|"isActive" -> !(surf && nBad > 0)|>], Null]];
    If[StringQ[Lookup[ids, "Veil", None]],
      itNoWait @ Quiet @ Check[ResoniteRealtime`ResoniteRealtimeUpdateSlot[ids["Veil"], <|"isActive" -> (surf && nBad > 0)|>], Null]];
    $itState["Thumbs", root] = Join[rec, <|"Phase" -> "Ready", "Level" -> itAccessLevel[], "Covers" -> covers, "Hidden" -> nBad|>];
    (* 覆いの文字を元に戻す (押した跡や経過のまま保存されると、次に出したとき紛らわしい) *)
    If[Lookup[rec, "VeilShown", $idVeilText] =!= $idVeilText,
      idVeilSay[root, $idVeilText]; $itState["Thumbs", root, "VeilShown"] = $idVeilText];
    idBoardStatus[root, "接続済み [" <> itAccessLabel[] <> "]" <>
      If[Lookup[rec, "Phase", "Ready"] === "Checking",
        "  (" <> ToString[Round[iNow[] - Lookup[rec, "ConnectStart", rec["ConnectAt"]]]] <> " 秒)", ""] <>
      If[nBad > 0, "  機密度で非表示 " <> ToString[nBad], ""] <>
      (* 開示してよい方針: 升目は全部見せ、中身を開けない件数を知らせる *)
      With[{nLock = If[itThumbsDisclosableQ[], Count[rows, r_ /; !itAllowedQ[Lookup[r, "PrivacyLevel", 1.0]]], 0]},
        If[nLock > 0, "  中身は開けない " <> ToString[nLock], ""]] <>
      If[note =!= "", "  " <> note, ""]];
    nBad];

(* 覆い 1 枚 (升目の画像と題名の上。後に作るので上に描かれ、押しても下の升目に届かない) *)
idCover[content_String, L_Association, i_Integer, row_Association] :=
  Module[{c, t, id = ResoniteRealtime`ResoniteRealtimeNewId["Cover"]},
    c = icSlot["Cover" <> ToString[i], content, "Id" -> id];
    icComp[c, $icUIX <> "RectTransform", itAnchors[itThumbCell[L, i], {L["W"], L["H"]}]];
    icImage[c, RGBColor[0.13, 0.14, 0.17, 1]];
    t = icSlot["Text", c];
    icComp[t, $icUIX <> "RectTransform", <|"AnchorMin" -> {0., 0.}, "AnchorMax" -> {1., 1.}|>];
    itText[t, "非表示\nPL " <> itFmt[Lookup[row, "PrivacyLevel", 1.0]], 22., "Center", "Middle", Automatic,
      RGBColor[0.6, 0.62, 0.68, 1]];
    id];

(* 升目の中心の前 (一覧の座標系、m)。開いた PDF をそこに出す *)
(* 升目の中心 (根の座標系、m、拡大前)。パネルは根の原点が中心 (Canvas も裏板も根の中心)。UIX の升目は左上原点で y が下向き *)
idCellOffset[rec_Association, i_Integer] :=
  Module[{L = Lookup[rec, "Layout", None], ps = Lookup[rec, "Scale", 0.0006], r},
    If[!AssociationQ[L], Return[{0., 0., 0.}]];
    r = itThumbCell[L, i];
    N[{(r[[1]] + r[[3]]/2 - L["W"]/2)*ps, (L["H"]/2 - (r[[2]] + r[[4]]/2))*ps, 0.}]];

(* 雛形の保管がある一覧 *)
idBoardStash[] := SelectFirst[Lookup[Values[itThumbs[]], "Stash", None], StringQ, None];

(* ============================================================
   2. ワールド情報の仕掛けの残骸を片付ける (2026-09-25 実機: Root 直下に 4 つ溜まっていた。
   カーネルが入れ替わるたびに作り、前のカーネルの物が残る)。自分の仕掛けが組み上がっていれば、同じ名前の他の物を消す
   ============================================================ *)
(* 標準ビューアの複製ガジェットの置き場 "Mathematica PDFs" も同じ (中は ProtoFlux 5 ノードだけ。複製は置いたら外へ出す) *)
idSweepWorldInfo[kids_List] :=
  Module[{w = itWorldInfo[], d = Lookup[$itState, "PDFDup", None], stale = {}, named},
    named[name_, keep_] := Select[kids, AssociationQ[#] && StringQ[Lookup[#, "id", None]] && #["id"] =!= keep &&
      ToString[itVal[Lookup[#, "name", ""]]] === name &];
    If[AssociationQ[w] && NumericQ[Lookup[w, "Built", None]] && StringQ[Lookup[w, "Root", None]],
      stale = Join[stale, named[$itWorldInfoName, w["Root"]]]];
    If[AssociationQ[d] && StringQ[Lookup[d, "Holder", None]],
      stale = Join[stale, named["Mathematica PDFs", d["Holder"]]]];
    Scan[itNoWait @ Quiet @ Check[ResoniteRealtime`ResoniteRealtimeRemoveSlot[#["id"]], Null] &, stale];
    Lookup[stale, "id", {}]];

(* ============================================================
   3. 作業用カーネル (2026-09-25)

   監視の tick は割り込み型の評価なので、tick の中で長く塞ぐと FE の Dynamic も割り込めず、FE が
   「動的評価の放棄 (動的更新を無効にする / 引き続き待機する)」や「ノートブックコンテンツをフォーマットしています」の
   ダイアログを出す。VR の中からは閉じられない (ユーザー報告)。重い仕事は常駐の作業用カーネル 1 つに回す:
     - サムネイルの帯 (画像の読み込み・貼り合わせ・JPEG。289 件で ~40 s)
     - Eagle フォルダの一覧 (3.5-11 s。行と機密度はこのカーネルの SourceVault で作る)
     - 大きな PDF のページ数 (130 MB で 5-8 s)
   LinkLaunch は 0.02 s で戻り、カーネルは裏で ~2 s で立ち上がる (LocalSubmit は呼ぶたびに 2-3 s 呼び出し側を止める)。
   関数の定義は Language`ExtendedFullDefinition で 1 回送る (パッケージを読み直したら送り直す)。仕事は EvaluatePacket を
   書いて戻り、tick ごとに LinkReadyQ を見て ReturnPacket を拾う (待たない)。-subkernel なのでサブカーネルの席を使う。
   ============================================================ *)
If[!ValueQ[ResoniteRealtime`$ResoniteTabletWorker], ResoniteRealtime`$ResoniteTabletWorker = True];
If[!AssociationQ[$idWorker], $idWorker = <|"Link" -> None, "Phase" -> "Off", "Queue" -> {}, "Job" -> None|>];
$idWorkerJobSeconds = 600; $idWorkerStartSeconds = 60;

idWorkerExe[] := FileNameJoin[{$InstallationDirectory,
  Switch[$OperatingSystem, "Windows", "WolframKernel.exe", "MacOSX", "MacOS/WolframKernel", _, "Executables/WolframKernel"]}];
(* 送る定義はロードごとに 1 回だけ作る (毎回作ると ~1 s。2026-09-25 実測)。このファイルを読み直すと作り直す *)
$idWorkerDefsCache = None;
idWorkerDefs[] :=
  If[AssociationQ[$idWorkerDefsCache], $idWorkerDefsCache["Defs"],
    With[{d = Language`ExtendedFullDefinition[{idSheetWork, idPageCountWork, idEagleListWork, idWorkerPack}]},
      $idWorkerDefsCache = <|"Defs" -> d, "Hash" -> Hash[d]|>; d]];
idWorkerDefsHash[] := (idWorkerDefs[]; $idWorkerDefsCache["Hash"]);
idWorkerUsableQ[] := TrueQ[ResoniteRealtime`$ResoniteTabletWorker] && itTickActiveQ[];
idLinkAliveQ[l_] := Head[l] === LinkObject && MemberQ[Links[], l];

(* 仕事を積む。held = HoldComplete[f[値...]] (値は埋め込み済み)、then[結果] は tick の中で呼ぶ (結果が取れなければ $Failed) *)
idWorkSubmit[kind_String, held_HoldComplete, then_, label_String] :=
  Module[{id = StringTake[CreateUUID[], 8]},
    (* Module の変数 (Temporary) が残った式は送らない: 作業用カーネルでは未定義の記号になる *)
    If[Cases[held, x_Symbol /; MemberQ[Attributes[x], Temporary] :> HoldForm[x], {0, Infinity}, Heads -> True] =!= {},
      $itState["LastError"] = iFailure["WorkerExpr", "作業用カーネルに送る式に値の入っていない変数があります: " <> label];
      Quiet @ Check[then[$Failed], Null];
      Return[None]];
    $idWorker["Queue"] = Append[Replace[Lookup[$idWorker, "Queue", {}], Except[_List] -> {}],
      <|"Id" -> id, "Kind" -> kind, "Expr" -> held, "Then" -> then, "Label" -> label, "Queued" -> iNow[]|>];
    id];
idWorkPendingQ[id_] := MemberQ[Lookup[Join[Lookup[$idWorker, "Queue", {}], DeleteCases[{Lookup[$idWorker, "Job", None]}, None]], "Id", {}], id];

(* 大きな結果は作業用カーネルがファイル (WXF) に書き、ここはファイル名だけを受け取る (2026-09-25 実測: 2 MB の結果を
   リンクで受けると、Resonite が CPU を使っている間は作業用カーネルの書き出しが遅く、LinkReadyQ が True になった後の
   LinkRead が 8.8 s tick を止めた。ファイルなら読むのは 0.05 s) *)
idWorkerPack[r_] :=
  If[ByteCount[r] > 200000,
    With[{f = FileNameJoin[{$TemporaryDirectory, "rr_worker_" <> StringTake[CreateUUID[], 12] <> ".wxf"}]},
      If[Quiet[BinaryWrite[f, BinarySerialize[r]]; Close[f]] === f, <|"WorkerFile" -> f|>, r]],
    r];
idWorkerUnpack[r_] :=
  If[AssociationQ[r] && StringQ[Lookup[r, "WorkerFile", None]],
    With[{f = r["WorkerFile"]},
      WithCleanup[Quiet @ Check[BinaryDeserialize[ReadByteArray[f]], $Failed], Quiet[DeleteFile[f]]]],
    r];
idWorkerFinish[job_Association, result_] :=
  (With[{r = idWorkerUnpack[result]},
     $idWorker["LastResult"] = <|"Kind" -> job["Kind"], "Pid" -> If[AssociationQ[r], Lookup[r, "Pid", None], None],
       "Failed" -> (r === $Failed), "Seconds" -> Round[iNow[] - Lookup[job, "Started", iNow[]], 0.1]|>;
     Quiet @ Check[job["Then"][r], $itState["LastError"] = iFailure["WorkerThen", "作業の後始末に失敗: " <> job["Label"]]]];
   $idWorker["Job"] = None; $idWorker["Phase"] = "Ready");

idWorkerKill[why_String] :=
  Module[{w = $idWorker},
    If[idLinkAliveQ[w["Link"]], Quiet[LinkClose[w["Link"]]]];
    $itState["LastError"] = iFailure["Worker", why];
    If[AssociationQ[w["Job"]], Quiet @ Check[w["Job"]["Then"][$Failed], Null]];
    $idWorker = Join[w, <|"Link" -> None, "Phase" -> "Off", "Job" -> None|>]];

(* tick ごと: 立ち上げ → 定義を送る → 仕事を 1 つずつ送って結果を拾う。どれも待たない *)
idWorkerStep[] :=
  Module[{w = $idWorker, link, p, job, defs, n},
    If[Lookup[w, "Queue", {}] === {} && Lookup[w, "Job", None] === None && !MemberQ[{"Starting", "Defs"}, w["Phase"]], Return[None]];
    link = w["Link"];
    If[!idLinkAliveQ[link],
      link = Quiet @ Check[LinkLaunch["\"" <> idWorkerExe[] <> "\" -subkernel -noinit -wstp"], $Failed];
      (* すぐ LinkActivate する (0.2 s)。しないと LinkReadyQ は接続前から True を返し、最初の LinkRead がカーネルの
         立ち上がり (2-9 s。Resonite が動いていると遅い) まで tick を止めた (2026-09-25 実測)。LinkActivate の後は
         InputNamePacket が届くまで LinkReadyQ は False *)
      If[Head[link] === LinkObject, If[Head[Quiet @ Check[LinkActivate[link], $Failed]] =!= LinkObject, Quiet[LinkClose[link]]; link = $Failed]];
      If[Head[link] =!= LinkObject,
        (* 起動できない: 積んだ仕事は失敗として後始末へ (呼び出し側が代わりの手を打つ) *)
        Scan[Quiet @ Check[#["Then"][$Failed], Null] &, Lookup[w, "Queue", {}]];
        $idWorker = Join[w, <|"Link" -> None, "Phase" -> "Off", "Queue" -> {}, "Job" -> None|>];
        $itState["LastError"] = iFailure["Worker", "作業用カーネルを起動できません"];
        Return[None]];
      $idWorker = Join[w, <|"Link" -> link, "Phase" -> "Starting", "Since" -> iNow[], "DefsHash" -> None|>];
      Return[None]];
    Switch[w["Phase"],
      "Starting",
        While[LinkReadyQ[link],
          p = LinkRead[link, Hold];
          If[MatchQ[p, Hold[InputNamePacket[___]]],
            defs = idWorkerDefs[];
            With[{d = defs}, LinkWrite[link, Unevaluated[EvaluatePacket[Language`ExtendedFullDefinition[] = d; Null]]]];
            $idWorker = Join[$idWorker, <|"Phase" -> "Defs", "DefsHash" -> idWorkerDefsHash[], "Since" -> iNow[]|>];
            Return[None]]];
        If[iNow[] - w["Since"] > $idWorkerStartSeconds, idWorkerKill["作業用カーネルが立ち上がりません"]],
      "Defs",
        While[LinkReadyQ[link], p = LinkRead[link, Hold];
          If[MatchQ[p, Hold[ReturnPacket[_]]], $idWorker["Phase"] = "Ready"; Return[None]]];
        If[iNow[] - w["Since"] > $idWorkerStartSeconds, idWorkerKill["作業用カーネルに定義を送れません"]],
      "Ready",
        (* パッケージを読み直して定義が変わっていたら送り直す *)
        If[idWorkerDefsHash[] =!= w["DefsHash"],
          With[{d = idWorkerDefs[]}, LinkWrite[link, Unevaluated[EvaluatePacket[Language`ExtendedFullDefinition[] = d; Null]]]];
          $idWorker = Join[$idWorker, <|"Phase" -> "Defs", "DefsHash" -> idWorkerDefsHash[], "Since" -> iNow[]|>];
          Return[None]];
        If[w["Queue"] =!= {},
          job = First[w["Queue"]];
          job["Expr"] /. HoldComplete[x_] :> LinkWrite[link, Unevaluated[EvaluatePacket[idWorkerPack[x]]]];
          $idWorker = Join[$idWorker, <|"Queue" -> Rest[w["Queue"]], "Job" -> Append[job, "Started" -> iNow[]], "Phase" -> "Busy"|>]],
      "Busy",
        job = w["Job"];
        (* 結果は評価せずに受け取る。作業用の関数が評価されずに戻って来た (引数の型違い等) なら失敗 — ここで評価すると
           重い仕事をこのカーネルでやってしまう (2026-09-25 実測: Module の変数を渡し忘れて一覧取得がこちらで 10 s 走った) *)
        While[LinkReadyQ[link], p = LinkRead[link, Hold];
          If[MatchQ[p, Hold[ReturnPacket[_]]],
            idWorkerFinish[job, Replace[p, {
              Hold[ReturnPacket[(idSheetWork | idPageCountWork | idEagleListWork | idWorkerPack)[___]]] -> $Failed,
              Hold[ReturnPacket[x_]] :> x}]];
            Return[None]]];
        If[iNow[] - job["Started"] > $idWorkerJobSeconds, idWorkerKill["作業が終わりません: " <> job["Label"]]; Return[None]];
        (* 経過をタブレットの状態に (ターンの最中は書かない) *)
        n = Round[iNow[] - job["Queued"]];
        If[n =!= Lookup[w, "ShownSec", None] && !TrueQ[Quiet @ Check[itTurnActiveQ[], False]],
          itSetStatus[job["Label"] <> "… " <> ToString[n] <> " 秒 (別カーネル)"]; $idWorker["ShownSec"] = n],
      _, Null]];

(* 作業用カーネルを止める (次に仕事が来たら立ち上げ直す) *)
ResoniteRealtime`ResoniteTabletWorkerStop[] :=
  (If[idLinkAliveQ[$idWorker["Link"]], Quiet[LinkClose[$idWorker["Link"]]]];
   $idWorker = <|"Link" -> None, "Phase" -> "Off", "Queue" -> {}, "Job" -> None|>; Null);
ResoniteRealtime`ResoniteTabletWorkerStatus[] :=
  <|"Phase" -> $idWorker["Phase"], "Alive" -> idLinkAliveQ[$idWorker["Link"]], "Queue" -> Lookup[Lookup[$idWorker, "Queue", {}], "Label", {}],
    "Job" -> If[AssociationQ[$idWorker["Job"]], KeyTake[$idWorker["Job"], {"Id", "Kind", "Label", "Queued"}], None],
    "SlowTicks" -> Lookup[$itState, "SlowTicks", {}]|>;

(* ---- 作業用カーネルで動く関数 (このカーネルの状態に触れない。定義ごと送る) ---- *)
idReadImage[src_String] :=
  With[{fmt = itImageFormat[src]},
    Replace[itFirstImage[Quiet @ Check[If[fmt === Automatic, Import[src], Import[src, fmt]], $Failed]],
      $Failed :> If[fmt === Automatic, $Failed, itFirstImage[Quiet @ Check[Import[src], $Failed]]]]];
(* PDF の 1 ページ目 (40 dpi)。配信ディレクトリに thpdf_<鍵>.png でキャッシュ (このカーネルの itThumbImage と共有) *)
idPdfFirstPage[file_String, assetDir_String] :=
  Module[{key, cache, img},
    key = StringTake[Hash[{file, FileByteCount[file], Quiet[FileDate[file]]}, "SHA256", "HexString"], 16];
    cache = FileNameJoin[{assetDir, "thpdf_" <> key <> ".png"}];
    If[FileExistsQ[cache], Return[Quiet @ Check[Import[cache], $Failed]]];
    img = Quiet @ Check[TimeConstrained[Import[file, {"PDF", "PageImages", {1}}, ImageResolution -> 40], 8, $Failed], $Failed];
    img = If[ListQ[img] && img =!= {} && ImageQ[First[img]], First[img], $Failed];
    If[ImageQ[img], Quiet @ Check[Export[cache, img, "PNG"], Null]];
    img];
(* 帯を作って書く。読めない画像があれば "p" の名前に書く (次はキャッシュにしない) *)
idSheetWork[srcs_List, exts_List, L_Association, files_List, filesP_List, cols_Integer, assetDir_String] :=
  Module[{t0 = AbsoluteTime[], cut = False, imgs, out},
    imgs = Map[Which[
        # === None, $Failed,
        MatchQ[#, {"PDF", _String}], If[AbsoluteTime[] - t0 > 20, cut = True; $Failed, idPdfFirstPage[#[[2]], assetDir]],
        StringQ[#], idReadImage[#],
        True, $Failed] &, srcs];
    If[MemberQ[MapThread[#1 =!= None && !ImageQ[#2] &, {srcs, imgs}], True], cut = True];
    out = If[cut, filesP, files];
    Block[{$itThumbStripCols = cols},
      MapThread[Quiet @ Check[Export[#1, #2[[1]], "JPEG", "CompressionLevel" -> 0.15], Null] &, {out, itThumbStrips[imgs, exts, L]}]];
    <|"Files" -> out, "Cut" -> cut, "Seconds" -> Round[AbsoluteTime[] - t0, 0.1], "Pid" -> $ProcessID|>];
(* Check は使わない: 新しいカーネルで最初に PDF を読むと無害なメッセージが出て、数えられているのに 0 になった (2026-09-25) *)
idPageCountWork[file_String] := Replace[Quiet[Import[file, "PageCount"]], Except[_Integer?Positive] -> 0];
(* Eagle のフォルダの item (SourceVault_eagle.wl を作業用カーネルで読む。関数名は文字列にして定義を持ち込まない) *)
idEagleListWork[pkgFile_String, folder_String, lib_String, rec_] :=
  With[{f = ToExpression["SourceVault`SourceVaultEagleItemsInFolder"]},
    If[DownValues[f] === {}, Block[{$CharacterEncoding = "UTF-8"}, Quiet @ Get[pkgFile]]];
    Quiet @ Check[f[folder, "Library" -> lib, "Recursive" -> TrueQ[rec]], $Failed]];

(* ---- サムネイルの帯: キャッシュに無ければ作業用カーネルへ ---- *)
idMaybeSheetJob[rowsIn_, opts_List] :=
  Module[{o, plan, id, dir = ResoniteRealtime`ResoniteRealtimeAsset[]},
    If[!idWorkerUsableQ[] || !itBuildModeTick[] || !itLinkQ[] || !StringQ[dir], Return[None]];
    o = Association @ Join[Options[ResoniteRealtime`ResoniteThumbnailGadget], opts];
    plan = itThumbPlan[rowsIn, o];
    If[plan["Shown"] === {} || AllTrue[plan["Files"], FileExistsQ], Return[None]];   (* 速い道: そのまま組む *)
    id = StringTake[CreateUUID[], 8];
    $itDeferred[id] = <|"Expr" -> None, "Label" -> "サムネイル一覧", "Time" -> iNow[], "Status" -> "Pending", "Via" -> "Worker"|>;
    (* 送る式には値を埋め込む (Module の変数のまま送ると作業用カーネルでは未定義の記号になる) *)
    With[{srcs = plan["Srcs"], exts = plan["Exts"], L = plan["Layout"], files = plan["Files"], filesP = plan["FilesP"],
          cols = $itThumbStripCols, key = plan["Key"], rows = rowsIn, os = opts, bid = id, dir = dir},
      idWorkSubmit["Sheet", HoldComplete[idSheetWork[srcs, exts, L, files, filesP, cols, dir]],
        Function[res,
          If[AssociationQ[res] && ListQ[res["Files"]] && AllTrue[res["Files"], FileExistsQ],
            itEnqueueBuild["サムネイル一覧",
              Function[Block[{$idSheetOverride = <|"Key" -> key, "Files" -> res["Files"]|>},
                itThumbGadgetBuild[rows, Sequence @@ os]]], bid],
            (* 作業用カーネルが使えなかった: このカーネルで作る (少し止まる) *)
            itSetStatus["作業用カーネルが使えないので、このカーネルでサムネイルを作ります (少し止まります)"];
            itEnqueueBuild["サムネイル一覧", Function[itThumbGadgetBuild[rows, Sequence @@ os]], bid]]],
        "サムネイルを作っています (" <> ToString[Length[plan["Shown"]]] <> " 件)"]];
    <|"Deferred" -> True, "Id" -> id, "Via" -> "Worker", "Kind" -> "ThumbnailGadget", "Rows" -> Length[plan["Shown"]]|>];

(* ---- Eagle のフォルダ: 一覧は作業用カーネル、行 (機密度) はこのカーネル ---- *)
idMaybeEagleJob[folder_String, view_String, opts_List] :=
  Module[{o, lib, pkg, id},
    If[!idWorkerUsableQ[] || !itBuildModeTick[] || !itLinkQ[], Return[None]];
    If[icSym["SourceVault`SourceVaultEagleSummaryRow"] === None, Return[None]];
    lib = icSym["SourceVault`$SourceVaultEagleLibrary"];
    pkg = FileNameJoin[{$iPackageDirectory, "SourceVault_eagle.wl"}];
    If[!StringQ[lib] || !DirectoryQ[lib] || !FileExistsQ[pkg], Return[None]];
    o = Association @ Join[Options[ResoniteRealtime`ResoniteEagleFolderGadget], opts];
    id = StringTake[CreateUUID[], 8];
    $itDeferred[id] = <|"Expr" -> None, "Label" -> "Eagle フォルダ " <> folder, "Time" -> iNow[], "Status" -> "Pending", "Via" -> "Worker"|>;
    With[{oo = o, fv = folder, vv = view, bid = id, rec = TrueQ[o["Recursive"]], pkg = pkg, lib = lib},
      idWorkSubmit["EagleList", HoldComplete[idEagleListWork[pkg, fv, lib, rec]],
        Function[items,
          (* 行 (機密度) はこのカーネルの SourceVault で、tick ごとに少しずつ作る (289 件で 0.6-1.8 s) *)
          With[{rowF = icSym["SourceVault`SourceVaultEagleSummaryRow"]},
            If[!ListQ[items] || rowF === None,
              idEagleFolderDone[bid, fv, iFailure["EagleFolder", "Eagle のフォルダ " <> fv <> " を読めませんでした"], {}],
              idChunkSubmit[Select[items, AssociationQ], Function[it, Quiet @ Check[rowF[it], $Failed]],
                Function[rows0,
                  Module[{rows = Select[rows0, AssociationQ], title = Replace[oo["Title"], Automatic -> "Eagle: " <> fv]},
                    If[Lookup[oo, "Ext", All] =!= All,
                      rows = Select[rows, MemberQ[ToLowerCase /@ Flatten[{oo["Ext"]}], ToLowerCase[ToString[Lookup[#, "Ext", ""]]]] &]];
                    idEagleFolderDone[bid, fv,
                      If[vv === "Thumbnails",
                        ResoniteRealtime`ResoniteThumbnailGadget[rows, "Title" -> title, "Name" -> itBoardSlotName[fv]],
                        ResoniteRealtime`ResoniteListGadget[rows, "Title" -> title]], rows]]],
                "Eagle フォルダ " <> fv <> " の行を作っています"]]]],
        "Eagle フォルダ " <> folder <> " を読んでいます"]];
    <|"Deferred" -> True, "Id" -> id, "Via" -> "Worker", "Kind" -> "EagleFolder", "Folder" -> folder, "View" -> view|>];

idEagleFolderDone[bid_String, fv_String, r_, rows_List] :=
  ($itDeferred[bid] = Join[Lookup[$itDeferred, bid, <||>],
     <|"Status" -> If[FailureQ[r], "Failed", "Done"], "Result" -> r, "Finished" -> iNow[]|>];
   If[FailureQ[r], itSetStatus[ToString[r["MessageTemplate"]]],
     itSetStatus["Eagle フォルダ " <> fv <> ": " <> ToString[Length[rows]] <> " 件"]]);

(* ---- 小分けの仕事: items に f を tick ごとに $idChunkSeconds ぶんずつ当て、終わったら then[結果] ---- *)
$idChunkSeconds = 0.3;
idChunkSubmit[items_List, f_, then_, label_String] :=
  ($itState["ChunkJobs"] = Append[Replace[Lookup[$itState, "ChunkJobs", {}], Except[_List] -> {}],
     <|"Items" -> items, "Pos" -> 0, "Out" -> {}, "F" -> f, "Then" -> then, "Label" -> label, "Time" -> iNow[]|>];
   Length[items]);
idProcessChunkJobs[] :=
  Module[{jobs = Replace[Lookup[$itState, "ChunkJobs", {}], Except[_List] -> {}], j, t0 = iNow[], pos, n, out},
    If[jobs === {}, Return[None]];
    j = First[jobs]; pos = j["Pos"]; n = Length[j["Items"]]; out = j["Out"];
    While[pos < n && (pos === j["Pos"] || iNow[] - t0 < $idChunkSeconds),
      pos++; AppendTo[out, j["F"][j["Items"][[pos]]]]];
    If[pos < n,
      $itState["ChunkJobs"] = ReplacePart[jobs, 1 -> Join[j, <|"Pos" -> pos, "Out" -> out|>]];
      If[!TrueQ[Quiet @ Check[itTurnActiveQ[], False]],
        itSetStatus[j["Label"] <> " (" <> ToString[pos] <> " / " <> ToString[n] <> ")"]];
      Return[pos]];
    $itState["ChunkJobs"] = Rest[jobs];
    Quiet @ Check[j["Then"][out], $itState["LastError"] = iFailure["Chunk", "小分けの仕事の後始末に失敗: " <> j["Label"]]];
    n];

(* ---- PDF のページ数: 小さい物はその場で、大きい物は作業用カーネルで (分かるまで 0) ---- *)
$idPageCountInlineBytes = 5*10^6;
idPageKey[file_String] := Hash[{file, Quiet[FileByteCount[file]], Quiet[FileDate[file]]}, "SHA256", "HexString"];
idPageCounts[] := Replace[Lookup[$itState, "PageCounts", <||>], Except[_Association] -> <||>];
idPageCountCached[file_String] := Lookup[idPageCounts[], idPageKey[file], None];
idPageCountPendingQ[file_String] := KeyExistsQ[Replace[Lookup[$itState, "PageCountJobs", <||>], Except[_Association] -> <||>], idPageKey[file]];
idPageCount[file_String] :=
  Module[{k = idPageKey[file], c, n},
    c = Lookup[idPageCounts[], k, None];
    If[IntegerQ[c], Return[c]];
    If[!FileExistsQ[file], Return[0]];
    If[Quiet[FileByteCount[file]] <= $idPageCountInlineBytes || !idWorkerUsableQ[],
      n = idPageCountWork[file];
      If[n > 0, $itState["PageCounts"] = Append[idPageCounts[], k -> n]];   (* 数えられたときだけ覚える *)
      Return[n]];
    If[!idPageCountPendingQ[file] && iNow[] - Lookup[Replace[Lookup[$itState, "PageCountFailed", <||>], Except[_Association] -> <||>], k, -10^6] > 60,
      With[{kk = k, ff = file},
        $itState["PageCountJobs"] = Append[Replace[Lookup[$itState, "PageCountJobs", <||>], Except[_Association] -> <||>],
          kk -> idWorkSubmit["PageCount", HoldComplete[idPageCountWork[ff]],
            Function[n2,
              If[IntegerQ[n2] && n2 > 0, $itState["PageCounts"] = Append[idPageCounts[], kk -> n2],
                (* 数えられなかった (書きかけのファイル等): 覚えず、1 分後に数え直す *)
                $itState["PageCountFailed"] = Append[Replace[Lookup[$itState, "PageCountFailed", <||>], Except[_Association] -> <||>],
                  kk -> iNow[]]];
              $itState["PageCountJobs"] = KeyDrop[$itState["PageCountJobs"], kk]],
            "PDF のページ数を数えています"]]]];
    0];

End[];
EndPackage[];
