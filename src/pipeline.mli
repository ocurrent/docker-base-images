
module Windows_map : sig
  type key = Dockerfile_opam.Distro.t
  type 'a t = 'a Map.Make(Dockerfile_opam.Distro).t
  val empty : 'a t
end

module Make (OCurrent : S.OCURRENT) : sig
  open OCurrent

  val v : ocluster:OCluster.t -> repos:(Git_repositories.t Current.t) -> windows_version:(string Current.t Windows_map.t) -> unit Current.t
end

val v : ?channel:Current_slack.channel -> ocluster:Current_ocluster.t -> unit -> unit Current.t
(** The main pipeline. Builds images for all supported distribution, compiler version and architecture combinations. *)
