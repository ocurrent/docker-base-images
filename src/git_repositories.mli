type t = {
  opam_repository_master : Current_git.Commit_id.t;
  opam_2_0 : Current_git.Commit_id.t;
  opam_master : Current_git.Commit_id.t;
}

val get : schedule:Current_cache.Schedule.t -> t Current.t
