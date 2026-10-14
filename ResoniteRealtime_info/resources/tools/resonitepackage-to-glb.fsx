// resonitepackage-to-glb.fsx -- Resonite の .resonitepackage を glb (glTF 2.0 バイナリ) に変換する
//   ボーン・スキンウェイト・ブレンドシェイプ・マテリアル/テクスチャ付き。Resonite 標準のモデル書き出し
//   (ModelExporter/Assimp) はウェイトとブレンドシェイプを落とすので、パッケージ (MeshX 資産 + データツリー) から作る。
//
// 使い方:
//   dotnet fsi resonitepackage-to-glb.fsx <入力.resonitepackage> [出力.glb] [オプション]
//     --root=auto|object|<スロット名>  書き出す根。auto (既定) は AvatarRoot を持つスロットが 1 つならそれ、
//                                      無ければ最上位 (InventoryItem の包み "Holder" は外す)。object は最上位そのもの
//     --include-hidden                 無効なレンダラー・非アクティブなスロットのレンダラーも書き出す
//                                      (既定は Resonite で見えているものだけ。省いたものは一覧を出す)
//     --no-morph-normals               ブレンドシェイプの法線差分を書かない (小さくなる。Blender は元々使わない。
//                                      書く場合も長さ 1e-3 未満の差分は 0 にして疎アクセサに収める)
//     --keep-root-transform            根スロットの位置・回転を残す (既定は原点・正立に戻す。スケールは残す)
//     --saved-pose                     ボーンを保存時の姿勢のまま書く (既定はバインド姿勢 = 元モデルの T/A ポーズに戻す。
//                                      保存時の姿勢は IK で膝が曲がっている等のことがある)
//   出力を省くと入力と同じフォルダに <入力名>.glb を作る。
//   例: dotnet fsi resonitepackage-to-glb.fsx "%USERPROFILE%\Downloads\MyAvatar.resonitepackage"
//   Blender: ファイル > インポート > glTF 2.0。シェイプキーはメッシュのプロパティ、ボーンはポーズモードで動かせる。
//
// 前提: Resonite (Steam 版) と .NET 10 SDK。DLL は下の #I と resoniteDir のフォルダから読む (別の場所なら両方を書き換える)。
//   NuGet は使わない。glb は自前で書き、PNG/JPEG 以外の画像 (WebP 等) は Resonite 同梱の Bitmap2D で PNG にする。
//
// 変換の中身:
//   - パッケージ (ZIP) を Elements.Assets.RecordPackage で開き、R-Main.record の AssetURI が指すデータツリー (FrDT) を読む
//   - スロット (名前・TRS・親子) → ノード。書き出すレンダラー・そのボーン・BipedRig のボーンと、その先祖だけ残す
//   - SkinnedMeshRenderer / MeshRenderer → メッシュ (StaticMesh の資産を MeshX で読む。手続き型メッシュは対象外)
//     ジョイント = Bones のスロット、逆バインド行列 = MeshX の Bone.BindPose、ウェイト = RawBoneBindings
//     ブレンドシェイプ = モーフターゲット (疎アクセサ。名前は mesh.extras.targetNames、初期値は BlendShapeWeights)
//   - マテリアル: PBS / Xiexe / Unlit などの共通フィールド (Albedo・Main テクスチャ, 色, 法線, 発光, 遮蔽, 金属/滑らかさ,
//     BlendMode, Culling, テクスチャの Scale/Offset) を glTF の PBR に寄せる。トゥーン固有の値は捨てる
//     (元の型名は material.extras.resoniteType)。金属/滑らかさマップは形式が違うので使わない
//   - バインド姿勢: ボーンのスロットを「レンダラーの位置 × inverse(BindPose)」に置き直す (親から順に。共有ボーンは最初のメッシュ基準)
//   - 座標系: Resonite (左手系 Y 上) → glTF (右手系 Y 上) は X 反転。UV は v → 1-v。単位はメートルのまま
//   - BipedRig の対応表 (Hips → ノード名 など) は scenes[0].extras.resoniteHumanoid に入れる
//
// 対象は自分で書き出せたパッケージだけ。保護 (SimpleAvatarProtection やワールドの保存権限) の回避はしない。

#I @"C:\Program Files (x86)\Steam\steamapps\common\Resonite"
#r "Elements.Core.dll"
#r "Elements.Assets.dll"
#r "SkyFrost.Base.Models.dll"
#r "Renderite.Shared.dll"
#nowarn "3886" // jobj [ "k", v ] の 1 要素リスト

open Elements.Core
open Elements.Assets
open Renderite.Shared
open System
open System.Collections.Generic
open System.Globalization
open System.IO
open System.Runtime.Loader
open System.Text.Encodings.Web
open System.Text.Json
open System.Text.Json.Nodes

let resoniteDir = @"C:\Program Files (x86)\Steam\steamapps\common\Resonite"
AssemblyLoadContext.Default.add_Resolving(fun ctx name ->
    let p = Path.Combine(resoniteDir, name.Name + ".dll")
    if File.Exists p then ctx.LoadFromAssemblyPath p else null)

// ---------- 引数 ----------
let argv = fsi.CommandLineArgs |> Array.skip 1
let options, positional = argv |> Array.partition (fun a -> a.StartsWith "--")
let knownOptions = [ "--root"; "--include-hidden"; "--no-morph-normals"; "--keep-root-transform"; "--saved-pose" ]
let badOptions = options |> Array.filter (fun o -> not (knownOptions |> List.contains (o.Split('=').[0])))
if positional.Length < 1 || positional.Length > 2 || badOptions.Length > 0 then
    if badOptions.Length > 0 then eprintfn "不明なオプション: %s" (String.Join(" ", badOptions))
    eprintfn "usage: dotnet fsi resonitepackage-to-glb.fsx <in.resonitepackage> [out.glb] [--root=auto|object|<slot>] [--include-hidden] [--no-morph-normals] [--keep-root-transform] [--saved-pose]"
    exit 2
let inputPath = Path.GetFullPath positional.[0]
let outputPath = if positional.Length > 1 then Path.GetFullPath positional.[1] else Path.ChangeExtension(inputPath, ".glb")
let optionValue (name: string) =
    options |> Array.tryPick (fun o -> if o.StartsWith(name + "=") then Some (o.Substring(name.Length + 1)) else None)
let rootMode = defaultArg (optionValue "--root") "auto"
let includeHidden = options |> Array.contains "--include-hidden"
let morphNormals = not (options |> Array.contains "--no-morph-normals")
let keepRootTransform = options |> Array.contains "--keep-root-transform"
let bindPose = not (options |> Array.contains "--saved-pose")

// ---------- JSON の小道具 ----------
let ji (x: int) : JsonNode = JsonValue.Create x
let jl (x: int64) : JsonNode = JsonValue.Create x
let jf (x: float32) : JsonNode = JsonValue.Create(if Single.IsFinite x then x else 0.0f)
// min/max は float32 の値をそのまま double で書く (検証器が float32 精度で照合しても一致するように)
let jd (x: float32) : JsonNode = JsonValue.Create(float x)
let js (x: string) : JsonNode = JsonValue.Create(if isNull x then "" else x)
let jb (x: bool) : JsonNode = JsonValue.Create x
let jarr (xs: seq<JsonNode>) : JsonNode = JsonArray(Array.ofSeq xs) :> JsonNode
let jobj (kvs: (string * JsonNode) list) : JsonObject =
    let o = JsonObject()
    for (k, v) in kvs do
        if not (isNull v) then o.[k] <- v
    o
let addTo (a: JsonArray) (n: JsonNode) = a.Add n

let toBytes (a: Array) =
    let b = Array.zeroCreate<byte> (Buffer.ByteLength a)
    Buffer.BlockCopy(a, 0, b, 0, b.Length)
    b

let minMax (data: float32[]) (width: int) =
    let n = data.Length / width
    let mn = Array.create width Single.MaxValue
    let mx = Array.create width Single.MinValue
    for i in 0 .. n - 1 do
        for k in 0 .. width - 1 do
            let v = data.[i * width + k]
            if v < mn.[k] then mn.[k] <- v
            if v > mx.[k] then mx.[k] <- v
    if n = 0 then Array.zeroCreate width, Array.zeroCreate width else mn, mx

// ---------- glb の組み立て (Resonite の型は使わない) ----------
let ARRAY_BUFFER = 34962
let ELEMENT_ARRAY_BUFFER = 34963
let FLOAT = 5126
let UNSIGNED_INT = 5125
let UNSIGNED_SHORT = 5123
let UNSIGNED_BYTE = 5121

type GlbBuilder() =
    let bin = new MemoryStream()
    let views = JsonArray()
    let accessors = JsonArray()
    member _.Views = views
    member _.Accessors = accessors
    member _.Bin = bin
    member _.AddView(bytes: byte[], target: int) : int =
        while bin.Length % 4L <> 0L do bin.WriteByte 0uy
        let v = jobj [ "buffer", ji 0; "byteOffset", jl bin.Length; "byteLength", ji bytes.Length ]
        if target <> 0 then v.["target"] <- ji target
        bin.Write(bytes, 0, bytes.Length)
        addTo views v
        views.Count - 1
    member _.AddAccessor(view: int, componentType: int, count: int, typ: string, withMinMax: (float32[] * float32[]) option, normalized: bool) : int =
        let a = jobj [ "bufferView", ji view; "componentType", ji componentType; "count", ji count; "type", js typ ]
        if normalized then a.["normalized"] <- jb true
        match withMinMax with
        | Some (mn, mx) ->
            a.["min"] <- jarr [ for v in mn -> jd v ]
            a.["max"] <- jarr [ for v in mx -> jd v ]
        | None -> ()
        addTo accessors a
        accessors.Count - 1
    /// float の頂点属性など (width = 1..4 / 16)
    member g.FloatAccessor(data: float32[], width: int, typ: string, target: int, withMinMax: bool) : int =
        let view = g.AddView(toBytes data, target)
        g.AddAccessor(view, FLOAT, data.Length / width, typ, (if withMinMax then Some (minMax data width) else None), false)
    /// モーフターゲットの VEC3 差分。影響する頂点が少なければ疎アクセサにする
    member g.MorphAccessor(data: float32[], withMinMax: bool) : int =
        let count = data.Length / 3
        let nz = [| for i in 0 .. count - 1 do
                        if data.[3 * i] <> 0.0f || data.[3 * i + 1] <> 0.0f || data.[3 * i + 2] <> 0.0f then yield i |]
        if nz.Length * 10 >= count * 7 then g.FloatAccessor(data, 3, "VEC3", ARRAY_BUFFER, withMinMax)
        else
            // 疎アクセサは 1 件以上必要。影響なしのシェイプは 0 番に 0 を 1 件置く
            let idx = if nz.Length = 0 then [| 0u |] else nz |> Array.map uint32
            let vals = Array.zeroCreate<float32> (idx.Length * 3)
            if nz.Length > 0 then
                nz |> Array.iteri (fun k i -> vals.[3 * k] <- data.[3 * i]; vals.[3 * k + 1] <- data.[3 * i + 1]; vals.[3 * k + 2] <- data.[3 * i + 2])
            let iv = g.AddView(toBytes idx, 0)
            let vv = g.AddView(toBytes vals, 0)
            let a = jobj [ "componentType", ji FLOAT; "count", ji count; "type", js "VEC3" ]
            if withMinMax then
                let mn, mx = minMax data 3
                a.["min"] <- jarr [ for v in mn -> jd v ]
                a.["max"] <- jarr [ for v in mx -> jd v ]
            a.["sparse"] <- jobj [ "count", ji idx.Length
                                   "indices", jobj [ "bufferView", ji iv; "componentType", ji UNSIGNED_INT ]
                                   "values", jobj [ "bufferView", ji vv ] ]
            addTo accessors a
            accessors.Count - 1

let writeGlb (path: string) (gltf: JsonObject) (bin: byte[]) =
    let jsonOptions = JsonSerializerOptions(Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping)
    let jsonBytes = Text.Encoding.UTF8.GetBytes(gltf.ToJsonString jsonOptions)
    let pad n = (4 - n % 4) % 4
    let jsonLen = jsonBytes.Length + pad jsonBytes.Length
    let binLen = bin.Length + pad bin.Length
    let total = 12 + 8 + jsonLen + (if bin.Length > 0 then 8 + binLen else 0)
    Directory.CreateDirectory(Path.GetDirectoryName path) |> ignore
    use f = File.Create path
    use w = new BinaryWriter(f)
    w.Write 0x46546C67u // "glTF"
    w.Write 2u
    w.Write(uint32 total)
    w.Write(uint32 jsonLen)
    w.Write 0x4E4F534Au // "JSON"
    w.Write jsonBytes
    for _ in 1 .. pad jsonBytes.Length do w.Write 0x20uy
    if bin.Length > 0 then
        w.Write(uint32 binLen)
        w.Write 0x004E4942u // "BIN\0"
        w.Write bin
        for _ in 1 .. pad bin.Length do w.Write 0uy

// ---------- データツリーの読み取り ----------
/// 利用者に原因を伝えれば足りる失敗 (スタックトレースは出さない)
exception ConvertError of string

type Comp = { CId: string; CType: string; CData: DataTreeDictionary; CSlot: string }
type Slot =
    { SId: string; SName: string; Pos: float32[]; Rot: float32[]; Scl: float32[]; Active: bool
      Parent: string; Children: ResizeArray<string>; Comps: ResizeArray<Comp> }

let valueOf (n: DataTreeNode) : obj =
    match n with
    | :? DataTreeValue as v when not v.IsNull -> box v.Value
    | _ -> null

/// 同期メンバー {"ID":…, "Data":…} なら Data を、そうでなければノードそのものを返す
let fld (d: DataTreeDictionary) (key: string) : DataTreeNode =
    match d.TryGetNode key with
    | :? DataTreeDictionary as m when m.ContainsKey "Data" && m.ContainsKey "ID" -> m.TryGetNode "Data"
    | n -> n

let has (d: DataTreeDictionary) (key: string) = d.ContainsKey key
let fStr d k = match valueOf (fld d k) with null -> null | v -> string v
let fBool d k dflt =
    match valueOf (fld d k) with
    | null -> dflt
    | :? bool as b -> b
    | v -> try Convert.ToBoolean(v, CultureInfo.InvariantCulture) with _ -> dflt
let fNum d k : float32 option =
    match valueOf (fld d k) with
    | null | :? bool | :? string -> None
    | v -> try Some (Convert.ToSingle(v, CultureInfo.InvariantCulture)) with _ -> None
let fRef d k : string option = match fStr d k with null | "" -> None | s -> Some s

/// 数値のリスト ([x,y,z] や [r,g,b,a,"sRGB"] の数値部分)
let floats (n: DataTreeNode) : float32[] =
    match n with
    | :? DataTreeList as l ->
        l.Children
        |> Seq.choose (fun c ->
            match valueOf c with
            | null | :? string | :? bool -> None
            | v -> Some (Convert.ToSingle(v, CultureInfo.InvariantCulture)))
        |> Array.ofSeq
    | _ -> [||]

let colorProfile (n: DataTreeNode) : string option =
    match n with
    | :? DataTreeList as l -> l.Children |> Seq.tryPick (fun c -> match valueOf c with :? string as s -> Some s | _ -> None)
    | _ -> None

/// 同期リスト [{"ID":…,"Data":ref}, …] の参照先 ID
let listRefs (n: DataTreeNode) : string option[] =
    match n with
    | :? DataTreeList as l ->
        l.Children
        |> Seq.map (fun e ->
            match e with
            | :? DataTreeDictionary as ed ->
                (match valueOf (ed.TryGetNode "Data") with
                 | null -> None
                 | v -> let s = string v in if s = "" then None else Some s)
            | _ -> None)
        |> Array.ofSeq
    | _ -> [||]

/// 同期リスト [{"ID":…,"Data":数値}, …]
let listFloats (n: DataTreeNode) : float32[] =
    match n with
    | :? DataTreeList as l ->
        l.Children
        |> Seq.map (fun e ->
            match e with
            | :? DataTreeDictionary as ed ->
                (match valueOf (ed.TryGetNode "Data") with
                 | null | :? string | :? bool -> 0.0f
                 | v -> Convert.ToSingle(v, CultureInfo.InvariantCulture))
            | _ -> 0.0f)
        |> Array.ofSeq
    | _ -> [||]

/// "[FrooxEngine]FrooxEngine.SkinnedMeshRenderer" → "SkinnedMeshRenderer" (古い形式 "FrooxEngine.X, FrooxEngine" も)
let shortType (full: string) =
    if String.IsNullOrEmpty full then "?" else
    let s = if full.StartsWith "[" then full.Substring(full.IndexOf(']') + 1) else full
    let gen = s.IndexOf '<'
    let head, tail = if gen >= 0 then s.Substring(0, gen), s.Substring gen else s, ""
    let head = match head.IndexOf ',' with -1 -> head | i -> head.Substring(0, i)
    head.Substring(head.LastIndexOf('.') + 1) + tail

/// "@packdb:///<sig>" / "resdb:///<sig>.meshx" → "<sig>"
let assetSignature (raw: string) : string option =
    if String.IsNullOrEmpty raw then None else
    let s = if raw.StartsWith "@" then raw.Substring 1 else raw
    match Uri.TryCreate(s, UriKind.Absolute) with
    | true, u when u.Scheme = "packdb" || u.Scheme = "resdb" ->
        let p = u.AbsolutePath.Trim('/')
        let p = match p.IndexOf '.' with -1 -> p | i -> p.Substring(0, i)
        if p = "" then None else Some (p.ToLowerInvariant())
    | _ -> None

let urlExtension (raw: string) =
    if String.IsNullOrEmpty raw then "" else
    let s = raw.TrimStart('@')
    match Uri.TryCreate(s, UriKind.Absolute) with
    | true, u -> Path.GetExtension(u.AbsolutePath).TrimStart('.').ToLowerInvariant()
    | _ -> ""

let parseTree (root: DataTreeDictionary) =
    let types =
        match root.TryGetList "Types" with
        | null -> [||]
        | l -> l.Children |> Seq.map (fun c -> string (valueOf c)) |> Array.ofSeq
    let slots = Dictionary<string, Slot>()
    let comps = Dictionary<string, Comp>()
    let typeOf (c: DataTreeDictionary) =
        match valueOf (c.TryGetNode "Type") with
        | :? string as s -> shortType s
        | null -> "?"
        | v ->
            let i = Convert.ToInt32(v, CultureInfo.InvariantCulture)
            if i >= 0 && i < types.Length then shortType types.[i] else "?"
    let addComp (slotId: string) (c: DataTreeNode) : Comp option =
        match c with
        | :? DataTreeDictionary as cd ->
            match cd.TryGetNode "Data" with
            | :? DataTreeDictionary as data ->
                let id = string (valueOf (data.TryGetNode "ID"))
                let comp = { CId = id; CType = typeOf cd; CData = data; CSlot = slotId }
                if id <> "" then comps.[id] <- comp
                Some comp
            | _ -> None
        | _ -> None
    let vec (d: DataTreeDictionary) k (dflt: float32[]) =
        let v = floats (fld d k)
        if v.Length >= dflt.Length then v else dflt
    let rec walk (parent: string) (d: DataTreeDictionary) : string =
        let id = string (valueOf (d.TryGetNode "ID"))
        let s =
            { SId = id
              SName = (match fStr d "Name" with null -> "" | n -> n)
              Pos = vec d "Position" [| 0.0f; 0.0f; 0.0f |]
              Rot = vec d "Rotation" [| 0.0f; 0.0f; 0.0f; 1.0f |]
              Scl = vec d "Scale" [| 1.0f; 1.0f; 1.0f |]
              Active = fBool d "Active" true
              Parent = parent
              Children = ResizeArray()
              Comps = ResizeArray() }
        slots.[id] <- s
        match fld d "Components" with
        | :? DataTreeList as l -> for c in l.Children do addComp id c |> Option.iter s.Comps.Add
        | _ -> ()
        match d.TryGetNode "Children" with
        | :? DataTreeList as l ->
            for c in l.Children do
                match c with
                | :? DataTreeDictionary as cd -> s.Children.Add(walk id cd)
                | _ -> ()
        | _ -> ()
        id
    let rootId =
        match root.TryGetNode "Object" with
        | :? DataTreeDictionary as o -> walk null o
        | _ -> raise (ConvertError "データツリーに Object がありません")
    match root.TryGetNode "Assets" with
    | :? DataTreeList as l -> for c in l.Children do addComp null c |> ignore
    | _ -> ()
    rootId, slots, comps

// ---------- 座標変換 (Resonite 左手系 → glTF 右手系: X 反転) ----------
let mirrorPos (p: float32[]) = [| -p.[0]; p.[1]; p.[2] |]
let mirrorRot (q: float32[]) =
    let x, y, z, w = q.[0], -q.[1], -q.[2], q.[3]
    let l = sqrt (x * x + y * y + z * z + w * w)
    if l < 1e-6f || not (Single.IsFinite l) then [| 0.0f; 0.0f; 0.0f; 1.0f |] else [| x / l; y / l; z / l; w / l |]

/// Resonite の float4x4 (列ベクトル規約, mRC) を S·M·S (S = diag(-1,1,1,1)) にして列優先で並べる。最下行は (0,0,0,1) に揃える
let mirroredColumnMajor (m: float4x4) =
    let a = array2D [ [ m.m00; m.m01; m.m02; m.m03 ]
                      [ m.m10; m.m11; m.m12; m.m13 ]
                      [ m.m20; m.m21; m.m22; m.m23 ]
                      [ m.m30; m.m31; m.m32; m.m33 ] ]
    let s i = if i = 0 then -1.0f else 1.0f
    [| for c in 0 .. 3 do
         for r in 0 .. 3 do
             yield (if r = 3 then (if c = 3 then 1.0f else 0.0f) else a.[r, c] * s r * s c) |]

/// Resonite の float4x4 (列ベクトル規約) → System.Numerics (行ベクトル規約) = 転置
let toNumerics (m: float4x4) =
    Numerics.Matrix4x4(m.m00, m.m10, m.m20, m.m30,
                       m.m01, m.m11, m.m21, m.m31,
                       m.m02, m.m12, m.m22, m.m32,
                       m.m03, m.m13, m.m23, m.m33)

/// スロットの TRS (Resonite 空間) → System.Numerics の行ベクトル行列 (v * S * R * T)
let trsMatrix (p: float32[]) (q: float32[]) (s: float32[]) =
    Numerics.Matrix4x4.CreateScale(s.[0], s.[1], s.[2])
    * Numerics.Matrix4x4.CreateFromQuaternion(Numerics.Quaternion.Normalize(Numerics.Quaternion(q.[0], q.[1], q.[2], q.[3])))
    * Numerics.Matrix4x4.CreateTranslation(p.[0], p.[1], p.[2])

let identityColumnMajor = [| 1.0f; 0.0f; 0.0f; 0.0f; 0.0f; 1.0f; 0.0f; 0.0f; 0.0f; 0.0f; 1.0f; 0.0f; 0.0f; 0.0f; 0.0f; 1.0f |]

let srgbToLinear (c: float32) =
    if c <= 0.04045f then c / 12.92f else MathF.Pow((c + 0.055f) / 1.055f, 2.4f)

/// colorX [r,g,b,a,"sRGB"|"Linear"|"sRGBAlpha"] → 線形 RGBA。プロファイル無し (旧形式) は sRGB とみなす
let linearColor (n: DataTreeNode) : float32[] option =
    let v = floats n
    if v.Length < 3 then None else
    let a = if v.Length >= 4 then v.[3] else 1.0f
    match colorProfile n with
    | Some "Linear" -> Some [| v.[0]; v.[1]; v.[2]; a |]
    | Some "sRGBAlpha" -> Some [| srgbToLinear v.[0]; srgbToLinear v.[1]; srgbToLinear v.[2]; srgbToLinear a |]
    | _ -> Some [| srgbToLinear v.[0]; srgbToLinear v.[1]; srgbToLinear v.[2]; a |]

let isPng (b: byte[]) = b.Length > 8 && b.[0] = 0x89uy && b.[1] = 0x50uy && b.[2] = 0x4Euy && b.[3] = 0x47uy
let isJpeg (b: byte[]) = b.Length > 3 && b.[0] = 0xFFuy && b.[1] = 0xD8uy && b.[2] = 0xFFuy
let guessImageExt (b: byte[]) (urlExt: string) =
    let ascii (o: int) (len: int) = if b.Length >= o + len then Text.Encoding.ASCII.GetString(b, o, len) else ""
    if ascii 0 4 = "RIFF" && ascii 8 4 = "WEBP" then "webp"
    elif ascii 0 4 = "GIF8" then "gif"
    elif ascii 0 2 = "BM" then "bmp"
    elif ascii 0 4 = "DDS " then "dds"
    elif ascii 0 4 = "8BPS" then "psd"
    elif urlExt <> "" then urlExt
    else "png"

/// Resonite 同梱の Bitmap2D (FreeImage 等) で読み、PNG に書き直す
let convertToPng (bytes: byte[]) (ext: string) : byte[] option =
    try
        use s = new MemoryStream(bytes)
        let bmp = Bitmap2D.Load((s :> Stream), ext, Nullable false, AlphaHandling.KeepOriginal, Int32.MaxValue, 1.0f)
        use o = new MemoryStream()
        if bmp.Save((o :> Stream), "png", 100, true) then Some (o.ToArray()) else None
    with _ -> None

// ---------- 変換本体 ----------
type Geometry =
    { Pos: int; Nrm: int option; Uv0: int option; Uv1: int option
      Joints: int option; Weights: int option; RigidJoint: bool; Unweighted: int
      Prims: (int * int) list               // (submesh 番号, indices アクセサ)
      Targets: (string * int * int option)[] // (名前, POSITION, NORMAL)
      mutable Colors: int option option }   // 必要になったときに作る

let convert () =
    let warnings = ResizeArray<string>()
    let warn (s: string) = warnings.Add s
    if not (File.Exists inputPath) then raise (ConvertError (sprintf "入力ファイルがありません: %s" inputPath))
    use pkg =
        try RecordPackage.Decode inputPath
        with e -> raise (ConvertError (sprintf "パッケージとして開けません (%s): %s" e.Message inputPath))
    let readAsset (sg: string) : byte[] =
        use s = pkg.ReadAsset sg
        use ms = new MemoryStream()
        s.CopyTo ms
        ms.ToArray()
    let record = pkg.MainRecord
    let mainSig =
        match assetSignature record.AssetURI with
        | Some s when pkg.HasAsset s -> s
        | _ -> raise (ConvertError (sprintf "メインレコードのデータツリーがパッケージにありません (AssetURI=%s)" record.AssetURI))
    let tree = DataTreeConverter.LoadAuto(new MemoryStream(readAsset mainSig))
    let objectRoot, slots, comps = parseTree tree

    let hasComp (s: Slot) (t: string) = s.Comps |> Seq.exists (fun c -> c.CType = t)
    let dfsOrder (start: string) =
        let order = ResizeArray<string>()
        let rec go sid =
            order.Add sid
            for c in slots.[sid].Children do go c
        go start
        order

    // 書き出す根
    let exportRoot, rootReason =
        match rootMode with
        | "object" -> objectRoot, "object"
        | "auto" ->
            let avatarRoots =
                dfsOrder objectRoot
                |> Seq.filter (fun sid -> hasComp slots.[sid] "AvatarRoot")
                |> Seq.filter (fun sid ->
                    // 先祖に AvatarRoot が無い最上位のものだけ
                    let rec up (p: string) = if isNull p then true elif hasComp slots.[p] "AvatarRoot" then false else up slots.[p].Parent
                    up slots.[sid].Parent)
                |> List.ofSeq
            match avatarRoots with
            | [ r ] -> r, "auto: AvatarRoot"
            | _ ->
                let mutable r = objectRoot
                while hasComp slots.[r] "InventoryItem" && slots.[r].Children.Count = 1 do r <- slots.[r].Children.[0]
                r, (if r = objectRoot then "auto: 最上位" else "auto: InventoryItem の包みを外した")
        | name ->
            match dfsOrder objectRoot |> Seq.tryFind (fun sid -> slots.[sid].SName = name) with
            | Some r -> r, "--root で指定"
            | None -> raise (ConvertError (sprintf "--root=%s のスロットが見つかりません" name))
    let rec isUnder (sid: string) =
        if sid = exportRoot then true
        else match slots.TryGetValue sid with
             | true, s when not (isNull s.Parent) -> isUnder s.Parent
             | _ -> false
    // 根より下のスロットがすべてアクティブか (根そのものと根より上は見ない)
    let rec activeBelowRoot (sid: string) =
        if sid = exportRoot then true
        else let s = slots.[sid] in s.Active && (isNull s.Parent || activeBelowRoot s.Parent)
    let order = dfsOrder exportRoot

    // 書き出すレンダラー
    let renderers = ResizeArray<Comp * bool * string>() // (コンポーネント, Skinned, メッシュ資産)
    let skippedHidden = ResizeArray<string>()
    let skippedOther = ResizeArray<string>()
    for sid in order do
        for c in slots.[sid].Comps do
            if c.CType = "SkinnedMeshRenderer" || c.CType = "MeshRenderer" then
                let label = sprintf "%s (%s)" slots.[sid].SName c.CType
                let visible = fBool c.CData "Enabled" true && activeBelowRoot sid
                if not visible && not includeHidden then skippedHidden.Add label
                else
                    match fRef c.CData "Mesh" with
                    | None -> skippedOther.Add(label + ": メッシュ未設定")
                    | Some mid ->
                        match comps.TryGetValue mid with
                        | true, m when m.CType = "StaticMesh" ->
                            match assetSignature (fStr m.CData "URL") with
                            | Some sg when pkg.HasAsset sg -> renderers.Add((c, (c.CType = "SkinnedMeshRenderer"), sg))
                            | Some sg -> skippedOther.Add(sprintf "%s: メッシュ資産がパッケージに無い (%s)" label sg)
                            | None -> skippedOther.Add(sprintf "%s: メッシュ URL が読めない (%s)" label (fStr m.CData "URL"))
                        | true, m -> skippedOther.Add(sprintf "%s: %s は手続き型メッシュなので対象外" label m.CType)
                        | _ -> skippedOther.Add(label + ": メッシュの参照先が無い")

    // ヒューマノイド対応表
    let rig =
        order |> Seq.tryPick (fun sid -> slots.[sid].Comps |> Seq.tryFind (fun c -> c.CType = "BipedRig"))
    let rigBones =
        match rig with
        | Some r ->
            match fld r.CData "Bones" with
            | :? DataTreeDictionary as bd ->
                [ for kv in bd.Children do
                    let target =
                        match kv.Value with
                        | :? DataTreeDictionary as e -> (match valueOf (e.TryGetNode "Data") with null -> None | v -> Some (string v))
                        | n -> (match valueOf n with null -> None | v -> Some (string v))
                    match target with
                    | Some t when slots.ContainsKey t && isUnder t -> yield kv.Key, t
                    | _ -> () ]
            | _ -> []
        | None -> []

    // 残すスロット = 根 + レンダラー・ボーン・リグのスロットとその先祖
    let needed = HashSet<string>()
    let rec mark (sid: string) =
        if needed.Add sid && sid <> exportRoot then
            match slots.[sid].Parent with null -> () | p -> mark p
    mark exportRoot
    for (c, skinned, _) in renderers do
        mark c.CSlot
        if skinned then
            for b in listRefs (fld c.CData "Bones") do
                match b with
                | Some bsid when slots.ContainsKey bsid && isUnder bsid -> mark bsid
                | _ -> ()
    for (_, t) in rigBones do mark t

    let meshCache = Dictionary<string, MeshX>()
    let loadMesh (sg: string) =
        match meshCache.TryGetValue sg with
        | true, m -> m
        | _ ->
            let m = MeshX(new MemoryStream(readAsset sg))
            meshCache.[sg] <- m
            m

    // バインド姿勢: ボーンのスロットの大域行列を「レンダラーの大域行列 × inverse(BindPose)」にし、親から順に局所 TRS へ戻す
    // (行列はすべて Resonite 空間・行ベクトル規約。根は書き出すときと同じ扱い)
    let bindOverride = Dictionary<string, float32[] * float32[] * float32[]>()
    let mutable bindPoseConflicts = 0
    if bindPose then
        let localOf (s: Slot) =
            if s.SId = exportRoot && not keepRootTransform then trsMatrix [| 0.0f; 0.0f; 0.0f |] [| 0.0f; 0.0f; 0.0f; 1.0f |] s.Scl
            else trsMatrix s.Pos s.Rot s.Scl
        let savedGlobal = Dictionary<string, Numerics.Matrix4x4>()
        for sid in order do
            let s = slots.[sid]
            savedGlobal.[sid] <- if sid = exportRoot then localOf s else localOf s * savedGlobal.[s.Parent]
        let desired = Dictionary<string, Numerics.Matrix4x4>()
        for (c, skinned, sg) in renderers do
            if skinned then
                let mx = loadMesh sg
                let bones = listRefs (fld c.CData "Bones")
                for bi in 0 .. (min mx.BoneCount bones.Length) - 1 do
                    match bones.[bi] with
                    | Some b when b <> exportRoot && savedGlobal.ContainsKey b ->
                        match Numerics.Matrix4x4.Invert(toNumerics (mx.GetBone bi).BindPose) with
                        | true, inv ->
                            let target = inv * savedGlobal.[c.CSlot]
                            match desired.TryGetValue b with
                            | true, prev ->
                                // 共有ボーンでメッシュごとのバインド姿勢が食い違う (1 mm 超) ものは数える
                                if Numerics.Vector3.Distance(prev.Translation, target.Translation) > 0.001f then bindPoseConflicts <- bindPoseConflicts + 1
                            | _ -> desired.[b] <- target
                        | _ -> ()
                    | _ -> ()
        let newGlobal = Dictionary<string, Numerics.Matrix4x4>()
        for sid in order do
            let s = slots.[sid]
            if sid = exportRoot then newGlobal.[sid] <- localOf s
            else
                let parentGlobal = newGlobal.[s.Parent]
                match desired.TryGetValue sid with
                | true, gl ->
                    match Numerics.Matrix4x4.Invert parentGlobal with
                    | true, invParent ->
                        match Numerics.Matrix4x4.Decompose(gl * invParent) with
                        | true, sc, r, t ->
                            bindOverride.[sid] <- ([| t.X; t.Y; t.Z |], [| r.X; r.Y; r.Z; r.W |], [| sc.X; sc.Y; sc.Z |])
                            newGlobal.[sid] <- gl
                        | _ -> newGlobal.[sid] <- localOf s * parentGlobal
                    | _ -> newGlobal.[sid] <- localOf s * parentGlobal
                | _ -> newGlobal.[sid] <- localOf s * parentGlobal

    // ノード
    let g = GlbBuilder()
    let nodes = ResizeArray<JsonObject>()
    let children = ResizeArray<ResizeArray<int>>()
    let nodeOfSlot = Dictionary<string, int>()
    let newNode (name: string) =
        nodes.Add(jobj [ "name", js name ])
        children.Add(ResizeArray())
        nodes.Count - 1
    let setTRS (o: JsonObject) (t: float32[]) (r: float32[]) (s: float32[]) =
        if t |> Array.exists (fun v -> v <> 0.0f) then o.["translation"] <- jarr [ for v in t -> jf v ]
        if not (r.[0] = 0.0f && r.[1] = 0.0f && r.[2] = 0.0f && r.[3] = 1.0f) then o.["rotation"] <- jarr [ for v in r -> jf v ]
        if s |> Array.exists (fun v -> v <> 1.0f) then o.["scale"] <- jarr [ for v in s -> jf v ]
    let rec build (sid: string) : int =
        let s = slots.[sid]
        let idx = newNode s.SName
        nodeOfSlot.[sid] <- idx
        match bindOverride.TryGetValue sid with
        | true, (t, r, sc) -> setTRS nodes.[idx] (mirrorPos t) (mirrorRot r) sc
        | _ ->
            if sid = exportRoot && not keepRootTransform then setTRS nodes.[idx] [| 0.0f; 0.0f; 0.0f |] [| 0.0f; 0.0f; 0.0f; 1.0f |] s.Scl
            else setTRS nodes.[idx] (mirrorPos s.Pos) (mirrorRot s.Rot) s.Scl
        for c in s.Children do
            if needed.Contains c then children.[idx].Add(build c)
        idx
    let rootNode = build exportRoot
    let newChild (parent: int) (name: string) =
        let i = newNode name
        children.[parent].Add i
        i

    // テクスチャ・マテリアル
    let images = JsonArray()
    let samplers = JsonArray()
    let textures = JsonArray()
    let materials = JsonArray()
    let extensionsUsed = HashSet<string>()
    let samplerCache = Dictionary<string, int>()
    let textureCache = Dictionary<string, int option>()
    let materialCache = Dictionary<string, int option>()
    let slotName (c: Comp) = if isNull c.CSlot then c.CType else slots.[c.CSlot].SName
    let texture (tid: string) : int option =
        match textureCache.TryGetValue tid with
        | true, v -> v
        | _ ->
            let result =
                match comps.TryGetValue tid with
                | true, c when c.CType = "StaticTexture2D" ->
                    let url = fStr c.CData "URL"
                    match assetSignature url with
                    | Some sg when pkg.HasAsset sg ->
                        let bytes = readAsset sg
                        let image =
                            if isPng bytes then Some (bytes, "image/png")
                            elif isJpeg bytes then Some (bytes, "image/jpeg")
                            else
                                let ext = guessImageExt bytes (urlExtension url)
                                match convertToPng bytes ext with
                                | Some png -> Some (png, "image/png")
                                | None -> warn (sprintf "テクスチャ %s (%s) を PNG にできなかった" (slotName c) ext); None
                        match image with
                        | None -> None
                        | Some (data, mime) ->
                            let view = g.AddView(data, 0)
                            addTo images (jobj [ "name", js (slotName c); "bufferView", ji view; "mimeType", js mime ])
                            let wrap k =
                                match fStr c.CData k with
                                | "Clamp" -> 33071
                                | "Mirror" | "MirrorOnce" -> 33648
                                | _ -> 10497
                            let point = fStr c.CData "FilterMode" = "Point"
                            let mag, minf = if point then 9728, 9984 else 9729, 9987
                            let key = sprintf "%d/%d/%d/%d" mag minf (wrap "WrapModeU") (wrap "WrapModeV")
                            let sampler =
                                match samplerCache.TryGetValue key with
                                | true, i -> i
                                | _ ->
                                    addTo samplers (jobj [ "magFilter", ji mag; "minFilter", ji minf; "wrapS", ji (wrap "WrapModeU"); "wrapT", ji (wrap "WrapModeV") ])
                                    samplerCache.[key] <- samplers.Count - 1
                                    samplers.Count - 1
                            addTo textures (jobj [ "name", js (slotName c); "source", ji (images.Count - 1); "sampler", ji sampler ])
                            Some (textures.Count - 1)
                    | Some sg -> warn (sprintf "テクスチャ資産がパッケージに無い: %s (%s)" (slotName c) sg); None
                    | None -> warn (sprintf "テクスチャ URL が読めない: %s (%s)" (slotName c) url); None
                | true, c -> warn (sprintf "未対応のテクスチャ提供元: %s (%s)" (slotName c) c.CType); None
                | _ -> None
            textureCache.[tid] <- result
            result
    /// テクスチャ参照 → textureInfo (Scale/Offset は KHR_texture_transform。v 反転に合わせて offset_v = 1 - scale_v - offset_v)
    let textureInfo (d: DataTreeDictionary) (texKey: string) (uvKey: string) : JsonObject option =
        match fRef d texKey |> Option.bind texture with
        | None -> None
        | Some ti ->
            let o = jobj [ "index", ji ti ]
            if fNum d uvKey = Some 1.0f then o.["texCoord"] <- ji 1
            let pick keys dflt = keys |> List.tryPick (fun k -> let v = floats (fld d k) in if v.Length >= 2 then Some v else None) |> Option.defaultValue dflt
            let sc = pick [ texKey + "Scale"; "TextureScale" ] [| 1.0f; 1.0f |]
            let off = pick [ texKey + "Offset"; "TextureOffset" ] [| 0.0f; 0.0f |]
            if sc.[0] <> 1.0f || sc.[1] <> 1.0f || off.[0] <> 0.0f || off.[1] <> 0.0f then
                extensionsUsed.Add "KHR_texture_transform" |> ignore
                o.["extensions"] <- jobj [ "KHR_texture_transform",
                                           jobj [ "offset", jarr [ jf off.[0]; jf (1.0f - sc.[1] - off.[1]) ]
                                                  "scale", jarr [ jf sc.[0]; jf sc.[1] ] ] ]
            Some o
    let firstKey (d: DataTreeDictionary) (keys: string list) = keys |> List.tryFind (has d)
    let material (mid: string) : int option =
        match materialCache.TryGetValue mid with
        | true, v -> v
        | _ ->
            let result =
                match comps.TryGetValue mid with
                | true, c ->
                    let d = c.CData
                    // Resonite のインポーターが付ける "Material: " は外して元の名前に戻す
                    let name = slotName c
                    let m = jobj [ "name", js (if name.StartsWith "Material: " then name.Substring 10 else name) ]
                    let pbr = JsonObject()
                    match firstKey d [ "AlbedoColor"; "Color"; "TintColor"; "Tint"; "BaseColor" ] |> Option.bind (fun k -> linearColor (fld d k)) with
                    | Some col -> pbr.["baseColorFactor"] <- jarr [ for v in col -> jf (Math.Clamp(v, 0.0f, 1.0f)) ]
                    | None -> ()
                    match firstKey d [ "AlbedoTexture"; "MainTexture"; "Texture"; "BaseColorTexture" ] |> Option.bind (fun k -> textureInfo d k "AlbedoUV") with
                    | Some ti -> pbr.["baseColorTexture"] <- ti
                    | None -> ()
                    // 既定の metallicFactor は 1 なので必ず書く
                    let metallic = fNum d "Metallic" |> Option.defaultValue 0.0f
                    let smooth = firstKey d [ "Smoothness"; "Glossiness" ] |> Option.bind (fNum d) |> Option.defaultValue 0.0f
                    pbr.["metallicFactor"] <- jf (Math.Clamp(metallic, 0.0f, 1.0f))
                    pbr.["roughnessFactor"] <- jf (Math.Clamp(1.0f - smooth, 0.0f, 1.0f))
                    m.["pbrMetallicRoughness"] <- pbr
                    match textureInfo d "NormalMap" "NormalUV" with
                    | Some ti ->
                        match fNum d "NormalScale" with Some s when s <> 1.0f -> ti.["scale"] <- jf s | _ -> ()
                        m.["normalTexture"] <- ti
                    | None -> ()
                    match textureInfo d "OcclusionMap" "OcclusionUV" with
                    | Some ti -> m.["occlusionTexture"] <- ti
                    | None -> ()
                    let emissiveMap = firstKey d [ "EmissiveMap"; "EmissionMap" ] |> Option.bind (fun k -> textureInfo d k "EmissionUV")
                    match emissiveMap with Some ti -> m.["emissiveTexture"] <- ti | None -> ()
                    match firstKey d [ "EmissiveColor"; "EmissionColor" ] |> Option.bind (fun k -> linearColor (fld d k)) with
                    | Some col when col.[0] > 0.0f || col.[1] > 0.0f || col.[2] > 0.0f ->
                        let peak = max col.[0] (max col.[1] col.[2])
                        if peak > 1.0f then
                            m.["emissiveFactor"] <- jarr [ for i in 0 .. 2 -> jf (max 0.0f (col.[i] / peak)) ]
                            extensionsUsed.Add "KHR_materials_emissive_strength" |> ignore
                            m.["extensions"] <- jobj [ "KHR_materials_emissive_strength", jobj [ "emissiveStrength", jf peak ] ]
                        else m.["emissiveFactor"] <- jarr [ for i in 0 .. 2 -> jf (max 0.0f col.[i]) ]
                    | _ -> ()
                    match fStr d "BlendMode" with
                    | "Cutout" ->
                        m.["alphaMode"] <- js "MASK"
                        let cutoff = firstKey d [ "AlphaCutoff"; "AlphaClip" ] |> Option.bind (fNum d) |> Option.defaultValue 0.5f
                        if cutoff <> 0.5f then m.["alphaCutoff"] <- jf cutoff
                    | "Alpha" | "Transparent" | "Additive" | "Multiply" -> m.["alphaMode"] <- js "BLEND"
                    | _ -> ()
                    if fStr d "Culling" = "Off" || fStr d "Sidedness" = "Double" then m.["doubleSided"] <- jb true
                    if c.CType.Contains "Unlit" then
                        extensionsUsed.Add "KHR_materials_unlit" |> ignore
                        let ext = match m.["extensions"] with :? JsonObject as e -> e | _ -> (let e = JsonObject() in m.["extensions"] <- e; e)
                        ext.["KHR_materials_unlit"] <- JsonObject()
                    m.["extras"] <- jobj [ "resoniteType", js c.CType ]
                    addTo materials m
                    Some (materials.Count - 1)
                | _ -> None
            materialCache.[mid] <- result
            result

    // メッシュ
    let geoCache = Dictionary<string * bool, Geometry>()
    let multiFrameShapes = HashSet<string>()
    let geometry (sg: string) (mx: MeshX) (skinned: bool) : Geometry =
        match geoCache.TryGetValue((sg, skinned)) with
        | true, geo -> geo
        | _ ->
            let n = mx.VertexCount
            let rp = mx.RawPositions
            let pos = Array.zeroCreate<float32> (n * 3)
            for i in 0 .. n - 1 do
                pos.[3 * i] <- -rp.[i].x
                pos.[3 * i + 1] <- rp.[i].y
                pos.[3 * i + 2] <- rp.[i].z
            let posAcc = g.FloatAccessor(pos, 3, "VEC3", ARRAY_BUFFER, true)
            let nrmAcc =
                if mx.HasNormals then
                    let rn = mx.RawNormals
                    let a = Array.zeroCreate<float32> (n * 3)
                    for i in 0 .. n - 1 do
                        let x, y, z = -rn.[i].x, rn.[i].y, rn.[i].z
                        let l = sqrt (x * x + y * y + z * z)
                        if l > 1e-8f && Single.IsFinite l then
                            a.[3 * i] <- x / l
                            a.[3 * i + 1] <- y / l
                            a.[3 * i + 2] <- z / l
                        else a.[3 * i + 1] <- 1.0f
                    Some (g.FloatAccessor(a, 3, "VEC3", ARRAY_BUFFER, false))
                else None
            let uv (ch: int) =
                if ch >= mx.UV_ChannelCount then None else
                let a = Array.zeroCreate<float32> (n * 2)
                let ok =
                    try
                        match mx.GetUV_Dimension ch with
                        | 2 -> let u = mx.GetRawUVs ch in (for i in 0 .. n - 1 do a.[2 * i] <- u.[i].x; a.[2 * i + 1] <- 1.0f - u.[i].y); true
                        | 3 -> let u = mx.GetRawUVs_3D ch in (for i in 0 .. n - 1 do a.[2 * i] <- u.[i].x; a.[2 * i + 1] <- 1.0f - u.[i].y); true
                        | 4 -> let u = mx.GetRawUVs_4D ch in (for i in 0 .. n - 1 do a.[2 * i] <- u.[i].x; a.[2 * i + 1] <- 1.0f - u.[i].y); true
                        | _ -> false
                    with _ -> false
                if ok then Some (g.FloatAccessor(a, 2, "VEC2", ARRAY_BUFFER, false)) else None
            let uv0 = uv 0
            let uv1 = uv 1
            // スキン: 1 頂点 4 本まで。重複は合算、総和 1 に正規化。重みの無い頂点はレンダラー自身の剛体ジョイント (番号 = BoneCount) に付ける
            let boneCount = mx.BoneCount
            let jointsAcc, weightsAcc, rigid, unweighted =
                if skinned && boneCount > 0 && mx.HasBoneBindings then
                    let bb = mx.RawBoneBindings
                    let js16 = Array.zeroCreate<uint16> (n * 4)
                    let ws = Array.zeroCreate<float32> (n * 4)
                    let mutable unweighted = 0
                    let acc = Dictionary<int, float32>()
                    for i in 0 .. n - 1 do
                        let b = bb.[i]
                        acc.Clear()
                        for (j, w) in [ b.boneIndex0, b.weight0; b.boneIndex1, b.weight1; b.boneIndex2, b.weight2; b.boneIndex3, b.weight3 ] do
                            if j >= 0 && j < boneCount && w > 0.0f && Single.IsFinite w then
                                acc.[j] <- (match acc.TryGetValue j with | true, v -> v + w | _ -> w)
                        let total = acc.Values |> Seq.sum
                        if total <= 1e-6f then
                            unweighted <- unweighted + 1
                            js16.[4 * i] <- uint16 boneCount
                            ws.[4 * i] <- 1.0f
                        else
                            let mutable k = 0
                            for kv in acc |> Seq.sortByDescending (fun kv -> kv.Value) |> Seq.truncate 4 do
                                js16.[4 * i + k] <- uint16 kv.Key
                                ws.[4 * i + k] <- kv.Value / total
                                k <- k + 1
                    let jointsAcc =
                        if boneCount + 1 <= 256 then
                            let view = g.AddView(js16 |> Array.map byte, ARRAY_BUFFER)
                            g.AddAccessor(view, UNSIGNED_BYTE, n, "VEC4", None, false)
                        else
                            let view = g.AddView(toBytes js16, ARRAY_BUFFER)
                            g.AddAccessor(view, UNSIGNED_SHORT, n, "VEC4", None, false)
                    Some jointsAcc, Some (g.FloatAccessor(ws, 4, "VEC4", ARRAY_BUFFER, false)), unweighted > 0, unweighted
                else None, None, false, 0
            // 面: 三角形のサブメッシュだけ。X 反転に合わせて巻きを逆に
            let prims =
                [ for si in 0 .. mx.SubmeshCount - 1 do
                    let sm = mx.GetSubmesh si
                    if sm.Topology = SubmeshTopology.Triangles && sm.Count > 0 then
                        let raw = sm.RawIndicies
                        let tri = ResizeArray<uint32>(sm.Count * 3)
                        for t in 0 .. sm.Count - 1 do
                            let a, b, c = raw.[3 * t], raw.[3 * t + 1], raw.[3 * t + 2]
                            if a >= 0 && b >= 0 && c >= 0 && a < n && b < n && c < n then
                                tri.Add(uint32 a)
                                tri.Add(uint32 c)
                                tri.Add(uint32 b)
                        if tri.Count > 0 then
                            let acc =
                                if n < 65535 then
                                    let view = g.AddView(toBytes (tri.ToArray() |> Array.map uint16), ELEMENT_ARRAY_BUFFER)
                                    g.AddAccessor(view, UNSIGNED_SHORT, tri.Count, "SCALAR", None, false)
                                else
                                    let view = g.AddView(toBytes (tri.ToArray()), ELEMENT_ARRAY_BUFFER)
                                    g.AddAccessor(view, UNSIGNED_INT, tri.Count, "SCALAR", None, false)
                            yield si, acc
                    elif sm.Count > 0 then warn (sprintf "メッシュ %s のサブメッシュ %d は %A なので省いた" sg si sm.Topology) ]
            // ブレンドシェイプ: 重み最大のフレームを 1.0 相当に伸ばして 1 ターゲットにする
            let targets =
                if skinned && mx.BlendShapeCount > 0 then
                    [| for bi in 0 .. mx.BlendShapeCount - 1 do
                        let bs = mx.GetBlendShape bi
                        if bs.FrameCount > 1 then multiFrameShapes.Add bs.Name |> ignore
                        let frame = if bs.FrameCount = 0 then None else Some (bs.Frames |> Seq.maxBy (fun f -> f.Weight))
                        let scale = match frame with Some f when f.Weight > 1e-6f -> 1.0f / f.Weight | _ -> 1.0f
                        // epsilon 未満の差分は 0 にする (法線差分は全頂点に微小な揺れがあり、そのままだと疎にできない)
                        let deltas (raw: float3[]) (epsilon: float32) =
                            let a = Array.zeroCreate<float32> (n * 3)
                            if not (isNull raw) then
                                for i in 0 .. (min n raw.Length) - 1 do
                                    let d = raw.[i]
                                    if Single.IsFinite d.x && Single.IsFinite d.y && Single.IsFinite d.z
                                       && (epsilon = 0.0f || d.x * d.x + d.y * d.y + d.z * d.z >= epsilon * epsilon) then
                                        a.[3 * i] <- -d.x * scale
                                        a.[3 * i + 1] <- d.y * scale
                                        a.[3 * i + 2] <- d.z * scale
                            a
                        let posD = deltas (match frame with Some f -> f.RawPositions | None -> null) 0.0f
                        let posAcc = g.MorphAccessor(posD, true)
                        let nrmAcc =
                            match frame with
                            | Some f when morphNormals && bs.HasNormals && not (isNull f.RawNormals) -> Some (g.MorphAccessor(deltas f.RawNormals 1e-3f, false))
                            | _ -> None
                        yield (bs.Name, posAcc, nrmAcc) |]
                else [||]
            let geo =
                { Pos = posAcc; Nrm = nrmAcc; Uv0 = uv0; Uv1 = uv1; Joints = jointsAcc; Weights = weightsAcc
                  RigidJoint = rigid; Unweighted = unweighted; Prims = prims; Targets = targets; Colors = None }
            geoCache.[(sg, skinned)] <- geo
            geo
    let colorsOf (mx: MeshX) (geo: Geometry) =
        match geo.Colors with
        | Some c -> c
        | None ->
            let c =
                if mx.HasColors then
                    let n = mx.VertexCount
                    let rc = mx.RawColors
                    let srgb = mx.Profile <> ColorProfile.Linear
                    let a = Array.zeroCreate<float32> (n * 4)
                    for i in 0 .. n - 1 do
                        let conv v = let v = Math.Clamp(v, 0.0f, 1.0f) in if srgb then srgbToLinear v else v
                        a.[4 * i] <- conv rc.[i].r
                        a.[4 * i + 1] <- conv rc.[i].g
                        a.[4 * i + 2] <- conv rc.[i].b
                        a.[4 * i + 3] <- Math.Clamp(rc.[i].a, 0.0f, 1.0f)
                    Some (g.FloatAccessor(a, 4, "VEC4", ARRAY_BUFFER, false))
                else None
            geo.Colors <- Some c
            c

    let meshes = JsonArray()
    let skins = JsonArray()
    let mutable totalVerts = 0
    let mutable totalTris = 0
    let mutable totalShapes = 0
    let mutable missingBones = 0
    let mutable unweightedVerts = 0
    let rendererLines = ResizeArray<string>()
    for (c, skinned, sg) in renderers do
        let slot = slots.[c.CSlot]
        let mx = loadMesh sg
        let geo = geometry sg mx skinned
        if geo.Prims.IsEmpty then skippedOther.Add(sprintf "%s: 三角形が無い" slot.SName)
        else
            let baseNode = nodeOfSlot.[c.CSlot]
            let nodeIdx = if nodes.[baseNode].ContainsKey "mesh" then newChild baseNode (slot.SName + " (" + c.CType + ")") else baseNode
            let mats = listRefs (fld c.CData "Materials")
            let prims = JsonArray()
            for (si, idxAcc) in geo.Prims do
                let matComp = if si < mats.Length then mats.[si] else None
                let attrs = jobj [ "POSITION", ji geo.Pos ]
                geo.Nrm |> Option.iter (fun a -> attrs.["NORMAL"] <- ji a)
                geo.Uv0 |> Option.iter (fun a -> attrs.["TEXCOORD_0"] <- ji a)
                geo.Uv1 |> Option.iter (fun a -> attrs.["TEXCOORD_1"] <- ji a)
                geo.Joints |> Option.iter (fun a -> attrs.["JOINTS_0"] <- ji a)
                geo.Weights |> Option.iter (fun a -> attrs.["WEIGHTS_0"] <- ji a)
                // 頂点カラーは glTF では基本色に掛かるので、マテリアルが使うときだけ書く
                let usesVertexColors =
                    match matComp with
                    | Some mid -> (match comps.TryGetValue mid with | true, mc -> fBool mc.CData "UseVertexColors" false | _ -> false)
                    | None -> false
                if usesVertexColors then colorsOf mx geo |> Option.iter (fun a -> attrs.["COLOR_0"] <- ji a)
                let p = jobj [ "attributes", attrs; "indices", ji idxAcc ]
                matComp |> Option.bind material |> Option.iter (fun m -> p.["material"] <- ji m)
                if geo.Targets.Length > 0 then
                    p.["targets"] <- jarr [ for (_, pa, na) in geo.Targets ->
                                              let t = jobj [ "POSITION", ji pa ]
                                              na |> Option.iter (fun a -> t.["NORMAL"] <- ji a)
                                              t :> JsonNode ]
                addTo prims p
            let mesh = jobj [ "name", js slot.SName; "primitives", prims ]
            if geo.Targets.Length > 0 then
                let w = listFloats (fld c.CData "BlendShapeWeights")
                mesh.["weights"] <- jarr [ for i in 0 .. geo.Targets.Length - 1 -> jf (if i < w.Length then w.[i] else 0.0f) ]
                mesh.["extras"] <- jobj [ "targetNames", jarr [ for (name, _, _) in geo.Targets -> js name ] ]
            addTo meshes mesh
            nodes.[nodeIdx].["mesh"] <- ji (meshes.Count - 1)
            if not (fBool c.CData "Enabled" true && activeBelowRoot c.CSlot) then
                nodes.[nodeIdx].["extras"] <- jobj [ "resoniteHidden", jb true ]
            // スキン
            let mutable skinNote = ""
            if geo.Joints.IsSome then
                let bones = listRefs (fld c.CData "Bones")
                let used = HashSet<int>()
                let joints = ResizeArray<int>()
                let ibms = ResizeArray<float32>()
                let mutable missingHere = 0
                for bi in 0 .. mx.BoneCount - 1 do
                    let bone = mx.GetBone bi
                    let bp = bone.BindPose
                    let target =
                        match (if bi < bones.Length then bones.[bi] else None) with
                        | Some bsid when nodeOfSlot.ContainsKey bsid -> Some nodeOfSlot.[bsid]
                        | _ -> None
                    let joint =
                        match target with
                        | Some j when used.Add j -> j
                        | Some j -> let k = newChild j (bone.Name + " (dup)") in used.Add k |> ignore; k
                        | None ->
                            // 参照先の無いボーンはバインド時の位置にダミーを置く (レンダラーに対して inverse(BindPose))
                            missingHere <- missingHere + 1
                            let k = newChild nodeIdx (bone.Name + " (missing)")
                            let mutable p = float3.Zero
                            let mutable q = floatQ.Identity
                            let mutable s = float3.One
                            bp.Inverse.Decompose(&p, &q, &s)
                            setTRS nodes.[k] (mirrorPos [| p.x; p.y; p.z |]) (mirrorRot [| q.x; q.y; q.z; q.w |]) [| s.x; s.y; s.z |]
                            used.Add k |> ignore
                            k
                    joints.Add joint
                    ibms.AddRange(mirroredColumnMajor bp)
                if geo.RigidJoint then
                    let j = if used.Add nodeIdx then nodeIdx else newChild nodeIdx (slot.SName + " (rigid)")
                    joints.Add j
                    ibms.AddRange identityColumnMajor
                let ibmAcc = g.FloatAccessor(ibms.ToArray(), 16, "MAT4", 0, false)
                addTo skins (jobj [ "name", js slot.SName; "inverseBindMatrices", ji ibmAcc; "joints", jarr [ for j in joints -> ji j ] ])
                nodes.[nodeIdx].["skin"] <- ji (skins.Count - 1)
                missingBones <- missingBones + missingHere
                unweightedVerts <- unweightedVerts + geo.Unweighted
                skinNote <- sprintf " ボーン%d%s%s" mx.BoneCount (if missingHere > 0 then sprintf " (参照先無し%d)" missingHere else "")
                                (if geo.Unweighted > 0 then sprintf " 重み無し頂点%d" geo.Unweighted else "")
            let tris = geo.Prims |> List.sumBy (fun (_, a) -> (g.Accessors.[a].["count"].GetValue<int>()) / 3)
            totalVerts <- totalVerts + mx.VertexCount
            totalTris <- totalTris + tris
            totalShapes <- totalShapes + geo.Targets.Length
            rendererLines.Add(sprintf "  %s: 頂点%d 三角形%d サブメッシュ%d%s%s" slot.SName mx.VertexCount tris geo.Prims.Length skinNote
                                (if geo.Targets.Length > 0 then sprintf " シェイプ%d" geo.Targets.Length else ""))

    // 子の配列を確定
    for i in 0 .. nodes.Count - 1 do
        if children.[i].Count > 0 then nodes.[i].["children"] <- jarr [ for c in children.[i] -> ji c ]

    // 組み立て
    let gltf = JsonObject()
    gltf.["asset"] <- jobj [ "version", js "2.0"; "generator", js "resonitepackage-to-glb.fsx (Resonite package converter)" ]
    let humanoid = JsonObject()
    for (bodyNode, sid) in rigBones do
        match nodeOfSlot.TryGetValue sid with
        | true, ni -> humanoid.[bodyNode] <- jobj [ "node", ji ni; "name", js slots.[sid].SName ]
        | _ -> ()
    let scene = jobj [ "name", js slots.[exportRoot].SName; "nodes", jarr [ ji rootNode ] ]
    let sceneExtras = jobj [ "resoniteRecord", js record.Name ]
    if humanoid.Count > 0 then sceneExtras.["resoniteHumanoid"] <- humanoid
    scene.["extras"] <- sceneExtras
    gltf.["scene"] <- ji 0
    gltf.["scenes"] <- jarr [ scene ]
    let nodeArray = JsonArray()
    for n in nodes do addTo nodeArray n
    gltf.["nodes"] <- nodeArray
    let putIfAny (key: string) (a: JsonArray) = if a.Count > 0 then gltf.[key] <- a
    putIfAny "meshes" meshes
    putIfAny "skins" skins
    putIfAny "materials" materials
    putIfAny "textures" textures
    putIfAny "images" images
    putIfAny "samplers" samplers
    putIfAny "accessors" g.Accessors
    putIfAny "bufferViews" g.Views
    let bin = g.Bin.ToArray()
    if bin.Length > 0 then gltf.["buffers"] <- jarr [ jobj [ "byteLength", ji bin.Length ] ]
    if extensionsUsed.Count > 0 then gltf.["extensionsUsed"] <- jarr [ for e in extensionsUsed -> js e ]
    writeGlb outputPath gltf bin

    // 報告
    printfn "入力: %s" inputPath
    printfn "レコード: %s" record.Name
    printfn "根: %s (%s)" slots.[exportRoot].SName rootReason
    printfn "姿勢: %s" (if bindPose then sprintf "バインド姿勢 (ボーン %d 本を置き直した)" bindOverride.Count else "保存時の姿勢 (--saved-pose)")
    if bindPoseConflicts > 0 then printfn "注意: メッシュ間でバインド姿勢が食い違うボーン参照 %d 件 (最初のメッシュに合わせた)" bindPoseConflicts
    printfn "レンダラー: %d 個を書き出し" rendererLines.Count
    for l in rendererLines do printfn "%s" l
    printfn "合計: 頂点%d 三角形%d シェイプキー%d ノード%d マテリアル%d テクスチャ%d" totalVerts totalTris totalShapes nodes.Count materials.Count textures.Count
    if skippedHidden.Count > 0 then
        printfn "非表示なので省いた (--include-hidden で含める): %d 個" skippedHidden.Count
        for s in skippedHidden do printfn "  %s" s
        if rendererLines.Count = 0 then printfn "注意: 見えているレンダラーが 1 つも無い (根より下に非アクティブなスロットがある)。--include-hidden を付けて再実行する"
    if skippedOther.Count > 0 then
        printfn "書き出せなかったレンダラー: %d 個" skippedOther.Count
        for s in skippedOther do printfn "  %s" s
    if missingBones > 0 then printfn "注意: 参照先の無いボーン %d 本はバインド位置のダミーにした" missingBones
    if unweightedVerts > 0 then printfn "注意: 重みの無い頂点 %d 個はレンダラーに固定した" unweightedVerts
    if multiFrameShapes.Count > 0 then printfn "注意: 複数フレームのブレンドシェイプ %d 個は最大フレームだけにした" multiFrameShapes.Count
    for w in warnings |> Seq.distinct do printfn "注意: %s" w
    printfn "出力: %s (%.1f MB)" outputPath (float (FileInfo(outputPath).Length) / 1048576.0)

try
    convert ()
with
| ConvertError msg ->
    eprintfn "変換に失敗: %s" msg
    exit 1
| e ->
    eprintfn "変換に失敗: %s" (e.ToString())
    exit 1
