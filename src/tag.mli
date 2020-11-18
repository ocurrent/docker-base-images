val v : ?latest_distro:bool -> ?arch:Ocaml_version.arch -> ?switch:Ocaml_version.t -> Dockerfile_distro.t -> string
(** [v ?latest_distro ?arch ?switch distro] is the Docker tag to use for an image built on [distro] and [arch]
    with OCaml compiler [switch] installed. If [switch] is [None] then this is a base image
    with no switches. If [arch] is set then this is a staging image, which will later be combined
    into a cross-platform image. If [latest_distro] is true (default: false) then the distro
    version will not be included in the tag (e.g. [alpine-ocaml-4.10]).  *)

val v_alias : Dockerfile_distro.t -> string
(** [v_alias ?switch distro] is a short tag for [distro], without the OCaml version (e.g. [alpine-3.12]).
    If [latest] is [true] (default: [false]) then the distro version will not be included (e.g. [alpine]). *)

val latest : string
(** [latest] is the single ":latest" tag. *)
