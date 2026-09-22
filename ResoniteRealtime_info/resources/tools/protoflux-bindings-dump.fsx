// ProtoFluxBindings.dll だけにあるノード (ValueInput<T> 等、FrooxEngine 文脈専用) を論理ノード風に出す
open System
open System.IO
open System.Reflection
open System.Runtime.Loader
open System.Text.RegularExpressions
let dir = @"C:\Program Files (x86)\Steam\steamapps\common\Resonite"
let alc = new AssemblyLoadContext("reso2", true)
alc.add_Resolving(fun ctx name ->
    let p = Path.Combine(dir, name.Name + ".dll")
    if File.Exists p then ctx.LoadFromAssemblyPath p else null)
let load n = alc.LoadFromAssemblyPath(Path.Combine(dir, n))
let fe = load "FrooxEngine.dll"
let binds = load "ProtoFluxBindings.dll"
let nodeBase = fe.GetType("FrooxEngine.ProtoFlux.ProtoFluxNode")
let safeTypes (a: Assembly) = try a.GetTypes() with :? ReflectionTypeLoadException as e -> e.Types |> Array.filter (fun t -> not (isNull t))
let rec tn (t: Type) : string =
    if t.IsGenericType then
        let n = (if t.Name.IndexOf(char 96) >= 0 then t.Name.Substring(0, t.Name.IndexOf(char 96)) else t.Name)
        n + "<" + String.Join(",", t.GetGenericArguments() |> Array.map tn) + ">"
    elif t.IsGenericParameter then t.Name else t.Name
let mapField (ft: string) =
    let m1 = Regex.Match(ft, "^SyncRef<INodeValueOutput<(.*)>>$")
    let m2 = Regex.Match(ft, "^SyncRef<INodeObjectOutput<(.*)>>$")
    let m3 = Regex.Match(ft, "^SyncRef<IGlobalValueProxy<(.*)>>$")
    let m4 = Regex.Match(ft, "^NodeValueOutput<(.*)>$")
    let m5 = Regex.Match(ft, "^NodeObjectOutput<(.*)>$")
    if m1.Success then Some ("ValueInput<" + m1.Groups.[1].Value + ">")
    elif m2.Success then Some ("ObjectInput<" + m2.Groups.[1].Value + ">")
    elif m3.Success then Some ("GlobalRef<" + m3.Groups.[1].Value + ">")
    elif m4.Success then Some ("ValueOutput<" + m4.Groups.[1].Value + ">")
    elif m5.Success then Some ("ObjectOutput<" + m5.Groups.[1].Value + ">")
    elif ft.StartsWith "SyncRef<INodeOperation>" || ft.StartsWith "SyncRef<ISyncNodeOperation>" || ft.StartsWith "SyncRef<IAsyncNodeOperation>" then Some "Continuation"
    elif ft = "SyncNodeOperation" || ft = "AsyncNodeOperation" || ft = "AsyncResumption" then Some "Call"
    else None
let esc (s: string) = s.Replace("\\", "\\\\").Replace("\"", "\\\"")
let attrStr (t: Type) (attrName: string) =
    t.GetCustomAttributes(true)
    |> Array.tryPick (fun a ->
        if a.GetType().Name = attrName then
            let p = a.GetType().GetProperties() |> Array.tryFind (fun p -> p.PropertyType = typeof<string>)
            match p with Some p -> Some (string (p.GetValue a)) | None -> None
        else None)
let out = ResizeArray<string>()
for t in safeTypes binds do
    if not t.IsAbstract && t.IsPublic && not (isNull t.Namespace) && nodeBase.IsAssignableFrom t then
        let ns = if t.Namespace.StartsWith "FrooxEngine." then t.Namespace.Substring 12 else t.Namespace
        let fields = t.GetFields(BindingFlags.Public ||| BindingFlags.Instance ||| BindingFlags.FlattenHierarchy)
                     |> Array.choose (fun f -> match mapField (tn f.FieldType) with Some m -> Some (f.Name, m) | None -> None)
        let cat = defaultArg (attrStr t "NodeCategoryAttribute") ""
        let nm = defaultArg (attrStr t "NodeNameAttribute") ""
        let fs = fields |> Array.map (fun (n, ty) -> sprintf "{\"name\":\"%s\",\"type\":\"%s\"}" (esc n) (esc ty))
        out.Add(sprintf "{\"type\":\"%s\",\"namespace\":\"%s\",\"name\":\"%s\",\"category\":\"%s\",\"base\":\"%s\",\"fields\":[%s]}"
                    (esc (tn t)) (esc ns) (esc nm) (esc cat) (esc (tn t.BaseType)) (String.Join(",", fs)))
File.WriteAllText(fsi.CommandLineArgs.[1], "[" + String.Join(",\n", out) + "]")
printfn "wrote %d binding nodes" out.Count
