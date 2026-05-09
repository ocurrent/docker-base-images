open Current.Syntax

module Cluster_api = Current_ocluster.Cluster_api

let ( let* ) = Result.bind

module Products = struct
  type t = Current_ocluster.Connection.t

  let id = "win-version"

  module Key = struct
    type t = {
      product : string;
      pool : string;
    }

    let digest { product; pool } =
      let json = `Assoc [
        "product", `String product;
        "pool", `String pool;
      ] in
      Yojson.Safe.to_string json
  end

  module Value = Current.String

  let tail ~buffer ~job build_job =
    let rec aux start =
      match Cluster_api.Job.log build_job start with
      | Error (`Capnp e) -> Fmt.error_msg "%a" Capnp_rpc.Error.pp e
      | Ok ("", _) -> Ok ()
      | Ok (data, next) ->
        Buffer.add_string buffer data;
        Current.Job.write job data;
        aux next
    in aux 0L

  let run_job ~buffer ~job build_job =
    let on_cancel _ =
      match Cluster_api.Job.cancel build_job with
      | Ok () -> ()
      | Error (`Capnp e) -> Current.Job.log job "Cancel failed: %a" Capnp_rpc.Error.pp e
    in
    Current.Job.with_handler job ~on_cancel @@ fun () ->
    match tail ~buffer ~job build_job with
    | Error _ as e -> e
    | Ok () ->
      match Cluster_api.Job.result build_job with
      | Error (`Capnp e) -> Error (`Msg (Fmt.to_to_string Capnp_rpc.Error.pp e))
      | Ok _ as x -> x

  let parse_output job build_job =
    let buffer = Buffer.create 1024 in
    let* (_ : string) = Capnp_rpc.Std.Capability.with_ref build_job (run_job ~buffer ~job) in
    let normalized = String.concat "" (String.split_on_char '\r' (Buffer.contents buffer)) in
    match Astring.String.cuts ~sep:"\nOuTPuT\n" normalized with
    | [_; output; _] -> Ok output
    | [_; rest ] when Astring.String.is_prefix ~affix:"OuTPuT\n" rest -> Ok ""
    | _ -> Error (`Msg "Missing output from command\n\n")

  let build connection job {Key.product; pool} =
    let spec_str = Printf.sprintf "FROM %s\nRUN powershell -NoProfile -Command \"'%.0f' | Out-Null; $k = Get-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion'; 'OuTPuT'; '{0}.{1}.{2}.{3}' -f $k.CurrentMajorVersionNumber, $k.CurrentMinorVersionNumber, $k.CurrentBuildNumber, $k.UBR; 'OuTPuT'\"" product (Unix.time ()) in
    let action = Cluster_api.Submission.docker_build (`Contents spec_str) in
    let pool = Current_ocluster.Connection.pool ~job ~pool ~action ~cache_hint:product connection in
    let build_job = Current.Job.start_with ~pool job ~level:Current.Level.Mostly_harmless in
    parse_output job build_job

  let pp f _ = Fmt.string f "Windows version"

  let auto_cancel = true
end

module Cache = Current_cache.Make(Products)

let get ~caps ~schedule connection product pool =
  let cache = Cache.create ~caps in
  Current.component "%s" product |>
  let> key = Current.return { Products.Key.product = product; pool } in
  Cache.get cache ~schedule connection key
