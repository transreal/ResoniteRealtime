(* ::Package:: *)

(* ResoniteRealtime.wl -- Mathematica \:304b\:3089 Resonite \:3092\:5236\:5fa1\:3059\:308b\:30d6\:30ea\:30c3\:30b8

   This file is encoded in UTF-8.
   Load via: Block[{$CharacterEncoding="UTF-8"}, Get["ResoniteRealtime.wl"]]

   \:4f9d\:5b58: ResoniteRealtime_ws.wl (\:540c\:3058\:30c7\:30a3\:30ec\:30af\:30c8\:30ea\:3002\:81ea\:52d5\:3067\:30ed\:30fc\:30c9\:3059\:308b)

   ---- \:7d4c\:8def ----

   L1 \:30ea\:30a2\:30eb\:30bf\:30a4\:30e0: WL \:304c WebSocket \:30b5\:30fc\:30d0\:3002\:4e16\:754c\:306e WebsocketClient \:304c\:7e4b\:3044\:3067\:304f\:308b\:3002
       ProtoFlux \:306f JSON \:3092\:6271\:3048\:306a\:3044\:306e\:3067 TAB \:533a\:5207\:308a\:306e\:884c\:30d7\:30ed\:30c8\:30b3\:30eb\:306b\:3059\:308b\:3002
         \:4e16\:754c \[RightArrow] WL :  evt<TAB>userJoined<TAB>nconc
         WL \[RightArrow] \:4e16\:754c :  cmd<TAB>show<TAB>http://127.0.0.1:9090/plot/1.png
       \:30db\:30b9\:30c8\:3067\:3042\:308b\:5fc5\:8981\:304c\:306a\:3044 / \:5f80\:5fa9\:304c\:901f\:3044\:3002\:30a4\:30d9\:30f3\:30c8\:3068\:30c8\:30ea\:30ac\:306f\:3053\:3061\:3089\:3002

   L2 \:69cb\:9020: WL \:304c ResoniteLink (\:516c\:5f0f, 2026.1.8.6\:301c) \:306e\:30af\:30e9\:30a4\:30a2\:30f3\:30c8\:3002
       WebSocket + JSON \:3067\:30c7\:30fc\:30bf\:30e2\:30c7\:30eb\:3092\:8aad\:307f\:66f8\:304d\:3059\:308b\:3002
       Resonite \:5074: Dashboard \[RightArrow] Session \[RightArrow] Settings \[RightArrow] "Enable ResoniteLink"\:3002
       \:8868\:793a\:3055\:308c\:305f port \:3092 ResoniteRealtimeLinkConnect[port] \:306b\:6e21\:3059\:3002
       **\:30bb\:30c3\:30b7\:30e7\:30f3\:306e\:30db\:30b9\:30c8\:3067\:3042\:308b\:5fc5\:8981\:304c\:3042\:308b**\:3002\:30ea\:30a2\:30eb\:30bf\:30a4\:30e0\:5236\:5fa1\:306b\:306f\:4f7f\:308f\:306a\:3044
       (\:516c\:5f0f\:304c\:300cin-game \:306e OSC/WebSocket \:3092\:4f7f\:3048\:300d\:3068\:660e\:8a00\:3057\:3066\:3044\:308b)\:3002

   ---- \:4f7f\:3044\:65b9 ----

     ResoniteRealtimeStart[]                    (* L1 \:30b5\:30fc\:30d0\:8d77\:52d5 *)
     ResoniteRealtimeOn["evt", Print]           (* \:4e16\:754c\:304b\:3089\:306e\:30a4\:30d9\:30f3\:30c8\:306b\:30cf\:30f3\:30c9\:30e9 *)
     ResoniteRealtimeSend["cmd", "show", url]   (* \:4e16\:754c\:3078\:9001\:308b *)

     ResoniteRealtimeLinkConnect[41234]         (* L2 \:63a5\:7d9a *)
     ResoniteRealtimeGetSlot["Root", "Depth" -> 1]
     ResoniteRealtimeAddSlot["Name" -> "Hello", "Position" -> {0, 1.5, 2}]
     ResoniteRealtimeAddComponent[slotId, "[FrooxEngine]FrooxEngine.Grabbable",
       <|"Scalable" -> True|>]

     ResoniteRealtimeStatus[]  /  ResoniteRealtimeMonitor[]  /  ResoniteRealtimeStop[]

   ---- \:524d\:63d0 (\:5c0e\:5165\:306f ResoniteRealtime_info/docs/setup.md) ----

   - WebSocket \:5c64 (ResoniteRealtime_ws.wl) \:306f\:7d14 Wolfram \:3067\:4f9d\:5b58\:30bc\:30ed\:3002L1 / L2 / \:677f\:306e\:8868\:793a\:306f\:3053\:306e\:30d1\:30c3\:30b1\:30fc\:30b8\:3060\:3051\:3067\:52d5\:304f\:3002
   - \:4efb\:610f: claudecode.wl + NBAccess.wl (Chat / ProtoFlux \:751f\:6210 / \:30bf\:30d6\:30ec\:30c3\:30c8\:306e ClaudeEval)\:3001SourceVault.wl (\:8cc7\:6599\:306e\:8868\:793a\:30fb\:4e00\:89a7)\:3001
     ResoLoop.wl + resoloop CLI (3D \:751f\:6210 = ResoniteGraphics3D\:3002resoloop \:306f\:5225\:30d7\:30ed\:30b8\:30a7\:30af\:30c8\:30fbAGPL \:306a\:306e\:3067\:540c\:68b1\:3057\:306a\:3044)\:3001
     Flux-SDK (ProtoGraph \:306e build)\:3002
   - \:30ea\:30dd\:30b8\:30c8\:30ea\:306b\:542b\:3081\:306a\:3044\:53c2\:7167\:30c7\:30fc\:30bf: ResoniteRealtime_info/references/protoflux-nodes.json (Resonite \:306e DLL \:3092\:53cd\:5c04\:3057\:3066\:4f5c\:308b) \:3068
     references/protograph/ (Flux SDK \:516c\:5f0f docs \:306e\:629c\:7c8b)\:3002ProtoFlux \:751f\:6210\:3092\:4f7f\:3046\:3068\:304d\:3060\:3051 setup.md \:306e\:624b\:9806\:3067\:4f5c\:308b\:3002

   ---- \:8a2d\:8a08\:4e0a\:306e\:7d04\:675f ----

   - \:5e38\:99d0 Dynamic \:3067\:30dd\:30fc\:30ea\:30f3\:30b0\:3057\:306a\:3044 (\:30d1\:30ec\:30c3\:30c8\:5e38\:99d0 UpdateInterval \:306f FE \:3092\:6bba\:3059)\:3002
     Monitor \:306f\:624b\:52d5\:66f4\:65b0\:30dc\:30bf\:30f3\:5f0f\:3002
   - SocketListen \:306e\:30b3\:30fc\:30eb\:30d0\:30c3\:30af\:304b\:3089\:306f FrontEnd \:3092\:89e6\:3089\:306a\:3044\:3002
   - ResoniteLink \:306f beta\:3002\:30e1\:30c3\:30bb\:30fc\:30b8\:7d44\:7acb\:306f iRLMessage / iRLValue \:306b\:9589\:3058\:8fbc\:3081\:3001
     \:30b9\:30ad\:30fc\:30de\:5909\:66f4\:306f\:3053\:306e 2 \:3064\:306e\:8ffd\:968f\:3067\:6e08\:3080\:3088\:3046\:306b\:3059\:308b\:3002
*)

Quiet[Remove["Global`ResoniteRealtime*"], {Remove::rmnsm}];
Quiet[Remove["Global`$ResoniteRealtime*"], {Remove::rmnsm}];

BeginPackage["ResoniteRealtime`"];

$ResoniteRealtimeVersion::usage = "$ResoniteRealtimeVersion \:306f\:30d1\:30c3\:30b1\:30fc\:30b8\:306e\:30d0\:30fc\:30b8\:30e7\:30f3\:3002";

ResoniteRealtimeStart::usage =
  "ResoniteRealtimeStart[] \:306f L1 \:30d6\:30ea\:30c3\:30b8 (WebSocket \:30b5\:30fc\:30d0) \:3092\:8d77\:52d5\:3059\:308b\:3002\n" <>
  "\:30aa\:30d7\:30b7\:30e7\:30f3: \"Port\" -> 17300, \"Heartbeat\" -> 25 (\:79d2\:30010 \:3067\:7121\:52b9), \"LinkPort\" -> None\:3002\n" <>
  "\:4e16\:754c\:5074\:306f WebsocketClient \:306e URL \:306b ws://127.0.0.1:<Port>/bridge \:3092\:5165\:308c\:308b\:3002";

ResoniteRealtimeStop::usage =
  "ResoniteRealtimeStop[] \:306f L1 \:30b5\:30fc\:30d0\:3068 L2 (ResoniteLink) \:63a5\:7d9a\:3001heartbeat \:30bf\:30b9\:30af\:3092\:6b62\:3081\:308b\:3002";

ResoniteRealtimeStatus::usage =
  "ResoniteRealtimeStatus[] \:306f\:30d6\:30ea\:30c3\:30b8\:3068 ResoniteLink \:306e\:72b6\:614b\:3092 Association \:3067\:8fd4\:3059\:3002";

ResoniteRealtimeMonitor::usage =
  "ResoniteRealtimeMonitor[] \:306f\:72b6\:614b\:8868\:793a\:3092\:8fd4\:3059\:3002\:5e38\:99d0\:30dd\:30fc\:30ea\:30f3\:30b0\:306f\:305b\:305a\:3001\:66f4\:65b0\:30dc\:30bf\:30f3\:3067\:8aad\:307f\:76f4\:3059\:3002";

ResoniteRealtimeSend::usage =
  "ResoniteRealtimeSend[verb, args...] \:306f TAB \:533a\:5207\:308a\:306e\:884c\:3092\:3001\:7e4b\:304c\:3063\:3066\:3044\:308b\:4e16\:754c\:5074\:306e\:63a5\:7d9a\:3059\:3079\:3066\:3078\:9001\:308b\:3002";

ResoniteRealtimeSendTo::usage =
  "ResoniteRealtimeSendTo[connId, verb, args...] \:306f\:9001\:308a\:5148\:306e\:63a5\:7d9a\:3092\:6307\:5b9a\:3057\:3066\:884c\:3092\:9001\:308b\:3002\n" <>
  "connId \:306f ResoniteRealtimeStatus[][\"BridgeConnections\"] \:3084\:30cf\:30f3\:30c9\:30e9\:306e \"Connection\" \:3067\:5f97\:308b\:3002";

ResoniteRealtimeOn::usage =
  "ResoniteRealtimeOn[verb, f] \:306f\:4e16\:754c\:304b\:3089\:5c4a\:3044\:305f\:884c\:306e\:5148\:982d\:8a9e\:304c verb \:306e\:3068\:304d f \:3092\:547c\:3076\:3002\n" <>
  "f \:306f <|\"Verb\", \"Args\", \"Line\", \"Connection\", \"Time\"|> \:3092\:53d7\:3051\:308b\:3002\n" <>
  "ResoniteRealtimeOn[All, f] \:306f\:5168\:3066\:306e\:884c\:3068\:63a5\:7d9a/\:5207\:65ad (\"$open\" / \"$close\") \:3067 f \:3092\:547c\:3076\:3002\n" <>
  "\:4e16\:754c\:5074\:304c\:4f55\:3092\:9001\:3063\:3066\:304f\:308b\:304b\:5206\:304b\:3089\:306a\:3044\:7acb\:3061\:4e0a\:3052\:671f\:306f\:3053\:308c\:3067\:8997\:304f\:3068\:3088\:3044\:3002\n" <>
  "ResoniteRealtimeOn[verb, None] \:3067\:89e3\:9664\:3002ResoniteRealtimeOn[] \:3067\:767b\:9332\:4e00\:89a7\:3002";

ResoniteRealtimeEvents::usage =
  "ResoniteRealtimeEvents[] \:306f\:76f4\:8fd1\:306b\:4e16\:754c\:304b\:3089\:5c4a\:3044\:305f\:884c (\:65e2\:5b9a 50 \:4ef6) \:3092\:8fd4\:3059\:3002";

ResoniteRealtimeLinkConnect::usage =
  "ResoniteRealtimeLinkConnect[port] \:306f ResoniteLink (ws://localhost:port/) \:306b\:63a5\:7d9a\:3059\:308b\:3002\n" <>
  "port \:306f Resonite \:306e Dashboard \[RightArrow] Session \[RightArrow] Settings \:3067 \"Enable ResoniteLink\" \:3057\:305f\:969b\:306b\:8868\:793a\:3055\:308c\:308b\:5024\:3002\n" <>
  "ResoniteRealtimeLinkConnect[] \:306f ResoniteRealtimeDiscover[] \:3067\:30dd\:30fc\:30c8\:3092\:898b\:3064\:3051\:3066\:63a5\:7d9a\:3059\:308b (\:5019\:88dc\:304c\:7121\:3051\:308c\:3070 Failure[\"NoResoniteLink\"])\:3002\n" <>
  "\:30aa\:30d7\:30b7\:30e7\:30f3: \"Host\" -> \"localhost\", \"Quiet\" -> False (True \:306a\:3089 Print \:3057\:306a\:3044)\:3002";
ResoniteRealtimeDiscover::usage =
  "ResoniteRealtimeDiscover[] \:306f\:6709\:52b9\:5316\:3055\:308c\:3066\:3044\:308b ResoniteLink \:306e\:30dd\:30fc\:30c8\:3092\:63a2\:3057 {<|\"Port\", \"URL\", \"Process\", \"Source\"|> ...} \:3092\:8fd4\:3059\:3002\n" <>
  "\:9806\:306b (1) Windows \:306e http.sys \:767b\:9332\:4e00\:89a7 (netsh http show servicestate\:3002Resonite / Renderite.Host \:306e\:30d7\:30ed\:30bb\:30b9\:304c\:767b\:9332\:3057\:305f\n" <>
  "HTTP://LOCALHOST:<port>/\:3002\:5373\:6642)\:3001(2) ResoLoop.wl \:304c\:3042\:308c\:3070 resoloop discover (\:7d04 12 \:79d2)\:3001(3) \:74b0\:5883\:5909\:6570 RESONITE_LINK_URL\:3002";

ResoniteRealtimeLinkDisconnect::usage = "ResoniteRealtimeLinkDisconnect[] \:306f ResoniteLink \:63a5\:7d9a\:3092\:9589\:3058\:308b\:3002";

ResoniteRealtimeLink::usage =
  "ResoniteRealtimeLink[assoc] \:306f ResoniteLink \:3078\:751f\:306e\:30e1\:30c3\:30bb\:30fc\:30b8\:3092\:9001\:308a\:3001\:5fdc\:7b54\:3092\:5f85\:3063\:3066\:8fd4\:3059\:3002\n" <>
  "\:30aa\:30d7\:30b7\:30e7\:30f3: \"Timeout\" -> 10, \"Wait\" -> True (False \:306a\:3089\:9001\:308b\:3060\:3051), \"Match\" -> Automatic\:3002\n" <>
  "\:65e2\:5b9a\:3067\:306f\:300c\:9001\:4fe1\:5f8c\:306b\:5c4a\:3044\:305f\:4e2d\:3067 JSON \:3068\:3057\:3066\:89e3\:91c8\:3067\:304d\:305f\:6700\:521d\:306e\:30e1\:30c3\:30bb\:30fc\:30b8\:300d\:3092\:5fdc\:7b54\:3068\:3059\:308b\:3002\n" <>
  "\"Match\" \:306b\:8ff0\:8a9e\:3092\:6e21\:3059\:3068\:3001\:305d\:308c\:3092\:6e80\:305f\:3059\:3082\:306e\:3060\:3051\:3092\:5fdc\:7b54\:3068\:307f\:306a\:3059 (\:76f8\:95a2 ID \:304c\:5165\:3063\:305f\:3068\:304d\:306e\:53d7\:3051\:53e3)\:3002";

ResoniteRealtimeLinkMessages::usage =
  "ResoniteRealtimeLinkMessages[] \:306f ResoniteLink \:304b\:3089\:5c4a\:3044\:305f\:76f4\:8fd1\:306e\:30e1\:30c3\:30bb\:30fc\:30b8\:3092\:8fd4\:3059\:3002";

ResoniteRealtimeGetSlot::usage =
  "ResoniteRealtimeGetSlot[slotId] \:306f getSlot \:3092\:9001\:308b\:3002slotId \:65e2\:5b9a\:306f \"Root\"\:3002\n" <>
  "\:30aa\:30d7\:30b7\:30e7\:30f3: \"Depth\" -> 0 (-1 \:3067\:5168\:968e\:5c64), \"IncludeComponentData\" -> False\:3002";

ResoniteRealtimeAddSlot::usage =
  "ResoniteRealtimeAddSlot[\"Name\" -> \"...\", \"Parent\" -> \"Root\", \"Position\" -> {x,y,z}, ...] \:306f addSlot \:3092\:9001\:308b\:3002\n" <>
  "\"Id\" \:3092\:7701\:7565\:3059\:308b\:3068 WL_Slot_<n> \:3092\:81ea\:52d5\:63a1\:756a\:3059\:308b\:3002\:8fd4\:308a\:5024\:306e \"Id\" \:304c\:4ee5\:5f8c\:306e\:53c2\:7167 ID\:3002";

ResoniteRealtimeUpdateSlot::usage =
  "ResoniteRealtimeUpdateSlot[slotId, <|\"scale\" -> {2,2,2|>}] \:306f updateSlot \:3092\:9001\:308b\:3002\:6307\:5b9a\:3057\:305f\:9805\:76ee\:3060\:3051\:5909\:308f\:308b\:3002";

ResoniteRealtimeRemoveSlot::usage = "ResoniteRealtimeRemoveSlot[slotId] \:306f removeSlot \:3092\:9001\:308b\:3002";

ResoniteRealtimeAddComponent::usage =
  "ResoniteRealtimeAddComponent[slotId, componentType, members] \:306f addComponent \:3092\:9001\:308b\:3002\n" <>
  "componentType \:306f Resonite \:306e\:30b3\:30f3\:30dd\:30fc\:30cd\:30f3\:30c8\:30a2\:30bf\:30c3\:30c1\:30e3\:3068\:540c\:3058\:66f8\:5f0f (\:4f8b \"[FrooxEngine]FrooxEngine.Grabbable\")\:3002";

ResoniteRealtimeUpdateComponent::usage =
  "ResoniteRealtimeUpdateComponent[componentId, members] \:306f updateComponent \:3092\:9001\:308b\:3002";

ResoniteRealtimeRef::usage =
  "ResoniteRealtimeRef[id] \:306f ResoniteLink \:306e reference \:5024 (<|\"$type\" -> \"reference\", \"targetId\" -> id|>) \:3092\:4f5c\:308b\:3002";

ResoniteRealtimeValue::usage =
  "ResoniteRealtimeValue[expr] \:306f WL \:306e\:5024\:3092 ResoniteLink \:306e\:578b\:4ed8\:304d\:5024\:3078\:5909\:63db\:3059\:308b\:3002\n" <>
  "String/Integer/Real/True|False/{x,y}/{x,y,z}/{x,y,z,w}/RGBColor \:306b\:5bfe\:5fdc\:3002\n" <>
  "ResoniteRealtimeValue[\"float3\", {0,1,2}] \:306e\:3088\:3046\:306b\:578b\:3092\:660e\:793a\:3059\:308b\:3053\:3068\:3082\:3067\:304d\:308b\:3002";

ResoniteRealtimeNewId::usage = "ResoniteRealtimeNewId[\"Slot\"] \:306f WL_Slot_<n> \:5f62\:5f0f\:306e\:4e00\:610f\:306a ID \:3092\:4f5c\:308b\:3002";

ResoniteRealtimeShowImage::usage =
  "ResoniteRealtimeShowImage[expr] \:306f Graphics / Image / \:4efb\:610f\:306e\:5f0f\:3092 PNG \:306b\:3057\:3066\:914d\:4fe1\:3057\:3001\n" <>
  "\:305d\:306e URL \:3092 \"img\" \:884c\:3068\:3057\:3066\:4e16\:754c\:3078\:9001\:308b\:3002\:4e16\:754c\:5074\:306f\:53d7\:3051\:53d6\:3063\:305f\:6587\:5b57\:5217\:3092 StaticTexture2D \:306e URL \:306b\:66f8\:304f\:3002\n" <>
  "\:30aa\:30d7\:30b7\:30e7\:30f3: \"Size\" -> 800 (\:9577\:8fba\:30d4\:30af\:30bb\:30eb), \"Verb\" -> \"img\", \"Send\" -> True\:3002\n" <>
  "\:8fd4\:308a\:5024\:306f URL\:3002**HTTP \:306e URL \:30a2\:30bb\:30c3\:30c8\:306f\:5404\:30af\:30e9\:30a4\:30a2\:30f3\:30c8\:304c\:500b\:5225\:306b\:53d6\:308a\:306b\:884c\:304f**\:306e\:3067\:3001\n" <>
  "127.0.0.1 \:306f\:81ea\:5206\:306b\:3057\:304b\:898b\:3048\:306a\:3044\:3002\:8074\:8846\:304c\:3044\:308b\:5834\:3067\:306f \"PublicBaseURL\" \:3092\:8a2d\:5b9a\:3059\:308b\:3053\:3068\:3002";

ResoniteRealtimeBoard::usage =
  "ResoniteRealtimeBoard[] \:306f ResoniteLink \:3060\:3051\:3067\:300c\:753b\:50cf\:3092\:6620\:3059\:677f\:300d\:3092\:4e16\:754c\:306b\:7d44\:307f\:7acb\:3066\:308b\:3002\n" <>
  "Slot + StaticTexture2D + QuadMesh + UnlitMaterial + MeshRenderer \:3092\:4f5c\:308a\:3001ID \:3092 Association \:3067\:8fd4\:3059\:3002\n" <>
  "\:4ee5\:5f8c ResoniteRealtimeShowImage[expr] \:304c\:3053\:306e\:677f\:306e\:30c6\:30af\:30b9\:30c1\:30e3 URL \:3092\:5dee\:3057\:66ff\:3048\:308b (\:4e16\:754c\:5074\:306e\:64cd\:4f5c\:306f\:4e0d\:8981)\:3002\n" <>
  "\:30aa\:30d7\:30b7\:30e7\:30f3: \"Position\" -> {0,1.5,1.2}, \"Size\" -> 0.6, \"Rotation\" -> {x,y,z,w}, \"Name\", \"Parent\" -> \"Root\", \"Image\"\:3002";

ResoniteRealtimeRemoveBoard::usage = "ResoniteRealtimeRemoveBoard[] \:306f\:677f\:3092\:4e16\:754c\:304b\:3089\:524a\:9664\:3059\:308b\:3002";

ResoniteRealtimeAsset::usage =
  "ResoniteRealtimeAsset[file] \:306f\:30ed\:30fc\:30ab\:30eb\:30d5\:30a1\:30a4\:30eb\:3092\:914d\:4fe1\:5bfe\:8c61\:306b\:52a0\:3048\:3001\:305d\:306e URL \:3092\:8fd4\:3059 (\:9001\:4fe1\:306f\:3057\:306a\:3044)\:3002\n" <>
  "ResoniteRealtimeAsset[] \:306f\:914d\:4fe1\:30c7\:30a3\:30ec\:30af\:30c8\:30ea\:3092\:8fd4\:3059\:3002";

$ResoniteRealtimePublicBaseURL::usage =
  "$ResoniteRealtimePublicBaseURL \:306b \"https://example.com/rr\" \:306e\:3088\:3046\:306a\:516c\:958b URL \:3092\:5165\:308c\:3066\:304a\:304f\:3068\:3001\n" <>
  "ResoniteRealtimeShowImage \:304c localhost \:3067\:306f\:306a\:304f\:305d\:306e URL \:3092\:8fd4\:3059 (\:540c\:3058\:30bb\:30c3\:30b7\:30e7\:30f3\:306e\:4ed6\:306e\:4eba\:306b\:3082\:898b\:3048\:308b)\:3002\n" <>
  "\:305d\:306e\:5834\:5408\:306f\:914d\:4fe1\:30c7\:30a3\:30ec\:30af\:30c8\:30ea\:306e\:4e2d\:8eab\:3092\:81ea\:5206\:3067\:305d\:306e URL \:914d\:4e0b\:3078\:30a2\:30c3\:30d7\:30ed\:30fc\:30c9\:3059\:308b\:3053\:3068\:3002";

Begin["`Private`"];

(* ---- \:518d\:30ed\:30fc\:30c9\:6642\:306b\:53e4\:3044\:5b9a\:7fa9\:3092\:6b8b\:3055\:306a\:3044 ----
   \:5f15\:6570\:30d1\:30bf\:30fc\:30f3\:3092\:5909\:3048\:305f\:95a2\:6570 (\:4f8b: f[x_] \[RightArrow] f[x_, opts:OptionsPattern[]]) \:306f\:3001
   \:518d\:30ed\:30fc\:30c9\:3057\:3066\:3082**\:53e4\:3044\:5b9a\:7fa9\:304c\:6d88\:3048\:305a\:306b\:6b8b\:308a\:3001\:3088\:308a\:7279\:6b8a\:306a\:65b9\:304c\:5148\:306b\:5f53\:305f\:308b**\:3002
   2026-09-04 \:306b\:5b9f\:969b\:306b\:8e0f\:3093\:3060: LinkConnect \:306e\:30db\:30b9\:30c8\:540d\:3092\:76f4\:3057\:305f\:306e\:306b\:65e7\:5b9a\:7fa9\:304c\:4f7f\:308f\:308c\:7d9a\:3051\:305f\:3002
   \:516c\:958b\:30b7\:30f3\:30dc\:30eb (\:3053\:306e context \:76f4\:4e0b) \:306e\:5024\:3060\:3051\:843d\:3068\:3059\:3002::usage \:306f Clear \:3067\:306f\:6d88\:3048\:305a\:3001
   \:72b6\:614b\:5909\:6570\:306f ResoniteRealtime`Private` \:306b\:3042\:308b\:306e\:3067\:751f\:304d\:3066\:3044\:308b\:63a5\:7d9a\:3082\:58ca\:308c\:306a\:3044\:3002
   2026-09-26: \:524d\:306e\:30ed\:30fc\:30c9\:306e\:76e3\:8996 tick (ScheduledTask\:3001\:5272\:308a\:8fbc\:307f\:578b) \:306f\:518d\:30ed\:30fc\:30c9\:4e2d\:3082\:8d70\:308a\:3001Clear \:3057\:305f\:516c\:958b\:95a2\:6570
   (ResoniteRealtimeLinkMessages \:7b49) \:3092\:672a\:5b9a\:7fa9\:306e\:307e\:307e\:547c\:3093\:3067 Last::nolast \:3092\:51fa\:3057\:305f\:3002\:30ed\:30fc\:30c9\:306e\:9593\:306f tick \:306e Busy \:3092\:7acb\:3066\:3066
   \:4f55\:3082\:3055\:305b\:305a\:3001\:30d5\:30a1\:30a4\:30eb\:306e\:6700\:5f8c\:3067\:4e0b\:308d\:3059 (tick \:306f Busy \:306a\:3089\:5165\:53e3\:3067\:623b\:308b\:3002\:7acb\:3066\:305f\:306e\:306f\:3053\:3053\:306a\:306e\:3067\:6700\:5f8c\:306b\:5fc5\:305a False \:306b\:623b\:3059)\:3002 *)
If[AssociationQ[$itState], $itState["Busy"] = True];
If[AssociationQ[$icState], $icState["Busy"] = True];
Scan[Quiet[Clear[#]] &, Names["ResoniteRealtime`*"]];

ResoniteRealtime`$ResoniteRealtimeVersion = "0.2.1";

If[!StringQ[ResoniteRealtime`$ResoniteRealtimePublicBaseURL],
  ResoniteRealtime`$ResoniteRealtimePublicBaseURL = ""];

$iPackageDirectory = DirectoryName[$InputFileName];

(* ---- \:4e0b\:56de\:308a (WebSocket \:5c64) \:306e\:30ed\:30fc\:30c9 ----
   **\:6bce\:56de\:30ed\:30fc\:30c9\:3059\:308b\:3002** \:300c\:672a\:30ed\:30fc\:30c9\:306e\:3068\:304d\:3060\:3051\:300d\:306b\:3059\:308b\:3068\:3001_ws.wl \:3060\:3051\:3092\:76f4\:3057\:305f\:3068\:304d\:306b
   \:53e4\:3044\:5b9a\:7fa9\:304c\:6b8b\:308a\:3001Options \:306e\:98df\:3044\:9055\:3044 (OptionValue::nodef) \:306e\:3088\:3046\:306a\:5206\:304b\:308a\:306b\:304f\:3044\:58ca\:308c\:65b9\:3092\:3059\:308b
   (2026-09-04 \:5b9f\:6a5f\:3067\:8e0f\:3093\:3060)\:3002_ws.wl \:306e\:72b6\:614b\:5909\:6570\:306f\:3059\:3079\:3066 If[!AssociationQ[...]] \:3067
   \:30ac\:30fc\:30c9\:3057\:3066\:3042\:308b\:306e\:3067\:3001\:518d\:30ed\:30fc\:30c9\:3057\:3066\:3082\:751f\:304d\:3066\:3044\:308b\:63a5\:7d9a\:306f\:58ca\:308c\:306a\:3044\:3002 *)
Block[{$CharacterEncoding = "UTF-8"},
  Get[FileNameJoin[{$iPackageDirectory, "ResoniteRealtime_ws.wl"}]]];

(* ---- Chat \:30ac\:30b8\:30a7\:30c3\:30c8 (\:30ce\:30fc\:30c8\:30d6\:30c3\:30af\:306e Chat \:30bb\:30eb\:3092\:30ef\:30fc\:30eb\:30c9\:5185\:3067\:5b9f\:73fe\:3059\:308b) ----
   \:540c\:3058\:7406\:7531\:3067\:6bce\:56de\:30ed\:30fc\:30c9\:3059\:308b\:3002\:72b6\:614b\:306f $icState \:306b\:9589\:3058\:3001\:518d\:30ed\:30fc\:30c9\:3067\:58ca\:308c\:306a\:3044\:3002 *)
Block[{$CharacterEncoding = "UTF-8"},
  Get[FileNameJoin[{$iPackageDirectory, "ResoniteRealtime_chat.wl"}]]];

(* ---- ProtoFlux \:30ac\:30b8\:30a7\:30c3\:30c8 (ProtoGraph / \:30b0\:30e9\:30d5\:8a18\:8ff0\:3092 LLM \:306b\:66f8\:304b\:305b\:308b\:3002chat \:306e\:4e0a\:306b\:8f09\:308b) ---- *)
Block[{$CharacterEncoding = "UTF-8"},
  Get[FileNameJoin[{$iPackageDirectory, "ResoniteRealtime_flux.wl"}]]];
(* ---- \:30ea\:30f3\:30ab: \:30b0\:30e9\:30d5\:8a18\:8ff0\:3092 ResoniteLink \:3067\:30ce\:30fc\:30c9\:3068\:3057\:3066\:914d\:7f6e\:30fb\:7d50\:7dda ---- *)
Block[{$CharacterEncoding = "UTF-8"},
  Get[FileNameJoin[{$iPackageDirectory, "ResoniteRealtime_fluxlink.wl"}]]];
(* ---- \:30bf\:30d6\:30ec\:30c3\:30c8: ClaudeEval \:3092\:30ef\:30fc\:30eb\:30c9\:5185\:3067\:8d70\:3089\:305b\:308b (chat \:306e\:30d8\:30eb\:30d1\:306e\:4e0a\:306b\:8f09\:308b) ---- *)
Block[{$CharacterEncoding = "UTF-8"},
  Get[FileNameJoin[{$iPackageDirectory, "ResoniteRealtime_tablet.wl"}]]];
(* ---- Graphics3D -> \:30ef\:30fc\:30eb\:30c9\:5185\:306e 3D \:30aa\:30d6\:30b8\:30a7\:30af\:30c8 (resoloop \:306e\:30e1\:30c3\:30b7\:30e5\:8cc7\:7523\:53d6\:308a\:8fbc\:307f) ---- *)
Block[{$CharacterEncoding = "UTF-8"},
  Get[FileNameJoin[{$iPackageDirectory, "ResoniteRealtime_mesh.wl"}]]];
(* ---- \:96db\:5f62\:306a\:3057\:306e PDF \:30d3\:30e5\:30fc\:30a2 + \:30a4\:30f3\:30d9\:30f3\:30c8\:30ea\:306b\:4fdd\:5b58\:3067\:304d\:308b\:30b5\:30e0\:30cd\:30a4\:30eb\:4e00\:89a7 (\:30bf\:30d6\:30ec\:30c3\:30c8\:306e\:90e8\:54c1\:3092\:4f7f\:3046\:30022026-09-25) ---- *)
Block[{$CharacterEncoding = "UTF-8"},
  Get[FileNameJoin[{$iPackageDirectory, "ResoniteRealtime_docboard.wl"}]]];
(* ---- \:30b5\:30e0\:30cd\:30a4\:30eb\:4e00\:89a7\:3092\:66f2\:9762\:306b\:8cbc\:308b (\:5186\:7b52 / \:7403\:306e\:5185\:5074 / \:30e1\:30d3\:30a6\:30b9\:306e\:5e2f / \:4efb\:610f\:306e\:9762\:3002\:4e00\:89a7\:306e\:90e8\:54c1\:3092\:4f7f\:3046\:30022026-09-26) ---- *)
Block[{$CharacterEncoding = "UTF-8"},
  Get[FileNameJoin[{$iPackageDirectory, "ResoniteRealtime_surface.wl"}]]];
(* ---- PDF \:306e\:5199\:3057\:3092 web \:30b5\:30fc\:30d0\:306b\:7f6e\:304f (Private / Contacts \:306e\:30ef\:30fc\:30eb\:30c9\:3067\:30d5\:30ec\:30f3\:30c9\:306b\:3082\:898b\:3048\:308b\:3088\:3046\:306b\:30022026-09-25) ---- *)
Block[{$CharacterEncoding = "UTF-8"},
  Get[FileNameJoin[{$iPackageDirectory, "ResoniteRealtime_pdfcache.wl"}]]];

(* ---- \:72b6\:614b (\:518d\:30ed\:30fc\:30c9\:3067\:58ca\:3055\:306a\:3044) ---- *)
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
   \:5171\:901a
   ============================================================ *)

iNow[] := AbsoluteTime[];

SetAttributes[iPush, HoldFirst];
iPush[listSym_Symbol, item_, limit_Integer] :=
  listSym = Take[Append[listSym, item], -Min[Length[listSym] + 1, limit]];

iFailure[tag_String, msg_String] :=
  Failure[tag, <|"MessageTemplate" -> msg|>];

(* ID \:306f\:30ab\:30fc\:30cd\:30eb\:3054\:3068\:306e\:30bf\:30b0 + \:9023\:756a\:3002
   **\:9023\:756a\:3060\:3051\:306b\:3057\:3066\:306f\:3044\:3051\:306a\:3044**: ResoniteLink \:306e ID \:767b\:9332\:306f Resonite \:306e\:30bb\:30c3\:30b7\:30e7\:30f3\:304c
   \:7d9a\:304f\:304b\:304e\:308a\:6b8b\:308a\:3001removeSlot \:3057\:3066\:3082\:89e3\:653e\:3055\:308c\:306a\:3044\:3002\:30ab\:30fc\:30cd\:30eb\:3092\:518d\:8d77\:52d5\:3057\:3066\:9023\:756a\:304c 1 \:306b
   \:623b\:308b\:3068\:3001\:524d\:306e\:30ab\:30fc\:30cd\:30eb\:304c\:4f7f\:3063\:305f ID \:3068\:885d\:7a81\:3057\:3066
   "ID 'WL_Board_1' is already in use" \:3067\:843d\:3061\:308b (2026-09-05 \:5b9f\:6a5f\:3067\:8e0f\:3093\:3060)\:3002 *)
If[!StringQ[$iSessionTag],
  $iSessionTag = IntegerString[Round[AbsoluteTime[]*10] - 39975000000, 36]];

ResoniteRealtime`ResoniteRealtimeNewId[prefix_String : "Obj"] := (
  $iIdCounter = $iIdCounter + 1;
  "WL" <> $iSessionTag <> "_" <> prefix <> "_" <> ToString[$iIdCounter]);

(* ============================================================
   L1: \:30d6\:30ea\:30c3\:30b8 (\:884c\:30d7\:30ed\:30c8\:30b3\:30eb)
   ============================================================ *)

(* \:8a18\:9332 \[RightArrow] verb \:5225\:30cf\:30f3\:30c9\:30e9 \[RightArrow] catch-all (All) \:306e\:9806\:306b\:6d41\:3059\:3002
   catch-all \:306f\:300c\:4e16\:754c\:304c\:4f55\:3092\:9001\:3063\:3066\:3044\:308b\:306e\:304b\:5206\:304b\:3089\:306a\:3044\:300d\:7acb\:3061\:4e0a\:3052\:671f\:306e\:305f\:3081\:306e\:3082\:306e\:3067\:3001
   $open / $close \:3082\:540c\:3058\:5f62\:306e\:30ec\:30b3\:30fc\:30c9\:3067\:6e21\:3059\:3002 *)
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

(* \:3053\:306e\:30d6\:30ea\:30c3\:30b8\:30b5\:30fc\:30d0\:306b\:7e4b\:304c\:3063\:3066\:3044\:308b\:63a5\:7d9a\:3060\:3051\:3092\:8fd4\:3059\:3002
   role \:3060\:3051\:3067\:9078\:3076\:3068\:3001\:5225\:7528\:9014\:3067\:7acb\:3066\:305f RRWSServe \:306e\:63a5\:7d9a (\:305f\:3068\:3048\:3070 L2 \:306e\:76f8\:624b\:304c
   \:540c\:4e00\:30ab\:30fc\:30cd\:30eb\:306b\:3044\:308b\:5834\:5408) \:307e\:3067\:62fe\:3063\:3066 heartbeat \:3092\:9001\:308a\:3064\:3051\:3066\:3057\:307e\:3046\:3002 *)
iBridgeConnections[] :=
  If[!StringQ[$iState["Server"]], {},
    Keys @ Select[
      Quiet @ Check[ResoniteRealtime`RRWSStatus[]["Connections"], <||>],
      #["Role"] === "server" && #["Server"] === $iState["Server"] &]];

(* Resonite \:306e WebsocketClient \:306f\:300c\:30b5\:30fc\:30d0\:304b\:3089 60 \:79d2\:4f55\:3082\:6765\:306a\:3044\:300d\:3068\:5207\:65ad\:3059\:308b\:3002
   \:65e2\:5b9a\:306f **ping \:30d5\:30ec\:30fc\:30e0** \:3067\:53e9\:304f: \:30d7\:30ed\:30c8\:30b3\:30eb\:5c64\:306e\:30d5\:30ec\:30fc\:30e0\:306a\:306e\:3067
   WebsocketTextMessageReceiver \:306b\:306f\:51fa\:3066\:3053\:306a\:3044 = \:4e16\:754c\:5074\:306e ProtoFlux \:304c
   \:672c\:7269\:306e\:30e1\:30c3\:30bb\:30fc\:30b8\:3060\:3051\:3092\:898b\:3089\:308c\:308b (\:5206\:5c90\:30ce\:30fc\:30c9\:3092\:4f5c\:3089\:305a\:306b\:6e08\:3080)\:3002
   "HeartbeatMode" -> "Text" \:306b\:3059\:308b\:3068\:5f93\:6765\:3069\:304a\:308a "hb<TAB>\:6642\:523b" \:3092\:9001\:308b\:3002 *)
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
   L3: \:540c\:3058\:30dd\:30fc\:30c8\:3067\:9759\:7684\:30d5\:30a1\:30a4\:30eb\:3092\:914d\:308b (\:753b\:50cf\:30fb\:97f3\:30fb\:30c7\:30fc\:30bf\:3092\:4e16\:754c\:3078)
   ============================================================ *)

$iAssetDirectory =
  FileNameJoin[{$TemporaryDirectory, "ResoniteRealtime", "assets"}];

$iContentTypes = <|
  "png" -> "image/png", "jpg" -> "image/jpeg", "jpeg" -> "image/jpeg",
  "gif" -> "image/gif", "webp" -> "image/webp", "svg" -> "image/svg+xml",
  "wav" -> "audio/wav", "mp3" -> "audio/mpeg", "ogg" -> "audio/ogg",
  "mp4" -> "video/mp4", "webm" -> "video/webm",
  "txt" -> "text/plain; charset=utf-8", "csv" -> "text/csv; charset=utf-8",
  "json" -> "application/json; charset=utf-8", "pdf" -> "application/pdf"|>;

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

(* ---- URL \:306e\:30d1\:30fc\:30bb\:30f3\:30c8\:7b26\:53f7\:5316 (2026-09-24) ----
   \:65e5\:672c\:8a9e\:3084\:7a7a\:767d\:30fb\:304b\:304e\:62ec\:5f27\:3092\:542b\:3080\:30d5\:30a1\:30a4\:30eb\:540d (Eagle \:306e PDF \:7b49) \:3092 URL \:306b\:305d\:306e\:307e\:307e\:5165\:308c\:308b\:3068\:3001Resonite \:306f UTF-8 \:306e\:30d1\:30fc\:30bb\:30f3\:30c8
   \:7b26\:53f7\:5316\:3067\:8981\:6c42\:3057\:3066\:304f\:308b (%E6%9C%88...)\:3002\:914d\:4fe1\:5074\:304c\:5143\:306b\:623b\:3055\:305a\:306b\:63a2\:3057\:3066\:3044\:305f\:306e\:3067 404 \:306b\:306a\:308a\:3001\:6a19\:6e96\:30d3\:30e5\:30fc\:30a2\:304c\:7a7a (1/-1) \:3060\:3063\:305f\:3002
   URL \:3092\:4f5c\:308b\:5074\:3067\:7b26\:53f7\:5316\:3057 (\:975e\:4e88\:7d04\:6587\:5b57 A-Z a-z 0-9 - . _ ~ \:4ee5\:5916\:3092 %XX)\:3001\:914d\:4fe1\:5074\:3067 UTF-8 \:3068\:3057\:3066\:623b\:3059\:3002"+" \:306f\:7a7a\:767d\:306b\:3057\:306a\:3044 *)
iPercentEncode[s_String] :=
  StringJoin @ Map[
    If[(48 <= # <= 57) || (65 <= # <= 90) || (97 <= # <= 122) || MemberQ[{45, 46, 95, 126}, #],
      FromCharacterCode[#], "%" <> ToUpperCase[IntegerString[#, 16, 2]]] &,
    Normal[StringToByteArray[s, "UTF-8"]]];
iPercentDecode[s_String] :=
  Module[{b = Normal[StringToByteArray[s, "UTF-8"]], n, i = 1, hexQ, out},
    n = Length[b];
    hexQ = (48 <= # <= 57) || (65 <= # <= 70) || (97 <= # <= 102) &;
    out = Reap[
      While[i <= n,
        If[b[[i]] === 37 && i + 2 <= n && hexQ[b[[i + 1]]] && hexQ[b[[i + 2]]],
          Sow[FromDigits[FromCharacterCode[b[[i + 1 ;; i + 2]]], 16]]; i += 3,
          Sow[b[[i]]]; i++]]][[2]];
    If[out === {}, "", Quiet @ Check[ByteArrayToString[ByteArray[First[out]], "UTF-8"], s]]];

(* /a/<name> \:3060\:3051\:3092\:914d\:308b\:3002.. \:3092\:542b\:3080\:8981\:6c42\:3068\:914d\:4fe1\:30c7\:30a3\:30ec\:30af\:30c8\:30ea\:5916\:306f\:62d2\:5426\:3059\:308b (\:5fa9\:53f7\:3057\:305f\:5f8c\:306e\:540d\:524d\:3067\:8abf\:3079\:308b\:3002%2F \:306a\:3069\:306e\:629c\:3051\:9053\:3092\:585e\:3050)\:3002 *)
iHTTPHandler[req_Association] :=
  Module[{path, name, file, ext, body},
    path = First[StringSplit[Lookup[req, "Path", "/"], "?"], "/"];
    If[!StringStartsQ[path, "/a/"],
      Return[iHTTPResponse["404 Not Found", "text/plain",
        StringToByteArray["not found", "UTF-8"]]]];
    name = iPercentDecode[StringDrop[path, 3]];
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
    If[!FileExistsQ[file], Return[iFailure["NoSuchFile", file <> " \:304c\:898b\:3064\:304b\:308a\:307e\:305b\:3093\:3002"]]];
    name = FileNameTake[file];
    target = FileNameJoin[{dir, name}];
    If[ExpandFileName[file] =!= ExpandFileName[target],
      Quiet[CopyFile[file, target, OverwriteTarget -> True]]];
    iBaseURL[] <> "/" <> iPercentEncode[name]];

(* \:30e9\:30b9\:30bf\:30e9\:30a4\:30ba\:306f 1 \:304b\:6240\:306b\:3002Graphics \:306e\:307e\:307e ImageQ \:3067\:5224\:5b9a\:3059\:308b\:3068\:7e26\:6a2a\:6bd4\:5408\:308f\:305b\:304c
   \:9ed9\:3063\:3066\:98db\:3076 (2026-09-04 \:306e\:30c6\:30b9\:30c8\:3067\:691c\:51fa)\:3002 *)
iRasterize[expr_, size_] :=
  If[ImageQ[expr], expr,
    Quiet @ Check[Rasterize[expr, "Image", ImageSize -> size], $Failed]];

Options[ResoniteRealtime`ResoniteRealtimeShowImage] = {
  "Size" -> 800, "Verb" -> "img", "Send" -> True, "Target" -> Automatic};

(* Target:
     Automatic \[LongDash] \:677f (ResoniteRealtimeBoard \:3067\:4f5c\:3063\:305f\:3082\:306e) \:304c\:3042\:308c\:3070 L2 \:3067 URL \:3092\:5dee\:3057\:66ff\:3048\:308b\:3002
                 \:7121\:3051\:308c\:3070 L1 \:306e\:884c ("img<TAB>URL") \:3092\:9001\:308b\:3002
     "Board" / "Bridge" / None \[LongDash] \:660e\:793a\:6307\:5b9a\:3002 *)
ResoniteRealtime`ResoniteRealtimeShowImage[expr_, opts : OptionsPattern[]] :=
  Module[{size, verb, send, target, img, dir, name, file, url, board},
    size   = OptionValue[ResoniteRealtime`ResoniteRealtimeShowImage, {opts}, "Size"];
    verb   = OptionValue[ResoniteRealtime`ResoniteRealtimeShowImage, {opts}, "Verb"];
    send   = OptionValue[ResoniteRealtime`ResoniteRealtimeShowImage, {opts}, "Send"];
    target = OptionValue[ResoniteRealtime`ResoniteRealtimeShowImage, {opts}, "Target"];
    img = iRasterize[expr, size];
    If[!ImageQ[img], Return[iFailure["Rasterize", "\:753b\:50cf\:306b\:5909\:63db\:3067\:304d\:307e\:305b\:3093\:3067\:3057\:305f\:3002"]]];
    dir  = iEnsureAssetDirectory[];
    (* Resonite \:306f URL \:5358\:4f4d\:3067\:30a2\:30bb\:30c3\:30c8\:3092\:30ad\:30e3\:30c3\:30b7\:30e5\:3059\:308b\:306e\:3067\:6bce\:56de\:5225\:540d\:306b\:3059\:308b *)
    name = "img" <> ToString[Round[iNow[]*1000]] <> ".png";
    file = FileNameJoin[{dir, name}];
    Quiet @ Check[Export[file, img, "PNG"], Return[iFailure["Export", "PNG \:3092\:66f8\:3051\:307e\:305b\:3093\:3067\:3057\:305f\:3002"]]];
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

(* ---- \:677f (L2 \:3060\:3051\:3067\:7d44\:307f\:7acb\:3066\:308b\:3002\:4e16\:754c\:5074\:306e\:30ce\:30fc\:30c9\:4f5c\:696d\:306f\:4e0d\:8981) ----
   \:69cb\:6210: Slot + StaticTexture2D + QuadMesh + UnlitMaterial + MeshRenderer\:3002
   \:578b\:540d\:306f ResoniteLink \:306e\:30e2\:30c7\:30eb\:5b9a\:7fa9\:306b\:5408\:308f\:305b\:308b:
     Uri \:30d5\:30a3\:30fc\:30eb\:30c9\:306f "Uri" (\:5c0f\:6587\:5b57 "uri" \:306f\:5f3e\:304b\:308c\:308b)\:3001
     SyncList \:306f <|"$type" -> "list", "elements" -> {...}|>\:3002
   ID \:306f\:30bb\:30c3\:30b7\:30e7\:30f3\:5185\:3067\:4e00\:610f\:3002**removeSlot \:3057\:305f\:3042\:3068\:3082\:540c\:3058 ID \:306f\:518d\:5229\:7528\:3067\:304d\:306a\:3044**\:306e\:3067
   \:6bce\:56de ResoniteRealtimeNewId \:3067\:63a1\:308b\:3002 *)

Options[ResoniteRealtime`ResoniteRealtimeBoard] = {
  "Position" -> {0, 1.5, 1.2}, "Rotation" -> None, "Size" -> 0.6,
  "Name" -> "Mathematica Board", "Parent" -> "Root", "Image" -> None};

ResoniteRealtime`ResoniteRealtimeBoard[opts : OptionsPattern[]] :=
  Module[{pos, rot, sz, name, parent, image, ids, url, r},
    If[!StringQ[$iState["Link"]],
      Return[iFailure["NotConnected",
        "\:677f\:306e\:7d44\:307f\:7acb\:3066\:306b\:306f ResoniteLink \:304c\:8981\:308a\:307e\:3059\:3002ResoniteRealtimeLinkConnect[port] \:3092\:5148\:306b\:5b9f\:884c\:3057\:3066\:304f\:3060\:3055\:3044\:3002"]]];
    pos    = OptionValue[ResoniteRealtime`ResoniteRealtimeBoard, {opts}, "Position"];
    rot    = OptionValue[ResoniteRealtime`ResoniteRealtimeBoard, {opts}, "Rotation"];
    sz     = OptionValue[ResoniteRealtime`ResoniteRealtimeBoard, {opts}, "Size"];
    name   = OptionValue[ResoniteRealtime`ResoniteRealtimeBoard, {opts}, "Name"];
    parent = OptionValue[ResoniteRealtime`ResoniteRealtimeBoard, {opts}, "Parent"];
    image  = OptionValue[ResoniteRealtime`ResoniteRealtimeBoard, {opts}, "Image"];

    (* \:5148\:306b\:30e9\:30b9\:30bf\:30e9\:30a4\:30ba\:3057\:3066 Image \:306e\:307e\:307e\:6301\:3061\:56de\:308b (\:7e26\:6a2a\:6bd4\:5408\:308f\:305b\:306b\:4f7f\:3046) *)
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

(* \:753b\:50cf\:306e\:7e26\:6a2a\:6bd4\:306b\:5408\:308f\:305b\:3066\:677f\:306e\:5f62\:3092\:76f4\:3059 (QuadMesh \:306f\:6b63\:65b9\:5f62\:306a\:306e\:3067 slot \:306e scale \:3067\:8abf\:6574) *)
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
      Print[Style["ResoniteRealtime \:306f\:3059\:3067\:306b\:8d77\:52d5\:3057\:3066\:3044\:307e\:3059\:3002", Italic]];
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

    Print[Style["ResoniteRealtime \:8d77\:52d5\:3057\:307e\:3057\:305f", Bold, Darker[Green]]];
    Print["
  \:4e16\:754c\:5074\:306e WebsocketClient \:306b\:5165\:308c\:308b URL:
    ws://127.0.0.1:" <> ToString[port] <> "/bridge

  ResoniteRealtimeSend[\"cmd\", ...]   \[RightArrow] \:4e16\:754c\:3078\:9001\:308b
  ResoniteRealtimeOn[\"evt\", f]       \[RightArrow] \:4e16\:754c\:304b\:3089\:306e\:30a4\:30d9\:30f3\:30c8\:3092\:53d7\:3051\:308b
  ResoniteRealtimeLinkConnect[port]  \[RightArrow] ResoniteLink \:306b\:7e4b\:3050 (Dashboard \:3067\:6709\:52b9\:5316\:3057\:305f port)
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
    Print[Style["ResoniteRealtime \:3092\:505c\:6b62\:3057\:307e\:3057\:305f\:3002", Italic]];
    ResoniteRealtime`ResoniteRealtimeStatus[]];

ResoniteRealtime`ResoniteRealtimeSend[verb_String, args___] :=
  Module[{conns, line},
    conns = iBridgeConnections[];
    If[conns === {}, Return[iFailure["NoBridgeConnection",
      "\:4e16\:754c\:304b\:3089 WebSocket \:63a5\:7d9a\:304c\:6765\:3066\:3044\:307e\:305b\:3093\:3002in-world \:306e WebsocketClient \:3092\:78ba\:8a8d\:3057\:3066\:304f\:3060\:3055\:3044\:3002"]]];
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

(* ---- \:30dd\:30fc\:30c8\:306e\:81ea\:52d5\:691c\:51fa ----
   ResoniteLink \:306f http.sys (HttpListener) \:3067 HTTP://LOCALHOST:<port>/ \:3092\:767b\:9332\:3059\:308b\:3002\:767b\:9332\:4e00\:89a7\:306f
   `netsh http show servicestate view=requestq` \:3067\:53d6\:308c\:3001\:8981\:6c42\:30ad\:30e5\:30fc\:3054\:3068\:306b\:6240\:6709\:30d7\:30ed\:30bb\:30b9 (Resonite \:306e\:5834\:5408
   Renderite.Host.exe / Resonite.exe) \:3068\:767b\:9332 URL \:304c\:4e26\:3076 (2026-09-22 \:5b9f\:6e2c\:3001port 8403)\:3002UDP \:306e announce \:3092
   \:805e\:304f resoloop discover (12 \:79d2) \:3088\:308a\:901f\:304f\:3001\:4f9d\:5b58\:3082\:7121\:3044\:3002
   **netsh \:306e\:898b\:51fa\:3057\:306f Windows \:306e\:8868\:793a\:8a00\:8a9e\:3067\:5909\:308f\:308b** (\:65e5\:672c\:8a9e\:7248\:306f\:300c\:8981\:6c42\:30ad\:30e5\:30fc\:540d:\:300d\:300c\:30a4\:30e1\:30fc\:30b8:\:300d) \:306e\:3067\:3001
   \:898b\:51fa\:3057\:8a9e\:3067\:306f\:62fe\:308f\:306a\:3044: (1) \:30ad\:30e5\:30fc\:306e\:5207\:308c\:76ee\:306f\:5b57\:4e0b\:3052\:306e\:7121\:3044\:884c\:3001(2) \:30d7\:30ed\:30bb\:30b9\:306f ASCII \:306e exe \:30d1\:30b9\:3001
   \:3068\:3044\:3046\:5b57\:9762\:3060\:3051\:3067\:5224\:5b9a\:3059\:308b (2026-09-23\:3001\:65e5\:672c\:8a9e Windows \:3067\:82f1\:8a9e\:898b\:51fa\:3057\:524d\:63d0\:306e\:65e7\:5b9f\:88c5\:304c\:5019\:88dc 0 \:306b\:306a\:3063\:3066\:3044\:305f)\:3002 *)
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
    (* DownValues \:306f HoldAll\:3002Module \:5909\:6570\:306e\:307e\:307e\:6e21\:3059\:3068 f \:81ea\:8eab\:3092\:898b\:3066\:5e38\:306b 0 \:306b\:306a\:308b\:306e\:3067 Evaluate \:304c\:8981\:308b *)
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
        Print[Style["ResoniteLink \:304c\:898b\:3064\:304b\:308a\:307e\:305b\:3093\:3002Dashboard \[RightArrow] Session \[RightArrow] Settings \[RightArrow] Enable ResoniteLink (\:30db\:30b9\:30c8\:3067\:3042\:308b\:3053\:3068)\:3002", Red]]];
      Return[Failure["NoResoniteLink",
        <|"MessageTemplate" -> "\:6709\:52b9\:5316\:3055\:308c\:305f ResoniteLink \:304c\:898b\:3064\:304b\:308a\:307e\:305b\:3093 (netsh / resoloop discover / RESONITE_LINK_URL)\:3002"|>]]];
    ResoniteRealtime`ResoniteRealtimeLinkConnect[First[found]["Port"], opts]];

(* **\:30db\:30b9\:30c8\:540d\:306f localhost\:3002127.0.0.1 \:3067\:306f\:7e4b\:304c\:3089\:306a\:3044\:3002**
   ResoniteLink \:306f .NET \:306e HttpListener (http.sys) \:3067\:5f85\:3061\:53d7\:3051\:3066\:304a\:308a\:3001\:767b\:9332\:3055\:308c\:3066\:3044\:308b
   \:30d7\:30ec\:30d5\:30a3\:30c3\:30af\:30b9\:304c localhost \:306a\:306e\:3067\:3001127.0.0.1 \:3067\:6765\:305f\:8981\:6c42\:306f http.sys \:304c
   400 Bad Request (Server: Microsoft-HTTPAPI/2.0) \:3067\:5f3e\:304f\:3002\:30a2\:30d7\:30ea\:307e\:3067\:5c4a\:304b\:306a\:3044\:3002
   2026-09-04 \:5b9f\:6a5f\:3067\:78ba\:8a8d (node \:306e WebSocket \:30af\:30e9\:30a4\:30a2\:30f3\:30c8\:3067\:3082\:540c\:3058\:6319\:52d5)\:3002 *)
ResoniteRealtime`ResoniteRealtimeLinkConnect[port_Integer, opts : OptionsPattern[]] :=
  Module[{conn, host},
    host = OptionValue[ResoniteRealtime`ResoniteRealtimeLinkConnect, {opts}, "Host"];
    If[StringQ[$iState["Link"]], ResoniteRealtime`ResoniteRealtimeLinkDisconnect[]];
    conn = ResoniteRealtime`RRWSConnect[
      "ws://" <> host <> ":" <> ToString[port] <> "/", iLinkHandler];
    If[!StringQ[conn],
      If[!TrueQ[OptionValue[ResoniteRealtime`ResoniteRealtimeLinkConnect, {opts}, "Quiet"]],
        Print[Style["ResoniteLink \:306b\:63a5\:7d9a\:3067\:304d\:307e\:305b\:3093\:3067\:3057\:305f\:3002", Red]];
        Print["  Dashboard \[RightArrow] \:30bb\:30c3\:30b7\:30e7\:30f3 \[RightArrow] \"Resonite\:30ea\:30f3\:30af\:3092\:6709\:52b9\:5316\" \:3068\:3001\:8868\:793a\:3055\:308c\:305f\:30dd\:30fc\:30c8\:756a\:53f7\:3092\:78ba\:8a8d\:3057\:3066\:304f\:3060\:3055\:3044\:3002"];
        Print["  \:30db\:30b9\:30c8\:540d\:306f localhost \:3067\:3059 (127.0.0.1 \:306f http.sys \:304c 400 \:3067\:5f3e\:304d\:307e\:3059)\:3002"]];
      Return[conn]];
    $iState = Join[$iState, <|"Link" -> conn, "LinkPort" -> port|>];
    If[!TrueQ[OptionValue[ResoniteRealtime`ResoniteRealtimeLinkConnect, {opts}, "Quiet"]],
      Print[Style["ResoniteLink \:63a5\:7d9a (port " <> ToString[port] <> ")", Bold, Darker[Green]]]];
    conn];

ResoniteRealtime`ResoniteRealtimeLinkDisconnect[] := (
  If[StringQ[$iState["Link"]], Quiet[ResoniteRealtime`RRWSClose[$iState["Link"]]]];
  $iState = Join[$iState, <|"Link" -> None|>];
  None);

ResoniteRealtime`ResoniteRealtimeLinkMessages[n_Integer : 20] :=
  Take[$iLinkMessages, -Min[n, Length[$iLinkMessages]]];

Options[ResoniteRealtime`ResoniteRealtimeLink] = {
  "Timeout" -> 10, "Wait" -> Automatic, "Match" -> Automatic, "Raw" -> False};

(* "Wait" -> Automatic \:306f $iLinkWaitDefault (\:65e2\:5b9a True) \:306b\:5f93\:3046\:3002ScheduledTask / SocketListen \:306e\:4e2d\:3067\:306f
   \:5fdc\:7b54\:3092\:53d7\:3051\:308b\:975e\:540c\:671f\:30cf\:30f3\:30c9\:30e9\:304c\:8d70\:308c\:305a\:5f85\:3061\:304c\:5fc5\:305a\:30bf\:30a4\:30e0\:30a2\:30a6\:30c8\:3059\:308b (2026-09-06 \:5b9f\:6a5f) \:306e\:3067\:3001
   \:305d\:3053\:304b\:3089\:547c\:3076\:5074\:306f Block[{$iLinkWaitDefault = False}, ...] \:3067\:9001\:308a\:3063\:3071\:306a\:3057\:306b\:3059\:308b\:3002 *)
If[!BooleanQ[$iLinkWaitDefault], $iLinkWaitDefault = True];

(* \:5fdc\:7b54\:306e\:7167\:5408 (2026-09-04 \:306b\:5b9f\:6a5f\:3067\:78ba\:8a8d\:3057\:305f\:4ed5\:69d8):
     - \:30ea\:30af\:30a8\:30b9\:30c8\:306b "messageId" \:3092\:5165\:308c\:308b\:3068\:3001\:5fdc\:7b54\:306e "sourceMessageId" \:306b\:8fd4\:3063\:3066\:304f\:308b\:3002
       \:3053\:308c\:3092\:76f8\:95a2 ID \:3068\:3057\:3066\:4f7f\:3046\:3002\:547c\:3073\:51fa\:3057\:5074\:304c messageId \:3092\:660e\:793a\:3057\:3066\:3044\:308c\:3070\:305d\:308c\:3092\:5c0a\:91cd\:3059\:308b\:3002
     - \:5fdc\:7b54\:306f\:6210\:5426\:306b\:3088\:3089\:305a "success" (Bool) \:3068 "errorInfo" (String|Null) \:3092\:6301\:3064\:3002
       success \:304c False \:306e\:3068\:304d\:306f errorInfo \:3092 Failure \:306b\:3057\:3066\:8fd4\:3059 ("Raw" -> True \:3067\:751f\:306e\:307e\:307e)\:3002
     - $type \:306f\:8981\:6c42\:3068\:5bfe\:306b\:306a\:3089\:306a\:3044 (getSlot \:3078\:306e\:5fdc\:7b54\:306f "slotData")\:3002\:3060\:304b\:3089 $type \:3067\:306f\:7167\:5408\:3057\:306a\:3044\:3002 *)
ResoniteRealtime`ResoniteRealtimeLink[msg_Association, opts : OptionsPattern[]] :=
  Module[{conn, timeout, wait, match, raw, t0, ba, full, msgId, candidates, res},
    conn = $iState["Link"];
    If[!StringQ[conn],
      Return[iFailure["NotConnected",
        "ResoniteLink \:306b\:63a5\:7d9a\:3057\:3066\:3044\:307e\:305b\:3093\:3002ResoniteRealtimeLinkConnect[port] \:3092\:5148\:306b\:5b9f\:884c\:3057\:3066\:304f\:3060\:3055\:3044\:3002"]]];
    timeout = OptionValue[ResoniteRealtime`ResoniteRealtimeLink, {opts}, "Timeout"];
    wait    = Replace[OptionValue[ResoniteRealtime`ResoniteRealtimeLink, {opts}, "Wait"],
      Automatic -> $iLinkWaitDefault];
    match   = OptionValue[ResoniteRealtime`ResoniteRealtimeLink, {opts}, "Match"];
    raw     = OptionValue[ResoniteRealtime`ResoniteRealtimeLink, {opts}, "Raw"];
    msgId   = Lookup[msg, "messageId", ResoniteRealtime`ResoniteRealtimeNewId["Msg"]];
    full    = Join[<|"messageId" -> msgId|>, msg];
    (* ExportByteArray \:306a\:3089 UTF-8 \:30d0\:30a4\:30c8\:5217\:304c\:4e00\:5ea6\:3060\:3051\:51fa\:308b (ExportString "RawJSON" \:306f
       byte \:6587\:5b57\:5217\:306a\:306e\:3067\:4e8c\:91cd\:30a8\:30f3\:30b3\:30fc\:30c9\:306e\:5143\:306b\:306a\:308b) *)
    ba = Quiet @ Check[ExportByteArray[full, "RawJSON"], $Failed];
    If[!ByteArrayQ[ba], Return[iFailure["BadMessage", "JSON \:3078\:5909\:63db\:3067\:304d\:307e\:305b\:3093\:3067\:3057\:305f\:3002"]]];
    t0 = iNow[];
    ResoniteRealtime`RRWSSend[conn, ba];
    If[!TrueQ[wait], Return[<|"Sent" -> True, "MessageId" -> msgId|>]];
    ResoniteRealtime`RRWSFlush[];   (* \:307e\:3068\:3081\:66f8\:304d\:306e\:9014\:4e2d\:306a\:3089\:3001\:5f85\:3064\:524d\:306b\:5410\:304d\:51fa\:3059 (\:6e9c\:3081\:305f\:307e\:307e\:3060\:3068\:5fdc\:7b54\:304c\:6765\:306a\:3044) *)
    candidates = {};
    (* 2026-09-22: \:53d7\:4fe1\:30d0\:30c3\:30d5\:30a1\:306f $iLinkLimit (100) \:4ef6\:3067\:5207\:308a\:8a70\:3081\:3089\:308c\:308b\:3002\:4ee5\:524d\:306f\:300c\:9001\:4fe1\:524d\:306e\:4ef6\:6570\:3088\:308a\:5f8c\:308d\:300d\:3092
       \:898b\:3066\:3044\:305f\:306e\:3067\:3001\:63a5\:7d9a\:5185\:306e 101 \:4ef6\:76ee\:4ee5\:964d\:306f\:5fdc\:7b54\:304c\:6c38\:9060\:306b\:898b\:3048\:305a\:30bf\:30a4\:30e0\:30a2\:30a6\:30c8\:3057\:305f (\:30bf\:30d6\:30ec\:30c3\:30c8\:306e\:7d44\:307f\:7acb\:3066
       ~100 \:30e1\:30c3\:30bb\:30fc\:30b8\:3067\:5b9f\:6e2c)\:3002\:9001\:4fe1\:6642\:523b\:4ee5\:964d\:306b\:53d7\:3051\:305f\:3082\:306e\:304b\:3089\:7167\:5408\:3059\:308b\:3002 *)
    While[candidates === {} && iNow[] - t0 < timeout,
      Pause[0.02];
      candidates = Select[$iLinkMessages,
        Lookup[#, "Time", 0] >= t0 && iLinkResponseQ[#["Message"], match, msgId] &]];
    If[candidates === {},
      Return[iFailure["Timeout",
        "ResoniteLink \:304b\:3089 " <> ToString[timeout] <> " \:79d2\:4ee5\:5185\:306b\:5fdc\:7b54\:304c\:3042\:308a\:307e\:305b\:3093\:3067\:3057\:305f\:3002"]]];
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
      (* sourceMessageId \:304c\:4ed8\:3044\:3066\:3044\:308b\:5b9f\:88c5\:3067\:306f\:53b3\:5bc6\:306b\:7167\:5408\:3059\:308b\:3002
         \:4ed8\:3044\:3066\:3044\:306a\:3044\:5fdc\:7b54 (Null) \:306f\:3001\:76f8\:95a2\:306e\:624b\:639b\:304b\:308a\:304c\:7121\:3044\:306e\:3067\:5f93\:6765\:3069\:304a\:308a\:53d7\:3051\:5165\:308c\:308b\:3002 *)
      With[{src = Lookup[m, "sourceMessageId", Null]},
        src === msgId || src === Null || src === None],
      TrueQ[match[m]]];

(* ---- \:578b\:4ed8\:304d\:5024 ---- *)

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

(* ---- \:30b3\:30de\:30f3\:30c9 ---- *)

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

(* addSlot: \:4f4d\:7f6e\:30fb\:56de\:8ee2\:30fb\:30b9\:30b1\:30fc\:30eb\:30fb\:540d\:524d\:30fb\:89aa\:3092\:307e\:3068\:3081\:3066\:6307\:5b9a\:3067\:304d\:308b *)
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
      (* \:30ad\:30fc\:540d\:306f\:5fdc\:7b54\:3068\:540c\:3058 "isActive" (updateSlot \:3067\:5b9f\:6e2c\:3002"active" \:306f\:7121\:8996\:3055\:308c\:308b) *)
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
   \:72b6\:614b\:8868\:793a
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

(* \:5e38\:99d0\:30dd\:30fc\:30ea\:30f3\:30b0\:306f\:3057\:306a\:3044\:3002\:62bc\:3057\:305f\:3068\:304d\:3060\:3051\:8aad\:307f\:76f4\:3059 (\:30d1\:30ec\:30c3\:30c8\:5e38\:99d0 Dynamic \:306f FE \:3092\:6bba\:3059) *)
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
              "   \:63a5\:7d9a: ", Length[st["BridgeConnections"]]}],
            Row[{"link: ",
              If[TrueQ[st["LinkConnected"]],
                Style["connected :" <> ToString[st["LinkPort"]], Darker[Green]],
                Style["disconnected", Gray]]}],
            Row[{"events: ", st["Events"], "   link msgs: ", st["LinkMessages"]}],
            Row[{
              Button["\:66f4\:65b0", tick++, ImageSize -> {60, 24}],
              Spacer[6],
              Button["\:505c\:6b62", ResoniteRealtime`ResoniteRealtimeStop[]; tick++,
                ImageSize -> {60, 24}]}]},
            Spacings -> 0.4],
          Background -> GrayLevel[0.97], FrameMargins -> 8]],
      TrackedSymbols :> {tick}]];

End[];

EndPackage[];

(* \:518d\:30ed\:30fc\:30c9\:306e\:9593\:6b62\:3081\:3066\:3044\:305f\:76e3\:8996 tick \:3092\:623b\:3059 (\:30d5\:30a1\:30a4\:30eb\:982d\:306e Busy\:3002\:5b9a\:7fa9\:306f\:3059\:3079\:3066\:5165\:308c\:76f4\:3057\:305f) *)
If[AssociationQ[ResoniteRealtime`Private`$itState], ResoniteRealtime`Private`$itState["Busy"] = False];
If[AssociationQ[ResoniteRealtime`Private`$icState], ResoniteRealtime`Private`$icState["Busy"] = False];

(*Print[Style["ResoniteRealtime \:30d1\:30c3\:30b1\:30fc\:30b8\:304c\:30ed\:30fc\:30c9\:3055\:308c\:307e\:3057\:305f\:3002", Bold]];
Print["
  ResoniteRealtimeStart[]              \[RightArrow] L1 \:30d6\:30ea\:30c3\:30b8\:8d77\:52d5 (ws://127.0.0.1:17300/bridge)
  ResoniteRealtimeOn[verb, f]          \[RightArrow] \:4e16\:754c\:304b\:3089\:306e\:884c\:306b\:30cf\:30f3\:30c9\:30e9\:3092\:767b\:9332
  ResoniteRealtimeSend[verb, args...]  \[RightArrow] \:4e16\:754c\:3078 TAB \:533a\:5207\:308a\:306e\:884c\:3092\:9001\:308b
  ResoniteRealtimeLinkConnect[]        \[RightArrow] ResoniteLink \:306b\:63a5\:7d9a (port \:306f\:81ea\:52d5\:691c\:51fa\:3002ResoniteRealtimeLinkConnect[port] \:3067\:660e\:793a)
  ResoniteTabletServe[]                \[RightArrow] \:5e38\:99d0\:76e3\:8996: ResoniteLink \:3092\:81ea\:52d5\:691c\:51fa\:3057\:3066\:7e4b\:304e\:3001\:30ef\:30fc\:30eb\:30c9\:306e\:30bf\:30d6\:30ec\:30c3\:30c8\:306e\:300c\:63a5\:7d9a\:300d\:3092\:5f85\:3064 (NB \:3067\:306f\:81ea\:52d5\:8d77\:52d5)
  ResoniteRealtimeGetSlot[]            \[RightArrow] \:30b7\:30fc\:30f3\:968e\:5c64\:3092\:53d6\:5f97
  ResoniteRealtimeAddSlot[...]         \[RightArrow] slot \:3092\:4f5c\:308b
  ResoniteRealtimeStatus[] / ResoniteRealtimeMonitor[] / ResoniteRealtimeStop[]
  ResoniteChatGadget[] / ResoniteChatStart[]  \[RightArrow] \:30ef\:30fc\:30eb\:30c9\:5185 Chat \:30d1\:30cd\:30eb\:3092\:4f5c\:308a\:3001\:5165\:529b\:3092\:76e3\:8996
  ResoniteChat[prompt] / ResoniteChatCell[]   \[RightArrow] Chat \:30bb\:30eb\:306e\:7b54\:3048\:3092\:30ef\:30fc\:30eb\:30c9\:3078\:51fa\:3059
  ResoniteAccessLevel[\"Private\"|\"Contacts\"|\"Public\", \"Owner\" -> True]  \[RightArrow] \:8868\:793a\:4e0a\:9650 PL (1.0 / 0.5 / 0.25\:3002\:975e\:30aa\:30fc\:30ca\:30fc\:306f 0.25)
  ResoniteFluxChat[spec] / ResoniteFluxCell[] \[RightArrow] ProtoFlux (ProtoGraph) \:3092\:751f\:6210\:3057\:3066\:51fa\:3059
  ResoniteTablet[]                     \[RightArrow] \:30ef\:30fc\:30eb\:30c9\:5185\:30bf\:30d6\:30ec\:30c3\:30c8 (ClaudeEval / \:627f\:8a8d / \:30b9\:30af\:30ed\:30fc\:30eb\:51fa\:529b / \:30d3\:30e5\:30fc\:30a2)
  ResoniteShowObject[uri|row|file|expr] / ResoniteListGadget[rows] \[RightArrow] SourceVault \:30aa\:30d6\:30b8\:30a7\:30af\:30c8\:3068\:4e00\:89a7\:3092\:30ef\:30fc\:30eb\:30c9\:3078
  ResoniteColorToggleBox[{Red, Blue}]  \[RightArrow] \:30af\:30ea\:30c3\:30af\:3067\:8272\:304c\:5207\:308a\:66ff\:308f\:308b\:7bb1 (\:63d0\:6848\:30b3\:30fc\:30c9 1 \:3064\:3067\:4f5c\:308c\:308b\:90e8\:54c1)
"];*)

(* \:30ce\:30fc\:30c8\:30d6\:30c3\:30af\:306e\:30bb\:30c3\:30b7\:30e7\:30f3\:3067\:306f\:5e38\:99d0\:76e3\:8996\:3092\:81ea\:52d5\:3067\:59cb\:3081\:308b (\:30a4\:30f3\:30d9\:30f3\:30c8\:30ea\:304b\:3089\:51fa\:3057\:305f\:30bf\:30d6\:30ec\:30c3\:30c8\:306e\:300c\:63a5\:7d9a\:300d\:3067\:4f7f\:3048\:308b\:3088\:3046\:306b)\:3002
   \:30d8\:30c3\:30c9\:30ec\:30b9 (\:30c6\:30b9\:30c8 / \:30b5\:30fc\:30d3\:30b9\:30ab\:30fc\:30cd\:30eb) \:3067\:306f\:59cb\:3081\:306a\:3044\:3002$ResoniteTabletAutoServe = False \:3067\:6b62\:3081\:3089\:308c\:308b\:3002 *)
If[!BooleanQ[ResoniteRealtime`$ResoniteTabletAutoServe], ResoniteRealtime`$ResoniteTabletAutoServe = True];
If[TrueQ[ResoniteRealtime`$ResoniteTabletAutoServe] && TrueQ[$Notebooks] &&
   Names["ResoniteRealtime`ResoniteTabletServe"] =!= {},
  Quiet @ Check[ResoniteRealtime`ResoniteTabletServe[], Null]];
