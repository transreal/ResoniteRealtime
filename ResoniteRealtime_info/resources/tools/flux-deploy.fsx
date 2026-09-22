// flux-deploy.fsx -- Flux SDK の ResoniteLink 連携で ProtoGraph モジュールを 1 回だけデプロイする
// (実験的。公式ドキュメント "ResoniteLink Getting Started" のホットリロード例を単発に組み替えたもの。
//  Flux SDK の API は beta で変わり得る。動かないときはまず .brson の手動インポートを使う。)
//
// 使い方: dotnet fsi flux-deploy.fsx <projectDir> <Main/Module> <resoniteLinkPort> [parentSlotName]
// 前提: flux-sdk (Papaltine.FluxSDK 1.9.x) でビルドできるプロジェクト、Resonite で ResoniteLink 有効 (ホスト)。

#r "nuget: FParsec-Pipes, 1.1.2.0"
#r "nuget: FSharp.Data.Json.Core, 6.6.0.0"
#r "nuget: YellowDogMan.ResoniteLink, 0.13.1"
#r "nuget: Papaltine.ResoniteLink.RPath, 0.6.0"
#r "nuget: Papaltine.FluxSDK.Core, 1.9.0"

open System
open System.IO
open FluxSDK.Build.Incremental
open FluxSDK.Common
open FluxSDK.Incremental.StepCE
open FluxSDK.Incremental.Store
open FluxSDK.ResoniteLink
open FluxSDK.ResoniteLink.Workflow
open ResoniteLink
open ResoniteLink.RPath
open FluxSDK.ResoniteLink.StepExtensions

let args = fsi.CommandLineArgs |> Array.skip 1
if args.Length < 3 then
    eprintfn "usage: dotnet fsi flux-deploy.fsx <projectDir> <Main/Module> <port> [parentSlotName]"
    exit 2

let projectDir = Path.GetFullPath args.[0]
let modulePath = args.[1]
let port = int args.[2]
let parentName = if args.Length > 3 then args.[3] else "Flux"

let store = Build.initializeStore ()
// 127.0.0.1 は http.sys が 400 で弾くので localhost を使う
let link = Link.initialize (Uri (sprintf "ws://localhost:%d/" port))

let ensureParentExists (name: string) : Step<Slot> =
    step {
        let! existing = Query.root |> Query.child (fun slot -> slot.Name.Value = name) false |> Query.first
        match existing |> Seq.tryHead with
        | Some parent -> return parent
        | None ->
            let parentId = Reso.newID ()
            let! created =
                Reso.slot (ID = parentId, Name = name, Position = float3 (y = 1.5f)) [] []
                |> Slot.addUnder Slot.ROOT_SLOT_ID
            if not created.Success then failwith (sprintf "Failed to create parent slot '%s': %A" name created.ErrorInfo)
            let! found = Query.findSlotByID parentId |> Query.first
            match found |> Seq.tryHead with
            | Some parent -> return parent
            | None -> return failwith (sprintf "Created parent slot '%s' was not found." name)
    }

let manifest = Build.loadManifest projectDir
let config = Build.defaultConfig manifest
let target = Loader.DeployTarget.Bare (ensureParentExists parentName)

// 単発: ホットリロードのイベントハンドラ 1 回分だけを走らせる。
// runUntilExit は watch ループなので、初回ロードだけを Trigger にして即終了させたいが、
// 公開 API に単発実行が無い場合はこの部分を Flux SDK の版に合わせて直す。
let onEvent (_: TriggerEvent[]) : Step<unit> =
    step {
        match! Loader.replace config modulePath target with
        | Ok childId -> printfn "DEPLOYED %s (slot %s)" modulePath childId
        | Error message -> eprintfn "ERROR %s" message
        exit 0
    }

let workflowConfig =
    { WorkflowConfig.Default onEvent with
        Triggers = [| Custom (initialLoadKey, initialLoadObservable) |] }

runUntilExit store link workflowConfig
