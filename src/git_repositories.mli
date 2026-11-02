type t = {
  opam_repository_master : Current_git.Commit_id.t;
  opam : (Dockerfile_opam.Opam_version.t * Current_git.Commit_id.t) list;
      (** One commit per opam version, in the order of
          [Dockerfile_opam.Opam_version.all]. Releases resolve to the head of
          their branch; [`Dev] resolves to the newest tagged release. *)
}

val get : schedule:Current_cache.Schedule.t -> t Current.t
