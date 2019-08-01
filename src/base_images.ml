let () = Logging.init ()

let main config mode =
  let engine = Current.Engine.create ~config Pipeline.v in
  Logging.run begin
    Lwt.choose [
      Current.Engine.thread engine;
      Current_web.run ~mode engine;
    ]
  end

(* Command-line parsing *)

open Cmdliner

let cmd =
  let doc = "Build the ocaml/opam images for Docker Hub" in
  Term.(const main $ Current.Config.cmdliner $ Current_web.cmdliner),
  Term.info "docker_build_local" ~doc

let () = Term.(exit @@ eval cmd)
