module Platform_map : (Map.S with type key = string)

module Switch_map : (Map.S with type key = Ocaml_version.t)

type state = Ok | Failed | Active

(** Each platform builds one non-OCaml opam image, and then an image for every version of OCaml.
    For [p : platforms], [fst p] is the state for the image of each switch for each platform,
    and [snd p] is the state for the non-OCaml image for each platform. *)
type t = state Switch_map.t Platform_map.t * state Platform_map.t

val get_images_per_platform : unit -> t

val update_images_per_platform : platform:string -> switch:Ocaml_version.t option -> state -> unit

val get_latest_build_time : unit -> float option
