val v : ?arch:Ocaml_version.arch -> ?switch:Ocaml_version.t -> Dockerfile_distro.t -> string
(** [v ?arch ?switch distro] is the Docker tag to use for an image built on [distro] and [arch]
    with OCaml compiler [switch] installed. If [switch] is [None] then this is a base image
    with no switches. If [arch] is set then this is a staging image, which will later be combined
    into a cross-platform image. *)

val v_alias : Dockerfile_distro.t -> string
(** [v_alias distro] is a short tag for [distro], without the OCaml version. *)

val latest : string
(** [latest] is the single ":latest" tag. *)
