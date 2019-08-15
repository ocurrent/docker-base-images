let () = Logging.init ()

let read_channel_uri path =
  try
    let ch = open_in path in
    let uri = input_line ch in
    close_in ch;
    Current_slack.channel (Uri.of_string (String.trim uri))
  with ex ->
    Fmt.failwith "Failed to read slack URI from %S: %a" path Fmt.exn ex

let main config mode channel =
  let channel = Option.map read_channel_uri channel in
  let engine = Current.Engine.create ~config (Pipeline.v ?channel) in
  Logging.run begin
    Lwt.choose [
      Current.Engine.thread engine;
      Current_web.run ~mode engine;
    ]
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

let cmd =
  let doc = "Build the ocaml/opam images for Docker Hub" in
  Term.(const main $ Current.Config.cmdliner $ Current_web.cmdliner $ slack),
  Term.info "docker_build_local" ~doc

let () = Term.(exit @@ eval cmd)
