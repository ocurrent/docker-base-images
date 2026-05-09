
module Windows_map : sig
  type key = Dockerfile_opam.Distro.t
  type 'a t = 'a Map.Make(Dockerfile_opam.Distro).t
  val empty : 'a t
  val add : key -> 'a -> 'a t -> 'a t
end

module Make (OCurrent : S.OCURRENT) : sig
  open OCurrent

  val v : ocluster:OCluster.t -> repos:(Git_repositories.t Current.t) -> windows_version:(string Current.t Windows_map.t) -> unit Current.t
end

val v
  : ?slack:Current_slack.t
  -> ?channel:Current_slack.channel
  -> caps:Current_cache.caps
  -> connection:Current_ocluster.Connection.t
  -> staging_auth:(string * string) option
  -> unit
  -> unit Current.t
(** The main pipeline. Builds images for all supported distribution, compiler version and architecture combinations. *)
