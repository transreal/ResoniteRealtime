open System
open System.IO
open System.Reflection
open System.Runtime.Loader
open System.Text.RegularExpressions
let dir = @"C:\Program Files (x86)\Steam\steamapps\common\Resonite"
let alc = new AssemblyLoadContext("reso", true)
alc.add_Resolving(fun ctx name ->
    let p = Path.Combine(dir, name.Name + ".dll")
    if File.Exists p then ctx.LoadFromAssemblyPath p else null)
let asm = alc.LoadFromAssemblyPath(Path.Combine(dir, "FrooxEngine.dll"))
let pat = Regex(fsi.CommandLineArgs.[1])
let types =
    try asm.GetTypes() with :? ReflectionTypeLoadException as e -> e.Types |> Array.filter (fun t -> not (isNull t))
for t in types do
    if pat.IsMatch(t.FullName) && not t.IsAbstract then
        let fields =
            t.GetFields(BindingFlags.Public ||| BindingFlags.Instance ||| BindingFlags.FlattenHierarchy)
            |> Array.filter (fun f -> f.FieldType.Name.Contains "Sync" || f.FieldType.Name.Contains "Ref")
            |> Array.map (fun f -> sprintf "%s:%s" f.Name (f.FieldType.Name.Replace("`1","")))
        printfn "%s  [%s]" t.FullName (String.Join(", ", fields))
