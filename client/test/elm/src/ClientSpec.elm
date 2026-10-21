port module ClientSpec exposing (main)

{-| Generates random view sequences A -> B -> C for client/test/run.mjs, and
routes the events the patcher reports back through `Jorn.Event`.

The generators use small alphabets so that consecutive views collide often and
exercise every diff branch.

-}

import Dict exposing (Dict)
import Jorn.Attribute as Attr
import Jorn.Element
import Jorn.Event as Events
import Jorn.Internal.Event as Routing
import Jorn.Internal.Patch
import Jorn.Internal.Vdom as Vdom exposing (Element(..))
import Jorn.Patch
import Json.Decode as Decode
import Json.Encode as Encode exposing (Value)
import Random exposing (Generator)


port generate : ({ seed : Int, count : Int } -> msg) -> Sub msg


port route : ({ caseId : Int, message : Value } -> msg) -> Sub msg


port out : Value -> Cmd msg


type Msg
    = Generate { seed : Int, count : Int }
    | Route { caseId : Int, message : Value }


type alias Model =
    Dict Int (Vdom.Element String)


main : Program () Model Msg
main =
    Platform.worker
        { init = \_ -> ( Dict.empty, Cmd.none )
        , update = update
        , subscriptions = \_ -> Sub.batch [ generate Generate, route Route ]
        }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Generate { seed, count } ->
            let
                ( triples, _ ) =
                    Random.step (Random.list count triple) (Random.initialSeed seed)

                labelled =
                    List.map (\( a, b, c ) -> ( label a, label b, label c )) triples
            in
            ( labelled |> List.indexedMap (\i ( _, _, c ) -> ( i, c )) |> Dict.fromList
            , out
                (Encode.list
                    (\( a, b, c ) ->
                        let
                            -- As the runtime does: B as the diff from A
                            -- kept it, with its memos built, diffs to C.
                            ( ab, keptB ) =
                                Jorn.Internal.Patch.diffKeeping a b
                        in
                        Encode.object
                            [ ( "a", Jorn.Patch.encodeHtml a )
                            , ( "b", Jorn.Patch.encodeHtml b )
                            , ( "c", Jorn.Patch.encodeHtml c )
                            , ( "html", Encode.list (Encode.string << Jorn.Element.toString) [ a, b, c ] )
                            , ( "ab", Jorn.Patch.encode ab )
                            , ( "bc", Jorn.Patch.encode (Jorn.Patch.diff keptB c) )
                            , ( "keepAB", encodeSurvivors (survivors a b) )
                            , ( "keepBC", encodeSurvivors (survivors keptB c) )
                            ]
                    )
                    labelled
                )
            )

        Route { caseId, message } ->
            let
                result =
                    case ( Dict.get caseId model, Decode.decodeValue Routing.decoder message ) of
                        ( Just view, Ok incoming ) ->
                            case Routing.route incoming view of
                                Ok id ->
                                    "ok:" ++ id

                                Err error ->
                                    "err:" ++ Routing.errorToString error

                        ( Nothing, _ ) ->
                            "err:unknown case"

                        ( _, Err error ) ->
                            "err:" ++ Decode.errorToString error
            in
            ( model, out (Encode.string result) )



-- GENERATION


triple : Generator ( Vdom.Element (), Vdom.Element (), Vdom.Element () )
triple =
    Random.uniform unrelated [ evolving ]
        |> Random.andThen identity


unrelated : Generator ( Vdom.Element (), Vdom.Element (), Vdom.Element () )
unrelated =
    Random.map3 (\a b c -> ( a, b, c )) (tree 4) (tree 4) (tree 4)


evolving : Generator ( Vdom.Element (), Vdom.Element (), Vdom.Element () )
evolving =
    tree 6
        |> Random.andThen
            (\a ->
                mutate a
                    |> Random.andThen (\b -> Random.map (\c -> ( a, b, c )) (mutate b))
            )


{-| A small random edit: most nodes survive untouched.
-}
mutate : Vdom.Element () -> Generator (Vdom.Element ())
mutate html =
    case html of
        Text _ ->
            Random.weighted ( 9, Random.constant html ) [ ( 1, tree 0 ), ( 0.3, tree 2 ) ]
                |> Random.andThen identity

        Fragment kids ->
            Random.map Fragment (mutateChildren "" kids)

        Keyed key kid ->
            Random.map (Keyed key) (mutate kid)

        Memo _ view ->
            Random.map memoOf (mutate (view ()))

        Raw ns tag attrs content ->
            Random.weighted ( 6, Random.constant html )
                [ ( 1, Random.map (Raw ns tag attrs) rawHtml )
                , ( 1, Random.int 0 2 |> Random.andThen (\n -> Random.list n attribute) |> Random.map (\new -> Raw ns tag (dedupe new) content) )
                , ( 0.5, tree 2 )
                ]
                |> Random.andThen identity

        Element ns tag closing attrs kids ->
            Random.weighted ( 40, Random.constant Nothing ) [ ( 1, Random.map Just (tree 2) ) ]
                |> Random.andThen identity
                |> Random.andThen
                    (\replacement ->
                        case replacement of
                            Just other ->
                                Random.constant other

                            Nothing ->
                                Random.map2 (Element ns tag closing)
                                    (Random.weighted ( 12, Random.constant attrs ) [ ( 1, Random.int 0 3 |> Random.andThen (\n -> Random.list n attribute) |> Random.map dedupe ) ]
                                        |> Random.andThen identity
                                    )
                                    (mutateChildren tag kids)
                    )


mutateChildren : String -> List (Vdom.Element ()) -> Generator (List (Vdom.Element ()))
mutateChildren tag kids =
    if tag == "input" then
        Random.constant []

    else if List.any isKeyed kids then
        mutateKeyed kids

    else
        Random.map3
            (\mutated extra dropLast ->
                let
                    kept =
                        if dropLast then
                            List.take (List.length mutated - 1) mutated

                        else
                            mutated
                in
                kept ++ extra
            )
            (traverse mutate kids)
            (Random.weighted ( 12, Random.constant [] ) [ ( 1, Random.map List.singleton (tree 2) ) ] |> Random.andThen identity)
            (Random.weighted ( 12, False ) [ ( 1, True ) ])


{-| What keyed lists go through: items edited in place, then sometimes
shuffled, thinned out, or given new items anywhere.
-}
mutateKeyed : List (Vdom.Element ()) -> Generator (List (Vdom.Element ()))
mutateKeyed kids =
    traverse mutate kids
        |> Random.andThen (\mutated -> Random.weighted ( 1, shuffle mutated ) [ ( 1, Random.constant mutated ) ] |> Random.andThen identity)
        |> Random.andThen (\items -> Random.list (List.length items) (Random.weighted ( 5, True ) [ ( 1, False ) ]) |> Random.map (keepWhere items))
        |> Random.andThen
            (\items ->
                Random.int 0 2
                    |> Random.andThen (\n -> Random.list n (Random.pair (Random.int 0 (List.length items)) (keyedChild 2)))
                    |> Random.map (List.foldl (\( at, item ) acc -> List.take at acc ++ item :: List.drop at acc) items)
            )


shuffle : List a -> Generator (List a)
shuffle items =
    Random.list (List.length items) (Random.float 0 1)
        |> Random.map (\weights -> List.map2 Tuple.pair weights items |> List.sortBy Tuple.first |> List.map Tuple.second)


keepWhere : List a -> List Bool -> List a
keepWhere items keeps =
    List.map2 Tuple.pair keeps items
        |> List.filterMap
            (\( keep, item ) ->
                if keep then
                    Just item

                else
                    Nothing
            )


isKeyed : Vdom.Element msg -> Bool
isKeyed html =
    case html of
        Keyed _ _ ->
            True

        _ ->
            False


traverse : (a -> Generator b) -> List a -> Generator (List b)
traverse f items =
    List.foldr (\item acc -> Random.map2 (::) (f item) acc) (Random.constant []) items


{-| Small alphabets so that A, B and C collide often, which is what exercises
the interesting diff branches.
-}
tree : Int -> Generator (Vdom.Element ())
tree depth =
    let
        text =
            Random.map Text (Random.uniform "" [ "a", "b", "<&\u{00A0}>" ])
    in
    if depth <= 0 then
        text

    else
        Random.weighted ( 1, text ) [ ( 3, element depth ), ( 1, fragment depth ), ( 1, keyedList depth ), ( 0.5, raw ), ( 0.5, memo depth ) ]
            |> Random.andThen identity


{-| Keys from a small alphabet, so they repeat and consecutive lists overlap.
A few children go unkeyed, and some keyed children sit inside fragments.
-}
keyedList : Int -> Generator (Vdom.Element ())
keyedList depth =
    Random.map2 (Element "" "ul" Vdom.Normal)
        (Random.int 0 2 |> Random.andThen (\n -> Random.list n attribute) |> Random.map dedupe)
        (Random.int 0 6 |> Random.andThen (\n -> Random.list n (keyedChild (depth - 1))))


keyedChild : Int -> Generator (Vdom.Element ())
keyedChild depth =
    Random.weighted ( 8, Random.map2 Keyed (Random.uniform "a" [ "b", "c", "d", "e", "f" ]) (tree depth) )
        [ ( 1, tree depth )
        , ( 1, Random.map2 (\k kid -> Fragment [ Keyed k kid ]) (Random.uniform "g" [ "h" ]) (tree depth) )
        ]
        |> Random.andThen identity


{-| Fragments nest, and can be empty: `none` is the empty fragment.
-}
fragment : Int -> Generator (Vdom.Element ())
fragment depth =
    Random.int 0 3
        |> Random.andThen (\n -> Random.list n (tree (depth - 1)))
        |> Random.map Fragment


{-| A memo whose dependencies say exactly what it builds, as they should, so
the same subtree in the same place in consecutive views is skipped.
-}
memo : Int -> Generator (Vdom.Element ())
memo depth =
    Random.map memoOf (tree (depth - 1))


memoOf : Vdom.Element () -> Vdom.Element ()
memoOf content =
    Jorn.Element.memo [ Jorn.Patch.encodeHtml content ] (\() -> content)


{-| Raw HTML, with and without elements inside, so the test also checks that
nothing reaches into it.
-}
raw : Generator (Vdom.Element ())
raw =
    Random.map3 (Raw "")
        (Random.uniform "div" [ "span" ])
        (Random.int 0 2 |> Random.andThen (\n -> Random.list n attribute) |> Random.map dedupe)
        rawHtml


rawHtml : Generator String
rawHtml =
    Random.uniform "" [ "a", "<i>a</i>", "<b>b</b><i>c</i>" ]


element : Int -> Generator (Vdom.Element ())
element depth =
    Random.uniform ( "", "div" ) [ ( "", "span" ), ( "", "li" ), ( "", "button" ), ( "", "input" ), ( "http://www.w3.org/2000/svg", "g" ) ]
        |> Random.andThen
            (\( ns, tag ) ->
                Random.map2
                    (Element ns
                        tag
                        (if tag == "input" then
                            Vdom.Void

                         else
                            Vdom.Normal
                        )
                    )
                    (Random.int 0 4 |> Random.andThen (\n -> Random.list n attribute) |> Random.map dedupe)
                    (if tag == "input" then
                        Random.constant []

                     else
                        Random.int 0 3 |> Random.andThen (\n -> Random.list n (tree (depth - 1)))
                    )
            )


attribute : Generator (Vdom.Attribute ())
attribute =
    Random.uniform (Random.map Attr.class (Random.uniform "" [ "x", "y" ]))
        [ Random.map (Attr.attribute "title") (Random.uniform "" [ "x", "y", "\"&\u{00A0}" ])
        , Random.constant Attr.none
        , Random.map2 Attr.style (Random.uniform "color" [ "top" ]) (Random.uniform "red" [ "0" ])
        , Random.map Attr.value (Random.uniform "" [ "v", "w" ])
        , Random.map Attr.checked (Random.uniform True [ False ])
        , Random.map Attr.disabled (Random.uniform True [ False ])
        , Random.map (\n -> Attr.property "config" (Encode.list Encode.int (List.range 0 n))) (Random.int 0 2)
        , Random.map3
            (\name prevent advanced ->
                (if prevent then
                    Events.preventDefault

                 else
                    identity
                )
                    (if advanced then
                        -- No page asks it here, as in server mode, so only
                        -- its options apply, whatever it answers.
                        Events.advanced name (Decode.succeed { message = (), preventDefault = True, stopPropagation = True })

                     else
                        Events.on name (Decode.succeed ())
                    )
            )
            (Random.uniform "click" [ "input", "mouseover" ])
            (Random.uniform True [ False ])
            (Random.uniform False [ True ])
        ]
        |> Random.andThen identity


{-| One attribute per name, so the comparison isn't muddied by an element
carrying, say, both an attribute and a property called `checked`.
-}
dedupe : List (Vdom.Attribute msg) -> List (Vdom.Attribute msg)
dedupe attributes =
    List.foldl
        (\attr ( seen, acc ) ->
            let
                n =
                    attrName attr
            in
            if List.member n seen then
                ( seen, acc )

            else
                ( n :: seen, acc ++ [ attr ] )
        )
        ( [], [] )
        attributes
        |> Tuple.second


attrName : Vdom.Attribute msg -> String
attrName attr =
    case attr of
        Vdom.Attr n _ ->
            n

        Vdom.Prop n _ ->
            n

        Vdom.On n _ ->
            "on" ++ n

        Vdom.Options _ wrapped ->
            attrName wrapped

        Vdom.NoAttribute ->
            ""



-- LABELLING


{-| Make each handler produce its element's position in document order.
-}
label : Vdom.Element () -> Vdom.Element String
label html =
    case html of
        Fragment kids ->
            -- A root fragment with several children is wrapped in an element
            -- of its own, which comes first on screen.
            if List.length (Vdom.flatten kids) > 1 then
                Tuple.first (labelChildren kids 1) |> Fragment

            else
                Tuple.first (labelChildren kids 0) |> Fragment

        _ ->
            Tuple.first (labelHelp html 0)


labelHelp : Vdom.Element () -> Int -> ( Vdom.Element String, Int )
labelHelp html next =
    case html of
        Text s ->
            ( Text s, next )

        Fragment kids ->
            labelChildren kids next
                |> Tuple.mapFirst Fragment

        Keyed key kid ->
            labelHelp kid next
                |> Tuple.mapFirst (Keyed key)

        Element ns tag closing attrs kids ->
            let
                id =
                    String.fromInt next

                ( newKids, after ) =
                    labelChildren kids (next + 1)
            in
            ( Element ns tag closing (List.map (relabel id) attrs) newKids, after )

        Raw ns tag attrs content ->
            ( Raw ns tag (List.map (relabel (String.fromInt next)) attrs) content, next + 1 )

        Memo key view ->
            -- What a memo builds stands for one node, like a whole view, and
            -- its handlers' numbers depend on where it is, so that goes into
            -- its dependencies too.
            let
                ( content, after ) =
                    labelHelp (Vdom.root (view ())) next
            in
            ( Memo (key ++ "@" ++ String.fromInt next) (\() -> content), after )


{-| A fragment isn't an element, so its children carry on the numbering of
their parent's, which is the order they appear in on screen.
-}
labelChildren : List (Vdom.Element ()) -> Int -> ( List (Vdom.Element String), Int )
labelChildren kids next =
    List.foldl
        (\kid ( acc, n ) ->
            let
                ( k, n2 ) =
                    labelHelp kid n
            in
            ( acc ++ [ k ], n2 )
        )
        ( [], next )
        kids


relabel : String -> Vdom.Attribute () -> Vdom.Attribute String
relabel id attr =
    case attr of
        Vdom.Attr n v ->
            Vdom.Attr n v

        Vdom.Prop n v ->
            Vdom.Prop n v

        Vdom.On n _ ->
            Vdom.On n (Decode.succeed (Vdom.handler id))

        Vdom.Options options wrapped ->
            Vdom.Options options (relabel id wrapped)

        Vdom.NoAttribute ->
            Vdom.NoAttribute



-- SURVIVORS


{-| The nodes that should keep their DOM node from one view to the next, as
pairs of paths: the same node in both, matched the way the diff matches them,
by key where there are keys and by position otherwise. The test checks that
the patcher really moves these nodes rather than recreating them.
-}
survivors : Vdom.Element msg -> Vdom.Element msg -> List ( List Int, List Int )
survivors old new =
    survivorsHelp [] [] (Vdom.root old) (Vdom.root new) []


survivorsHelp : List Int -> List Int -> Vdom.Element msg -> Vdom.Element msg -> List ( List Int, List Int ) -> List ( List Int, List Int )
survivorsHelp oldPath newPath old new acc =
    case ( old, new ) of
        ( Memo oldKey view, Memo newKey _ ) ->
            -- The diff skips memos with the same dependencies, so everything
            -- in one stays where it was, even keyed children whose keys
            -- changed, since keys aren't part of what the page shows.
            if oldKey == newKey then
                survivorsHelp oldPath newPath (Vdom.root (view ())) (Vdom.root (view ())) acc

            else
                survivorsHelp oldPath newPath (Vdom.root (view ())) new acc

        ( Memo _ view, _ ) ->
            survivorsHelp oldPath newPath (Vdom.root (view ())) new acc

        ( _, Memo _ view ) ->
            survivorsHelp oldPath newPath old (Vdom.root (view ())) acc

        ( Text _, Text _ ) ->
            ( List.reverse oldPath, List.reverse newPath ) :: acc

        ( Element oldNs oldTag _ _ oldKids, Element newNs newTag _ _ newKids ) ->
            if oldNs == newNs && oldTag == newTag then
                matchChildren (Vdom.flatten oldKids) (Vdom.flatten newKids)
                    |> List.foldl
                        (\( ( i, o ), ( j, n ) ) a -> survivorsHelp (i :: oldPath) (j :: newPath) o n a)
                        (( List.reverse oldPath, List.reverse newPath ) :: acc)

            else
                acc

        ( Raw oldNs oldTag _ _, Raw newNs newTag _ _ ) ->
            if oldNs == newNs && oldTag == newTag then
                ( List.reverse oldPath, List.reverse newPath ) :: acc

            else
                acc

        _ ->
            acc


matchChildren : List (Vdom.Element msg) -> List (Vdom.Element msg) -> List ( ( Int, Vdom.Element msg ), ( Int, Vdom.Element msg ) )
matchChildren olds news =
    if List.any isKeyed olds || List.any isKeyed news then
        let
            oldByKey =
                Vdom.keys olds |> List.indexedMap (\i ( k, o ) -> ( k, ( i, o ) )) |> Dict.fromList
        in
        Vdom.keys news
            |> List.indexedMap (\j ( k, n ) -> Dict.get k oldByKey |> Maybe.map (\match -> ( match, ( j, n ) )))
            |> List.filterMap identity

    else
        List.map2 Tuple.pair (List.indexedMap Tuple.pair olds) (List.indexedMap Tuple.pair news)


encodeSurvivors : List ( List Int, List Int ) -> Value
encodeSurvivors pairs =
    Encode.list (\( a, b ) -> Encode.list (Encode.list Encode.int) [ a, b ]) pairs
