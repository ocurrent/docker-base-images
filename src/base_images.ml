open Capnp_rpc_lwt
open Lwt.Infix

let program_name = "base_images"

module Rpc = Current_rpc.Impl(Current)

let setup_log style_renderer default_level =
  Prometheus_unix.Logging.init ?default_level ();
  Fmt_tty.setup_std_outputs ?style_renderer ();
  Prometheus.CollectorRegistry.(register_pre_collect default) Metrics.update;
  Metrics.init_last_build_time ()

(* A low-security Docker Hub user used to push images to the staging area.
   Low-security because we never rely on the tags in this repository, just the hashes. *)
let staging_user = "ocurrentbuilder"

let read_first_line path =
  let ch = open_in path in
  Fun.protect (fun () -> input_line ch)
    ~finally:(fun () -> close_in ch)

let read_channel_uri path =
  try
    let uri = read_first_line path in
    Current_slack.channel (Uri.of_string (String.trim uri))
  with ex ->
    Fmt.failwith "Failed to read slack URI from %S: %a" path Fmt.exn ex

let run_capnp = function
  | None -> Lwt.return (Capnp_rpc_unix.client_only_vat (), None)
  | Some public_address ->
    let config =
      Capnp_rpc_unix.Vat_config.create
        ~public_address
        ~secret_key:(`File Conf.Capnp.secret_key)
        (Capnp_rpc_unix.Network.Location.tcp ~host:"0.0.0.0" ~port:Conf.Capnp.internal_port)
    in
    let rpc_engine, rpc_engine_resolver = Capability.promise () in
    let service_id = Capnp_rpc_unix.Vat_config.derived_id config "engine" in
    let restore = Capnp_rpc_net.Restorer.single service_id rpc_engine in
    Capnp_rpc_unix.serve config ~restore >>= fun vat ->
    let uri = Capnp_rpc_unix.Vat.sturdy_uri vat service_id in
    let ch = open_out Conf.Capnp.cap_file in
    output_string ch (Uri.to_string uri ^ "\n");
    close_out ch;
    Logs.app (fun f -> f "Wrote capability reference to %S" Conf.Capnp.cap_file);
    Lwt.return (vat, Some rpc_engine_resolver)

(* Access control policy. *)
let has_role user = function
  | `Viewer | `Monitor -> true
  | _ ->
    match Option.map Current_web.User.id user with
    | Some ( "github:talex5"
           | "github:avsm"
           | "github:kit-ty-kate"
           | "github:samoht"
           | "github:dra27"
           | "github:mtelvers"
           | "github:tmcgilchrist"
           | "github:MisterDA"
           | "github:moyodiallo"
           | "github:shonfeder"
           | "github:punchagan"
           | "github:DTE003"
           ) -> true
    | _ -> false

let main () config mode channel capnp_address github_auth submission_uri staging_password_file prometheus_config =
  Lwt_main.run begin
    let channel = Option.map read_channel_uri channel in
    let staging_auth = staging_password_file |> Option.map (fun path -> staging_user, read_first_line path) in
    run_capnp capnp_address >>= fun (vat, rpc_engine_resolver) ->
    let submission_cap = Capnp_rpc_unix.Vat.import_exn vat submission_uri in
    let connection = Current_ocluster.Connection.create submission_cap in
    let ocluster = Current_ocluster.v ?push_auth:staging_auth ~urgent:`Never connection in
    let engine = Current.Engine.create ~config (Pipeline.v ?channel ~ocluster) in
    rpc_engine_resolver |> Option.iter (fun r -> Capability.resolve_ok r (Rpc.engine engine));
    let authn = Option.map Current_github.Auth.make_login_uri github_auth in
    let has_role =
      if github_auth = None then Current_web.Site.allow_all
      else has_role
    in
    let secure_cookies = channel <> None in        (* TODO: find a better way to detect production use *)
    let routes =
      Routes.(s "login" /? nil @--> Current_github.Auth.login github_auth) ::
      Current_web.routes engine in
    let site = Current_web.Site.v ?authn ~secure_cookies ~has_role ~name:program_name ~refresh_pipeline:60 routes in
    let prometheus = List.map (Lwt.map Result.ok) (Prometheus_unix.serve prometheus_config) in
    Lwt.choose ([
      Current.Engine.thread engine;
      Current_web.run ~mode site;
    ] @ prometheus)
  end

(* Command-line parsing *)

open Cmdliner

let slack =
  Arg.value @@
  Arg.opt Arg.(some file) None @@
  Arg.info
    ~doc:"A file containing the URI of the endpoint for status updates"
    ~docv:"URI-FILE"
    ["slack"]

let parse_tcp s =
  let open Astring in
  match String.cut ~sep:":" s with
  | None -> Error (`Msg "Missing :PORT in listen address")
  | Some (host, port) ->
    match String.to_int port with
    | None -> Error (`Msg "PORT must be an integer")
    | Some port ->
      Ok (Capnp_rpc_unix.Network.Location.tcp ~host ~port)

let capnp_address =
  let conv = Arg.conv (parse_tcp, Capnp_rpc_unix.Network.Location.pp) in
  Arg.value @@
  Arg.opt (Arg.some conv) None @@
  Arg.info
    ~doc:"Public address (HOST:PORT) for Cap'n Proto RPC (default: no RPC)"
    ~docv:"ADDR"
    ["capnp-address"]

let submission_service =
  Arg.required @@
  Arg.opt Arg.(some Capnp_rpc_unix.sturdy_uri) None @@
  Arg.info
    ~doc:"The submission.cap file for the build scheduler service"
    ~docv:"FILE"
    ["submission-service"]

let staging_password =
  Arg.value @@
  Arg.opt Arg.(some file) None @@
  Arg.info
    ~doc:(Printf.sprintf "A file containing the password for the %S Docker Hub user" staging_user)
    ~docv:"FILE"
    ["staging-password-file"]

let setup_log =
  let docs = Manpage.s_common_options in
  Term.(const setup_log $ Fmt_cli.style_renderer ~docs () $ Logs_cli.level ~docs ())

let cmd =
  let doc = "Build the ocaml/opam images for Docker Hub" in
  let info = Cmd.info program_name ~doc in 
  Cmd.v info
    Term.(
      term_result (
        const main
        $ setup_log
        $ Current.Config.cmdliner
        $ Current_web.cmdliner
        $ slack
        $ capnp_address
        $ Current_github.Auth.cmdliner
        $ submission_service
        $ staging_password
        $ Prometheus_unix.opts))

let () =
  match Sys.argv with
  | [| _; "--dump" |] -> Dump.run ()
  | _ -> exit @@ Cmd.eval cmd
