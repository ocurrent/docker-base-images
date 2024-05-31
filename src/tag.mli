val tag_of_compiler : Ocaml_version.t -> string
(** [tag_of_compiler switch] returns a tag identifying the compiler by
    its version and variants. *)

val v : ?arch:Ocaml_version.arch -> ?switch:Ocaml_version.t -> Dockerfile_opam.Distro.t -> string
(** [v ?arch ?switch distro] is the Docker tag to use for an image built on [distro] and [arch]
    with OCaml compiler [switch] installed. If [switch] is [None] then this is a base image
    with no switches. If [arch] is set then this is a staging image, which will later be combined
    into a cross-platform image. *)

val base : ?arch:Ocaml_version.arch -> Dockerfile_opam.Distro.t -> string
(** [base ?arch distro] is the Docker tag to use for a base image for [distro] and [arch]. *)

val v_alias : Dockerfile_opam.Distro.t -> string
(** [v_alias distro] is a short tag for [distro], without the OCaml version. *)

val latest : string
(** [latest] is the single ":latest" tag. *)

val archive : ?staging:bool -> unit -> string
(** [latest] is the single ":archive" tag of the opam package archives.
    If [staging] is true (default: false) the tag points to the image in
    the staging repository. *)
