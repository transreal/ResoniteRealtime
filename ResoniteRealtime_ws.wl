(* ::Package:: *)

(* ResoniteRealtime_ws.wl -- 純 Wolfram の WebSocket 層 (RFC 6455, server + client)

   This file is encoded in UTF-8.
   Load via: Block[{$CharacterEncoding="UTF-8"}, Get["ResoniteRealtime_ws.wl"]]

   位置づけ:
     ResoniteRealtime.wl の下回り。Resonite との 2 経路が両方 WebSocket なので、
     サーバ側 (in-world WebsocketClient が繋いでくる) とクライアント側
     (ResoniteLink へ繋ぎに行く) の両方を 1 つのフレーム codec で賄う。

   設計:
     - 依存ゼロ。SocketOpen / SocketListen / SocketConnect だけで完結する
       (Python ワーカーも J/Link も使わない)。
     - サーバ側はマスク解除のみ、クライアント側は送信フレームをマスクする
       (RFC 6455: クライアント→サーバのフレームは必ずマスクされる)。
     - 受信は SocketListen の非同期ハンドラ。FrontEnd 通信は一切しない
       (WebServer.wl 冒頭の rule 95-B 例外と同じ扱い)。
     - BinaryWrite は 512 バイト単位に割る (WebServer.wl iSendResponse と同じ理由:
       環境によって 1 回の書き込みサイズが制限される)。
     - ハンドラ内で Pause しない (SocketListen コンテキストで FE をブロックする)。

   公開 API:
     RRWSServe[port, handler]      → サーバ起動。handler は Association を受ける
     RRWSStopServe[serverId]       → サーバ停止 (接続も閉じる)
     RRWSConnect[url, handler]     → クライアント接続 (ws://host:port/path)
     RRWSSend[connId, text]        → テキストフレーム送信
     RRWSPing[connId]              → ping 送信 (keepalive)
     RRWSClose[connId]             → close ハンドシェイクして切断
     RRWSStatus[]                  → サーバ/接続の一覧 (Association)
     RRWSConnections[]             → 接続 ID のリスト

   handler が受け取る Association:
     <|"Event" -> "Open"|"Message"|"Close"|"Error",
       "Connection" -> connId, "Role" -> "server"|"client",
       "Data" -> text (Message のとき), "Opcode" -> 1|2, "Time" -> AbsoluteTime|>
*)

BeginPackage["ResoniteRealtime`"];

RRWSServe::usage =
  "RRWSServe[port, handler] は port で WebSocket サーバを起動し、サーバ ID を返す。\n" <>
  "handler[assoc] は \"Event\" が \"Open\" / \"Message\" / \"Close\" の Association を受ける。\n" <>
  "オプション: \"BindAddress\" -> \"127.0.0.1\" (既定) | \"0.0.0.0\"。";

RRWSStopServe::usage =
  "RRWSStopServe[serverId] はサーバと、そのサーバが持つ接続をすべて閉じる。RRWSStopServe[] は全サーバ。";

RRWSConnect::usage =
  "RRWSConnect[\"ws://127.0.0.1:1234/path\", handler] はクライアントとして接続し、接続 ID を返す。\n" <>
  "ハンドシェイクは同期 (既定 10 秒)、以後の受信は非同期。オプション: \"Timeout\" -> 10。";

RRWSSend::usage =
  "RRWSSend[connId, text] はテキストフレームを送る。text は String または ByteArray (UTF-8 とみなす)。";

RRWSPing::usage = "RRWSPing[connId] は ping フレームを送る (keepalive 用)。";

RRWSClose::usage = "RRWSClose[connId] は close フレームを送ってソケットを閉じる。";

RRWSStatus::usage = "RRWSStatus[] はサーバと接続の状態を Association で返す。";

RRWSSweep::usage =
  "RRWSSweep[] は閉じ待ちのソケットを回収する。公開 API から自動で呼ばれるので通常は不要。\n" <>
  "SocketListen のコールバック内では何もしない (そこで Close するとカーネルが落ちるため)。";

RRWSConnections::usage = "RRWSConnections[] は生きている接続 ID のリストを返す。";

$RRWSLastError::usage = "$RRWSLastError は最後に握りつぶされたハンドラ例外の記録。";

Begin["`Private`"];

(* 再ロード時に古い定義を残さない (本体 ResoniteRealtime.wl と同じ理由。
   この 1 ファイルだけを Get したときのためにここにも置く)。
   状態は ResoniteRealtime`Private` 側なので接続は保たれる。 *)
Scan[Quiet[Clear[#]] &, Names["ResoniteRealtime`RRWS*"]];

$iWSGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

(* 再ロードで生きている接続を落とさないよう、初期化はガード付き *)
If[!AssociationQ[$iWSConns],   $iWSConns   = <||>];
If[!AssociationQ[$iWSServers], $iWSServers = <||>];
If[!AssociationQ[$iWSIndex],   $iWSIndex   = <||>];   (* socket key -> connId *)
If[!IntegerQ[$iWSCounter],     $iWSCounter = 0];
If[!ListQ[$iWSGraveyard],      $iWSGraveyard = {}];   (* 遅延クローズ待ち *)
$iWSInCallback = False;
If[!ValueQ[ResoniteRealtime`$RRWSLastError], ResoniteRealtime`$RRWSLastError = None];

(* ============================================================
   小道具
   ============================================================ *)

iSocketKey[sock_SocketObject] := ToString[InputForm[sock]];
iSocketKey[_] := "";

iNextId[prefix_String] := (
  $iWSCounter = $iWSCounter + 1;
  prefix <> ToString[$iWSCounter]);

iEmptyBA[] := ByteArray[{}];

iBAJoin[a_ByteArray, b_ByteArray] :=
  Which[
    Length[a] === 0, b,
    Length[b] === 0, a,
    True, ByteArray[Join[Normal[a], Normal[b]]]];

(* 512 バイト単位の確実な書き込み (WebServer.wl iSendResponse と同じ方針) *)
iWriteBytes[sock_SocketObject, ba_ByteArray] :=
  Module[{list = Normal[ba], n, i = 1},
    n = Length[list];
    While[i <= n,
      Quiet[BinaryWrite[sock, ByteArray[list[[i ;; Min[i + 511, n]]]]]];
      i += 512];
    n];

iCallHandler[f_, arg_Association] :=
  Module[{res},
    res = Check[f[arg], $Failed];
    If[res === $Failed,
      ResoniteRealtime`$RRWSLastError =
        <|"Time" -> AbsoluteTime[], "Argument" -> arg|>];
    res];

iCallHandler[_, _] := Null;

(* ============================================================
   フレーム codec
   ============================================================ *)

(* opcode: 1 text / 2 binary / 8 close / 9 ping / 10 pong *)
iEncodeFrame[opcode_Integer, payload_ByteArray, masked : (True | False) : False] :=
  Module[{pl = Normal[payload], n, header, key, body},
    n = Length[pl];
    header = {BitOr[128, opcode]};
    Which[
      n < 126,
        header = Join[header, {If[masked, BitOr[128, n], n]}],
      n < 65536,
        header = Join[header,
          {If[masked, BitOr[128, 126], 126],
           BitAnd[BitShiftRight[n, 8], 255], BitAnd[n, 255]}],
      True,
        header = Join[header,
          {If[masked, BitOr[128, 127], 127]},
          Table[BitAnd[BitShiftRight[n, 8*(7 - k)], 255], {k, 0, 7}]]];
    If[masked,
      key  = RandomInteger[{0, 255}, 4];
      body = BitXor[pl, PadRight[{}, n, key]];
      ByteArray[Join[header, key, body]],
      ByteArray[Join[header, pl]]]];

(* buffer から 1 フレーム取り出す。
   返り値: {frame, rest} または None (まだ足りない) *)
iDecodeFrame[buf_ByteArray] :=
  Module[{b, len, b0, b1, fin, opcode, masked, len7, off, plen, key, payload},
    len = Length[buf];
    If[len < 2, Return[None]];
    b = Normal[buf];
    b0 = b[[1]]; b1 = b[[2]];
    fin    = BitAnd[b0, 128] > 0;
    opcode = BitAnd[b0, 15];
    masked = BitAnd[b1, 128] > 0;
    len7   = BitAnd[b1, 127];
    Which[
      len7 < 126, plen = len7; off = 2,
      len7 === 126,
        If[len < 4, Return[None]];
        plen = b[[3]]*256 + b[[4]]; off = 4,
      True,
        If[len < 10, Return[None]];
        plen = FromDigits[b[[3 ;; 10]], 256]; off = 10];
    If[masked,
      If[len < off + 4, Return[None]];
      key = b[[off + 1 ;; off + 4]];
      off = off + 4,
      key = None];
    If[len < off + plen, Return[None]];
    payload = If[plen === 0, {}, b[[off + 1 ;; off + plen]]];
    If[masked && plen > 0,
      payload = BitXor[payload, PadRight[{}, plen, key]]];
    {<|"Fin" -> fin, "Opcode" -> opcode, "Payload" -> ByteArray[payload]|>,
     If[len > off + plen, ByteArray[b[[off + plen + 1 ;; len]]], iEmptyBA[]]}];

(* ============================================================
   ハンドシェイク
   ============================================================ *)

iAcceptKey[clientKey_String] :=
  BaseEncode[Hash[clientKey <> $iWSGUID, "SHA", "ByteArray"]];

iFindHeaderEnd[buf_ByteArray] :=
  Module[{pos},
    If[Length[buf] < 4, Return[None]];
    pos = SequencePosition[Normal[buf], {13, 10, 13, 10}, 1];
    If[pos === {}, None, pos[[1, 2]]]];

(* "GET /a/x.png HTTP/1.1" -> "/a/x.png" *)
iRequestPath[text_String] :=
  Module[{first, parts},
    first = First[StringSplit[text, "\r\n"], ""];
    parts = StringSplit[first, " "];
    If[Length[parts] >= 2, parts[[2]], "/"]];

iParseHeaders[text_String] :=
  Association @ Cases[
    StringSplit[text, "\r\n"],
    line_String /; StringContainsQ[line, ":"] :>
      Rule[
        ToLowerCase @ StringTrim @ First @ StringSplit[line, ":", 2],
        StringTrim @ Last @ StringSplit[line, ":", 2]]];

(* ============================================================
   接続テーブル
   ============================================================ *)

iRegisterConn[connId_String, assoc_Association] := (
  $iWSConns = Append[$iWSConns, connId -> assoc];
  $iWSIndex = Append[$iWSIndex, iSocketKey[assoc["Socket"]] -> connId];
  connId);

iDropConn[connId_String] :=
  Module[{c = Lookup[$iWSConns, connId, None]},
    If[AssociationQ[c],
      $iWSIndex = KeyDrop[$iWSIndex, iSocketKey[c["Socket"]]];
      $iWSConns = KeyDrop[$iWSConns, connId]];
    connId];

iConnOf[sock_SocketObject] := Lookup[$iWSIndex, iSocketKey[sock], None];

iUpdateConn[connId_String, rules_Association] :=
  If[KeyExistsQ[$iWSConns, connId],
    $iWSConns[connId] = Join[$iWSConns[connId], rules]];

(* ============================================================
   受信処理 (サーバ・クライアント共通)
   ============================================================ *)

(* コールバックはすべて $iWSInCallback = True の下で走らせる (iSweep の抑止) *)
iSocketEvent[assoc_Association] :=
  Block[{$iWSInCallback = True}, iSocketEvent0[assoc]];

iSocketEvent[_] := Null;

iSocketEvent0[assoc_Association] :=
  Module[{sock, data, connId},
    sock = Lookup[assoc, "SourceSocket", None];
    If[!MatchQ[sock, _SocketObject], Return[Null]];
    data = Lookup[assoc, "DataByteArray", None];
    If[!ByteArrayQ[data] || Length[data] === 0, Return[Null]];
    connId = iConnOf[sock];
    If[connId === None,
      (* 新規接続 (サーバ側): どのサーバのものか listener 経由で分からないので
         ここでは扱えない。iServerAccept で登録済みのはず。 *)
      Return[Null]];
    iUpdateConn[connId,
      <|"Buffer" -> iBAJoin[$iWSConns[connId]["Buffer"], data],
        "LastRecv" -> AbsoluteTime[]|>];
    iPump[connId]];

iSocketEvent0[_] := Null;

(* buffer を可能な限り処理する *)
iPump[connId_String] :=
  Module[{c, done = False},
    While[!done,
      c = Lookup[$iWSConns, connId, None];
      If[!AssociationQ[c], Return[Null]];
      If[TrueQ[c["Handshake"]],
        done = !iPumpFrames[connId],
        done = !iPumpHandshake[connId]]]];

(* サーバ側ハンドシェイク応答。まだヘッダが揃わなければ False *)
iPumpHandshake[connId_String] :=
  Module[{c, endPos, text, headers, key, resp, srv, httpHandler, reply},
    c = $iWSConns[connId];
    If[c["Role"] =!= "server", Return[False]];
    endPos = iFindHeaderEnd[c["Buffer"]];
    If[endPos === None, Return[False]];
    text = Quiet @ Check[
      ByteArrayToString[ByteArray[Normal[c["Buffer"]][[1 ;; endPos]]], "UTF-8"],
      ""];
    headers = iParseHeaders[text];
    key = Lookup[headers, "sec-websocket-key", None];
    (* Upgrade でない = ただの HTTP GET。同じポートで静的ファイルも配れるように
       サーバに登録された HTTPHandler へ渡す (画像を Resonite に読ませる用途。
       ws と同じ host:port なのでホストアクセスの許可を使い回せる)。 *)
    If[!StringQ[key],
      srv = Lookup[$iWSServers, Lookup[c, "Server", ""], <||>];
      httpHandler = Lookup[srv, "HTTPHandler", None];
      If[httpHandler =!= None,
        reply = iCallHandler[httpHandler,
          <|"Method" -> StringTake[text, UpTo[8]],
            "Request" -> text, "Headers" -> headers,
            "Path" -> iRequestPath[text], "Connection" -> connId|>];
        If[ByteArrayQ[reply], iWriteBytes[c["Socket"], reply]]];
      iCloseSocket[connId, "HTTP"];
      Return[False]];
    resp = StringJoin[
      "HTTP/1.1 101 Switching Protocols\r\n",
      "Upgrade: websocket\r\n",
      "Connection: Upgrade\r\n",
      "Sec-WebSocket-Accept: ", iAcceptKey[key], "\r\n\r\n"];
    iWriteBytes[c["Socket"], StringToByteArray[resp, "UTF-8"]];
    iUpdateConn[connId,
      <|"Handshake" -> True,
        "Buffer" -> If[Length[c["Buffer"]] > endPos,
          ByteArray[Normal[c["Buffer"]][[endPos + 1 ;; -1]]], iEmptyBA[]],
        "Headers" -> headers|>];
    iCallHandler[c["Handler"],
      <|"Event" -> "Open", "Connection" -> connId, "Role" -> "server",
        "Time" -> AbsoluteTime[]|>];
    True];

(* フレームを 1 つ処理する。処理できたら True *)
iPumpFrames[connId_String] :=
  Module[{c, res, frame, rest, op, payload, text},
    c = $iWSConns[connId];
    res = iDecodeFrame[c["Buffer"]];
    If[res === None, Return[False]];
    {frame, rest} = res;
    iUpdateConn[connId, <|"Buffer" -> rest|>];
    op      = frame["Opcode"];
    payload = frame["Payload"];
    Which[
      (* continuation / text / binary *)
      op === 0 || op === 1 || op === 2,
        Module[{fragOp, fragData, finished},
          fragOp   = If[op === 0, c["FragOpcode"], op];
          fragData = If[op === 0, iBAJoin[c["FragData"], payload], payload];
          finished = TrueQ[frame["Fin"]];
          If[!finished,
            iUpdateConn[connId,
              <|"FragOpcode" -> fragOp, "FragData" -> fragData|>],
            iUpdateConn[connId,
              <|"FragOpcode" -> 1, "FragData" -> iEmptyBA[],
                "Received" -> c["Received"] + 1|>];
            text = If[fragOp === 1,
              Quiet @ Check[ByteArrayToString[fragData, "UTF-8"], ""], None];
            iCallHandler[c["Handler"],
              <|"Event" -> "Message", "Connection" -> connId,
                "Role" -> c["Role"], "Opcode" -> fragOp,
                "Data" -> If[fragOp === 1, text, fragData],
                "Time" -> AbsoluteTime[]|>]]],
      (* close *)
      op === 8,
        iWriteBytes[c["Socket"], iEncodeFrame[8, iEmptyBA[], c["Role"] === "client"]];
        iCloseSocket[connId, "Peer"],
      (* ping *)
      op === 9,
        iWriteBytes[c["Socket"], iEncodeFrame[10, payload, c["Role"] === "client"]],
      (* pong *)
      op === 10,
        iUpdateConn[connId, <|"LastPong" -> AbsoluteTime[]|>],
      True, Null];
    True];

(* ---- クローズ規約 (実測で決めた。順序を変えないこと) ----

   1) 索引から先に外す。閉鎖中に届くイベントを「知らない接続」として捨てる。
      同一カーネル内に両端がある場合 (WL クライアント ⇄ WL サーバ) は close フレームの
      往復が非同期ハンドラの再入を起こすため、これが無いと閉じかけの接続を二重処理する。

   2) **実際の Close / DeleteObject は SocketListen コールバックの中で絶対にやらない。**
      墓場 ($iWSGraveyard) に積んで、トップレベル (公開 API) から iSweep[] で回収する。
      コールバック内で Close すると、以後に別ソケットを閉じたときカーネルごと落ちる
      (2026-09-04 実測: node クライアントが切断 → server 側を callback 内で Close →
       その後 WL クライアントを RRWSClose した瞬間に "The product exited for an
       unknown reason."。墓場方式にすると再現しない)。

   3) listener を削除してから socket を閉じる。逆順だと生きている SocketListener が
      閉じたソケットのイベントを拾って落ちる。

   4) ハンドラ通知は後始末のあと。ハンドラが再入しても状態は整合している。 *)

iRetireConn[c_Association] :=
  AppendTo[$iWSGraveyard,
    <|"Listener" -> c["Listener"], "Socket" -> c["Socket"], "Time" -> AbsoluteTime[]|>];

iSweep[] :=
  Module[{g},
    If[TrueQ[$iWSInCallback] || $iWSGraveyard === {}, Return[0]];
    g = $iWSGraveyard;
    $iWSGraveyard = {};
    Scan[
      Function[e,
        If[MatchQ[e["Listener"], _SocketListener], Quiet[DeleteObject[e["Listener"]]]];
        Quiet[Close[e["Socket"]]]],
      g];
    Length[g]];

iCloseSocket[connId_String, reason_String] :=
  Module[{c = Lookup[$iWSConns, connId, None]},
    If[!AssociationQ[c], Return[connId]];
    iDropConn[connId];
    iRetireConn[c];
    iCallHandler[c["Handler"],
      <|"Event" -> "Close", "Connection" -> connId, "Role" -> c["Role"],
        "Reason" -> reason, "Time" -> AbsoluteTime[]|>];
    connId];

(* ============================================================
   サーバ
   ============================================================ *)

iServerEvent[serverId_String, assoc_Association] :=
  Block[{$iWSInCallback = True}, iServerEvent0[serverId, assoc]];

iServerEvent0[serverId_String, assoc_Association] :=
  Module[{sock, connId},
    sock = Lookup[assoc, "SourceSocket", None];
    If[!MatchQ[sock, _SocketObject], Return[Null]];
    connId = iConnOf[sock];
    If[connId === None,
      connId = iNextId["ws"];
      iRegisterConn[connId,
        <|"Socket" -> sock, "Role" -> "server", "Server" -> serverId,
          "Handler" -> $iWSServers[serverId]["Handler"],
          "Buffer" -> iEmptyBA[], "Handshake" -> False,
          "FragOpcode" -> 1, "FragData" -> iEmptyBA[],
          "Opened" -> AbsoluteTime[], "LastRecv" -> AbsoluteTime[],
          "LastPong" -> None, "Sent" -> 0, "Received" -> 0,
          "Listener" -> None|>]];
    iSocketEvent[assoc]];

ResoniteRealtime`RRWSServe[port_Integer, handler_, opts : OptionsPattern[]] :=
  Module[{bind, sock, serverId, listener},
    iSweep[];
    bind = OptionValue[ResoniteRealtime`RRWSServe, {opts}, "BindAddress"];
    sock = Quiet @ Check[
      If[bind === "127.0.0.1" || bind === Automatic,
        SocketOpen[{"127.0.0.1", port}, "TCP"],
        SocketOpen[{bind, port}, "TCP"]],
      $Failed];
    If[!MatchQ[sock, _SocketObject],
      Return[Failure["PortUnavailable",
        <|"MessageTemplate" -> "port `1` を開けませんでした。", "MessageParameters" -> {port}|>]]];
    serverId = iNextId["wss"];
    $iWSServers = Append[$iWSServers,
      serverId -> <|"Socket" -> sock, "Port" -> port, "Handler" -> handler,
        "HTTPHandler" -> OptionValue[ResoniteRealtime`RRWSServe, {opts}, "HTTPHandler"],
        "Listener" -> None, "Started" -> AbsoluteTime[]|>];
    listener = SocketListen[sock,
      Function[ev, ResoniteRealtime`Private`iServerEvent[serverId, ev]]];
    $iWSServers[serverId] =
      Join[$iWSServers[serverId], <|"Listener" -> listener|>];
    serverId];

Options[ResoniteRealtime`RRWSServe] = {
  "BindAddress" -> "127.0.0.1", "HTTPHandler" -> None};

ResoniteRealtime`RRWSStopServe[serverId_String] :=
  Module[{s = Lookup[$iWSServers, serverId, None]},
    If[!AssociationQ[s], Return[$Failed]];
    Scan[iCloseSocket[#, "ServerStopped"] &,
      Keys @ Select[$iWSConns, #["Server"] === serverId &]];
    iRetireConn[<|"Listener" -> s["Listener"], "Socket" -> s["Socket"]|>];
    $iWSServers = KeyDrop[$iWSServers, serverId];
    (* 相手側 (同一カーネル内のこともある) のコールバックが動く余地を作ってから回収 *)
    Pause[0.15];
    iSweep[];
    serverId];

ResoniteRealtime`RRWSStopServe[] := Scan[ResoniteRealtime`RRWSStopServe, Keys[$iWSServers]];

(* ============================================================
   クライアント
   ============================================================ *)

(* 末尾が "/" の URL に注意。StringSplit は末尾の空要素を落とすので
   StringSplit["h:1/", "/", 2] は {"h:1"} になり、Last がホスト名を返してしまう
   (2026-09-04: ws://127.0.0.1:13116/ が GET /127.0.0.1:13116 になり
    ResoniteLink 側の http.sys に 400 Bad Request で弾かれた)。
   最初の "/" の位置で切る。 *)
iParseWSURL[url_String] :=
  Module[{rest, hostport, path, host, port, slash},
    rest = Which[
      StringStartsQ[url, "ws://"],  StringDrop[url, 5],
      StringStartsQ[url, "http://"], StringDrop[url, 7],
      True, url];
    slash = StringPosition[rest, "/", 1];
    {hostport, path} = If[slash === {},
      {rest, "/"},
      {StringTake[rest, slash[[1, 1]] - 1], StringDrop[rest, slash[[1, 1]] - 1]}];
    If[path === "", path = "/"];
    {host, port} = If[StringContainsQ[hostport, ":"],
      {First @ StringSplit[hostport, ":"],
       ToExpression @ Last @ StringSplit[hostport, ":"]},
      {hostport, 80}];
    <|"Host" -> host, "Port" -> port, "Path" -> path|>];

ResoniteRealtime`RRWSConnect[url_String, handler_, opts : OptionsPattern[]] :=
  Module[{u, timeout, sock, key, req, buf, endPos, text, headers, connId, listener, t0},
    iSweep[];
    timeout = OptionValue[ResoniteRealtime`RRWSConnect, {opts}, "Timeout"];
    u = iParseWSURL[url];
    sock = Quiet @ Check[
      SocketConnect[u["Host"] <> ":" <> ToString[u["Port"]], "TCP"], $Failed];
    If[!MatchQ[sock, _SocketObject],
      Return[Failure["ConnectFailed",
        <|"MessageTemplate" -> "`1` へ接続できませんでした。",
          "MessageParameters" -> {url}|>]]];
    key = BaseEncode[ByteArray[RandomInteger[{0, 255}, 16]]];
    req = StringJoin[
      "GET ", u["Path"], " HTTP/1.1\r\n",
      "Host: ", u["Host"], ":", ToString[u["Port"]], "\r\n",
      "Upgrade: websocket\r\n",
      "Connection: Upgrade\r\n",
      "Sec-WebSocket-Key: ", key, "\r\n",
      "Sec-WebSocket-Version: 13\r\n\r\n"];
    iWriteBytes[sock, StringToByteArray[req, "UTF-8"]];
    (* ハンドシェイク応答は同期で読む *)
    buf = iEmptyBA[];
    t0 = AbsoluteTime[];
    endPos = None;
    While[endPos === None && AbsoluteTime[] - t0 < timeout,
      Module[{chunk},
        chunk = Quiet @ TimeConstrained[SocketReadMessage[sock], timeout, None];
        If[ByteArrayQ[chunk] && Length[chunk] > 0,
          buf = iBAJoin[buf, chunk];
          endPos = iFindHeaderEnd[buf],
          Break[]]]];
    If[endPos === None,
      Quiet[Close[sock]];
      Return[Failure["HandshakeTimeout",
        <|"MessageTemplate" -> "`1` のハンドシェイク応答が来ませんでした。",
          "MessageParameters" -> {url}|>]]];
    text = Quiet @ Check[
      ByteArrayToString[ByteArray[Normal[buf][[1 ;; endPos]]], "UTF-8"], ""];
    If[!StringContainsQ[text, "101"],
      Quiet[Close[sock]];
      Return[Failure["HandshakeRejected",
        <|"MessageTemplate" -> "ハンドシェイクが 101 になりませんでした: `1`",
          "MessageParameters" -> {StringTake[text, UpTo[120]]}|>]]];
    headers = iParseHeaders[text];
    If[Lookup[headers, "sec-websocket-accept", ""] =!= iAcceptKey[key],
      Quiet[Close[sock]];
      Return[Failure["BadAcceptKey",
        <|"MessageTemplate" -> "Sec-WebSocket-Accept が一致しません。"|>]]];
    connId = iNextId["wc"];
    iRegisterConn[connId,
      <|"Socket" -> sock, "Role" -> "client", "Server" -> None,
        "Handler" -> handler, "URL" -> url,
        "Buffer" -> If[Length[buf] > endPos,
          ByteArray[Normal[buf][[endPos + 1 ;; -1]]], iEmptyBA[]],
        "Handshake" -> True, "FragOpcode" -> 1, "FragData" -> iEmptyBA[],
        "Opened" -> AbsoluteTime[], "LastRecv" -> AbsoluteTime[],
        "LastPong" -> None, "Sent" -> 0, "Received" -> 0,
        "Headers" -> headers, "Listener" -> None|>];
    listener = SocketListen[sock, ResoniteRealtime`Private`iSocketEvent];
    iUpdateConn[connId, <|"Listener" -> listener|>];
    iCallHandler[handler,
      <|"Event" -> "Open", "Connection" -> connId, "Role" -> "client",
        "Time" -> AbsoluteTime[]|>];
    (* ハンドシェイク直後に届いていた分を処理 *)
    iPump[connId];
    connId];

Options[ResoniteRealtime`RRWSConnect] = {"Timeout" -> 10};

(* ============================================================
   送信 / 状態
   ============================================================ *)

iSendFrame[connId_String, opcode_Integer, payload_ByteArray] :=
  Module[{c = Lookup[$iWSConns, connId, None]},
    If[!AssociationQ[c], Return[$Failed]];
    If[!TrueQ[c["Handshake"]], Return[$Failed]];
    iWriteBytes[c["Socket"], iEncodeFrame[opcode, payload, c["Role"] === "client"]];
    iUpdateConn[connId, <|"Sent" -> c["Sent"] + 1, "LastSend" -> AbsoluteTime[]|>];
    Length[payload]];

ResoniteRealtime`RRWSSend[connId_String, text_String] :=
  iSendFrame[connId, 1, StringToByteArray[text, "UTF-8"]];

ResoniteRealtime`RRWSSend[connId_String, ba_ByteArray] := iSendFrame[connId, 1, ba];

ResoniteRealtime`RRWSPing[connId_String] := iSendFrame[connId, 9, iEmptyBA[]];

ResoniteRealtime`RRWSClose[connId_String] :=
  Module[{c = Lookup[$iWSConns, connId, None]},
    If[!AssociationQ[c], Return[$Failed]];
    Quiet[iSendFrame[connId, 8, iEmptyBA[]]];
    iCloseSocket[connId, "Local"];
    (* 相手の close 応答 (同一カーネルなら非同期ハンドラ) を捌いてから回収する *)
    Pause[0.15];
    iSweep[];
    connId];

ResoniteRealtime`RRWSSweep[] := iSweep[];

ResoniteRealtime`RRWSConnections[] := Keys[$iWSConns];

ResoniteRealtime`RRWSStatus[] := (iSweep[];
  <|"Servers" -> Association @ KeyValueMap[
      #1 -> <|"Port" -> #2["Port"], "Started" -> #2["Started"]|> &, $iWSServers],
    "Connections" -> Association @ KeyValueMap[
      #1 -> <|"Role" -> #2["Role"], "URL" -> Lookup[#2, "URL", None],
        "Server" -> Lookup[#2, "Server", None],
        "Handshake" -> #2["Handshake"], "Sent" -> #2["Sent"],
        "Received" -> #2["Received"],
        "IdleSeconds" -> Round[AbsoluteTime[] - #2["LastRecv"], 0.1]|> &,
      $iWSConns]|>);

End[];

EndPackage[];
