(*
 * Copyright (c) 2019-2020 Craig Ferguson <me@craigfe.io>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

open Ppxlib

module Make (T : sig
  val namespace : string

  val default_library : string
end) =
struct
  module Attributes = Attributes.Make (T)

  let with_engine f ~loc ~path:_ =
    let (module S) = Ast_builder.make loc in
    f (module Engine.Located (Attributes) (S) : Engine.S)

  let deriving_args () =
    Deriving.Args.(empty +> arg "name" (estring __) +> arg "lib" __)

  let library =
    lazy
      (let library = ref (Some T.default_library) in
       let doc =
         Format.sprintf
           "<module-path> Set the module path containing the combinators to \
            use (defaults to %s). An empty string is interpreted as the \
            current module."
           T.default_library
       in
       Ppxlib.Driver.add_arg "--lib"
         (Arg.String (function "" -> library := None | s -> library := Some s))
         ~doc;
       library)

  let register_deriver () =
    let library = Lazy.force library in
    let str_type_decl =
      let attributes = Attributes.all in
      Deriving.Generator.make ~attributes (deriving_args ())
        ( with_engine @@ fun (module L) input_ast name lib ->
          let lib =
            match lib with Some s -> L.parse_lib s | None -> !library
          in
          L.derive_str ?name ?lib input_ast )
    in
    let sig_type_decl =
      Deriving.Generator.make (deriving_args ())
        ( with_engine @@ fun (module L) input_ast name lib ->
          let lib =
            match lib with Some s -> L.parse_lib s | None -> !library
          in
          L.derive_sig ?name ?lib input_ast )
    in
    Deriving.add ~str_type_decl ~sig_type_decl T.namespace |> Deriving.ignore

  let register_extension () =
    let library = Lazy.force library in
    let extension =
      Extension.declare (T.namespace ^ ".typ") Extension.Context.expression
        Ast_pattern.(ptyp __)
        (with_engine @@ fun (module L) -> L.expand_typ ?lib:!library)
    in
    Reserved_namespaces.reserve T.namespace;
    Driver.register_transformation ~extensions:[ extension ] T.namespace
end
