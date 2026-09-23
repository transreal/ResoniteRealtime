(* ::Package:: *)

(* ResoniteRealtime.wl -- Mathematica から Resonite を制御するブリッジ

   This file is encoded in UTF-8.
   Load via: Block[{$CharacterEncoding="UTF-8"}, Get["ResoniteRealtime.wl"]]

   依存: ResoniteRealtime_ws.wl (同じディレクトリ。自動でロードする)

   ---- 経路 ----

   L1 リアルタイム: WL が WebSocket サーバ。世界の WebsocketClient が繋いでくる。
       ProtoFlux は JSON を扱えないので TAB 区切りの行プロトコルにする。
         世界 → WL :  evt<TAB>userJoined<TAB>nconc
         WL → 世界 :  cmd<TAB>show<TAB>http://127.0.0.1:9090/plot/1.png
       ホストである必要がない / 往復が速い。イベントとトリガはこちら。

   L2 構造: WL が ResoniteLink (公式, 2026.1.8.6〜) のクライアント。
       WebSocket + JSON でデータモデルを読み書きする。
       Resonite 側: Dashboard → Session → Settings → "Enable ResoniteLink"。
       表示された port を ResoniteRealtimeLinkConnect[port] に渡す。
       **セッションのホストである必要がある**。リアルタイム制御には使わない
       (公式が「in-game の OSC/WebSocket を使え」と明言している)。

   ---- 使い方 ----

     ResoniteRealtimeStart[]                    (* L1 サーバ起動 *)
     ResoniteRealtimeOn["evt", Print]           (* 世界からのイベントにハンドラ *)
     ResoniteRealtimeSend["cmd", "show", url]   (* 世界へ送る *)

     ResoniteRealtimeLinkConnect[41234]         (* L2 接続 *)
     ResoniteRealtimeGetSlot["Root", "Depth" -> 1]
     ResoniteRealtimeAddSlot["Name" -> "Hello", "Position" -> {0, 1.5, 2}]
     ResoniteRealtimeAddComponent[slotId, "[FrooxEngine]FrooxEngine.Grabbable",
       <|"Scalable" -> True|>]

     ResoniteRealtimeStatus[]  /  ResoniteRealtimeMonitor[]  /  ResoniteRealtimeStop[]

   ---- 前提 (導入は ResoniteRealtime_info/docs/setup.md) ----

   - WebSocket 層 (ResoniteRealtime_ws.wl) は純 Wolfram で依存ゼロ。L1 / L2 / 板の表示はこのパッケージだけで動く。
   - 任意: claudecode.wl + NBAccess.wl (Chat / ProtoFlux 生成 / タブレットの ClaudeEval)、SourceVault.wl (資料の表示・一覧)、
     ResoLoop.wl + resoloop CLI (3D 生成 = ResoniteGraphics3D。resoloop は別プロジェクト・AGPL なので同梱しない)、
     Flux-SDK (ProtoGraph の build)。
   - リポジトリに含めない参照データ: ResoniteRealtime_info/references/protoflux-nodes.json (Resonite の DLL を反射して作る) と
     references/protograph/ (Flux SDK 公式 docs の抜粋)。ProtoFlux 生成を使うときだけ setup.md の手順で作る。

   ---- 設計上の約束 ----

   - 常駐 Dynamic でポーリングしない (パレット常駐 UpdateInterval は FE を殺す)。
     Monitor は手動更新ボタン式。
   - SocketListen のコールバックからは FrontEnd を触らない。
   - ResoniteLink は beta。メッセージ組立は iRLMessage / iRLValue に閉じ込め、
     スキーマ変更はこの 2 つの追随で済むようにする。
*)

Quiet[Remove["Global`ResoniteRealtime*"], {Remove::rmnsm}];
Quiet[Remove["Global`$ResoniteRealtime*"], {Remove::rmnsm}];

BeginPackage["ResoniteRealtime`"];

$ResoniteRealtimeVersion::usage = "$ResoniteRealtimeVersion はパッケージのバージョン。";

ResoniteRealtimeStart::usage =
  "ResoniteRealtimeStart[] は L1 ブリッジ (WebSocket サーバ) を起動する。\n" <>
  "オプション: \"Port\" -> 17300, \"Heartbeat\" -> 25 (秒、0 で無効), \"LinkPort\" -> None。\n" <>
  "世界側は WebsocketClient の URL に ws://127.0.0.1:<Port>/bridge を入れる。";

ResoniteRealtimeStop::usage =
  "ResoniteRealtimeStop[] は L1 サーバと L2 (ResoniteLink) 接続、heartbeat タスクを止める。";

ResoniteRealtimeStatus::usage =
  "ResoniteRealtimeStatus[] はブリッジと ResoniteLink の状態を Association で返す。";

ResoniteRealtimeMonitor::usage =
  "ResoniteRealtimeMonitor[] は状態表示を返す。常駐ポーリングはせず、更新ボタンで読み直す。";

ResoniteRealtimeSend::usage =
  "ResoniteRealtimeSend[verb, args...] は TAB 区切りの行を、繋がっている世界側の接続すべてへ送る。";

ResoniteRealtimeSendTo::usage =
  "ResoniteRealtimeSendTo[connId, verb, args...] は送り先の接続を指定して行を送る。\n" <>
  "connId は ResoniteRealtimeStatus[][\"BridgeConnections\"] やハンドラの \"Connection\" で得る。";

ResoniteRealtimeOn::usage =
  "ResoniteRealtimeOn[verb, f] は世界から届いた行の先頭語が verb のとき f を呼ぶ。\n" <>
  "f は <|\"Verb\", \"Args\", \"Line\", \"Connection\", \"Time\"|> を受ける。\n" <>
  "ResoniteRealtimeOn[All, f] は全ての行と接続/切断 (\"$open\" / \"$close\") で f を呼ぶ。\n" <>
  "世界側が何を送ってくるか分からない立ち上げ期はこれで覗くとよい。\n" <>
  "ResoniteRealtimeOn[verb, None] で解除。ResoniteRealtimeOn[] で登録一覧。";

ResoniteRealtimeEvents::usage =
  "ResoniteRealtimeEvents[] は直近に世界から届いた行 (既定 50 件) を返す。";

ResoniteRealtimeLinkConnect::usage =
  "ResoniteRealtimeLinkConnect[port] は ResoniteLink (ws://localhost:port/) に接続する。\n" <>
  "port は Resonite の Dashboard → Session → Settings で \"Enable ResoniteLink\" した際に表示される値。\n" <>
  "ResoniteRealtimeLinkConnect[] は ResoniteRealtimeDiscover[] でポートを見つけて接続する (候補が無ければ Failure[\"NoResoniteLink\"])。\n" <>
  "オプション: \"Host\" -> \"localhost\", \"Quiet\" -> False (True なら Print しない)。";
ResoniteRealtimeDiscover::usage =
  "ResoniteRealtimeDiscover[] は有効化されている ResoniteLink のポートを探し {<|\"Port\", \"URL\", \"Process\", \"Source\"|> ...} を返す。\n" <>
  "順に (1) Windows の http.sys 登録一覧 (netsh http show servicestate。Resonite / Renderite.Host のプロセスが登録した\n" <>
  "HTTP://LOCALHOST:<port>/。即時)、(2) ResoLoop.wl があれば resoloop discover (約 12 秒)、(3) 環境変数 RESONITE_LINK_URL。";

ResoniteRealtimeLinkDisconnect::usage = "ResoniteRealtimeLinkDisconnect[] は ResoniteLink 接続を閉じる。";

ResoniteRealtimeLink::usage =
  "ResoniteRealtimeLink[assoc] は ResoniteLink へ生のメッセージを送り、応答を待って返す。\n" <>
  "オプション: \"Timeout\" -> 10, \"Wait\" -> True (False なら送るだけ), \"Match\" -> Automatic。\n" <>
  "既定では「送信後に届いた中で JSON として解釈できた最初のメッセージ」を応答とする。\n" <>
  "\"Match\" に述語を渡すと、それを満たすものだけを応答とみなす (相関 ID が入ったときの受け口)。";

ResoniteRealtimeLinkMessages::usage =
  "ResoniteRealtimeLinkMessages[] は ResoniteLink から届いた直近のメッセージを返す。";

ResoniteRealtimeGetSlot::usage =
  "ResoniteRealtimeGetSlot[slotId] は getSlot を送る。slotId 既定は \"Root\"。\n" <>
  "オプション: \"Depth\" -> 0 (-1 で全階層), \"IncludeComponentData\" -> False。";

ResoniteRealtimeAddSlot::usage =
  "ResoniteRealtimeAddSlot[\"Name\" -> \"...\", \"Parent\" -> \"Root\", \"Position\" -> {x,y,z}, ...] は addSlot を送る。\n" <>
  "\"Id\" を省略すると WL_Slot_<n> を自動採番する。返り値の \"Id\" が以後の参照 ID。";

ResoniteRealtimeUpdateSlot::usage =
  "ResoniteRealtimeUpdateSlot[slotId, <|\"scale\" -> {2,2,2|>}] は updateSlot を送る。指定した項目だけ変わる。";

ResoniteRealtimeRemoveSlot::usage = "ResoniteRealtimeRemoveSlot[slotId] は removeSlot を送る。";

ResoniteRealtimeAddComponent::usage =
  "ResoniteRealtimeAddComponent[slotId, componentType, members] は addComponent を送る。\n" <>
  "componentType は Resonite のコンポーネントアタッチャと同じ書式 (例 \"[FrooxEngine]FrooxEngine.Grabbable\")。";

ResoniteRealtimeUpdateComponent::usage =
  "ResoniteRealtimeUpdateComponent[componentId, members] は updateComponent を送る。";

ResoniteRealtimeRef::usage =
  "ResoniteRealtimeRef[id] は ResoniteLink の reference 値 (<|\"$type\" -> \"reference\", \"targetId\" -> id|>) を作る。";

ResoniteRealtimeValue::usage =
  "ResoniteRealtimeValue[expr] は WL の値を ResoniteLink の型付き値へ変換する。\n" <>
  "String/Integer/Real/True|False/{x,y}/{x,y,z}/{x,y,z,w}/RGBColor に対応。\n" <>
  "ResoniteRealtimeValue[\"float3\", {0,1,2}] のように型を明示することもできる。";

ResoniteRealtimeNewId::usage = "ResoniteRealtimeNewId[\"Slot\"] は WL_Slot_<n> 形式の一意な ID を作る。";

ResoniteRealtimeShowImage::usage =
  "ResoniteRealtimeShowImage[expr] は Graphics / Image / 任意の式を PNG にして配信し、\n" <>
  "その URL を \"img\" 行として世界へ送る。世界側は受け取った文字列を StaticTexture2D の URL に書く。\n" <>
  "オプション: \"Size\" -> 800 (長辺ピクセル), \"Verb\" -> \"img\", \"Send\" -> True。\n" <>
  "返り値は URL。**HTTP の URL アセットは各クライアントが個別に取りに行く**ので、\n" <>
  "127.0.0.1 は自分にしか見えない。聴衆がいる場では \"PublicBaseURL\" を設定すること。";

ResoniteRealtimeBoard::usage =
  "ResoniteRealtimeBoard[] は ResoniteLink だけで「画像を映す板」を世界に組み立てる。\n" <>
  "Slot + StaticTexture2D + QuadMesh + UnlitMaterial + MeshRenderer を作り、ID を Association で返す。\n" <>
  "以後 ResoniteRealtimeShowImage[expr] がこの板のテクスチャ URL を差し替える (世界側の操作は不要)。\n" <>
  "オプション: \"Position\" -> {0,1.5,1.2}, \"Size\" -> 0.6, \"Rotation\" -> {x,y,z,w}, \"Name\", \"Parent\" -> \"Root\", \"Image\"。";

ResoniteRealtimeRemoveBoard::usage = "ResoniteRealtimeRemoveBoard[] は板を世界から削除する。";

ResoniteRealtimeAsset::usage =
  "ResoniteRealtimeAsset[file] はローカルファイルを配信対象に加え、その URL を返す (送信はしない)。\n" <>
  "ResoniteRealtimeAsset[] は配信ディレクトリを返す。";

$ResoniteRealtimePublicBaseURL::usage =
  "$ResoniteRealtimePublicBaseURL に \"https://example.com/rr\" のような公開 URL を入れておくと、\n" <>
  "ResoniteRealtimeShowImage が localhost ではなくその URL を返す (同じセッションの他の人にも見える)。\n" <>
  "その場合は配信ディレクトリの中身を自分でその URL 配下へアップロードすること。";

Begin["`Private`"];

(* ---- 再ロード時に古い定義を残さない ----
   引数パターンを変えた関数 (例: f[x_] → f[x_, opts:OptionsPattern[]]) は、
   再ロードしても**古い定義が消えずに残り、より特殊な方が先に当たる**。
   2026-09-04 に実際に踏んだ: LinkConnect のホスト名を直したのに旧定義が使われ続けた。
   公開シンボル (この context 直下) の値だけ落とす。::usage は Clear では消えず、
   状態変数は ResoniteRealtime`Private` にあるので生きている接続も壊れない。 *)
Scan[Quiet[Clear[#]] &, Names["ResoniteRealtime`*"]];

ResoniteRealtime`$ResoniteRealtimeVersion = "0.2.1";

If[!StringQ[ResoniteRealtime`$ResoniteRealtimePublicBaseURL],
  ResoniteRealtime`$ResoniteRealtimePublicBaseURL = ""];

$iPackageDirectory = DirectoryName[$InputFileName];

(* ---- 下回り (WebSocket 層) のロード ----
   **毎回ロードする。** 「未ロードのときだけ」にすると、_ws.wl だけを直したときに
   古い定義が残り、Options の食い違い (OptionValue::nodef) のような分かりにくい壊れ方をする
   (2026-09-04 実機で踏んだ)。_ws.wl の状態変数はすべて If[!AssociationQ[...]] で
   ガードしてあるので、再ロードしても生きている接続は壊れない。 *)
Block[{$CharacterEncoding = "UTF-8"},
  Get[FileNameJoin[{$iPackageDirectory, "ResoniteRealtime_ws.wl"}]]];

(* ---- Chat ガジェット (ノートブックの Chat セルをワールド内で実現する) ----
   同じ理由で毎回ロードする。状態は $icState に閉じ、再ロードで壊れない。 *)
Block[{$CharacterEncoding = "UTF-8"},
  Get[FileNameJoin[{$iPackageDirectory, "ResoniteRealtime_chat.wl"}]]];

(* ---- ProtoFlux ガジェット (ProtoGraph / グラフ記述を LLM に書かせる。chat の上に載る) ---- *)
Block[{$CharacterEncoding = "UTF-8"},
  Get[FileNameJoin[{$iPackageDirectory, "ResoniteRealtime_flux.wl"}]]];
(* ---- リンカ: グラフ記述を ResoniteLink でノードとして配置・結線 ---- *)
Block[{$CharacterEncoding = "UTF-8"},
  Get[FileNameJoin[{$iPackageDirectory, "ResoniteRealtime_fluxlink.wl"}]]];
(* ---- タブレット: ClaudeEval をワールド内で走らせる (chat のヘルパの上に載る) ---- *)
Block[{$CharacterEncoding = "UTF-8"},
  Get[FileNameJoin[{$iPackageDirectory, "ResoniteRealtime_tablet.wl"}]]];
(* ---- Graphics3D -> ワールド内の 3D オブジェクト (resoloop のメッシュ資産取り込み) ---- *)
Block[{$CharacterEncoding = "UTF-8"},
  Get[FileNameJoin[{$iPackageDirectory, "ResoniteRealtime_mesh.wl"}]]];

(* ---- 状態 (再ロードで壊さない) ---- *)
If[!AssociationQ[$iState],
  $iState = <|
    "Server" -> None, "Port" -> None, "Heartbeat" -> None, "HeartbeatTask" -> None,
    "Link" -> None, "LinkPort" -> None, "Started" -> None|>];
If[!AssociationQ[$iHandlers], $iHandlers = <||>];
If[!ListQ[$iEvents], $iEvents = {}];
If[!ListQ[$iLinkMessages], $iLinkMessages = {}];
If[!IntegerQ[$iIdCounter], $iIdCounter = 0];

$iEventLimit = 200;
$iLinkLimit  = 100;

(* ============================================================
   共通
   ============================================================ *)

iNow[] := AbsoluteTime[];

SetAttributes[iPush, HoldFirst];
iPush[listSym_Symbol, item_, limit_Integer] :=
  listSym = Take[Append[listSym, item], -Min[Length[listSym] + 1, limit]];

iFailure[tag_String, msg_String] :=
  Failure[tag, <|"MessageTemplate" -> msg|>];

(* ID はカーネルごとのタグ + 連番。
   **連番だけにしてはいけない**: ResoniteLink の ID 登録は Resonite のセッションが
   続くかぎり残り、removeSlot しても解放されない。カーネルを再起動して連番が 1 に
   戻ると、前のカーネルが使った ID と衝突して
   "ID 'WL_Board_1' is already in use" で落ちる (2026-09-05 実機で踏んだ)。 *)
If[!StringQ[$iSessionTag],
  $iSessionTag = IntegerString[Round[AbsoluteTime[]*10] - 39975000000, 36]];

ResoniteRealtime`ResoniteRealtimeNewId[prefix_String : "Obj"] := (
  $iIdCounter = $iIdCounter + 1;
  "WL" <> $iSessionTag <> "_" <> prefix <> "_" <> ToString[$iIdCounter]);

(* ============================================================
   L1: ブリッジ (行プロトコル)
   ============================================================ *)

(* 記録 → verb 別ハンドラ → catch-all (All) の順に流す。
   catch-all は「世界が何を送っているのか分からない」立ち上げ期のためのもので、
   $open / $close も同じ形のレコードで渡す。 *)
iDispatch[rec_Association] :=
  Module[{f},
    iPush[$iEvents, rec, $iEventLimit];
    f = Lookup[$iHandlers, rec["Verb"], None];
    If[f =!= None, Quiet[Check[f[rec], Null]]];
    f = Lookup[$iHandlers, All, None];
    If[f =!= None, Quiet[Check[f[rec], Null]]];
    rec];

iBridgeHandler[a_Association] :=
  Module[{line, parts, verb},
    Switch[a["Event"],
      "Message",
        line = a["Data"];
        If[!StringQ[line], Return[Null]];
        parts = StringSplit[line, "\t"];
        verb  = If[parts === {}, "", First[parts]];
        iDispatch[<|"Verb" -> verb, "Args" -> Rest[parts], "Line" -> line,
          "Connection" -> a["Connection"], "Time" -> iNow[]|>],
      "Open",
        iDispatch[<|"Verb" -> "$open", "Args" -> {}, "Line" -> "",
          "Connection" -> a["Connection"], "Time" -> iNow[]|>],
      "Close",
        iDispatch[<|"Verb" -> "$close", "Args" -> {Lookup[a, "Reason", ""]},
          "Line" -> "", "Connection" -> a["Connection"], "Time" -> iNow[]|>],
      _, Null]];

(* このブリッジサーバに繋がっている接続だけを返す。
   role だけで選ぶと、別用途で立てた RRWSServe の接続 (たとえば L2 の相手が
   同一カーネルにいる場合) まで拾って heartbeat を送りつけてしまう。 *)
iBridgeConnections[] :=
  If[!StringQ[$iState["Server"]], {},
    Keys @ Select[
      Quiet @ Check[ResoniteRealtime`RRWSStatus[]["Connections"], <||>],
      #["Role"] === "server" && #["Server"] === $iState["Server"] &]];

(* Resonite の WebsocketClient は「サーバから 60 秒何も来ない」と切断する。
   既定は **ping フレーム** で叩く: プロトコル層のフレームなので
   WebsocketTextMessageReceiver には出てこない = 世界側の ProtoFlux が
   本物のメッセージだけを見られる (分岐ノードを作らずに済む)。
   "HeartbeatMode" -> "Text" にすると従来どおり "hb<TAB>時刻" を送る。 *)
iHeartbeat[] :=
  Module[{conns, mode},
    conns = iBridgeConnections[];
    mode = Lookup[$iState, "HeartbeatMode", "Ping"];
    Scan[
      If[mode === "Text",
          ResoniteRealtime`RRWSSend[#, "hb\t" <> ToString[Round[iNow[]]]],
          ResoniteRealtime`RRWSPing[#]] &,
      conns];
    ResoniteRealtime`RRWSSweep[];
    Length[conns]];

(* ============================================================
   L3: 同じポートで静的ファイルを配る (画像・音・データを世界へ)
   ============================================================ *)

$iAssetDirectory =
  FileNameJoin[{$TemporaryDirectory, "ResoniteRealtime", "assets"}];

$iContentTypes = <|
  "png" -> "image/png", "jpg" -> "image/jpeg", "jpeg" -> "image/jpeg",
  "gif" -> "image/gif", "webp" -> "image/webp", "svg" -> "image/svg+xml",
  "wav" -> "audio/wav", "mp3" -> "audio/mpeg", "ogg" -> "audio/ogg",
  "mp4" -> "video/mp4", "webm" -> "video/webm",
  "txt" -> "text/plain; charset=utf-8", "csv" -> "text/csv; charset=utf-8",
  "json" -> "application/json; charset=utf-8"|>;

iEnsureAssetDirectory[] := (
  If[!DirectoryQ[$iAssetDirectory], CreateDirectory[$iAssetDirectory]];
  $iAssetDirectory);

iHTTPResponse[status_String, contentType_String, body_ByteArray] :=
  Join[
    StringToByteArray[
      "HTTP/1.1 " <> status <> "\r\n" <>
      "Content-Type: " <> contentType <> "\r\n" <>
      "Content-Length: " <> ToString[Length[body]] <> "\r\n" <>
      "Cache-Control: no-cache\r\n" <>
      "Connection: close\r\n\r\n", "UTF-8"],
    body];

(* /a/<name> だけを配る。.. を含む要求と配信ディレクトリ外は拒否する。 *)
iHTTPHandler[req_Association] :=
  Module[{path, name, file, ext, body},
    path = First[StringSplit[Lookup[req, "Path", "/"], "?"], "/"];
    If[!StringStartsQ[path, "/a/"],
      Return[iHTTPResponse["404 Not Found", "text/plain",
        StringToByteArray["not found", "UTF-8"]]]];
    name = StringDrop[path, 3];
    If[StringContainsQ[name, ".."] || StringContainsQ[name, "/"] ||
       StringContainsQ[name, "\\"] || name === "",
      Return[iHTTPResponse["400 Bad Request", "text/plain",
        StringToByteArray["bad path", "UTF-8"]]]];
    file = FileNameJoin[{$iAssetDirectory, name}];
    If[!FileExistsQ[file],
      Return[iHTTPResponse["404 Not Found", "text/plain",
        StringToByteArray["not found", "UTF-8"]]]];
    body = Quiet @ Check[ReadByteArray[file], $Failed];
    If[!ByteArrayQ[body],
      Return[iHTTPResponse["500 Internal Server Error", "text/plain",
        StringToByteArray["read error", "UTF-8"]]]];
    ext = ToLowerCase[FileExtension[file]];
    iHTTPResponse["200 OK",
      Lookup[$iContentTypes, ext, "application/octet-stream"], body]];

iBaseURL[] :=
  If[StringQ[ResoniteRealtime`$ResoniteRealtimePublicBaseURL] &&
     StringLength[ResoniteRealtime`$ResoniteRealtimePublicBaseURL] > 0,
    StringTrim[ResoniteRealtime`$ResoniteRealtimePublicBaseURL, "/"],
    "http://127.0.0.1:" <> ToString[$iState["Port"]] <> "/a"];

ResoniteRealtime`ResoniteRealtimeAsset[] := iEnsureAssetDirectory[];

ResoniteRealtime`ResoniteRealtimeAsset[file_String] :=
  Module[{dir, name, target},
    dir = iEnsureAssetDirectory[];
    If[!FileExistsQ[file], Return[iFailure["NoSuchFile", file <> " が見つかりません。"]]];
    name = FileNameTake[file];
    target = FileNameJoin[{dir, name}];
    If[ExpandFileName[file] =!= ExpandFileName[target],
      Quiet[CopyFile[file, target, OverwriteTarget -> True]]];
    iBaseURL[] <> "/" <> name];

(* ラスタライズは 1 か所に。Graphics のまま ImageQ で判定すると縦横比合わせが
   黙って飛ぶ (2026-09-04 のテストで検出)。 *)
iRasterize[expr_, size_] :=
  If[ImageQ[expr], expr,
    Quiet @ Check[Rasterize[expr, "Image", ImageSize -> size], $Failed]];

Options[ResoniteRealtime`ResoniteRealtimeShowImage] = {
  "Size" -> 800, "Verb" -> "img", "Send" -> True, "Target" -> Automatic};

(* Target:
     Automatic — 板 (ResoniteRealtimeBoard で作ったもの) があれば L2 で URL を差し替える。
                 無ければ L1 の行 ("img<TAB>URL") を送る。
     "Board" / "Bridge" / None — 明示指定。 *)
ResoniteRealtime`ResoniteRealtimeShowImage[expr_, opts : OptionsPattern[]] :=
  Module[{size, verb, send, target, img, dir, name, file, url, board},
    size   = OptionValue[ResoniteRealtime`ResoniteRealtimeShowImage, {opts}, "Size"];
    verb   = OptionValue[ResoniteRealtime`ResoniteRealtimeShowImage, {opts}, "Verb"];
    send   = OptionValue[ResoniteRealtime`ResoniteRealtimeShowImage, {opts}, "Send"];
    target = OptionValue[ResoniteRealtime`ResoniteRealtimeShowImage, {opts}, "Target"];
    img = iRasterize[expr, size];
    If[!ImageQ[img], Return[iFailure["Rasterize", "画像に変換できませんでした。"]]];
    dir  = iEnsureAssetDirectory[];
    (* Resonite は URL 単位でアセットをキャッシュするので毎回別名にする *)
    name = "img" <> ToString[Round[iNow[]*1000]] <> ".png";
    file = FileNameJoin[{dir, name}];
    Quiet @ Check[Export[file, img, "PNG"], Return[iFailure["Export", "PNG を書けませんでした。"]]];
    url = iBaseURL[] <> "/" <> name;
    board = Lookup[$iState, "Board", None];
    If[TrueQ[send],
      Which[
        (target === Automatic || target === "Board") && AssociationQ[board],
          ResoniteRealtime`ResoniteRealtimeUpdateComponent[board["Texture"],
            <|"URL" -> ResoniteRealtime`ResoniteRealtimeValue["Uri", url]|>];
          iFitBoard[board, img],
        target === Automatic || target === "Bridge",
          ResoniteRealtime`ResoniteRealtimeSend[verb, url],
        True, Null]];
    url];

(* ---- 板 (L2 だけで組み立てる。世界側のノード作業は不要) ----
   構成: Slot + StaticTexture2D + QuadMesh + UnlitMaterial + MeshRenderer。
   型名は ResoniteLink のモデル定義に合わせる:
     Uri フィールドは "Uri" (小文字 "uri" は弾かれる)、
     SyncList は <|"$type" -> "list", "elements" -> {...}|>。
   ID はセッション内で一意。**removeSlot したあとも同じ ID は再利用できない**ので
   毎回 ResoniteRealtimeNewId で採る。 *)

Options[ResoniteRealtime`ResoniteRealtimeBoard] = {
  "Position" -> {0, 1.5, 1.2}, "Rotation" -> None, "Size" -> 0.6,
  "Name" -> "Mathematica Board", "Parent" -> "Root", "Image" -> None};

ResoniteRealtime`ResoniteRealtimeBoard[opts : OptionsPattern[]] :=
  Module[{pos, rot, sz, name, parent, image, ids, url, r},
    If[!StringQ[$iState["Link"]],
      Return[iFailure["NotConnected",
        "板の組み立てには ResoniteLink が要ります。ResoniteRealtimeLinkConnect[port] を先に実行してください。"]]];
    pos    = OptionValue[ResoniteRealtime`ResoniteRealtimeBoard, {opts}, "Position"];
    rot    = OptionValue[ResoniteRealtime`ResoniteRealtimeBoard, {opts}, "Rotation"];
    sz     = OptionValue[ResoniteRealtime`ResoniteRealtimeBoard, {opts}, "Size"];
    name   = OptionValue[ResoniteRealtime`ResoniteRealtimeBoard, {opts}, "Name"];
    parent = OptionValue[ResoniteRealtime`ResoniteRealtimeBoard, {opts}, "Parent"];
    image  = OptionValue[ResoniteRealtime`ResoniteRealtimeBoard, {opts}, "Image"];

    (* 先にラスタライズして Image のまま持ち回る (縦横比合わせに使う) *)
    image = If[image === None, None, iRasterize[image, 800]];
    url = If[image === None, "",
      ResoniteRealtime`ResoniteRealtimeShowImage[image, "Send" -> False]];
    If[MatchQ[url, _Failure], Return[url]];

    ids = <|"Slot" -> ResoniteRealtime`ResoniteRealtimeNewId["Board"],
      "Texture" -> ResoniteRealtime`ResoniteRealtimeNewId["Tex"],
      "Mesh" -> ResoniteRealtime`ResoniteRealtimeNewId["Quad"],
      "Material" -> ResoniteRealtime`ResoniteRealtimeNewId["Mat"],
      "Renderer" -> ResoniteRealtime`ResoniteRealtimeNewId["Rend"]|>;

    r = ResoniteRealtime`ResoniteRealtimeLink[<|"$type" -> "addSlot",
      "data" -> Join[
        <|"id" -> ids["Slot"],
          "parent" -> ResoniteRealtime`ResoniteRealtimeRef[parent],
          "name" -> ResoniteRealtime`ResoniteRealtimeValue[name],
          "position" -> ResoniteRealtime`ResoniteRealtimeValue[pos],
          "scale" -> ResoniteRealtime`ResoniteRealtimeValue[{sz, sz, sz}]|>,
        If[ListQ[rot] && Length[rot] === 4,
          <|"rotation" -> ResoniteRealtime`ResoniteRealtimeValue[rot]|>, <||>]]|>];
    If[MatchQ[r, _Failure], Return[r]];

    r = ResoniteRealtime`ResoniteRealtimeAddComponent[ids["Slot"],
      "[FrooxEngine]FrooxEngine.StaticTexture2D",
      <|"URL" -> ResoniteRealtime`ResoniteRealtimeValue["Uri", url]|>, ids["Texture"]];
    If[MatchQ[r["Response"], _Failure], Return[r["Response"]]];

    r = ResoniteRealtime`ResoniteRealtimeAddComponent[ids["Slot"],
      "[FrooxEngine]FrooxEngine.QuadMesh", <||>, ids["Mesh"]];
    If[MatchQ[r["Response"], _Failure], Return[r["Response"]]];

    r = ResoniteRealtime`ResoniteRealtimeAddComponent[ids["Slot"],
      "[FrooxEngine]FrooxEngine.UnlitMaterial",
      <|"Texture" -> ResoniteRealtime`ResoniteRealtimeRef[ids["Texture"]]|>, ids["Material"]];
    If[MatchQ[r["Response"], _Failure], Return[r["Response"]]];

    r = ResoniteRealtime`ResoniteRealtimeAddComponent[ids["Slot"],
      "[FrooxEngine]FrooxEngine.MeshRenderer",
      <|"Mesh" -> ResoniteRealtime`ResoniteRealtimeRef[ids["Mesh"]],
        "Materials" -> <|"$type" -> "list",
          "elements" -> {ResoniteRealtime`ResoniteRealtimeRef[ids["Material"]]}|>|>,
      ids["Renderer"]];
    If[MatchQ[r["Response"], _Failure], Return[r["Response"]]];

    ids = Join[ids, <|"Size" -> sz, "URL" -> url|>];
    $iState = Join[$iState, <|"Board" -> ids|>];
    If[image =!= None && ImageQ[image], iFitBoard[ids, image]];
    ids];

(* 画像の縦横比に合わせて板の形を直す (QuadMesh は正方形なので slot の scale で調整) *)
iFitBoard[board_Association, img_] :=
  Module[{dim, w, h, sz},
    If[!ImageQ[img], Return[Null]];
    dim = ImageDimensions[img];
    sz = Lookup[board, "Size", 0.6];
    {w, h} = dim / Max[dim];
    ResoniteRealtime`ResoniteRealtimeUpdateSlot[board["Slot"],
      <|"scale" -> {sz*w, sz*h, sz}|>]];

iFitBoard[_, _] := Null;

ResoniteRealtime`ResoniteRealtimeRemoveBoard[] :=
  Module[{board = Lookup[$iState, "Board", None], r},
    If[!AssociationQ[board], Return[None]];
    r = ResoniteRealtime`ResoniteRealtimeRemoveSlot[board["Slot"]];
    $iState = Join[$iState, <|"Board" -> None|>];
    r];

Options[ResoniteRealtime`ResoniteRealtimeStart] = {
  "Port" -> 17300, "Heartbeat" -> 25, "LinkPort" -> None,
  "BindAddress" -> "127.0.0.1", "HeartbeatMode" -> "Ping"};

ResoniteRealtime`ResoniteRealtimeStart[opts : OptionsPattern[]] :=
  Module[{port, hb, linkPort, bind, hbMode, sid},
    port     = OptionValue[ResoniteRealtime`ResoniteRealtimeStart, {opts}, "Port"];
    hb       = OptionValue[ResoniteRealtime`ResoniteRealtimeStart, {opts}, "Heartbeat"];
    linkPort = OptionValue[ResoniteRealtime`ResoniteRealtimeStart, {opts}, "LinkPort"];
    bind     = OptionValue[ResoniteRealtime`ResoniteRealtimeStart, {opts}, "BindAddress"];
    hbMode   = OptionValue[ResoniteRealtime`ResoniteRealtimeStart, {opts}, "HeartbeatMode"];

    If[StringQ[$iState["Server"]],
      Print[Style["ResoniteRealtime はすでに起動しています。", Italic]];
      Return[ResoniteRealtime`ResoniteRealtimeStatus[]]];

    iEnsureAssetDirectory[];
    sid = ResoniteRealtime`RRWSServe[port, iBridgeHandler,
      "BindAddress" -> bind, "HTTPHandler" -> iHTTPHandler];
    If[!StringQ[sid], Return[sid]];

    $iState = Join[$iState,
      <|"Server" -> sid, "Port" -> port, "Heartbeat" -> hb,
        "HeartbeatMode" -> hbMode, "Started" -> iNow[]|>];

    If[NumericQ[hb] && hb > 0,
      $iState = Join[$iState,
        <|"HeartbeatTask" ->
          SessionSubmit[ScheduledTask[ResoniteRealtime`Private`iHeartbeat[], hb]]|>]];

    If[IntegerQ[linkPort], ResoniteRealtime`ResoniteRealtimeLinkConnect[linkPort]];

    Print[Style["ResoniteRealtime 起動しました", Bold, Darker[Green]]];
    Print["
  世界側の WebsocketClient に入れる URL:
    ws://127.0.0.1:" <> ToString[port] <> "/bridge

  ResoniteRealtimeSend[\"cmd\", ...]   → 世界へ送る
  ResoniteRealtimeOn[\"evt\", f]       → 世界からのイベントを受ける
  ResoniteRealtimeLinkConnect[port]  → ResoniteLink に繋ぐ (Dashboard で有効化した port)
  ResoniteRealtimeStatus[] / ResoniteRealtimeStop[]
"];
    ResoniteRealtime`ResoniteRealtimeStatus[]];

ResoniteRealtime`ResoniteRealtimeStop[] :=
  Module[{},
    If[MatchQ[$iState["HeartbeatTask"], _TaskObject], Quiet[TaskRemove[$iState["HeartbeatTask"]]]];
    ResoniteRealtime`ResoniteRealtimeLinkDisconnect[];
    If[StringQ[$iState["Server"]], Quiet[ResoniteRealtime`RRWSStopServe[$iState["Server"]]]];
    $iState = Join[$iState,
      <|"Server" -> None, "Port" -> None, "HeartbeatTask" -> None, "Started" -> None|>];
    Print[Style["ResoniteRealtime を停止しました。", Italic]];
    ResoniteRealtime`ResoniteRealtimeStatus[]];

ResoniteRealtime`ResoniteRealtimeSend[verb_String, args___] :=
  Module[{conns, line},
    conns = iBridgeConnections[];
    If[conns === {}, Return[iFailure["NoBridgeConnection",
      "世界から WebSocket 接続が来ていません。in-world の WebsocketClient を確認してください。"]]];
    line = StringRiffle[Prepend[Map[iToField, {args}], verb], "\t"];
    Association @ Map[# -> ResoniteRealtime`RRWSSend[#, line] &, conns]];

ResoniteRealtime`ResoniteRealtimeSendTo[connId_String, verb_String, args___] :=
  ResoniteRealtime`RRWSSend[connId,
    StringRiffle[Prepend[Map[iToField, {args}], verb], "\t"]];

iToField[s_String] := StringReplace[s, {"\t" -> " ", "\n" -> " "}];
iToField[x_] := iToField[ToString[x, InputForm]];
iToField[x_?NumericQ] := ToString[N[x]];

ResoniteRealtime`ResoniteRealtimeOn[verb : (_String | All), None] := (
  $iHandlers = KeyDrop[$iHandlers, verb]; $iHandlers);

ResoniteRealtime`ResoniteRealtimeOn[verb : (_String | All), f_] := (
  $iHandlers = Append[$iHandlers, verb -> f]; Keys[$iHandlers]);

ResoniteRealtime`ResoniteRealtimeOn[] := $iHandlers;

ResoniteRealtime`ResoniteRealtimeEvents[n_Integer : 50] :=
  Take[$iEvents, -Min[n, Length[$iEvents]]];

(* ============================================================
   L2: ResoniteLink
   ============================================================ *)

iLinkHandler[a_Association] :=
  Module[{parsed},
    Switch[a["Event"],
      "Message",
        parsed = Quiet @ Check[
          ImportByteArray[StringToByteArray[a["Data"], "UTF-8"], "RawJSON"],
          <|"$parseError" -> a["Data"]|>];
        iPush[$iLinkMessages, <|"Time" -> iNow[], "Message" -> parsed|>, $iLinkLimit],
      "Close",
        $iState = Join[$iState, <|"Link" -> None|>],
      _, Null]];

Options[ResoniteRealtime`ResoniteRealtimeLinkConnect] = {"Host" -> "localhost", "Quiet" -> False};

(* ---- ポートの自動検出 ----
   ResoniteLink は http.sys (HttpListener) で HTTP://LOCALHOST:<port>/ を登録する。登録一覧は
   `netsh http show servicestate view=requestq` で取れ、要求キューごとに所有プロセス (Resonite の場合
   Renderite.Host.exe / Resonite.exe) と登録 URL が並ぶ (2026-09-22 実測、port 8403)。UDP の announce を
   聞く resoloop discover (12 秒) より速く、依存も無い。
   **netsh の見出しは Windows の表示言語で変わる** (日本語版は「要求キュー名:」「イメージ:」) ので、
   見出し語では拾わない: (1) キューの切れ目は字下げの無い行、(2) プロセスは ASCII の exe パス、
   という字面だけで判定する (2026-09-23、日本語 Windows で英語見出し前提の旧実装が候補 0 になっていた)。 *)
iParseNetshHttp[out_String] :=
  Module[{blocks},
    blocks = StringSplit[out, RegularExpression["(?m)^(?=[^\\s])"]];
    Flatten @ Map[
      Function[b,
        With[{procs = StringCases[b, RegularExpression["[\\p{L}]:[\\\\/][^\\r\\n]*?\\.exe"]],
              ports = DeleteDuplicates @ StringCases[b, RegularExpression["(?i)HTTPS?://(?:LOCALHOST|127\\.0\\.0\\.1|\\+|\\*):(\\d+)/"] :> ToExpression["$1"]]},
          If[AnyTrue[procs, StringContainsQ[#, "Resonite" | "Renderite", IgnoreCase -> True] &],
            Map[<|"Port" -> #, "URL" -> "ws://localhost:" <> ToString[#] <> "/",
                "Process" -> FileNameTake[First[procs]], "Source" -> "netsh"|> &, ports],
            {}]]],
      blocks]];

iDiscoverNetsh[] :=
  Module[{out},
    If[$OperatingSystem =!= "Windows", Return[{}]];
    out = Quiet @ Check[RunProcess[{"netsh", "http", "show", "servicestate", "view=requestq"}, "StandardOutput"], $Failed];
    If[!StringQ[out], {}, iParseNetshHttp[out]]];

iDiscoverResoLoop[] :=
  Module[{f, r},
    If[Names["ResoLoop`ResoLoopDiscover"] === {}, Return[{}]];
    f = Symbol["ResoLoop`ResoLoopDiscover"];
    (* DownValues は HoldAll。Module 変数のまま渡すと f 自身を見て常に 0 になるので Evaluate が要る *)
    If[Length[DownValues[Evaluate[f]]] === 0, Return[{}]];
    r = Quiet @ Check[f[], $Failed];
    If[!ListQ[r], Return[{}]];
    Map[With[{url = Lookup[#, "url", ""]},
        With[{p = StringCases[url, ":" ~~ d : DigitCharacter .. ~~ "/" :> ToExpression[d]]},
          If[p === {}, Nothing,
            <|"Port" -> First[p], "URL" -> url, "Process" -> Lookup[#, "sessionName", ""], "Source" -> "resoloop"|>]]] &,
      Select[r, AssociationQ]]];

iDiscoverEnvironment[] :=
  Module[{u = Environment["RESONITE_LINK_URL"], p},
    If[!StringQ[u], Return[{}]];
    p = StringCases[u, ":" ~~ d : DigitCharacter .. :> ToExpression[d]];
    If[p === {}, {}, {<|"Port" -> Last[p], "URL" -> u, "Process" -> "RESONITE_LINK_URL", "Source" -> "env"|>}]];

ResoniteRealtime`ResoniteRealtimeDiscover[] :=
  Module[{r},
    r = iDiscoverNetsh[];
    If[r === {}, r = iDiscoverResoLoop[]];
    If[r === {}, r = iDiscoverEnvironment[]];
    r];

ResoniteRealtime`ResoniteRealtimeLinkConnect[opts : OptionsPattern[]] :=
  ResoniteRealtime`ResoniteRealtimeLinkConnect[Automatic, opts];
ResoniteRealtime`ResoniteRealtimeLinkConnect[Automatic, opts : OptionsPattern[]] :=
  Module[{found = ResoniteRealtime`ResoniteRealtimeDiscover[]},
    If[found === {},
      If[!TrueQ[OptionValue[ResoniteRealtime`ResoniteRealtimeLinkConnect, {opts}, "Quiet"]],
        Print[Style["ResoniteLink が見つかりません。Dashboard → Session → Settings → Enable ResoniteLink (ホストであること)。", Red]]];
      Return[Failure["NoResoniteLink",
        <|"MessageTemplate" -> "有効化された ResoniteLink が見つかりません (netsh / resoloop discover / RESONITE_LINK_URL)。"|>]]];
    ResoniteRealtime`ResoniteRealtimeLinkConnect[First[found]["Port"], opts]];

(* **ホスト名は localhost。127.0.0.1 では繋がらない。**
   ResoniteLink は .NET の HttpListener (http.sys) で待ち受けており、登録されている
   プレフィックスが localhost なので、127.0.0.1 で来た要求は http.sys が
   400 Bad Request (Server: Microsoft-HTTPAPI/2.0) で弾く。アプリまで届かない。
   2026-09-04 実機で確認 (node の WebSocket クライアントでも同じ挙動)。 *)
ResoniteRealtime`ResoniteRealtimeLinkConnect[port_Integer, opts : OptionsPattern[]] :=
  Module[{conn, host},
    host = OptionValue[ResoniteRealtime`ResoniteRealtimeLinkConnect, {opts}, "Host"];
    If[StringQ[$iState["Link"]], ResoniteRealtime`ResoniteRealtimeLinkDisconnect[]];
    conn = ResoniteRealtime`RRWSConnect[
      "ws://" <> host <> ":" <> ToString[port] <> "/", iLinkHandler];
    If[!StringQ[conn],
      If[!TrueQ[OptionValue[ResoniteRealtime`ResoniteRealtimeLinkConnect, {opts}, "Quiet"]],
        Print[Style["ResoniteLink に接続できませんでした。", Red]];
        Print["  Dashboard → セッション → \"Resoniteリンクを有効化\" と、表示されたポート番号を確認してください。"];
        Print["  ホスト名は localhost です (127.0.0.1 は http.sys が 400 で弾きます)。"]];
      Return[conn]];
    $iState = Join[$iState, <|"Link" -> conn, "LinkPort" -> port|>];
    If[!TrueQ[OptionValue[ResoniteRealtime`ResoniteRealtimeLinkConnect, {opts}, "Quiet"]],
      Print[Style["ResoniteLink 接続 (port " <> ToString[port] <> ")", Bold, Darker[Green]]]];
    conn];

ResoniteRealtime`ResoniteRealtimeLinkDisconnect[] := (
  If[StringQ[$iState["Link"]], Quiet[ResoniteRealtime`RRWSClose[$iState["Link"]]]];
  $iState = Join[$iState, <|"Link" -> None|>];
  None);

ResoniteRealtime`ResoniteRealtimeLinkMessages[n_Integer : 20] :=
  Take[$iLinkMessages, -Min[n, Length[$iLinkMessages]]];

Options[ResoniteRealtime`ResoniteRealtimeLink] = {
  "Timeout" -> 10, "Wait" -> Automatic, "Match" -> Automatic, "Raw" -> False};

(* "Wait" -> Automatic は $iLinkWaitDefault (既定 True) に従う。ScheduledTask / SocketListen の中では
   応答を受ける非同期ハンドラが走れず待ちが必ずタイムアウトする (2026-09-06 実機) ので、
   そこから呼ぶ側は Block[{$iLinkWaitDefault = False}, ...] で送りっぱなしにする。 *)
If[!BooleanQ[$iLinkWaitDefault], $iLinkWaitDefault = True];

(* 応答の照合 (2026-09-04 に実機で確認した仕様):
     - リクエストに "messageId" を入れると、応答の "sourceMessageId" に返ってくる。
       これを相関 ID として使う。呼び出し側が messageId を明示していればそれを尊重する。
     - 応答は成否によらず "success" (Bool) と "errorInfo" (String|Null) を持つ。
       success が False のときは errorInfo を Failure にして返す ("Raw" -> True で生のまま)。
     - $type は要求と対にならない (getSlot への応答は "slotData")。だから $type では照合しない。 *)
ResoniteRealtime`ResoniteRealtimeLink[msg_Association, opts : OptionsPattern[]] :=
  Module[{conn, timeout, wait, match, raw, t0, ba, full, msgId, candidates, res},
    conn = $iState["Link"];
    If[!StringQ[conn],
      Return[iFailure["NotConnected",
        "ResoniteLink に接続していません。ResoniteRealtimeLinkConnect[port] を先に実行してください。"]]];
    timeout = OptionValue[ResoniteRealtime`ResoniteRealtimeLink, {opts}, "Timeout"];
    wait    = Replace[OptionValue[ResoniteRealtime`ResoniteRealtimeLink, {opts}, "Wait"],
      Automatic -> $iLinkWaitDefault];
    match   = OptionValue[ResoniteRealtime`ResoniteRealtimeLink, {opts}, "Match"];
    raw     = OptionValue[ResoniteRealtime`ResoniteRealtimeLink, {opts}, "Raw"];
    msgId   = Lookup[msg, "messageId", ResoniteRealtime`ResoniteRealtimeNewId["Msg"]];
    full    = Join[<|"messageId" -> msgId|>, msg];
    (* ExportByteArray なら UTF-8 バイト列が一度だけ出る (ExportString "RawJSON" は
       byte 文字列なので二重エンコードの元になる) *)
    ba = Quiet @ Check[ExportByteArray[full, "RawJSON"], $Failed];
    If[!ByteArrayQ[ba], Return[iFailure["BadMessage", "JSON へ変換できませんでした。"]]];
    t0 = iNow[];
    ResoniteRealtime`RRWSSend[conn, ba];
    If[!TrueQ[wait], Return[<|"Sent" -> True, "MessageId" -> msgId|>]];
    candidates = {};
    (* 2026-09-22: 受信バッファは $iLinkLimit (100) 件で切り詰められる。以前は「送信前の件数より後ろ」を
       見ていたので、接続内の 101 件目以降は応答が永遠に見えずタイムアウトした (タブレットの組み立て
       ~100 メッセージで実測)。送信時刻以降に受けたものから照合する。 *)
    While[candidates === {} && iNow[] - t0 < timeout,
      Pause[0.02];
      candidates = Select[$iLinkMessages,
        Lookup[#, "Time", 0] >= t0 && iLinkResponseQ[#["Message"], match, msgId] &]];
    If[candidates === {},
      Return[iFailure["Timeout",
        "ResoniteLink から " <> ToString[timeout] <> " 秒以内に応答がありませんでした。"]]];
    res = First[candidates]["Message"];
    If[!TrueQ[raw] && AssociationQ[res] && Lookup[res, "success", True] === False,
      Failure["ResoniteLinkError",
        <|"MessageTemplate" -> "ResoniteLink: `1`",
          "MessageParameters" -> {ToString[Lookup[res, "errorInfo", "unknown error"]]},
          "Response" -> res|>],
      res]];

iLinkResponseQ[m_, match_, msgId_] :=
  AssociationQ[m] && !KeyExistsQ[m, "$parseError"] &&
    If[match === Automatic,
      (* sourceMessageId が付いている実装では厳密に照合する。
         付いていない応答 (Null) は、相関の手掛かりが無いので従来どおり受け入れる。 *)
      With[{src = Lookup[m, "sourceMessageId", Null]},
        src === msgId || src === Null || src === None],
      TrueQ[match[m]]];

(* ---- 型付き値 ---- *)

ResoniteRealtime`ResoniteRealtimeRef[id_String] :=
  <|"$type" -> "reference", "targetId" -> id|>;

ResoniteRealtime`ResoniteRealtimeValue[type_String, value_] :=
  <|"$type" -> type, "value" -> value|>;

ResoniteRealtime`ResoniteRealtimeValue[a_Association] /; KeyExistsQ[a, "$type"] := a;

ResoniteRealtime`ResoniteRealtimeValue[s_String] := <|"$type" -> "string", "value" -> s|>;
ResoniteRealtime`ResoniteRealtimeValue[True]     := <|"$type" -> "bool", "value" -> True|>;
ResoniteRealtime`ResoniteRealtimeValue[False]    := <|"$type" -> "bool", "value" -> False|>;
ResoniteRealtime`ResoniteRealtimeValue[n_Integer]:= <|"$type" -> "int", "value" -> n|>;
ResoniteRealtime`ResoniteRealtimeValue[x_?NumericQ] := <|"$type" -> "float", "value" -> N[x]|>;

ResoniteRealtime`ResoniteRealtimeValue[{x_?NumericQ, y_?NumericQ}] :=
  <|"$type" -> "float2", "value" -> <|"x" -> N[x], "y" -> N[y]|>|>;

ResoniteRealtime`ResoniteRealtimeValue[{x_?NumericQ, y_?NumericQ, z_?NumericQ}] :=
  <|"$type" -> "float3", "value" -> <|"x" -> N[x], "y" -> N[y], "z" -> N[z]|>|>;

ResoniteRealtime`ResoniteRealtimeValue[{x_?NumericQ, y_?NumericQ, z_?NumericQ, w_?NumericQ}] :=
  <|"$type" -> "float4", "value" -> <|"x" -> N[x], "y" -> N[y], "z" -> N[z], "w" -> N[w]|>|>;

ResoniteRealtime`ResoniteRealtimeValue[c_RGBColor] :=
  With[{l = List @@ ColorConvert[c, "RGB"]},
    <|"$type" -> "colorX",
      "value" -> <|"r" -> N[l[[1]]], "g" -> N[l[[2]]], "b" -> N[l[[3]]],
        "a" -> If[Length[l] >= 4, N[l[[4]]], 1.]|>|>];

iValues[members_Association] :=
  Association @ KeyValueMap[#1 -> ResoniteRealtime`ResoniteRealtimeValue[#2] &, members];

(* ---- コマンド ---- *)

Options[ResoniteRealtime`ResoniteRealtimeGetSlot] = {
  "Depth" -> 0, "IncludeComponentData" -> False, "Timeout" -> 10, "Wait" -> Automatic};

ResoniteRealtime`ResoniteRealtimeGetSlot[slotId_String : "Root", opts : OptionsPattern[]] :=
  ResoniteRealtime`ResoniteRealtimeLink[
    <|"$type" -> "getSlot", "slotId" -> slotId,
      "includeComponentData" ->
        TrueQ[OptionValue[ResoniteRealtime`ResoniteRealtimeGetSlot, {opts}, "IncludeComponentData"]],
      "depth" -> OptionValue[ResoniteRealtime`ResoniteRealtimeGetSlot, {opts}, "Depth"]|>,
    "Timeout" -> OptionValue[ResoniteRealtime`ResoniteRealtimeGetSlot, {opts}, "Timeout"],
    "Wait" -> OptionValue[ResoniteRealtime`ResoniteRealtimeGetSlot, {opts}, "Wait"]];

(* addSlot: 位置・回転・スケール・名前・親をまとめて指定できる *)
ResoniteRealtime`ResoniteRealtimeAddSlot[opts___Rule] :=
  Module[{o, id, data, res},
    o  = Association[{opts}];
    id = Lookup[o, "Id", ResoniteRealtime`ResoniteRealtimeNewId["Slot"]];
    data = <|"id" -> id|>;
    If[KeyExistsQ[o, "Parent"],
      data = Append[data,
        "parent" -> ResoniteRealtime`ResoniteRealtimeRef[Lookup[o, "Parent"]]]];
    If[KeyExistsQ[o, "Name"],
      data = Append[data, "name" -> ResoniteRealtime`ResoniteRealtimeValue[Lookup[o, "Name"]]]];
    If[KeyExistsQ[o, "Position"],
      data = Append[data, "position" -> ResoniteRealtime`ResoniteRealtimeValue[Lookup[o, "Position"]]]];
    If[KeyExistsQ[o, "Rotation"],
      data = Append[data, "rotation" -> ResoniteRealtime`ResoniteRealtimeValue[Lookup[o, "Rotation"]]]];
    If[KeyExistsQ[o, "Scale"],
      data = Append[data, "scale" -> ResoniteRealtime`ResoniteRealtimeValue[Lookup[o, "Scale"]]]];
    If[KeyExistsQ[o, "Active"],
      (* キー名は応答と同じ "isActive" (updateSlot で実測。"active" は無視される) *)
      data = Append[data, "isActive" -> ResoniteRealtime`ResoniteRealtimeValue[Lookup[o, "Active"]]]];
    res = ResoniteRealtime`ResoniteRealtimeLink[<|"$type" -> "addSlot", "data" -> data|>];
    <|"Id" -> id, "Response" -> res|>];

ResoniteRealtime`ResoniteRealtimeUpdateSlot[slotId_String, members_Association] :=
  ResoniteRealtime`ResoniteRealtimeLink[
    <|"$type" -> "updateSlot",
      "data" -> Join[<|"id" -> slotId|>, iValues[members]]|>];

ResoniteRealtime`ResoniteRealtimeRemoveSlot[slotId_String] :=
  ResoniteRealtime`ResoniteRealtimeLink[<|"$type" -> "removeSlot", "slotId" -> slotId|>];

ResoniteRealtime`ResoniteRealtimeAddComponent[slotId_String, componentType_String,
  members_Association : <||>, componentId_ : Automatic] :=
  Module[{id, res},
    id = If[StringQ[componentId], componentId,
      ResoniteRealtime`ResoniteRealtimeNewId["Comp"]];
    res = ResoniteRealtime`ResoniteRealtimeLink[
      <|"$type" -> "addComponent", "containerSlotId" -> slotId,
        "data" -> <|"id" -> id, "componentType" -> componentType,
          "members" -> iValues[members]|>|>];
    <|"Id" -> id, "Response" -> res|>];

ResoniteRealtime`ResoniteRealtimeUpdateComponent[componentId_String, members_Association] :=
  ResoniteRealtime`ResoniteRealtimeLink[
    <|"$type" -> "updateComponent",
      "data" -> <|"id" -> componentId, "members" -> iValues[members]|>|>];

(* ============================================================
   状態表示
   ============================================================ *)

ResoniteRealtime`ResoniteRealtimeStatus[] :=
  Module[{ws},
    ws = Quiet @ Check[ResoniteRealtime`RRWSStatus[], <||>];
    <|"Running" -> StringQ[$iState["Server"]],
      "Port" -> $iState["Port"],
      "BridgeConnections" -> iBridgeConnections[],
      "Heartbeat" -> $iState["Heartbeat"],
      "Link" -> $iState["Link"],
      "LinkPort" -> $iState["LinkPort"],
      "LinkConnected" -> StringQ[$iState["Link"]] &&
        KeyExistsQ[Lookup[ws, "Connections", <||>], $iState["Link"]],
      "Events" -> Length[$iEvents],
      "LinkMessages" -> Length[$iLinkMessages],
      "Uptime" -> If[NumericQ[$iState["Started"]],
        Round[iNow[] - $iState["Started"], 0.1], None],
      "WebSocket" -> ws|>];

(* 常駐ポーリングはしない。押したときだけ読み直す (パレット常駐 Dynamic は FE を殺す) *)
ResoniteRealtime`ResoniteRealtimeMonitor[] :=
  DynamicModule[{tick = 0},
    Dynamic[
      tick;
      Module[{st = ResoniteRealtime`ResoniteRealtimeStatus[]},
        Framed[
          Column[{
            Style["ResoniteRealtime " <> ResoniteRealtime`$ResoniteRealtimeVersion, Bold],
            Row[{"bridge: ",
              If[TrueQ[st["Running"]],
                Style["running :" <> ToString[st["Port"]], Darker[Green]],
                Style["stopped", Gray]],
              "   接続: ", Length[st["BridgeConnections"]]}],
            Row[{"link: ",
              If[TrueQ[st["LinkConnected"]],
                Style["connected :" <> ToString[st["LinkPort"]], Darker[Green]],
                Style["disconnected", Gray]]}],
            Row[{"events: ", st["Events"], "   link msgs: ", st["LinkMessages"]}],
            Row[{
              Button["更新", tick++, ImageSize -> {60, 24}],
              Spacer[6],
              Button["停止", ResoniteRealtime`ResoniteRealtimeStop[]; tick++,
                ImageSize -> {60, 24}]}]},
            Spacings -> 0.4],
          Background -> GrayLevel[0.97], FrameMargins -> 8]],
      TrackedSymbols :> {tick}]];

End[];

EndPackage[];

Print[Style["ResoniteRealtime パッケージがロードされました。", Bold]];
Print["
  ResoniteRealtimeStart[]              → L1 ブリッジ起動 (ws://127.0.0.1:17300/bridge)
  ResoniteRealtimeOn[verb, f]          → 世界からの行にハンドラを登録
  ResoniteRealtimeSend[verb, args...]  → 世界へ TAB 区切りの行を送る
  ResoniteRealtimeLinkConnect[]        → ResoniteLink に接続 (port は自動検出。ResoniteRealtimeLinkConnect[port] で明示)
  ResoniteTabletServe[]                → 常駐監視: ResoniteLink を自動検出して繋ぎ、ワールドのタブレットの「接続」を待つ (NB では自動起動)
  ResoniteRealtimeGetSlot[]            → シーン階層を取得
  ResoniteRealtimeAddSlot[...]         → slot を作る
  ResoniteRealtimeStatus[] / ResoniteRealtimeMonitor[] / ResoniteRealtimeStop[]
  ResoniteChatGadget[] / ResoniteChatStart[]  → ワールド内 Chat パネルを作り、入力を監視
  ResoniteChat[prompt] / ResoniteChatCell[]   → Chat セルの答えをワールドへ出す
  ResoniteAccessLevel[\"Private\"|\"Contacts\"|\"Public\", \"Owner\" -> True]  → 表示上限 PL (1.0 / 0.5 / 0.25。非オーナーは 0.25)
  ResoniteFluxChat[spec] / ResoniteFluxCell[] → ProtoFlux (ProtoGraph) を生成して出す
  ResoniteTablet[]                     → ワールド内タブレット (ClaudeEval / 承認 / スクロール出力 / ビューア)
  ResoniteShowObject[uri|row|file|expr] / ResoniteListGadget[rows] → SourceVault オブジェクトと一覧をワールドへ
  ResoniteColorToggleBox[{Red, Blue}]  → クリックで色が切り替わる箱 (提案コード 1 つで作れる部品)
"];

(* ノートブックのセッションでは常駐監視を自動で始める (インベントリから出したタブレットの「接続」で使えるように)。
   ヘッドレス (テスト / サービスカーネル) では始めない。$ResoniteTabletAutoServe = False で止められる。 *)
If[!BooleanQ[ResoniteRealtime`$ResoniteTabletAutoServe], ResoniteRealtime`$ResoniteTabletAutoServe = True];
If[TrueQ[ResoniteRealtime`$ResoniteTabletAutoServe] && TrueQ[$Notebooks] &&
   Names["ResoniteRealtime`ResoniteTabletServe"] =!= {},
  Quiet @ Check[ResoniteRealtime`ResoniteTabletServe[], Null]];
