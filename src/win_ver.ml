open Lwt.Infix
open Current.Syntax

let ( >>!= ) = Lwt_result.bind

module Products = struct
  type t = {
    ocluster : Current_ocluster.t;
  }

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
      Cluster_api.Job.log build_job start >>= function
      | Error (`Capnp e) -> Lwt.return @@ Fmt.error_msg "%a" Capnp_rpc.Error.pp e
      | Ok ("", _) -> Lwt_result.return ()
      | Ok (data, next) ->
        Buffer.add_string buffer data;
        Current.Job.write job data;
        aux next
    in aux 0L

  let run_job ~buffer ~job build_job =
    let on_cancel _ =
      Cluster_api.Job.cancel build_job >|= function
      | Ok () -> ()
      | Error (`Capnp e) -> Current.Job.log job "Cancel failed: %a" Capnp_rpc.Error.pp e
    in
    Current.Job.with_handler job ~on_cancel @@ fun () ->
    let result = Cluster_api.Job.result build_job in
    tail ~buffer ~job build_job >>!= fun () ->
    result >>= function
    | Error (`Capnp e) -> Lwt_result.fail (`Msg (Fmt.to_to_string Capnp_rpc.Error.pp e))
    | Ok _ as x -> Lwt.return x

  let parse_output job build_job =
    let buffer = Buffer.create 1024 in
    Capnp_rpc_lwt.Capability.with_ref build_job (run_job ~buffer ~job) >>!= fun (_ : string) ->
      match Astring.String.cuts ~sep:"\r\nOuTPuT\r\n" (Buffer.contents buffer) with
      | [_; output; _] -> Lwt_result.return output
      | [_; rest ] when Astring.String.is_prefix ~affix:"OuTPuT\r\n" rest -> Lwt_result.return ""
      | _ -> Lwt_result.fail (`Msg "Missing output from command\n\n")

  let build { ocluster } job {Key.product; pool} =
    let spec_str = Printf.sprintf "FROM %s\nRUN for /f \"tokens=4 delims=[] \" %%a in ('ver') do echo %.0f& echo OuTPuT& echo %%a& echo OuTPuT" product (Unix.time ()) in
    let action = Cluster_api.Submission.docker_build (`Contents spec_str) in
    let pool = Current_ocluster.Connection.pool ~job ~pool ~action ~cache_hint:product (Current_ocluster.connection ocluster) in
    Current.Job.start_with ~pool job ~level:Current.Level.Mostly_harmless >>=
    parse_output job

  let pp f _ = Fmt.string f "Windows version"

  let auto_cancel = true
end

module Cache = Current_cache.Make(Products)

let get ~schedule ocluster ( product, pool ) =
  Current.component "Windows Version" |>
  let> key = Current.return { Products.Key.product = product; pool } in
  Cache.get ~schedule { Products.ocluster } key

