open Lwt.Infix
open Current.Syntax

module Products = struct
  type t = No_context

  let id = "win-version"

  module Key = struct
    type t = {
      product : string;
    }

    let digest { product } =
      let json = `Assoc [
        "product", `String product;
      ] in
      Yojson.Safe.to_string json
  end

  module Value = Current.String

  let build No_context job {Key.product} =
    Metrics.set_last_build_time_now ();
    Current.Job.start job ~level:Current.Level.Mostly_harmless >>= fun () ->
            let _ = product in
    Lwt.return (Ok "foo bar")

  let pp f _ = Fmt.string f "Windows version"

  let auto_cancel = true
end

module Cache = Current_cache.Make(Products)

let get ~schedule =
  let product = "windows server" in
  Current.component "Windows Version" |>
  let> key = Current.return { Products.Key.product = product } in
  Cache.get ~schedule Products.No_context key

