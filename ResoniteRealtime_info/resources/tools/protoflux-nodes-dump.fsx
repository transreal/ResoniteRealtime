open System
open System.IO
open System.Reflection
open System.Runtime.Loader
let dir = @"C:\Program Files (x86)\Steam\steamapps\common\Resonite"
let alc = new AssemblyLoadContext("reso", true)
alc.add_Resolving(fun ctx name ->
    let p = Path.Combine(dir, name.Name + ".dll")
    if File.Exists p then ctx.LoadFromAssemblyPath p else null)
let load n = alc.LoadFromAssemblyPath(Path.Combine(dir, n))
let core = load "ProtoFlux.Core.dll"
let asms = [ core; load "ProtoFlux.Nodes.Core.dll"; load "ProtoFlux.Nodes.FrooxEngine.dll"; load "FrooxEngine.dll" ]
let nodeBase = core.GetType("ProtoFlux.Core.Node")
let safeTypes (a: Assembly) = try a.GetTypes() with :? ReflectionTypeLoadException as e -> e.Types |> Array.filter (fun t -> not (isNull t))
let rec tn (t: Type) : string =
    if t.IsGenericType then
        let n = (if t.Name.IndexOf(char 96) >= 0 then t.Name.Substring(0, t.Name.IndexOf(char 96)) else t.Name)
        n + "<" + String.Join(",", t.GetGenericArguments() |> Array.map tn) + ">"
    elif t.IsGenericParameter then t.Name
    else t.Name
let attrStr (t: Type) (attrName: string) =
    t.GetCustomAttributes(true)
    |> Array.tryPick (fun a ->
        if a.GetType().Name = attrName then
            let p = a.GetType().GetProperties() |> Array.tryFind (fun p -> p.PropertyType = typeof<string>)
            match p with Some p -> Some (string (p.GetValue a)) | None -> None
        else None)
let mode = fsi.CommandLineArgs.[1]
let filter = if mode = "show" && fsi.CommandLineArgs.Length > 2 then fsi.CommandLineArgs.[2] else ""
let esc (s: string) = s.Replace("\\", "\\\\").Replace("\"", "\\\"")
let out = ResizeArray<string>()
let mutable count = 0
for a in asms do
    for t in safeTypes a do
        if not t.IsAbstract && nodeBase.IsAssignableFrom t && t.IsPublic && (isNull t.Namespace |> not) && t.Namespace.Contains "ProtoFlux" then
            if filter = "" || t.FullName.Contains filter then
                count <- count + 1
                let fields =
                    t.GetFields(BindingFlags.Public ||| BindingFlags.Instance)
                    |> Array.map (fun f -> f.Name, tn f.FieldType)
                let cat = defaultArg (attrStr t "NodeCategoryAttribute") ""
                let nm  = defaultArg (attrStr t "NodeNameAttribute") ""
                if mode = "show" then
                    printfn "%s  [%s] name=%s cat=%s" (tn t) t.Namespace nm cat
                    for (n, ty) in fields do printfn "    %s : %s" n ty
                else
                    let fs = fields |> Array.map (fun (n, ty) -> sprintf "{\"name\":\"%s\",\"type\":\"%s\"}" (esc n) (esc ty))
                    out.Add(sprintf "{\"type\":\"%s\",\"namespace\":\"%s\",\"name\":\"%s\",\"category\":\"%s\",\"base\":\"%s\",\"fields\":[%s]}"
                                (esc (tn t)) (esc t.Namespace) (esc nm) (esc cat) (esc (tn t.BaseType)) (String.Join(",", fs)))
if mode <> "show" then
    File.WriteAllText(fsi.CommandLineArgs.[2], "[" + String.Join(",\n", out) + "]")
    printfn "wrote %d nodes" count
else printfn "%d nodes" count
