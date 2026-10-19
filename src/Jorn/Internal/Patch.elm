module Jorn.Internal.Patch exposing (Patch(..), Path, diff, encode, encodePatch)

{-| The diff runs identically on the server and in the browser, which is the
point: one rendering path, one protocol, one client patcher.

Ordering guarantee: patches are emitted so that applying them strictly in
order is always valid. Child patches only touch indices below
`min oldLength newLength`, and an element's `append` or `truncate` comes after
every patch aimed at its existing children.

Keyed children are the exception to that order: their `remove`, `move` and
`insert` patches come first, each index valid at the moment it's applied, and
the patches for the children themselves follow, at their final positions.

-}

import Array exposing (Array)
import Dict exposing (Dict)
import Jorn.Internal.Vdom as Vdom exposing (Element(..), EventOptions, Node)
import Json.Encode as Encode exposing (Value)
import Set exposing (Set)


{-| Child indices from the root. The root itself is `[]`.
-}
type alias Path =
    List Int


type Patch
    = Replace Path Node
    | SetText Path String
    | SetHtml Path String
    | SetAttribute Path String String
    | RemoveAttribute Path String
    | SetProperty Path String Value
    | RemoveProperty Path String
    | SetEvent Path String EventOptions
    | RemoveEvent Path String
    | Append Path (List Node)
    | Truncate Path Int
    | Insert Path Int Node
    | Move Path Int Int
    | Remove Path Int


diff : Element msg -> Element msg -> List Patch
diff old new =
    List.reverse (diffHelp [] (Vdom.root old) (Vdom.root new) [])


{-| `reversedPath` and the accumulator are both built backwards for cheap
consing; each is reversed exactly once. Neither tree is a fragment here: the
root has been resolved and children are flattened before they're compared.
-}
diffHelp : List Int -> Element msg -> Element msg -> List Patch -> List Patch
diffHelp reversedPath old new acc =
    case ( old, new ) of
        ( Text a, Text b ) ->
            if a == b then
                acc

            else
                SetText (List.reverse reversedPath) b :: acc

        ( Element oldNs oldTag _ oldAttrs oldKids, Element newNs newTag _ newAttrs newKids ) ->
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
                    |> diffList reversedPath (Vdom.flatten oldKids) (Vdom.flatten newKids)

            else
                Replace (List.reverse reversedPath) (Vdom.toNode new) :: acc

        ( Raw oldNs oldTag oldAttrs oldHtml, Raw newNs newTag newAttrs newHtml ) ->
            if oldNs == newNs && oldTag == newTag then
                let
                    path =
                        List.reverse reversedPath

                    withFacts =
                        diffFacts path (Vdom.facts oldAttrs) (Vdom.facts newAttrs) acc
                in
                if oldHtml == newHtml then
                    withFacts

                else
                    SetHtml path newHtml :: withFacts

            else
                Replace (List.reverse reversedPath) (Vdom.toNode new) :: acc

        _ ->
            Replace (List.reverse reversedPath) (Vdom.toNode new) :: acc


diffList : List Int -> List (Element msg) -> List (Element msg) -> List Patch -> List Patch
diffList reversedPath olds news acc =
    if List.any isKeyed olds || List.any isKeyed news then
        diffKeyed reversedPath olds news acc

    else
        diffChildren reversedPath 0 olds news acc


isKeyed : Element msg -> Bool
isKeyed html =
    case html of
        Keyed _ _ ->
            True

        _ ->
            False


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



-- KEYED CHILDREN


{-| Match children by key instead of by position, and move DOM nodes rather
than rewrite them.

Three passes. First, remove the children whose key is gone, last first so
each index is still valid when it's used. Then put the rest in order, working
from the end of the new list: a child that is new is inserted before the one
that follows it, and a child that has moved is moved there. The children that
form the longest run already in the right relative order never move, which
keeps the moves to a minimum. Finally, diff each surviving child against its
old self, at its final position.

-}
diffKeyed : List Int -> List (Element msg) -> List (Element msg) -> List Patch -> List Patch
diffKeyed reversedPath olds news acc =
    let
        path =
            List.reverse reversedPath

        oldPairs =
            Vdom.keys olds

        newPairs =
            Vdom.keys news

        newKeys =
            Set.fromList (List.map Tuple.first newPairs)

        oldByKey =
            Dict.fromList oldPairs

        removed =
            oldPairs
                |> List.indexedMap (\index ( key, _ ) -> ( index, key ))
                |> List.filter (\( _, key ) -> not (Set.member key newKeys))
                |> List.map Tuple.first

        kept =
            List.filter (\key -> Set.member key newKeys) (List.map Tuple.first oldPairs)

        keptPosition =
            Dict.fromList (List.indexedMap (\index key -> ( key, index )) kept)

        stable =
            newPairs
                |> List.filterMap (\( key, _ ) -> Dict.get key keptPosition |> Maybe.map (Tuple.pair key))
                |> longestIncreasing

        afterRemovals =
            List.foldr (\index a -> Remove path index :: a) acc removed

        ( afterMoves, _, _ ) =
            List.foldr (place path oldByKey stable) ( afterRemovals, kept, Nothing ) newPairs
    in
    newPairs
        |> List.indexedMap Tuple.pair
        |> List.foldl
            (\( index, ( key, new ) ) a ->
                case Dict.get key oldByKey of
                    Just old ->
                        diffHelp (index :: reversedPath) old new a

                    Nothing ->
                        a
            )
            afterMoves


{-| Put one child in place, directly before the child that follows it in the
new list (`anchor`), which is already placed. `current` is the order of keys
on screen as the patches so far leave it.
-}
place :
    Path
    -> Dict String (Element msg)
    -> Set String
    -> ( String, Element msg )
    -> ( List Patch, List String, Maybe String )
    -> ( List Patch, List String, Maybe String )
place path oldByKey stable ( key, new ) ( acc, current, anchor ) =
    if not (Dict.member key oldByKey) then
        let
            index =
                anchorIndex anchor current
        in
        ( Insert path index (Vdom.toNode new) :: acc, insertAt index key current, Just key )

    else if Set.member key stable then
        ( acc, current, Just key )

    else
        let
            from =
                indexOf key current

            without =
                removeAt from current

            to =
                anchorIndex anchor without
        in
        if from == to then
            ( acc, current, Just key )

        else
            ( Move path from to :: acc, insertAt to key without, Just key )


anchorIndex : Maybe String -> List String -> Int
anchorIndex anchor current =
    case anchor of
        Just key ->
            indexOf key current

        Nothing ->
            List.length current


indexOf : String -> List String -> Int
indexOf key items =
    indexOfHelp key 0 items


indexOfHelp : String -> Int -> List String -> Int
indexOfHelp key index items =
    case items of
        [] ->
            index

        item :: rest ->
            if item == key then
                index

            else
                indexOfHelp key (index + 1) rest


insertAt : Int -> a -> List a -> List a
insertAt index item items =
    List.take index items ++ item :: List.drop index items


removeAt : Int -> List a -> List a
removeAt index items =
    List.take index items ++ List.drop (index + 1) items


{-| The keys of a longest strictly increasing run of values, in O(n log n).
`tails` holds, for each run length, the index of the item ending the best run
of that length found so far, and `previous` links each item to the one before
it in its run.
-}
longestIncreasing : List ( String, Int ) -> Set String
longestIncreasing pairs =
    let
        items =
            Array.fromList pairs

        valueAt index =
            Array.get index items |> Maybe.map Tuple.second |> Maybe.withDefault 0

        step index ( _, value ) ( tails, previous ) =
            let
                length =
                    firstNotBelow valueAt value tails 0 (Array.length tails)

                before =
                    if length == 0 then
                        -1

                    else
                        Array.get (length - 1) tails |> Maybe.withDefault -1
            in
            ( if length == Array.length tails then
                Array.push index tails

              else
                Array.set length index tails
            , Array.push before previous
            )

        ( finalTails, links ) =
            Array.foldl (\pair ( acc, index ) -> ( step index pair acc, index + 1 )) ( ( Array.empty, Array.empty ), 0 ) items
                |> Tuple.first
    in
    case Array.get (Array.length finalTails - 1) finalTails of
        Nothing ->
            Set.empty

        Just last ->
            collectRun items links last Set.empty


firstNotBelow : (Int -> Int) -> Int -> Array Int -> Int -> Int -> Int
firstNotBelow valueAt value tails low high =
    if low >= high then
        low

    else
        let
            middle =
                (low + high) // 2
        in
        if valueAt (Array.get middle tails |> Maybe.withDefault 0) < value then
            firstNotBelow valueAt value tails (middle + 1) high

        else
            firstNotBelow valueAt value tails low middle


collectRun : Array ( String, Int ) -> Array Int -> Int -> Set String -> Set String
collectRun items links index acc =
    case Array.get index items of
        Nothing ->
            acc

        Just ( key, _ ) ->
            collectRun items links (Array.get index links |> Maybe.withDefault -1) (Set.insert key acc)


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

        SetHtml path content ->
            op "set-html" path [ ( "html", Encode.string content ) ]

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

        Insert path index node ->
            op "insert" path [ ( "index", Encode.int index ), ( "node", Vdom.encodeNode node ) ]

        Move path from to ->
            op "move" path [ ( "from", Encode.int from ), ( "to", Encode.int to ) ]

        Remove path index ->
            op "remove" path [ ( "index", Encode.int index ) ]


op : String -> Path -> List ( String, Value ) -> Value
op name path fields =
    Encode.object (( "op", Encode.string name ) :: ( "path", Encode.list Encode.int path ) :: fields)
