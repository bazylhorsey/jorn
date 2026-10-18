module Jorn.Internal.Patch exposing (Patch(..), Path, diff, encode, encodePatch)

{-| The diff runs identically on the server and in the browser, which is the
point: one rendering path, one protocol, one client patcher.

Ordering guarantee: patches are emitted so that applying them strictly in
order is always valid. Child patches only touch indices below
`min oldLength newLength`, and an element's `append` or `truncate` comes after
every patch aimed at its existing children.

-}

import Dict exposing (Dict)
import Jorn.Internal.Vdom as Vdom exposing (Element(..), EventOptions, Node)
import Json.Encode as Encode exposing (Value)


{-| Child indices from the root. The root itself is `[]`.
-}
type alias Path =
    List Int


type Patch
    = Replace Path Node
    | SetText Path String
    | SetAttribute Path String String
    | RemoveAttribute Path String
    | SetProperty Path String Value
    | RemoveProperty Path String
    | SetEvent Path String EventOptions
    | RemoveEvent Path String
    | Append Path (List Node)
    | Truncate Path Int


diff : Element msg -> Element msg -> List Patch
diff old new =
    List.reverse (diffHelp [] old new [])


{-| `reversedPath` and the accumulator are both built backwards for cheap
consing; each is reversed exactly once.
-}
diffHelp : List Int -> Element msg -> Element msg -> List Patch -> List Patch
diffHelp reversedPath old new acc =
    case ( old, new ) of
        ( Text a, Text b ) ->
            if a == b then
                acc

            else
                SetText (List.reverse reversedPath) b :: acc

        ( Element oldNs oldTag oldAttrs oldKids, Element newNs newTag newAttrs newKids ) ->
            if oldNs == newNs && oldTag == newTag then
                (case ( oldAttrs, newAttrs ) of
                    -- Fast path: most elements have no attributes, and building
                    -- and merging three empty dictionaries per element was the
                    -- dominant cost of the diff.
                    ( [], [] ) ->
                        acc

                    _ ->
                        diffFacts (List.reverse reversedPath) (Vdom.facts oldAttrs) (Vdom.facts newAttrs) acc
                )
                    |> diffChildren reversedPath 0 oldKids newKids

            else
                Replace (List.reverse reversedPath) (Vdom.toNode new) :: acc

        _ ->
            Replace (List.reverse reversedPath) (Vdom.toNode new) :: acc


diffChildren : List Int -> Int -> List (Element msg) -> List (Element msg) -> List Patch -> List Patch
diffChildren reversedPath index olds news acc =
    case ( olds, news ) of
        ( o :: os, n :: ns ) ->
            diffChildren reversedPath (index + 1) os ns (diffHelp (index :: reversedPath) o n acc)

        ( [], [] ) ->
            acc

        ( [], _ ) ->
            Append (List.reverse reversedPath) (List.map Vdom.toNode news) :: acc

        ( _, [] ) ->
            Truncate (List.reverse reversedPath) index :: acc


diffFacts : Path -> Vdom.Facts msg -> Vdom.Facts msg -> List Patch -> List Patch
diffFacts path old new acc =
    acc
        |> diffDict (==)
            (SetAttribute path)
            (RemoveAttribute path)
            old.attrs
            new.attrs
        |> diffDict sameValue
            (SetProperty path)
            (RemoveProperty path)
            old.props
            new.props
        -- Only the options are compared. Decoders can't be compared and don't
        -- need to be: they never leave Elm, and routing always uses the
        -- current tree's decoder.
        |> diffDict (\( a, _ ) ( b, _ ) -> a == b)
            (\name ( options, _ ) -> SetEvent path name options)
            (RemoveEvent path)
            old.events
            new.events


diffDict : (v -> v -> Bool) -> (String -> v -> Patch) -> (String -> Patch) -> Dict String v -> Dict String v -> List Patch -> List Patch
diffDict same set remove old new acc =
    Dict.merge
        (\key _ a -> remove key :: a)
        (\key o n a ->
            if same o n then
                a

            else
                set key n :: a
        )
        (\key n a -> set key n :: a)
        old
        new
        acc


{-| `(==)` on JSON values is unreliable in Elm, so compare canonical encodings.
-}
sameValue : Value -> Value -> Bool
sameValue a b =
    Encode.encode 0 a == Encode.encode 0 b



-- WIRE FORMAT


encode : List Patch -> Value
encode patches =
    Encode.list encodePatch patches


encodePatch : Patch -> Value
encodePatch patch =
    case patch of
        Replace path node ->
            op "replace" path [ ( "node", Vdom.encodeNode node ) ]

        SetText path content ->
            op "set-text" path [ ( "text", Encode.string content ) ]

        SetAttribute path name value ->
            op "set-attr" path [ ( "name", Encode.string name ), ( "value", Encode.string value ) ]

        RemoveAttribute path name ->
            op "remove-attr" path [ ( "name", Encode.string name ) ]

        SetProperty path name value ->
            op "set-prop" path [ ( "name", Encode.string name ), ( "value", value ) ]

        RemoveProperty path name ->
            op "remove-prop" path [ ( "name", Encode.string name ) ]

        SetEvent path name options ->
            op "set-event" path [ ( "name", Encode.string name ), ( "options", Vdom.encodeOptions options ) ]

        RemoveEvent path name ->
            op "remove-event" path [ ( "name", Encode.string name ) ]

        Append path nodes ->
            op "append" path [ ( "nodes", Encode.list Vdom.encodeNode nodes ) ]

        Truncate path length ->
            op "truncate" path [ ( "length", Encode.int length ) ]


op : String -> Path -> List ( String, Value ) -> Value
op name path fields =
    Encode.object (( "op", Encode.string name ) :: ( "path", Encode.list Encode.int path ) :: fields)
