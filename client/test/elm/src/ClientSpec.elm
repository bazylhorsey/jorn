port module ClientSpec exposing (main)

{-| Generates random view sequences A -> B -> C for client/test/run.mjs, and
routes the events the patcher reports back through `Jorn.Event`.

The generators use small alphabets so that consecutive views collide often and
exercise every diff branch.

-}

import Dict exposing (Dict)
import Jorn.Event
import Jorn.Html.Attributes as Attr
import Jorn.Html.Events as Events
import Jorn.Internal.Vdom as Vdom exposing (Html(..))
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
    Dict Int (Html String)


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
                        Encode.object
                            [ ( "a", Jorn.Patch.encodeHtml a )
                            , ( "b", Jorn.Patch.encodeHtml b )
                            , ( "c", Jorn.Patch.encodeHtml c )
                            , ( "ab", Jorn.Patch.encode (Jorn.Patch.diff a b) )
                            , ( "bc", Jorn.Patch.encode (Jorn.Patch.diff b c) )
                            ]
                    )
                    labelled
                )
            )

        Route { caseId, message } ->
            let
                result =
                    case ( Dict.get caseId model, Decode.decodeValue Jorn.Event.decoder message ) of
                        ( Just view, Ok incoming ) ->
                            case Jorn.Event.route incoming view of
                                Ok id ->
                                    "ok:" ++ id

                                Err error ->
                                    "err:" ++ Jorn.Event.errorToString error

                        ( Nothing, _ ) ->
                            "err:unknown case"

                        ( _, Err error ) ->
                            "err:" ++ Decode.errorToString error
            in
            ( model, out (Encode.string result) )



-- GENERATION


triple : Generator ( Html (), Html (), Html () )
triple =
    Random.uniform unrelated [ evolving ]
        |> Random.andThen identity


unrelated : Generator ( Html (), Html (), Html () )
unrelated =
    Random.map3 (\a b c -> ( a, b, c )) (tree 4) (tree 4) (tree 4)


evolving : Generator ( Html (), Html (), Html () )
evolving =
    tree 6
        |> Random.andThen
            (\a ->
                mutate a
                    |> Random.andThen (\b -> Random.map (\c -> ( a, b, c )) (mutate b))
            )


{-| A small random edit: most nodes survive untouched.
-}
mutate : Html () -> Generator (Html ())
mutate html =
    case html of
        Text _ ->
            Random.weighted ( 9, Random.constant html ) [ ( 1, tree 0 ), ( 0.3, tree 2 ) ]
                |> Random.andThen identity

        Element ns tag attrs kids ->
            Random.weighted ( 40, Random.constant Nothing ) [ ( 1, Random.map Just (tree 2) ) ]
                |> Random.andThen identity
                |> Random.andThen
                    (\replacement ->
                        case replacement of
                            Just other ->
                                Random.constant other

                            Nothing ->
                                Random.map2 (Element ns tag)
                                    (Random.weighted ( 12, Random.constant attrs ) [ ( 1, Random.int 0 3 |> Random.andThen (\n -> Random.list n attribute) |> Random.map dedupe ) ]
                                        |> Random.andThen identity
                                    )
                                    (mutateChildren tag kids)
                    )


mutateChildren : String -> List (Html ()) -> Generator (List (Html ()))
mutateChildren tag kids =
    if tag == "input" then
        Random.constant []

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


traverse : (a -> Generator b) -> List a -> Generator (List b)
traverse f items =
    List.foldr (\item acc -> Random.map2 (::) (f item) acc) (Random.constant []) items


{-| Small alphabets so that A, B and C collide often, which is what exercises
the interesting diff branches.
-}
tree : Int -> Generator (Html ())
tree depth =
    let
        text =
            Random.map Text (Random.uniform "" [ "a", "b" ])
    in
    if depth <= 0 then
        text

    else
        Random.weighted ( 1, text ) [ ( 3, element depth ) ]
            |> Random.andThen identity


element : Int -> Generator (Html ())
element depth =
    Random.uniform ( "", "div" ) [ ( "", "span" ), ( "", "li" ), ( "", "button" ), ( "", "input" ), ( "http://www.w3.org/2000/svg", "g" ) ]
        |> Random.andThen
            (\( ns, tag ) ->
                Random.map2 (Element ns tag)
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
        [ Random.map (Attr.attribute "title") (Random.uniform "" [ "x", "y" ])
        , Random.map Attr.value (Random.uniform "" [ "v", "w" ])
        , Random.map Attr.checked (Random.uniform True [ False ])
        , Random.map Attr.disabled (Random.uniform True [ False ])
        , Random.map (\n -> Attr.property "config" (Encode.list Encode.int (List.range 0 n))) (Random.int 0 2)
        , Random.map2
            (\name prevent -> Events.custom name { preventDefault = prevent, stopPropagation = False, include = [] } (Decode.succeed ()))
            (Random.uniform "click" [ "input", "mouseover" ])
            (Random.uniform True [ False ])
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

        Vdom.On n _ _ ->
            "on" ++ n



-- LABELLING


{-| Make each handler produce its element's position in document order.
-}
label : Html () -> Html String
label html =
    Tuple.first (labelHelp html 0)


labelHelp : Html () -> Int -> ( Html String, Int )
labelHelp html next =
    case html of
        Text s ->
            ( Text s, next )

        Element ns tag attrs kids ->
            let
                id =
                    String.fromInt next

                ( newKids, after ) =
                    List.foldl
                        (\kid ( acc, n ) ->
                            let
                                ( k, n2 ) =
                                    labelHelp kid n
                            in
                            ( acc ++ [ k ], n2 )
                        )
                        ( [], next + 1 )
                        kids
            in
            ( Element ns tag (List.map (relabel id) attrs) newKids, after )


relabel : String -> Vdom.Attribute () -> Vdom.Attribute String
relabel id attr =
    case attr of
        Vdom.Attr n v ->
            Vdom.Attr n v

        Vdom.Prop n v ->
            Vdom.Prop n v

        Vdom.On n options _ ->
            Vdom.On n options (Decode.succeed id)
