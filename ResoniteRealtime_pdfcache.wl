(* ::Package:: *)

(* ResoniteRealtime_pdfcache.wl -- フレンドにも PDF が見えるように、web サーバに一時的な写しを置く

   This file is encoded in UTF-8.
   ResoniteRealtime.wl が毎回ロードする (同じ ResoniteRealtime` コンテキスト。タブレット / docboard の部品の上に載る)。

   ---- なぜ要るか (2026-09-25) ----
   標準ビューアの StaticDocument.URL (と文書表示) は http://127.0.0.1:<port>/a/... を指す。HTTP の URL 資産は
   **各クライアントが自分で取りに行く**ので、フレンドの PC の 127.0.0.1 には何も無く、中身が見えない。

   ---- 何をするか (2026-09-25 ユーザー指示) ----
   ワールドが Private か Contacts (フレンド) で、自分がオーナーのときだけ、PDF を初めてワールドに出すときに
   利用者が設定した web サーバへ sftp で送り、
       <$ResonitePDFCacheBaseURL>/<SHA-256>.pdf
   を StaticDocument.URL にする (全員がこの URL を読む)。
     - 名前は**中身の SHA-256** (ファイル名のハッシュだと、名前を知っている人に URL を当てられ、
       中身が変わっても古い写しを指す)。同じ PDF は何度開いても同じ URL、送るのは 1 回。
     - 送る前に HEAD で確かめ、同じ大きさで置いてあればそのまま使う (前に送った物 / 別の PC が送った物)。
       サーバから消されていたら、その都度送り直す (開くたびに HEAD で確かめる。60 s 以内に確かめた物は省く)。
     - 送っている間は 127.0.0.1 で開き (オーナーはすぐ見える)、送り終わったら URL を差し替える。
     - 送り先に部分的なファイルを見せない: <hash>.pdf.part に送ってから rename する。
     - 機密度が $ResonitePDFCacheMaxLevel (既定 0.5) を超える PDF は送らない (オーナーだけに見える)。
       ワールドの表示上限とは別の、外のサーバに置いてよいかの上限。機密度が数値で取れない物も送らない。
   通信はすべて Git for Windows 同梱の sftp 対応 curl を StartProcess で走らせ、tick で終わりを拾う (待たない)。
   パスワードは NBAccess の SystemCredential (ResonitePDFCacheCredential[] で保存) を curl の標準入力の設定で渡す
   (コマンドラインに出さない)。資格情報の名前は既定で sftp://<user>@<host> (= アカウントの名前)。

   ---- 他のパッケージとの分離 (2026-09-26 ユーザー指示「片方だけ使う人、両方で別々のサーバを使いたい人もいる」) ----
   このパッケージのサーバ設定は自分の設定ファイルだけ (SlideWorkflow 等の設定は読まないし書かない。コードの依存も無い)。
   同じサーバの別のフォルダを別のパッケージが使うのは構わない。重なりうるのは資格情報の名前だけで、既定の名前はアカウント
   (user@host) で決まるので、
     - 同じアカウントなら 1 回保存したパスワードを両方が使う (同じアカウントのパスワードは同じなので正しい共有)
     - サーバかアカウントが違えば名前も違い、別々に保存される
   同じアカウントでもパッケージごとに分けたいときは ResonitePDFCacheSetup[..., "Credential" -> "名前"] で専用の名前にする
   (設定ファイルに名前だけ残す)。既定の名前のまま ResonitePDFCacheCredential[None] で消すと、同じアカウントを使う他のパッケージの
   パスワードも消えるので、戻り値で知らせる。
   SystemCredential に触るのは NBAccess だけ (NBGetCredential / NBSetCredential / NBRemoveCredential / NBCredentialConfiguredQ)。

   ---- サーバの設定 (2026-09-26、公開リポジトリ化) ----
   ソースにはサーバ名もアカウントもパスワードも書かない。置き場所は PC ごとの設定ファイル
   ($UserBaseDirectory/ApplicationData/ResoniteRealtime/pdfcache_server.json、ResonitePDFCacheSetup[upload, base] が書く)。
   設定が無ければ写しは置かず (オーナーだけに見える)、状態欄と ResonitePDFCacheStatus[] で設定の仕方を案内する。

   ---- 著作権 ----
   ワールドの設定でオーナー以外の保存を禁じる (ユーザーの運用)。ただし URL 自体はインスペクタ等で見え、
   ブラウザで直接取れるので、使い終わったら ResonitePDFCacheClear[] で消す。
*)

BeginPackage["ResoniteRealtime`"];

ResoniteRealtime`$ResonitePDFCache::usage =
  "$ResonitePDFCache (既定 True): ワールドが Private / Contacts でオーナーのとき、PDF を初めてワールドに出す際に web サーバへ\n" <>
  "一時的な写し (<SHA-256>.pdf) を置き、StaticDocument の URL をそれにする (フレンドにも見えるように)。False なら置かない。";
ResoniteRealtime`$ResonitePDFCacheBaseURL::usage =
  "$ResonitePDFCacheBaseURL は写しを読む URL の頭 (例 \"https://www.example.org/cache\")。既定は設定ファイル\n" <>
  "(ResonitePDFCacheSetup で保存) の値、無ければ None (写しを置かない)。";
ResoniteRealtime`$ResonitePDFCacheUploadURL::usage =
  "$ResonitePDFCacheUploadURL は写しを置く sftp の場所 (例 \"sftp://user@www.example.org/home/user/www/cache\")。既定は設定ファイルの値、\n" <>
  "無ければ None。パスワードは ResonitePDFCacheCredential[] で NBAccess 経由で保存する。";
ResoniteRealtime`ResonitePDFCacheSetup::usage =
  "ResonitePDFCacheSetup[\"sftp://user@host/path/to/www/cache\", \"https://host/cache\"] はフレンド用の PDF の写しを置くサーバを\n" <>
  "この PC に設定する (設定ファイル $UserBaseDirectory/ApplicationData/ResoniteRealtime/pdfcache_server.json に保存。ソースには書かない)。\n" <>
  "1 つ目は sftp で書き込む場所、2 つ目はそのディレクトリを https で読む URL。続けて ResonitePDFCacheCredential[] でパスワードを保存する。\n" <>
  "ResonitePDFCacheSetup[] は今の設定と案内、ResonitePDFCacheSetup[None] は設定を消す (写しを置かなくなる)。\n" <>
  "オプション \"Credential\" -> Automatic (既定: パスワードの名前 = sftp://user@host。同じアカウントを使う他のパッケージと共有) | \"名前\"\n" <>
  "(このパッケージ専用の名前。同じアカウントでもパスワードを分けて保存する)。設定は他のパッケージ (SlideWorkflow 等) と独立。";
ResoniteRealtime`ResonitePDFCacheCredential::usage =
  "ResonitePDFCacheCredential[] はキャッシュサーバの sftp パスワードをダイアログで尋ね、NBAccess 経由で SystemCredential に保存する\n" <>
  "(名前 = sftp://user@host。値はソースにもノートブックにも残らない)。ResonitePDFCacheCredential[password] で直接、\n" <>
  "ResonitePDFCacheCredential[None] で削除。名前が既定 (アカウント名) なら、同じアカウントを使う他のパッケージ (SlideWorkflow の\n" <>
  "SlideUploadCredential など) と同じ保存場所を共有する (戻り値の \"Shared\")。分けるには ResonitePDFCacheSetup の \"Credential\" で専用の名前に。";
ResoniteRealtime`$ResonitePDFCacheMaxLevel::usage =
  "$ResonitePDFCacheMaxLevel (既定 0.5): 機密度 (PrivacyLevel) がこれを超える PDF はサーバに置かない (オーナーだけに見える)。";
ResoniteRealtime`ResonitePDFCacheStatus::usage =
  "ResonitePDFCacheStatus[] は写しの状態 (<|hash -> <|\"Status\", \"Title\", \"URL\", \"Bytes\", \"Error\"|>|>) を返す。\n" <>
  "ResonitePDFCacheStatus[\"Skipped\"] は機密度が $ResonitePDFCacheMaxLevel を超えたので置かなかった PDF (直近 20)。";
ResoniteRealtime`ResonitePDFCacheRetry::usage =
  "ResonitePDFCacheRetry[] は失敗した写し (パスワード違い・通信失敗など) を確かめ直して送り直す。パスワード未保存で止まった物は、\n" <>
  "ResonitePDFCacheCredential[] で保存すれば 10 秒以内に自動で送り直すので呼ばなくてよい。";
ResoniteRealtime`ResonitePDFCacheList::usage =
  "ResonitePDFCacheList[] はサーバの cache に置いてある写しの名前を返す (sftp で一覧。待つ)。";
ResoniteRealtime`ResonitePDFCacheClear::usage =
  "ResonitePDFCacheClear[] はこの PC が置いた写し (台帳にある物) をサーバから消す。ResonitePDFCacheClear[All] は cache の\n" <>
  "*.pdf をすべて消す。ResonitePDFCacheClear[\"OlderThan\" -> days] は台帳で days 日より前に置いた物だけ。\n" <>
  "ResonitePDFCacheClear[{hash, ...}] は指定した物。戻り値: 消した名前のリスト。\n" <>
  "サムネイル一覧の見出しの「キャッシュ削除」ボタンは、どのフォルダの物かに関係なく cache の写し (<SHA-256>.pdf) をすべて消す\n" <>
  "(監視の tick で待たずに一覧 -> 削除。置いたビューアは 127.0.0.1 の URL に戻す)。";

Begin["`Private`"];

If[!BooleanQ[ResoniteRealtime`$ResonitePDFCache], ResoniteRealtime`$ResonitePDFCache = True];
(* ---- サーバの設定ファイル (PC ごと。ソースにサーバ名を書かない。2026-09-26) ---- *)
ipcConfigFile[] := FileNameJoin[{$UserBaseDirectory, "ApplicationData", "ResoniteRealtime", "pdfcache_server.json"}];
ipcReadConfig[] :=
  With[{f = ipcConfigFile[]},
    If[!FileExistsQ[f], <||>,
      Replace[Quiet @ Check[ImportByteArray[ReadByteArray[f], "RawJSON"], <||>], Except[_Association] -> <||>]]];
(* ロード時: 変数が文字列でなければ設定ファイルから (再ロードで公開記号は消えるので、設定はファイルが正本) *)
If[!StringQ[ResoniteRealtime`$ResonitePDFCacheBaseURL],
  ResoniteRealtime`$ResonitePDFCacheBaseURL = Replace[Lookup[ipcReadConfig[], "BaseURL", None], Except[_String] -> None]];
If[!StringQ[ResoniteRealtime`$ResonitePDFCacheUploadURL],
  ResoniteRealtime`$ResonitePDFCacheUploadURL = Replace[Lookup[ipcReadConfig[], "UploadURL", None], Except[_String] -> None]];
$ipcSetupGuide =
  "フレンドにも PDF を見せるキャッシュサーバが未設定です。ResonitePDFCacheSetup[\"sftp://user@host/path/www/cache\", " <>
  "\"https://host/cache\"] で設定し、ResonitePDFCacheCredential[] でパスワードを保存してください";
If[!NumericQ[ResoniteRealtime`$ResonitePDFCacheMaxLevel], ResoniteRealtime`$ResonitePDFCacheMaxLevel = 0.5];

(* 状態 (再ロードで壊さない): key (= SHA-256) -> 記録 *)
If[!AssociationQ[$ipcCache], $ipcCache = <||>];
If[!AssociationQ[$ipcHashMemo], $ipcHashMemo = <||>];
If[!ListQ[$ipcSkipped], $ipcSkipped = {}];   (* 機密度で置かなかった PDF (診断用、直近 20) *)
$ipcVerifySeconds = 60;         (* これより前に確かめた写しは、開くときにもう一度 HEAD で確かめる *)
$ipcHeadSeconds = 30;           (* HEAD の打ち切り *)
$ipcUploadSeconds = 1800;       (* 送信の打ち切り (大きな PDF) *)

(* ---- 小物 ---- *)

ipcEnabledQ[] := TrueQ[ResoniteRealtime`$ResonitePDFCache];
(* サーバが設定済みか (両方の URL が文字列で、sftp の場所が sftp://user@host/dir の形) *)
ipcConfiguredQ[] :=
  StringQ[ResoniteRealtime`$ResonitePDFCacheBaseURL] && StringQ[ResoniteRealtime`$ResonitePDFCacheUploadURL] &&
    AssociationQ[ipcTarget[]];

(* 置いてよいワールドか: 公開度 Private / Contacts で、自分がオーナー (自動判定が済んでいる) *)
ipcWorldOKQ[] :=
  TrueQ[ResoniteRealtime`$ResoniteWorldOwner] &&
    MemberQ[{"Private", "Contacts"}, ResoniteRealtime`$ResoniteWorldAccess];

ipcLevelOKQ[pl_] := itPL[pl] <= N[ResoniteRealtime`$ResonitePDFCacheMaxLevel] + 10^-9;

(* 中身の SHA-256 (パス・大きさ・更新時刻で覚える。130 MB で 0.5 s 前後) *)
ipcHash[file_String] :=
  Module[{k = {ExpandFileName[file], Quiet[FileByteCount[file]], Quiet[AbsoluteTime[FileDate[file]]]}, h},
    h = Lookup[$ipcHashMemo, Key[k], None];
    If[StringQ[h], Return[h]];
    h = Quiet @ Check[FileHash[file, "SHA256", All, "HexString"], $Failed];
    If[!StringQ[h], Return[$Failed]];
    h = ToLowerCase[h];
    If[Length[$ipcHashMemo] > 500, $ipcHashMemo = <||>];
    $ipcHashMemo[k] = h];

ipcPublicURL[key_String] := StringTrim[ResoniteRealtime`$ResonitePDFCacheBaseURL, "/"] <> "/" <> key <> ".pdf";

ipcTarget[] :=
  Module[{p, segs},
    If[!StringQ[ResoniteRealtime`$ResonitePDFCacheUploadURL], Return[$Failed]];
    p = Quiet @ Check[URLParse[ResoniteRealtime`$ResonitePDFCacheUploadURL], $Failed];
    (* パスワード入りの URL (user:password@host) は使わない (資格情報の名前やコマンドラインに出さない。パスワードは NBAccess) *)
    If[!AssociationQ[p] || ToLowerCase[ToString[Lookup[p, "Scheme", ""]]] =!= "sftp" || !StringQ[Lookup[p, "User", None]] ||
       StringContainsQ[p["User"], ":"],
      Return[$Failed]];
    segs = Select[Replace[Lookup[p, "Path", {}], {s_String :> StringSplit[s, "/"], Except[_List] -> {}}], StringQ[#] && # =!= "" &];
    <|"User" -> p["User"], "Host" -> p["Domain"] <> If[IntegerQ[Lookup[p, "Port", None]], ":" <> ToString[p["Port"]], ""],
      "Dir" -> "/" <> StringRiffle[segs, "/"]|>];

(* 資格情報の名前: 設定ファイルに専用の名前 ("Credential") があればそれ、無ければアカウント名 sftp://user@host
   (同じアカウントを使う他のパッケージと共有される) *)
ipcAccountCredName[t_Association] := "sftp://" <> t["User"] <> "@" <> t["Host"];
ipcCredName[t_Association] :=
  With[{n = Lookup[ipcReadConfigCached[], "Credential", None]}, If[StringQ[n] && StringTrim[n] =!= "", n, ipcAccountCredName[t]]];
ipcSharedCredQ[t_Association] := ipcCredName[t] === ipcAccountCredName[t];
(* 設定ファイルは tick ごとに読まない (更新時刻で覚える) *)
If[!ValueQ[$ipcConfigMemo], $ipcConfigMemo = {None, <||>}];
ipcReadConfigCached[] :=
  With[{f = ipcConfigFile[]},
    With[{k = {f, If[FileExistsQ[f], Quiet[FileDate[f]], None]}},
      If[$ipcConfigMemo[[1]] === k, $ipcConfigMemo[[2]], Last[$ipcConfigMemo = {k, ipcReadConfig[]}]]]];

ipcRemoteURL[t_Association, name_String] := "sftp://" <> t["Host"] <> t["Dir"] <> "/" <> name;

(* パスワード (値はこの層の外へ出さない)。NBAccess の SystemCredential *)
ipcNBAccessQ[] := Length[DownValues[NBAccess`NBGetCredential]] > 0;
ipcPassword[t_Association] :=
  If[!ipcNBAccessQ[], None,
    With[{v = Quiet @ Check[NBAccess`NBGetCredential[ipcCredName[t]], None]}, If[StringQ[v] && v =!= "", v, None]]];
(* 値を取らずに「保存済みか」だけ (パスワード待ちの自動再試行に使う) *)
ipcCredQ[t_Association] := ipcNBAccessQ[] && TrueQ[Quiet @ Check[NBAccess`NBCredentialConfiguredQ[ipcCredName[t]], False]];
ipcNoCredMessage[t_Association] :=
  If[!ipcNBAccessQ[],
    "NBAccess がこのカーネルに読み込まれていないので sftp のパスワードを取れません (Needs[\"NBAccess`\"])",
    "sftp のパスワード (" <> ipcCredName[t] <> ") がこの PC に保存されていません。ResonitePDFCacheCredential[] で保存すると" <>
      "自動で送り直します"];
$ipcCredRetrySeconds = 10;      (* パスワード待ちの写しを、保存されたか確かめる間隔 *)

(* sftp の使える curl (System32 の curl は sftp 非対応。SlideWorkflow と同じ探し方) *)
If[!ValueQ[$ipcCurl], $ipcCurl = None];
ipcCurl[] :=
  Module[{cands},
    If[StringQ[$ipcCurl], Return[$ipcCurl]];
    If[$ipcCurl === False, Return[None]];
    cands = Select[Flatten[{
        Map[Function[pf, If[StringQ[pf],
          {FileNameJoin[{pf, "Git", "mingw64", "bin", "curl.exe"}], FileNameJoin[{pf, "Git", "usr", "bin", "curl.exe"}]}, {}]],
          {Environment["ProgramFiles"], Environment["ProgramW6432"]}]}], FileExistsQ];
    $ipcCurl = SelectFirst[cands,
      Function[exe, With[{out = Quiet @ Check[RunProcess[{exe, "--version"}, "StandardOutput"], ""]},
        StringQ[out] && StringContainsQ[out, "sftp"]]], False];
    If[StringQ[$ipcCurl], $ipcCurl, None]];

ipcQuote[s_String] := "\"" <> StringReplace[s, {"\\" -> "\\\\", "\"" -> "\\\""}] <> "\"";

(* curl を裏で走らせる。cfg (パスワード等) は標準入力の設定 (-K -) で渡し、すぐ閉じる *)
ipcStart[args_List, cfg_String] :=
  Module[{exe = ipcCurl[], p},
    If[!StringQ[exe], Return[Failure["NoCurl", <|"MessageTemplate" -> "sftp の使える curl (Git for Windows 同梱) がありません。"|>]]];
    p = Quiet @ Check[StartProcess[Join[{exe}, args, {"-K", "-"}]], $Failed];
    If[Head[p] =!= ProcessObject, Return[Failure["CurlStart", <|"MessageTemplate" -> "curl を起動できませんでした。"|>]]];
    Quiet @ Check[(WriteString[p, cfg]; Close[ProcessConnection[p, "StandardInput"]]), Null];
    p];

(* 終わった curl の結果 (走っていれば None) *)
ipcFinished[p_ProcessObject] :=
  If[ProcessStatus[p] === "Running", None,
    <|"ExitCode" -> Quiet[ProcessInformation[p, "ExitCode"]],
      "Out" -> Replace[Quiet @ Check[ReadString[ProcessConnection[p, "StandardOutput"]], ""], Except[_String] -> ""],
      "Err" -> Replace[Quiet @ Check[ReadString[ProcessConnection[p, "StandardError"]], ""], Except[_String] -> ""]|>];
ipcFinished[_] := <|"ExitCode" -> -1, "Out" -> "", "Err" -> ""|>;

(* HEAD の応答見出しから状態コードと長さ (最後の応答) *)
ipcParseHead[out_String] :=
  Module[{blocks = StringSplit[StringReplace[out, "\r" -> ""], "\n\n"], last, code, len},
    blocks = Select[blocks, StringStartsQ[StringTrim[#], "HTTP/"] &];
    If[blocks === {}, Return[<|"Code" -> None, "Length" -> None|>]];
    last = StringTrim[Last[blocks]];
    code = StringCases[First[StringSplit[last, "\n"]], RegularExpression["^HTTP/\\S+\\s+(\\d{3})"] :> FromDigits["$1"]];
    len = StringCases[last, RegularExpression["(?im)^content-length:\\s*(\\d+)"] :> FromDigits["$1"]];
    <|"Code" -> If[code === {}, None, First[code]], "Length" -> If[len === {}, None, First[len]]|>];

(* 台帳 (この PC が置いた物と時刻。後で消すため。題名はローカルにだけ残す) *)
ipcLedgerFile[] := FileNameJoin[{$UserBaseDirectory, "ApplicationData", "ResoniteRealtime", "pdfcache.json"}];
ipcLedger[] :=
  With[{f = ipcLedgerFile[]},
    If[!FileExistsQ[f], <||>,
      Replace[Quiet @ Check[ImportByteArray[ReadByteArray[f], "RawJSON"], <||>], Except[_Association] -> <||>]]];
ipcLedgerPut[key_String, rec_Association] :=
  Module[{f = ipcLedgerFile[], l = ipcLedger[]},
    Quiet @ CreateDirectory[DirectoryName[f], CreateIntermediateDirectories -> True];
    l[key] = rec;
    Quiet @ Check[
      With[{s = OpenWrite[f, BinaryFormat -> True]}, BinaryWrite[s, ExportByteArray[l, "RawJSON"]]; Close[s]], Null]];
ipcLedgerDrop[keys_List] :=
  Module[{f = ipcLedgerFile[], l = ipcLedger[]},
    l = KeyDrop[l, keys];
    Quiet @ Check[
      With[{s = OpenWrite[f, BinaryFormat -> True]}, BinaryWrite[s, ExportByteArray[l, "RawJSON"]]; Close[s]], Null]];

(* ============================================================
   開くときの入口 (itNativeSpawn / ResoniteDocViewer から)
   ============================================================ *)

(* file を開くときの URL。写しが確かめ済みならその URL、そうでなければ local (127.0.0.1) のまま返し、
   置いてよい条件なら確かめ / 送信を始める。戻り値 <|"URL", "CacheKey"|>。 *)
ipcOpenURL[file_String, local_String, pl_, title_String] :=
  Module[{key, rec},
    If[!ipcEnabledQ[] || !ipcWorldOKQ[] || ToLowerCase[FileExtension[file]] =!= "pdf",
      Return[<|"URL" -> local, "CacheKey" -> None|>]];
    (* サーバ未設定 (公開リポジトリから入れた直後など): 写しは置かず、設定の仕方を状態欄に案内する (PC ごとに 1 セッション 1 回) *)
    If[!ipcConfiguredQ[],
      If[!TrueQ[$ipcGuided], $ipcGuided = True; itSetStatus[$ipcSetupGuide]];
      Return[<|"URL" -> local, "CacheKey" -> None|>]];
    (* 置けるワールドなのに機密度で置かないときは、黙らずに状態欄と記録に残す (2026-09-25 ユーザー指摘:
       「サムネイルから開いた PDF がアップロードされない」。Eagle の行はライブラリ既定の PL で 0.5 を超えることが多い) *)
    If[!ipcLevelOKQ[pl],
      $ipcSkipped = Take[Append[Replace[$ipcSkipped, Except[_List] -> {}],
        <|"Title" -> title, "File" -> file, "PrivacyLevel" -> itPL[pl], "Time" -> DateString[{"Hour", ":", "Minute", ":", "Second"}]|>],
        -Min[20, Length[Replace[$ipcSkipped, Except[_List] -> {}]] + 1]];
      itSetStatus["機密度 " <> itFmt[itPL[pl]] <> " > " <> itFmt[ResoniteRealtime`$ResonitePDFCacheMaxLevel] <>
        " なのでサーバに写しを置きません (フレンドには見えません): " <> itTruncate[title, 40]];
      Return[<|"URL" -> local, "CacheKey" -> None|>]];
    key = ipcHash[file];
    If[!StringQ[key], Return[<|"URL" -> local, "CacheKey" -> None|>]];
    rec = Lookup[$ipcCache, key, None];
    Which[
      !AssociationQ[rec] || rec["Status"] === "Failed",
        $ipcCache[key] = <|"Key" -> key, "File" -> file, "Local" -> local, "Title" -> title, "Bytes" -> FileByteCount[file],
          "Status" -> "Check", "Time" -> iNow[], "Verified" -> None, "Error" -> None|>,
      rec["Status"] === "Ready" && iNow[] - Replace[rec["Verified"], Except[_?NumericQ] -> 0] > $ipcVerifySeconds,
        (* 消されているかもしれない: 写しで開き、裏で確かめ直す (無ければ local に戻して送り直す) *)
        $ipcCache[key] = Join[KeyDrop[rec, "Uploaded"], <|"Status" -> "Recheck", "Local" -> local, "Time" -> iNow[]|>],
      True, $ipcCache[key] = Join[rec, <|"Local" -> local|>]];
    <|"URL" -> ipcURLFor[key, local], "CacheKey" -> key|>];

(* いま使う URL: 写しがある (Ready / Recheck) なら写し、無ければ local *)
ipcURLFor[key_, local_String] :=
  With[{rec = If[StringQ[key], Lookup[$ipcCache, key, None], None]},
    If[AssociationQ[rec] && MemberQ[{"Ready", "Recheck"}, rec["Status"]], ipcPublicURL[key], local]];

(* ============================================================
   tick (itPoll0 から): 確かめ -> 送信 -> 置いたビューアの URL を差し替え
   ============================================================ *)
ResoniteRealtime`Private`ipcTick[] :=
  (KeyValueMap[Function[{key, rec}, Quiet @ Check[ipcStep[key, rec], Null]], $ipcCache];
   (* 「キャッシュ削除」ボタンの裏の curl (一覧 -> 削除) *)
   Quiet @ Check[ipcClearStep[], $ipcClearJob = None]);

(* curl に渡してよいパス: ASCII の印字可能文字だけで、[ ] { } を含まない *)
ipcSafePathQ[p_String] := AllTrue[ToCharacterCode[p], 32 <= # <= 126 &] && StringFreeQ[p, "[" | "]" | "{" | "}"];
$ipcTempDir := FileNameJoin[{$TemporaryDirectory, "ResoniteRealtime_pdfcache"}];
ipcUploadSource[file_String, name_String] :=
  Module[{dst},
    If[ipcSafePathQ[file], Return[file]];
    dst = FileNameJoin[{$ipcTempDir, name}];
    If[!ipcSafePathQ[dst], Return[None]];
    Quiet @ CreateDirectory[$ipcTempDir, CreateIntermediateDirectories -> True];
    If[FileExistsQ[dst] && FileByteCount[dst] === FileByteCount[file], Return[dst]];
    If[StringQ[Quiet @ Check[CopyFile[file, dst, OverwriteTarget -> True], $Failed]], dst, None]];
(* 一時コピーだけ消す (元のファイルは消さない) *)
ipcDropTemp[src_String, file_String] :=
  If[src =!= file && StringStartsQ[src, $ipcTempDir], Quiet @ DeleteFile[src]];
ipcDropTemp[___] := Null;

ipcStep[key_String, rec_Association] :=
  Module[{t, r, h, pw, name, src},
    Switch[rec["Status"],
      "Check" | "Recheck",
        r = ipcStart[{"-sS", "-I", "--max-time", ToString[$ipcHeadSeconds]}, "url = " <> ipcQuote[ipcPublicURL[key]] <> "\n"];
        If[FailureQ[r], Return[ipcFail[key, r]]];
        $ipcCache[key] = Join[rec, <|"Status" -> rec["Status"] <> "ing", "Process" -> r, "Started" -> iNow[]|>],
      "Checking" | "Rechecking",
        r = ipcFinished[rec["Process"]];
        If[r === None,
          If[iNow[] - rec["Started"] > $ipcHeadSeconds + 10, Quiet[KillProcess[rec["Process"]]]; ipcFail[key, "HEAD が返りません"]];
          Return[None]];
        h = ipcParseHead[r["Out"]];
        Which[
          h["Code"] === 200 && h["Length"] === rec["Bytes"],
            ipcReady[key, "既に置いてありました"],
          r["ExitCode"] =!= 0 && h["Code"] === None,
            (* サーバに届かない: 送っても無駄。写しは使わない *)
            ipcFail[key, "HEAD に失敗 (curl exit " <> ToString[r["ExitCode"]] <> ")"],
          NumericQ[Lookup[rec, "Uploaded", None]],
            (* 送った直後なのに見えない: 送り直しを繰り返さない *)
            ipcFail[key, "送ったのに " <> ipcPublicURL[key] <> " が見えません (HTTP " <> ToString[h["Code"]] <>
              ", " <> ToString[h["Length"]] <> " / " <> ToString[rec["Bytes"]] <> " bytes)"],
          True,
            (* 無い (404) / 大きさが違う -> 送る。確かめ直しで無かったら置いたビューアを local に戻す *)
            $ipcCache[key] = Join[KeyDrop[rec, "Process"], <|"Status" -> "Upload"|>];
            If[rec["Status"] === "Rechecking", ipcSwapViewers[key]]],
      "Upload",
        t = ipcTarget[];
        If[!AssociationQ[t], Return[ipcFail[key, "$ResonitePDFCacheUploadURL が sftp://user@host/dir の形ではありません"]]];
        pw = ipcPassword[t];
        If[!StringQ[pw], Return[ipcFail[key, ipcNoCredMessage[t], "NoCredential"]]];
        If[!FileExistsQ[rec["File"]], Return[ipcFail[key, "ファイルがありません"]]];
        name = key <> ".pdf";
        (* 送るファイル: パスに ASCII 以外や [ ] { } があれば一時フォルダに <hash>.pdf で写す (2026-09-25 実機:
           「初等量子力学 [W.ハイトラー].pdf」で curl が [..] を URL の範囲指定と読み (exit 3 bad range)、日本語の引数も化けた) *)
        src = ipcUploadSource[rec["File"], name];
        If[!StringQ[src], Return[ipcFail[key, "送るための一時コピーを作れませんでした"]]];
        (* .part に送り、終わってから名前を付け替える (途中のファイルを見せない)。* は失敗を無視。--globoff で [ ] を展開しない *)
        r = ipcStart[{"-sS", "-k", "--globoff", "--connect-timeout", "30", "--max-time", ToString[$ipcUploadSeconds], "--ftp-create-dirs",
            "-T", src, ipcRemoteURL[t, name <> ".part"],
            "-Q", "-*rm " <> t["Dir"] <> "/" <> name, "-Q", "-rename " <> t["Dir"] <> "/" <> name <> ".part " <> t["Dir"] <> "/" <> name},
          "user = " <> ipcQuote[t["User"] <> ":" <> pw] <> "\n"];
        pw = None;
        If[FailureQ[r], ipcDropTemp[src, rec["File"]]; Return[ipcFail[key, r]]];
        $ipcCache[key] = Join[rec, <|"Status" -> "Uploading", "Process" -> r, "Started" -> iNow[], "Source" -> src|>];
        itSetStatus["PDF の写しをサーバに送っています (フレンド用): " <> itTruncate[rec["Title"], 40]],
      "Uploading",
        r = ipcFinished[rec["Process"]];
        If[r === None,
          If[iNow[] - rec["Started"] > $ipcUploadSeconds + 30, Quiet[KillProcess[rec["Process"]]];
            ipcDropTemp[Lookup[rec, "Source", None], rec["File"]]; ipcFail[key, "送信が終わりません"]];
          Return[None]];
        ipcDropTemp[Lookup[rec, "Source", None], rec["File"]];
        $ipcCache[key] = KeyDrop[$ipcCache[key], "Source"];
        Which[
          r["ExitCode"] === 0,
            ipcLedgerPut[key, <|"Title" -> rec["Title"], "Bytes" -> rec["Bytes"], "Uploaded" -> DateString["ISODateTime"]|>];
            (* 送った直後にもう一度 HEAD で確かめる (配信されてから URL を差し替える) *)
            $ipcCache[key] = Join[KeyDrop[rec, "Process"], <|"Status" -> "Check", "Uploaded" -> iNow[]|>],
          r["ExitCode"] === 67, ipcFail[key, "sftp の認証に失敗 (ResonitePDFCacheCredential[] で保存し直してください)", "Auth"],
          True, ipcFail[key, "送信に失敗 (curl exit " <> ToString[r["ExitCode"]] <> "): " <> itTruncate[StringTrim[r["Err"]], 200]]],
      (* パスワード待ち: 保存されたら、開き直さなくても送り直す (値は見ず、保存済みかだけを 10 s ごとに確かめる)。
         認証失敗 (パスワード違い) は同じ値で繰り返さない: 保存し直してから ResonitePDFCacheRetry[] か開き直す *)
      "Failed",
        t = ipcTarget[];
        If[Lookup[rec, "Reason", None] === "NoCredential" && AssociationQ[t] &&
           iNow[] - Lookup[rec, "CredCheckedAt", 0] >= $ipcCredRetrySeconds,
          $ipcCache[key, "CredCheckedAt"] = iNow[];
          If[ipcCredQ[t],
            ipcRetry[key];
            itSetStatus["sftp のパスワードが保存されたので PDF の写しを送ります: " <> itTruncate[rec["Title"], 40]]]],
      _, None]];

ipcRetry[key_String] :=
  With[{rec = $ipcCache[key]},
    $ipcCache[key] = Join[KeyDrop[rec, {"Reason", "Error", "Uploaded", "Process"}], <|"Status" -> "Check", "Time" -> iNow[]|>]];

ipcReady[key_String, note_String] :=
  Module[{rec = $ipcCache[key]},
    $ipcCache[key] = Join[KeyDrop[rec, {"Process", "Uploaded"}], <|"Status" -> "Ready", "Verified" -> iNow[], "Error" -> None|>];
    ipcSwapViewers[key];
    itSetStatus["フレンドにも見える URL にしました (" <> note <> "): " <> itTruncate[rec["Title"], 40]]];

ipcFail[key_String, why_] := ipcFail[key, why, None];
ipcFail[key_String, why_, reason_] :=
  Module[{rec = $ipcCache[key], msg = If[FailureQ[why], ToString[why["MessageTemplate"]], ToString[why]]},
    $ipcCache[key] = Join[KeyDrop[rec, "Process"], <|"Status" -> "Failed", "Error" -> msg, "FailedAt" -> iNow[],
      "Reason" -> reason, "CredCheckedAt" -> iNow[]|>];
    ipcSwapViewers[key];
    $itState["LastError"] = iFailure["PDFCache", msg, <|"Key" -> key, "Title" -> rec["Title"]|>];
    itSetStatus["PDF の写しを置けませんでした (フレンドには見えません): " <> itTruncate[msg, 120]]];

(* 置いたビューア (標準ビューアの複製 / 文書表示) のうち、この写しの物の URL を今の状態に合わせる (待たない) *)
ipcSwapViewers[key_String] :=
  Module[{rec = $ipcCache[key], want, n = 0},
    want = ipcURLFor[key, rec["Local"]];
    Do[With[{recs = Replace[Lookup[$itState, bag, <||>], Except[_Association] -> <||>]},
        KeyValueMap[Function[{root, v},
            If[Lookup[v, "CacheKey", None] === key && StringQ[Lookup[v, "Doc", None]] && Lookup[v, "URL", None] =!= want,
              itNoWait @ Quiet @ Check[ResoniteRealtime`ResoniteRealtimeUpdateComponent[v["Doc"],
                <|"URL" -> ResoniteRealtime`ResoniteRealtimeValue["Uri", want]|>], Null];
              $itState[bag, root, "URL"] = want; n++]],
          recs]],
      {bag, {"NativeDocs", "DocViewers"}}];
    n];

(* ============================================================
   公開 API
   ============================================================ *)
ResoniteRealtime`ResonitePDFCacheStatus["Skipped"] := $ipcSkipped;
(* 失敗した写しを確かめ直して送り直す (tick が進める)。戻り値: 対象の題名 *)
ResoniteRealtime`ResonitePDFCacheRetry[] :=
  With[{keys = Keys[Select[$ipcCache, #["Status"] === "Failed" &]]},
    Scan[ipcRetry, keys];
    Lookup[Lookup[$ipcCache, keys], "Title", {}]];
ResoniteRealtime`ResonitePDFCacheStatus[] :=
  Map[<|"Status" -> #["Status"], "Title" -> #["Title"], "URL" -> ipcPublicURL[#["Key"]], "Bytes" -> #["Bytes"],
      "Error" -> Lookup[#, "Error", None],
      "VerifiedSecondsAgo" -> If[NumericQ[Lookup[#, "Verified", None]], Round[iNow[] - #["Verified"]], None]|> &, $ipcCache];

(* 待つ版の curl (ノートブックから呼ぶ一覧・削除用)。cfg は標準入力の設定に足す行 (削除の quote など。名前が多いと
   コマンドラインの長さの上限 (Windows 32 KB) を超えるので引数に並べない) *)
ipcRunSync[args_List] := ipcRunSync[args, ""];
ipcRunSync[args_List, cfg_String] :=
  Module[{t = ipcTarget[], pw, exe = ipcCurl[], r},
    If[!AssociationQ[t], Return[Failure["PDFCache", <|"MessageTemplate" -> $ipcSetupGuide|>]]];
    If[!StringQ[exe], Return[Failure["NoCurl", <|"MessageTemplate" -> "sftp の使える curl がありません。"|>]]];
    pw = ipcPassword[t];
    If[!StringQ[pw], Return[Failure["NoCredential", <|"MessageTemplate" -> ipcNoCredMessage[t]|>]]];
    r = Quiet @ Check[RunProcess[Join[{exe, "-sS", "-k", "--connect-timeout", "30"}, args, {"-K", "-"}], All,
      "user = " <> ipcQuote[t["User"] <> ":" <> pw] <> "\n" <> cfg], $Failed];
    pw = None;
    If[!AssociationQ[r], Return[Failure["PDFCache", <|"MessageTemplate" -> "curl を起動できませんでした。"|>]]];
    If[r["ExitCode"] =!= 0,
      Return[Failure["PDFCache", <|"MessageTemplate" -> "curl exit " <> ToString[r["ExitCode"]] <> ": " <>
        itTruncate[StringTrim[ToString[r["StandardError"]]], 200]|>]]];
    <|"Target" -> t, "Out" -> r["StandardOutput"]|>];

ipcListURL[t_Association] := "sftp://" <> t["Host"] <> t["Dir"] <> "/";
(* 一覧の出力から写しの名前 (<SHA-256>.pdf と送りかけの .part だけ。同じディレクトリの他の物は触らない) *)
ipcCacheNames[out_String] :=
  Sort @ Select[StringTrim /@ StringSplit[out, "\n"], StringMatchQ[#, RegularExpression["[0-9a-f]{64}\\.pdf(\\.part)?"]] &];
(* 削除の quote (curl の設定の行。* は失敗を無視) *)
ipcRemoveConfig[t_Association, names_List] :=
  StringJoin[Map["quote = " <> ipcQuote["*rm " <> t["Dir"] <> "/" <> #] <> "\n" &, names]];

ResoniteRealtime`ResonitePDFCacheList[] :=
  Module[{t = ipcTarget[], r},
    If[!AssociationQ[t], Return[Failure["PDFCache", <|"MessageTemplate" -> $ipcSetupGuide|>]]];
    r = ipcRunSync[{"--list-only", ipcListURL[t]}];
    If[FailureQ[r], Return[r]];
    Sort @ Select[StringTrim /@ StringSplit[r["Out"], "\n"], StringEndsQ[#, ".pdf" | ".pdf.part"] &]];

(* 消した写しの後始末: 台帳から外し、置いたビューアを 127.0.0.1 の URL に戻して、状態から外す *)
ipcForget[keys_List] :=
  (ipcLedgerDrop[keys];
   Scan[If[AssociationQ[Lookup[$ipcCache, #, None]],
       $ipcCache[#] = Join[KeyDrop[$ipcCache[#], "Process"], <|"Status" -> "Removed"|>];
       Quiet @ Check[ipcSwapViewers[#], Null]] &, keys];
   $ipcCache = KeyDrop[$ipcCache, keys]);
(* 送信・確かめの最中でない写し (削除後に忘れてよい物) *)
ipcIdleKeys[] := Keys[Select[$ipcCache, !MemberQ[{"Uploading", "Checking", "Rechecking"}, Lookup[#, "Status", None]] &]];
ipcKeysOf[names_List] := DeleteDuplicates[StringReplace[names, RegularExpression["\\.pdf(\\.part)?$"] -> ""]];

ipcRemove[names_List] :=
  Module[{t = ipcTarget[], r},
    If[names === {}, Return[{}]];
    If[!AssociationQ[t], Return[Failure["PDFCache", <|"MessageTemplate" -> $ipcSetupGuide|>]]];
    (* 何も転送しない sftp の要求 (ディレクトリの一覧) に削除の quote を載せる *)
    r = ipcRunSync[{"--list-only", "-o", "NUL", ipcListURL[t]}, ipcRemoveConfig[t, names]];
    If[FailureQ[r], Return[r]];
    ipcForget[ipcKeysOf[names]];
    names];

Options[ResoniteRealtime`ResonitePDFCacheClear] = {"OlderThan" -> None};
ResoniteRealtime`ResonitePDFCacheClear[opts : OptionsPattern[]] :=
  Module[{l = ipcLedger[], days = OptionValue["OlderThan"], keys},
    keys = Keys[l];
    If[NumericQ[days],
      keys = Select[keys, Function[k, With[{d = Quiet @ Check[DateObject[l[k]["Uploaded"]], None]},
        DateObjectQ[d] && QuantityMagnitude[DateDifference[d, Now, "Day"]] > days]]]];
    ipcRemove[Map[# <> ".pdf" &, keys]]];
ResoniteRealtime`ResonitePDFCacheClear[All] :=
  With[{names = ResoniteRealtime`ResonitePDFCacheList[]},
    If[FailureQ[names], names, ipcRemove[names]]];
ResoniteRealtime`ResonitePDFCacheClear[keys : {__String}] :=
  ipcRemove[Map[If[StringEndsQ[#, ".pdf"], #, # <> ".pdf"] &, keys]];

(* ============================================================
   「キャッシュ削除」ボタン (サムネイル一覧の見出し、Selected = -5。2026-09-26 ユーザー指示):
   どの Eagle フォルダの物かに関係なく、サーバの cache にある写し (<SHA-256>.pdf / .part) をすべて消す。
   監視の tick の中から呼ばれるので待たない: curl を裏で走らせ (一覧 -> 削除)、ipcTick で終わりを拾う。
   say: 経過と結果を出す関数 (サムネイル一覧の状態欄)。二重に押されたら走っている方の経過を返すだけ
   ============================================================ *)
If[!AssociationQ[$ipcClearJob], $ipcClearJob = None];
ipcClearAllStart[say_] :=
  Module[{t = ipcTarget[], pw, p, msg},
    msg = Function[s, Quiet @ Check[say[s], Null]; itSetStatus[s]; s];
    If[AssociationQ[$ipcClearJob], Return[msg["キャッシュを削除しています… (" <> $ipcClearJob["Phase"] <> ")"]]];
    If[!ipcConfiguredQ[], Return[msg[$ipcSetupGuide]]];
    pw = ipcPassword[t];
    If[!StringQ[pw], Return[msg[ipcNoCredMessage[t]]]];
    p = ipcStart[{"-sS", "-k", "--connect-timeout", "30", "--max-time", "120", "--list-only", ipcListURL[t]},
      "user = " <> ipcQuote[t["User"] <> ":" <> pw] <> "\n"];
    pw = None;
    If[FailureQ[p], Return[msg["キャッシュを削除できません: " <> ToString[p["MessageTemplate"]]]]];
    $ipcClearJob = <|"Phase" -> "Listing", "Process" -> p, "Started" -> iNow[], "Say" -> say|>;
    msg["サーバのキャッシュを確認しています…"]];

ipcClearStep[] :=
  Module[{j = $ipcClearJob, r, names, t, pw, p, say},
    If[!AssociationQ[j], Return[None]];
    say = Function[s, Quiet @ Check[j["Say"][s], Null]; itSetStatus[s]];
    r = ipcFinished[j["Process"]];
    If[r === None,
      If[iNow[] - j["Started"] > 180,
        Quiet[KillProcess[j["Process"]]]; $ipcClearJob = None; say["キャッシュの削除が終わりません (打ち切りました)"]];
      Return[None]];
    If[r["ExitCode"] =!= 0,
      $ipcClearJob = None;
      Return[say["キャッシュを削除できません (curl exit " <> ToString[r["ExitCode"]] <> "): " <> itTruncate[StringTrim[r["Err"]], 120]]]];
    Switch[j["Phase"],
      "Listing",
        names = ipcCacheNames[r["Out"]];
        If[names === {}, $ipcClearJob = None; ipcForget[ipcIdleKeys[]]; Return[say["サーバに削除するキャッシュはありません"]]];
        t = ipcTarget[]; pw = ipcPassword[t];
        If[!AssociationQ[t] || !StringQ[pw], $ipcClearJob = None; Return[say[ipcNoCredMessage[t]]]];
        p = ipcStart[{"-sS", "-k", "--connect-timeout", "30", "--max-time", "300", "--list-only", "-o", "NUL", ipcListURL[t]},
          "user = " <> ipcQuote[t["User"] <> ":" <> pw] <> "\n" <> ipcRemoveConfig[t, names]];
        pw = None;
        If[FailureQ[p], $ipcClearJob = None; Return[say["キャッシュを削除できません: " <> ToString[p["MessageTemplate"]]]]];
        $ipcClearJob = Join[j, <|"Phase" -> "Removing", "Process" -> p, "Started" -> iNow[], "Names" -> names|>];
        say["サーバのキャッシュを " <> ToString[Length[names]] <> " 件削除しています…"],
      "Removing",
        $ipcClearJob = None;
        (* 置いたビューアのうちサーバの写しを指していた物は 127.0.0.1 に戻す (フレンドには見えなくなる) *)
        ipcForget[Union[ipcKeysOf[j["Names"]], ipcIdleKeys[]]];
        say["サーバのキャッシュを " <> ToString[Length[j["Names"]]] <> " 件削除しました (次に開くと送り直します)"],
      _, $ipcClearJob = None];
    j["Phase"]];

(* ============================================================
   サーバの設定とパスワード (公開リポジトリ化、2026-09-26。ソースにサーバ名もパスワードも書かない)
   ============================================================ *)
ResoniteRealtime`ResonitePDFCacheSetup[] :=
  With[{t = ipcTarget[]},
    <|"Configured" -> ipcConfiguredQ[], "UploadURL" -> ResoniteRealtime`$ResonitePDFCacheUploadURL,
      "BaseURL" -> ResoniteRealtime`$ResonitePDFCacheBaseURL, "ConfigFile" -> ipcConfigFile[],
      "Credential" -> If[AssociationQ[t], ipcCredName[t], None],
      (* True = アカウント名 (同じアカウントを使う他のパッケージと共有)、False = このパッケージ専用の名前 *)
      "CredentialShared" -> If[AssociationQ[t], ipcSharedCredQ[t], None],
      "PasswordSaved" -> If[AssociationQ[t], ipcCredQ[t], False],
      "Next" -> Which[
        !ipcConfiguredQ[], $ipcSetupGuide,
        !ipcCredQ[t], "ResonitePDFCacheCredential[] でパスワードを保存してください (NBAccess が要ります)",
        True, "設定済みです"]|>];
Options[ResoniteRealtime`ResonitePDFCacheSetup] = {"Credential" -> Automatic};
ResoniteRealtime`ResonitePDFCacheSetup[upload_String, base_String, opts : OptionsPattern[]] :=
  Module[{f = ipcConfigFile[], p = Quiet @ Check[URLParse[upload], $Failed], cred = OptionValue["Credential"], conf},
    If[!AssociationQ[p] || ToLowerCase[ToString[Lookup[p, "Scheme", ""]]] =!= "sftp" || !StringQ[Lookup[p, "User", None]] ||
       !StringQ[Lookup[p, "Domain", None]],
      Return[Failure["PDFCacheSetup", <|"MessageTemplate" -> "1 つ目は sftp://user@host/path/to/cache の形で指定してください。"|>]]];
    If[!StringMatchQ[base, RegularExpression["(?i)https?://.+"]],
      Return[Failure["PDFCacheSetup", <|"MessageTemplate" -> "2 つ目は写しのディレクトリを読む https://... の URL です。"|>]]];
    (* URLParse は user:password を "User" にまとめて返す *)
    If[StringContainsQ[p["User"], ":"] || StringQ[Lookup[p, "Password", None]],
      Return[Failure["PDFCacheSetup", <|"MessageTemplate" ->
        "URL にパスワードを入れないでください。パスワードは ResonitePDFCacheCredential[] で保存します。"|>]]];
    If[!(cred === Automatic || (StringQ[cred] && StringTrim[cred] =!= "")),
      Return[Failure["PDFCacheSetup", <|"MessageTemplate" -> "\"Credential\" は Automatic か、このパッケージ専用の名前 (文字列) です。"|>]]];
    conf = Join[<|"UploadURL" -> upload, "BaseURL" -> StringTrim[base, "/"]|>, If[StringQ[cred], <|"Credential" -> StringTrim[cred]|>, <||>]];
    Quiet @ CreateDirectory[DirectoryName[f], CreateIntermediateDirectories -> True];
    Quiet @ Check[With[{s = OpenWrite[f, BinaryFormat -> True]},
      BinaryWrite[s, ExportByteArray[conf, "RawJSON"]]; Close[s]],
      Return[Failure["PDFCacheSetup", <|"MessageTemplate" -> "設定ファイルを書けません: " <> f|>]]];
    $ipcConfigMemo = {None, <||>};
    ResoniteRealtime`$ResonitePDFCacheUploadURL = upload;
    ResoniteRealtime`$ResonitePDFCacheBaseURL = StringTrim[base, "/"];
    $ipcGuided = False;
    ResoniteRealtime`ResonitePDFCacheSetup[]];
ResoniteRealtime`ResonitePDFCacheSetup[None] :=
  (Quiet @ DeleteFile[ipcConfigFile[]]; $ipcConfigMemo = {None, <||>};
   ResoniteRealtime`$ResonitePDFCacheUploadURL = None; ResoniteRealtime`$ResonitePDFCacheBaseURL = None;
   ResoniteRealtime`ResonitePDFCacheSetup[]);

(* パスワード: SystemCredential の読み書きは NBAccess だけ (値はここで持たず、そのまま NBAccess に渡す) *)
ipcCredFailure[] :=
  Failure["PDFCacheCredential", <|"MessageTemplate" ->
    "NBAccess が読み込まれていません (Needs[\"NBAccess`\"])。SystemCredential は NBAccess 経由でだけ扱います。"|>];
ResoniteRealtime`ResonitePDFCacheCredential[] :=
  Module[{t = ipcTarget[], dlg},
    If[!AssociationQ[t], Return[Failure["PDFCacheCredential", <|"MessageTemplate" -> $ipcSetupGuide|>]]];
    If[!ipcNBAccessQ[], Return[ipcCredFailure[]]];
    If[!TrueQ[$Notebooks], Return[Failure["NoFrontEnd",
      <|"MessageTemplate" -> "ダイアログを出せません。ResonitePDFCacheCredential[password] で保存してください。"|>]]];
    dlg = Quiet[AuthenticationDialog[{"Password"}, WindowTitle -> "sftp " <> ipcCredName[t]]];
    If[!AssociationQ[dlg] || !StringQ[Lookup[dlg, "Password", None]] || dlg["Password"] === "", Return[$Canceled]];
    ResoniteRealtime`ResonitePDFCacheCredential[dlg["Password"]]];
ResoniteRealtime`ResonitePDFCacheCredential[password_String] :=
  Module[{t = ipcTarget[]},
    If[!AssociationQ[t], Return[Failure["PDFCacheCredential", <|"MessageTemplate" -> $ipcSetupGuide|>]]];
    If[!ipcNBAccessQ[], Return[ipcCredFailure[]]];
    If[!TrueQ[Quiet @ Check[NBAccess`NBSetCredential[ipcCredName[t], password], False]],
      Return[Failure["PDFCacheCredential", <|"MessageTemplate" -> "SystemCredential への保存に失敗しました: " <> ipcCredName[t]|>]]];
    <|"Credential" -> ipcCredName[t], "Configured" -> True, "Shared" -> ipcSharedCredQ[t]|>];
ResoniteRealtime`ResonitePDFCacheCredential[None] :=
  Module[{t = ipcTarget[]},
    If[!AssociationQ[t], Return[Failure["PDFCacheCredential", <|"MessageTemplate" -> $ipcSetupGuide|>]]];
    If[!ipcNBAccessQ[], Return[ipcCredFailure[]]];
    Quiet[NBAccess`NBRemoveCredential[ipcCredName[t]]];
    Join[<|"Credential" -> ipcCredName[t], "Configured" -> False, "Shared" -> ipcSharedCredQ[t]|>,
      If[ipcSharedCredQ[t],
        <|"Note" -> "この名前はアカウント名なので、同じアカウントを使う他のパッケージ (SlideWorkflow 等) のパスワードも消えました。" <>
          "分けて持つには ResonitePDFCacheSetup[..., \"Credential\" -> \"専用の名前\"] にしてください。"|>, <||>]]];

End[];
EndPackage[];
